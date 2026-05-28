import Foundation
import StoreKit

@MainActor
final class ReportPurchaseState: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var statusText = "综合报告未付费生成"

    let productID = "admission_calculator_ai_report"

    func canUnlockReport(isStale: Bool) -> Bool {
        !isUnlocked && !isStale
    }

    func unlockForPrototype() {
        isUnlocked = true
        statusText = "已完成报告生成权限"
    }
}

enum OpenAIReportError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(String)
    case timedOut
    case transportFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 OPENAI_API_KEY。Debug 环境可通过 Scheme 环境变量配置；正式上架应改由服务端代理调用 OpenAI。"
        case .invalidResponse:
            return "OpenAI 返回格式无法解析。"
        case .requestFailed(let detail):
            return detail
        case .timedOut:
            return "OpenAI 请求超时。通常是当前网络无法稳定访问 api.openai.com，或长报告生成超过等待时间；请切换网络/VPN 后重试。"
        case .transportFailed(let detail):
            return "OpenAI 网络请求失败：\(detail)"
        }
    }
}

struct OpenAIReportClient {
    static let defaultTimeout: TimeInterval = 180
    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = defaultTimeout
        configuration.timeoutIntervalForResource = defaultTimeout + 60
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    var model = "gpt-5.2"
    var apiKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
    var session: URLSession = OpenAIReportClient.defaultSession
    var requestTimeout: TimeInterval = OpenAIReportClient.defaultTimeout

    func generateReport(prompt: String) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else {
            throw OpenAIReportError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenAIResponseRequest(
            model: model,
            instructions: ReportService.openAIInstructions,
            input: prompt,
            reasoning: OpenAIReasoning(effort: "low"),
            text: OpenAITextOptions(verbosity: "high")
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .timedOut {
                throw OpenAIReportError.timedOut
            }
            throw OpenAIReportError.transportFailed(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIReportError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw OpenAIReportError.requestFailed(detail)
        }
        let decoded = try JSONDecoder().decode(OpenAIResponseBody.self, from: data)
        if let outputText = decoded.outputText, !outputText.isEmpty {
            return outputText
        }
        let nestedText = decoded.output
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
        guard !nestedText.isEmpty else {
            throw OpenAIReportError.invalidResponse
        }
        return nestedText
    }
}

private struct OpenAIResponseRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let reasoning: OpenAIReasoning
    let text: OpenAITextOptions

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case reasoning
        case text
    }
}

private struct OpenAIReasoning: Encodable {
    let effort: String
}

private struct OpenAITextOptions: Encodable {
    let verbosity: String
}

private struct OpenAIResponseBody: Decodable {
    let outputText: String?
    let output: [OpenAIOutputItem]

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputText = try container.decodeIfPresent(String.self, forKey: .outputText)
        output = try container.decodeIfPresent([OpenAIOutputItem].self, forKey: .output) ?? []
    }
}

private struct OpenAIOutputItem: Decodable {
    let content: [OpenAIOutputContent]?
}

private struct OpenAIOutputContent: Decodable {
    let text: String?
}

enum GateRuleDisplay {
    static func failureSummary(_ rule: CollegeGateRule) -> String {
        let source = rule.isOfficial ? "官方" : "推断"
        let url = rule.sourceURL.map { " 来源：\($0.absoluteString)" } ?? ""
        return "\(source) \(rule.title)：\(rule.detail)\(url)"
    }
}

enum ReportService {
    static let openAIInstructions = """
    你是美国本科申请规划顾问，专门解释一个离线概率引擎已经算出的结果。你必须遵守：
    - 不得修改、重算、覆盖或美化输入中的概率、分档和硬门槛。
    - 不得承诺录取，不得把估算称为预测或保证。
    - 必须明确所有概率都是估算；组合概率是“当前选择学校中至少被一所录取”的概率。
    - 报告重点必须放在当前不足、补救优先级和申请策略上；逐校内容保持简洁，不展开系统缺失数据、来源审计或置信度说明。
    - 除已计算概率、学校数量和硬门槛结果外，不要用数值描述影响强度；影响强弱用“极强、强、中、弱、极弱”等档位表达。
    - 不得添加输入中没有的学校；不得建议学生申请数据范围外学校作为本报告计算的一部分。
    - 用中文输出，结构清晰，面向中国高中生家庭，语气务实、细致、可执行。
    """

    static func makeReport(result: PortfolioResult) -> String {
        let profile = result.profileSnapshot
        guard profile.round == .regularDecision else {
            return "综合报告仅支持 RD 轮次。当前结果为 \(profile.round.rawValue) 轮次，只提供本轮逐校概率和组合概率，不生成综合报告。"
        }
        let blocked = result.schoolResults.filter { !$0.gateResult.passed }
        let schoolResults = result.schoolResults
        let schoolBriefs = schoolResults.isEmpty
            ? "尚未选择学校。"
            : schoolResults.map { schoolBriefLine(for: $0, profile: profile) }.joined(separator: "\n")
        let academicFit = schoolResults.isEmpty ? "尚未选择学校。" : schoolResults.map { school in
            detailedAcademicFitSummary(for: school, profile: profile)
        }.joined(separator: "\n")
        let gates = blocked.isEmpty
            ? "未发现已选学校的硬门槛失败项。"
            : blocked.map { "\($0.college.name)：\($0.gateResult.failedRules.map(Self.gateRuleSummary).joined(separator: "；"))" }.joined(separator: "\n")
        let selectionNotes = result.selectionWarnings.isEmpty
            ? "当前组合内学校均已纳入本次计算。"
            : result.selectionWarnings.joined(separator: "\n")
        let missingInputNotes = missingInputSummary(profile: profile, selectedCollegeIDs: result.calculatedCollegeIDs)
        let applicationCountImpact = applicationCountImpactSummary(result: result)
        let factorHighlights = factorHighlightSummary(result: result)
        let improvementPlan = comprehensiveImprovementPlan(result: result)
        let deficitSummary = coreDeficitSummary(result: result)
        let recommendationNotes: String
        switch result.selectionSource {
        case .automatic:
            if !result.recommendationSteps.isEmpty {
                recommendationNotes = result.recommendationWarnings.isEmpty
                    ? "自动推荐数量与计划选择数量一致。"
                    : result.recommendationWarnings.joined(separator: "\n")
            } else if result.schoolResults.isEmpty {
                recommendationNotes = result.recommendationWarnings.isEmpty
                    ? "自动推荐没有生成可计算学校。"
                    : result.recommendationWarnings.joined(separator: "\n")
            } else {
                recommendationNotes = "当前组合标记为自动推荐，但学校集合或顺位元数据没有通过当前画像快照校验；报告不会把它视为数量一致的自动推荐结果。"
            }
        case .manual:
            recommendationNotes = "当前为手动选校，未触发自动推荐缺口判断。"
        case .none:
            recommendationNotes = "尚未选择学校，未触发自动推荐。"
        }
        return """
        综合选校报告

        生成时间：\(generatedAtText(result.generatedAt))
        快照说明：本报告只解释该次提交的学生画像和选校组合（RD 轮次）；后续修改表单或选校后需要重新计算。

        画像摘要：\(profile.applicantStatus.rawValue)，\(profile.curriculum.rawValue) 课程，目标专业 \(profile.major.rawValue)，申请轮次 \(profile.round.rawValue)，高中背景 \(highSchoolName(profile.highSchoolID))。逐校概率会按学校政策重算标化影响。

        RD 当前选择学校中至少被一所录取的估算概率：
        综合大学 T10 至少一所（当前组合 \(tierCount(in: result, category: .nationalUniversity, maxRank: 10)) 所）：\(percent(result.t10AtLeastOne))
        综合大学 T11-T30 至少一所（当前组合 \(tierCount(in: result, category: .nationalUniversity, minRankExclusive: 10, maxRank: 30)) 所）：\(percent(result.t11T30AtLeastOne))
        综合大学 T30 至少一所（当前组合 \(tierCount(in: result, category: .nationalUniversity, maxRank: 30)) 所）：\(percent(result.t30AtLeastOne))
        综合大学 T50 至少一所（当前组合 \(tierCount(in: result, category: .nationalUniversity, maxRank: 50)) 所）：\(percent(result.t50AtLeastOne))
        文理学院 T10 至少一所（当前组合 \(tierCount(in: result, category: .liberalArtsCollege, maxRank: 10)) 所）：\(percent(result.liberalArtsT10AtLeastOne))
        文理学院 T30 至少一所（当前组合 \(tierCount(in: result, category: .liberalArtsCollege, maxRank: 30)) 所）：\(percent(result.liberalArtsT30AtLeastOne))
        全部已选至少一所（\(result.schoolResults.count) 所）：\(percent(result.selectedAtLeastOne))

        当前组合结构：
        来源：\(result.selectionSource.rawValue)。
        保底 \(result.selectedBucketCounts.likely) 所，目标 \(result.selectedBucketCounts.target) 所，争取 \(result.selectedBucketCounts.reach) 所，硬门槛未满足 \(result.selectedBucketCounts.blocked) 所。
        分档规则：争取 <20%，目标 20%-60%，保底 >=60%；保底是相对规划标签，不代表录取保证。
        \(selectionNotes)

        待补资料：
        \(missingInputNotes)

        当前主要不足：
        \(deficitSummary)

        目前影响概率较大的因素：
        \(factorHighlights)

        提高申请数量对概率的影响：
        \(applicationCountImpact)

        自动推荐提示：
        \(recommendationNotes)

        自动推荐依据：
        \(recommendationStrategySummary(result: result))

        学校简表：
        比较说明：高于本校基准、接近本校基准、低于本校基准、暂无可比基准或不适用。
        \(schoolBriefs)

        逐校精简判断：
        \(academicFit)

        申请策略与提升动作：
        \(improvementPlan)

        硬门槛：
        \(gates)

        执行原则：
        1. 先补齐所有 required 标化、英语或作品集门槛，再优化概率；硬门槛失败时单校概率为 0%。
        2. 对低概率但未被阻断的学校，按“硬门槛/学术匹配 -> 专业竞争 -> 轮次/资助 -> 活动叙事 -> 选校结构”的顺序处理。
        3. 若组合概率主要受申请数量限制，优先增加同梯度目标校和更低风险学校；只增加极高难度学校会受到同层相关性折扣，边际收益较小。
        4. 若某校已经接近本校历史/内部基准，下一步重点不只是继续堆分数，而是让专业方向、活动证据、文书主线和推荐信互相证明。
        5. 该报告只解释计算结果，不改变概率，也不承诺录取。
        """
    }

    static func makeOpenAIReportPrompt(result: PortfolioResult) -> String {
        guard result.profileSnapshot.round == .regularDecision else {
            return makeReport(result: result)
        }
        return """
        请基于下面的完整事实包，生成一份更有针对性、更人性化、更专业的付费版完整选校报告。

        你不是在做模板填空。请把事实包当作唯一事实来源，综合学生画像、本地基础报告、逐校概率、综合概率、学校平均/内部基准比较、提高申请概率的影响因子、硬门槛、警示和行动建议，在大体框架下自由组织语言和段落。可以调整标题和顺序，但必须覆盖这些内容：
        - 执行摘要：整体风险、最重要不足、最优先策略，并说明概率是估算，不是录取承诺。
        - 画像诊断：学生当前最强证据和最薄弱证据，不要泛泛鼓励。
        - 测算结果总览：原样保留综合大学 T10/T11-T30/T30/T50、文理学院 T10/T30、全部已选至少一所概率；解释同层相关性折扣。
        - 当前不足优先级：按“必须立即处理、明显拖累概率、材料优化项”归纳，不要机械逐校重复。
        - 学校简表：每所学校都要出现，包含学校名、单校概率、分档、硬门槛状态、基准比较文字、关键风险和优先动作。
        - 逐校策略：只写每所学校最值得家长和学生关注的判断，不要把每所大学写成长篇百科。
        - 提升方案：按 0-1 个月、1-3 个月、3-6 个月列行动，并说明影响路径，例如硬门槛、学术匹配、画像分、专业竞争、轮次/资助、选校结构。
        - 选校组合策略：说明保底/目标/争取/阻断结构、申请数量对至少一所概率的方向性影响、当前学校的边际收益测算，以及为什么精力有限时不是越多越好。
        - 家庭沟通版结论：克制、清楚、可执行，不制造焦虑。

        强制约束：
        - 不得修改、重算、覆盖或美化事实包中的概率、分档、硬门槛和学校列表。
        - 不得添加事实包外的学校；不得把建议申请数据范围外学校写成本报告计算的一部分。
        - 不得承诺录取，不得把估算说成预测或保证；“保底”也不是保证。
        - 不要展开系统缺失数据、来源审计或置信度说明。
        - 除已计算概率、学校数量、硬门槛结果和事实包里的学生/学校基准值外，不要用数字描述影响强度；影响强度用“极强、强、中、弱、极弱”等档位。
        - 不要暴露内部调整值、权重、参数或公式。
        - 如果事实包中同一信息在本地报告和结构化事实里重复，以结构化事实包为准。

        完整事实包如下：

        \(makeOpenAIReportFactPacket(result: result))
        """
    }

    private static func makeOpenAIReportFactPacket(result: PortfolioResult) -> String {
        let profile = result.profileSnapshot
        let selectedWarnings = result.selectionWarnings.isEmpty
            ? "当前组合内学校均已纳入本次计算。"
            : result.selectionWarnings.joined(separator: "\n")
        let recommendationWarnings = result.selectionSource == .automatic
            ? (result.recommendationWarnings.isEmpty ? "自动推荐未产生额外数量/范围警示。" : result.recommendationWarnings.joined(separator: "\n"))
            : "当前不是自动推荐组合。"

        return """
        ## 事实包总原则
        - 所有学校、概率、分档和硬门槛均来自本地离线概率引擎。
        - OpenAI 只能解释和组织这些事实，不能重新计算概率。
        - 报告应更像专业顾问写给家庭的分析，而不是逐项模板填空。

        ## 学生画像快照
        \(studentProfileFactBlock(profile))

        ## 组合概率与结构
        生成时间：\(generatedAtText(result.generatedAt))
        选校来源：\(result.selectionSource.rawValue)
        当前计算学校数：\(result.schoolResults.count) 所
        保底/目标/争取/阻断：\(result.selectedBucketCounts.likely)/\(result.selectedBucketCounts.target)/\(result.selectedBucketCounts.reach)/\(result.selectedBucketCounts.blocked)
        综合大学 T10 至少一所（当前组合 \(tierCount(in: result, category: .nationalUniversity, maxRank: 10)) 所）：\(percent(result.t10AtLeastOne))
        综合大学 T11-T30 至少一所（当前组合 \(tierCount(in: result, category: .nationalUniversity, minRankExclusive: 10, maxRank: 30)) 所）：\(percent(result.t11T30AtLeastOne))
        综合大学 T30 至少一所（当前组合 \(tierCount(in: result, category: .nationalUniversity, maxRank: 30)) 所）：\(percent(result.t30AtLeastOne))
        综合大学 T50 至少一所（当前组合 \(tierCount(in: result, category: .nationalUniversity, maxRank: 50)) 所）：\(percent(result.t50AtLeastOne))
        文理学院 T10 至少一所（当前组合 \(tierCount(in: result, category: .liberalArtsCollege, maxRank: 10)) 所）：\(percent(result.liberalArtsT10AtLeastOne))
        文理学院 T30 至少一所（当前组合 \(tierCount(in: result, category: .liberalArtsCollege, maxRank: 30)) 所）：\(percent(result.liberalArtsT30AtLeastOne))
        全部已选至少一所：\(percent(result.selectedAtLeastOne))
        分档规则：争取 <20%，目标 20%-60%，保底 >=60%；保底不是保证。
        申请数量与边际收益：
        \(applicationCountImpactSummary(result: result))

        ## 待补资料与警示
        待补资料：
        \(missingInputSummary(profile: profile, selectedCollegeIDs: result.calculatedCollegeIDs))

        选校范围警示：
        \(selectedWarnings)

        自动推荐警示：
        \(recommendationWarnings)

        逐校计算警示：
        \(warningSummary(result: result))

        ## 当前不足与概率驱动
        当前主要不足：
        \(coreDeficitSummary(result: result))

        提高申请概率的主要影响因子：
        \(factorHighlightSummary(result: result))

        自动推荐/组合策略依据：
        \(recommendationStrategySummary(result: result))

        ## 逐校计算事实
        比较说明：高于本校基准、接近本校基准、低于本校基准、暂无可比基准或不适用。
        \(schoolFactBlocks(result: result))

        ## 本地基础报告
        下面是本地生成报告，可作为报告框架和事实校验参考。OpenAI 可以重组表达，但不得更改其中的计算事实。

        \(makeReport(result: result))
        """
    }

    private static func studentProfileFactBlock(_ profile: StudentProfile) -> String {
        let testing: String
        if profile.testOptional {
            testing = "Test Optional / 不提交标化；残留 SAT/ACT 不进入学术匹配。"
        } else {
            let sat = profile.sat.map(String.init) ?? "未填"
            let act = profile.act.map(String.init) ?? "未填"
            let equivalent = submittedSATEquivalent(profile).map(String.init) ?? "未形成 SAT 等效分"
            testing = "SAT \(sat)，ACT \(act)，采用最强 SAT 等效：\(equivalent)。"
        }
        let english = [
            profile.toefl.map { "TOEFL \($0)" },
            profile.ielts.map { "IELTS \($0.formatted(.number.precision(.fractionLength(1))))" }
        ].compactMap { $0 }.joined(separator: "，")

        return """
        身份：\(profile.applicantStatus.rawValue)
        课程体系：\(profile.curriculum.rawValue)
        主 GPA/成绩：\(gradeFact(profile))
        班级排名：前 \(formatNumber(profile.classRankPercentile))%
        课程难度：\(profile.rigor)/5
        课程体系成绩证据：\(curriculumEvidenceComment(profile))
        标化策略：\(testing)
        英语证明：\(english.isEmpty ? "未填写 TOEFL/IELTS" : english)
        软性画像：活动 \(profile.activities)/5，科研/项目 \(profile.research)/5，奖项 \(profile.honors)/5，文书 \(profile.essay)/5，推荐信 \(profile.recommendations)/5
        高中背景：\(highSchoolName(profile.highSchoolID))
        目标专业：\(profile.major.rawValue)
        申请轮次：\(profile.round.rawValue)
        国际生资助需求：\(profile.needsAid ? "需要/会申请资助" : "不申请资助或未标记资助需求")
        艺术作品集：\(profile.hasPortfolio ? "已标记有作品集" : "未标记作品集")
        纳入文理学院：\(profile.includeLiberalArtsColleges ? "是" : "否")
        计划申请学校数：\(profile.requestedSchoolCount)
        """
    }

    private static func gradeFact(_ profile: StudentProfile) -> String {
        switch profile.gradeScale {
        case .percent:
            return "\(profile.gpaPercent.formatted(.number.precision(.fractionLength(1))))/100"
        case .fourPoint:
            return "\(profile.gpaFourPoint.formatted(.number.precision(.fractionLength(2))))/4.0（仅折算为内部学术指数，不当作真实百分制）"
        case .fivePoint:
            return "\(profile.gpaFivePoint.formatted(.number.precision(.fractionLength(2))))/5.0（仅折算为内部学术指数，不当作真实百分制）"
        case .letter:
            return "\(profile.letterGrade.rawValue)（仅折算为内部学术指数，不当作真实百分制）"
        }
    }

    private static func schoolFactBlocks(result: PortfolioResult) -> String {
        let profile = result.profileSnapshot
        guard !result.schoolResults.isEmpty else {
            return "尚未选择学校。"
        }
        return result.schoolResults.map { school in
            schoolFactBlock(school, profile: profile)
        }.joined(separator: "\n\n")
    }

    private static func schoolFactBlock(_ school: ChanceResult, profile: StudentProfile) -> String {
        let benchmark = AdmissionsSeedData.academicBenchmarks.first { $0.collegeID == school.college.id }
        let gateStatus: String
        if school.gateResult.passed {
            gateStatus = "通过"
        } else {
            gateStatus = "未通过：\(school.gateResult.failedRules.map(gateRuleSummary).joined(separator: "；"))"
        }
        let warnings = unique(school.warnings)
        let riskLines = schoolRiskLines(profile: profile, school: school, benchmark: benchmark)
        let actionLines = schoolActionLines(profile: profile, school: school, benchmark: benchmark)
        let academicComparison = benchmarkComparisonText(
            value: academicIndex(profile),
            target: benchmark?.gpaPercentBenchmark,
            higherIsBetter: true,
            closeThreshold: 2
        )
        let rankComparison = benchmarkComparisonText(
            value: profile.classRankPercentile,
            target: benchmark?.classRankPercentileBenchmark,
            higherIsBetter: false,
            closeThreshold: 3
        )
        let testingComparison: String
        if isTestFreeCollege(school.college) || profile.testOptional {
            testingComparison = "暂无可比基准或不适用"
        } else {
            testingComparison = benchmarkComparisonText(
                value: submittedSATEquivalent(profile).map(Double.init),
                target: benchmark?.satBenchmark.map(Double.init),
                higherIsBetter: true,
                closeThreshold: 30
            )
        }
        let rigorComparison = benchmarkComparisonText(
            value: Double(profile.rigor),
            target: benchmark?.rigorBenchmark.map(Double.init),
            higherIsBetter: true,
            closeThreshold: 0.5
        )

        return """
        ### \(school.college.name)
        学校类型/排名：\(school.college.category.rawValue) #\(school.college.rank)
        基础录取率：\(percent(school.baseRate))
        单校调整后概率：\(percent(school.adjustedProbability))
        分档：\(school.bucket.rawValue)
        硬门槛：\(gateStatus)
        与学校平均/内部基准比较：学术 \(academicComparison)，排名 \(rankComparison)，标化 \(testingComparison)，课程难度 \(rigorComparison)
        学术匹配说明：\(academicFitSummary(for: school))
        学校平均/内部基准明细：
        \(academicComparisonLines(profile: profile, school: school, benchmark: benchmark).joined(separator: "\n"))
        提高申请概率的影响因子：
        \(schoolFactorLines(school).joined(separator: "\n"))
        关键风险：
        \(riskLines.isEmpty ? "当前没有单项风险特别突出，重点看材料表达和选校结构。" : riskLines.map { "- \($0)" }.joined(separator: "\n"))
        优先动作：
        \(actionLines.joined(separator: "\n"))
        计算警示：
        \(warnings.isEmpty ? "无额外逐校警示。" : warnings.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    private static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private static func generatedAtText(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func tierCount(in result: PortfolioResult, category: CollegeCategory, minRankExclusive: Int = 0, maxRank: Int) -> Int {
        result.schoolResults.filter { $0.college.category == category && $0.college.rank > minRankExclusive && $0.college.rank <= maxRank }.count
    }

    private static func signed(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(2))))"
    }

    private static func impactBand(_ value: Double) -> String {
        let direction = value >= 0 ? "正向" : "负向"
        return "\(direction)\(strengthBand(abs(value)))"
    }

    private static func strengthBand(_ value: Double) -> String {
        switch value {
        case 0.08...:
            return "极强"
        case 0.05..<0.08:
            return "强"
        case 0.025..<0.05:
            return "中"
        case 0.01..<0.025:
            return "弱"
        default:
            return "极弱"
        }
    }

    private static func academicFitSummary(for school: ChanceResult) -> String {
        guard school.gateResult.passed else {
            return "\(school.college.name)：硬门槛未通过，优先补齐阻断项后再比较学术匹配。"
        }
        guard let factor = school.factors.first(where: { $0.label == "目标校学术匹配" }) else {
            return "\(school.college.name)：暂未形成学术匹配对比，建议先检查 GPA、排名、标化和课程难度。"
        }

        let direction: String
        if factor.value >= 0.04 {
            direction = "整体高于目标校内部基准，是当前画像优势。"
        } else if factor.value <= -0.04 {
            direction = "整体低于目标校内部基准，是优先提升项。"
        } else {
            direction = "整体接近目标校内部基准，提升空间主要看单项短板。"
        }
        return "\(school.college.name)：学术匹配为\(impactBand(factor.value))。\(direction) \(userFacingAcademicDetail(factor.detail))"
    }

    private static func detailedAcademicFitSummary(for school: ChanceResult, profile: StudentProfile) -> String {
        guard school.gateResult.passed else {
            return "\(school.college.name)：硬门槛未通过，优先补齐阻断项后再比较学术匹配。"
        }

        let benchmark = AdmissionsSeedData.academicBenchmarks.first { $0.collegeID == school.college.id }
        let fitLine = academicFitSummary(for: school)
        let riskLines = schoolRiskLines(profile: profile, school: school, benchmark: benchmark)
            .prefix(3)
            .joined(separator: "；")
        let actionLines = schoolActionLines(profile: profile, school: school, benchmark: benchmark)
            .prefix(2)
            .map { $0.replacingOccurrences(of: "- ", with: "") }
            .joined(separator: "；")
        let factorLines = schoolFactorLines(school)
            .prefix(3)
            .map { $0.replacingOccurrences(of: "- ", with: "") }
            .joined(separator: "；")

        return """
        \(fitLine)
        关键风险：\(riskLines.isEmpty ? "当前没有单项风险特别突出，重点看材料表达和选校结构。" : riskLines)
        主要驱动：\(factorLines.isEmpty ? "概率主要由基础率和整体画像共同决定。" : factorLines)
        优先动作：\(actionLines)
        """
    }

    private static func schoolBriefLine(for school: ChanceResult, profile: StudentProfile) -> String {
        guard school.gateResult.passed else {
            let failed = school.gateResult.failedRules.map(gateRuleSummary).joined(separator: "；")
            return "\(school.college.name)：\(percent(school.adjustedProbability))（\(school.bucket.rawValue)）｜硬门槛未通过｜学术 暂无可比基准或不适用 标化 暂无可比基准或不适用 课程 暂无可比基准或不适用｜优先动作：先补齐 \(failed)。"
        }

        let benchmark = AdmissionsSeedData.academicBenchmarks.first { $0.collegeID == school.college.id }
        let academics = benchmarkComparisonText(
            value: academicIndex(profile),
            target: benchmark?.gpaPercentBenchmark,
            higherIsBetter: true,
            closeThreshold: 2
        )
        let testing: String
        if isTestFreeCollege(school.college) || profile.testOptional {
            testing = "暂无可比基准或不适用"
        } else {
            testing = benchmarkComparisonText(
                value: submittedSATEquivalent(profile).map(Double.init),
                target: benchmark?.satBenchmark.map(Double.init),
                higherIsBetter: true,
                closeThreshold: 30
            )
        }
        let rigor = benchmarkComparisonText(
            value: Double(profile.rigor),
            target: benchmark?.rigorBenchmark.map(Double.init),
            higherIsBetter: true,
            closeThreshold: 0.5
        )
        let risk = schoolRiskLines(profile: profile, school: school, benchmark: benchmark).first ?? "无单项特别突出风险"
        let action = schoolActionLines(profile: profile, school: school, benchmark: benchmark).first?
            .replacingOccurrences(of: "- ", with: "") ?? "保持材料一致性，重点优化专业叙事和选校结构。"
        return "\(school.college.name)：\(percent(school.adjustedProbability))（\(school.bucket.rawValue)）｜硬门槛通过｜学术 \(academics) 标化 \(testing) 课程 \(rigor)｜关键风险：\(risk)｜优先动作：\(action)"
    }

    private static func benchmarkComparisonText(value: Double?, target: Double?, higherIsBetter: Bool, closeThreshold: Double) -> String {
        guard let value, let target else {
            return "暂无可比基准或不适用"
        }
        let gap = higherIsBetter ? value - target : target - value
        if gap > closeThreshold {
            return "高于本校基准"
        }
        if gap < -closeThreshold {
            return "低于本校基准"
        }
        return "接近本校基准"
    }

    private static func schoolRiskLines(profile: StudentProfile, school: ChanceResult, benchmark: AcademicBenchmark?) -> [String] {
        var risks: [String] = []
        let college = school.college
        let gpaIndex = academicIndex(profile)
        let satEquivalent = submittedSATEquivalent(profile)

        if let target = benchmark?.gpaPercentBenchmark, gpaIndex < target - 2 {
            risks.append("学术匹配低于本校内部基准")
        }
        if let target = benchmark?.classRankPercentileBenchmark, profile.classRankPercentile > target + 3 {
            risks.append("校内排名相对目标校偏弱")
        }
        if !isTestFreeCollege(college), let target = benchmark?.satBenchmark {
            if let satEquivalent, satEquivalent < target - 30 {
                risks.append("标化与本校基准有差距")
            } else if satEquivalent == nil && !profile.testOptional {
                risks.append("标化策略尚未明确")
            }
        }
        if let target = benchmark?.rigorBenchmark, profile.rigor < target {
            risks.append("课程难度证据需要补强")
        }
        if curriculumPerformanceIndex(profile) < 70 {
            risks.append("课程体系成绩证据不足")
        }
        if profile.activities < 4 || profile.research < 4 || profile.honors < 4 {
            risks.append("专业证据链仍不够集中")
        }
        if profile.essay < 4 {
            risks.append("文书主线需要更清晰")
        }
        if profile.needsAid && profile.applicantStatus.isInternational {
            risks.append("国际生资助需求会增加策略风险")
        }
        return risks
    }

    private static func academicComparisonLines(profile: StudentProfile, school: ChanceResult, benchmark: AcademicBenchmark?) -> [String] {
        let college = school.college
        let gpaIndex = academicIndex(profile)
        let rank = profile.classRankPercentile
        let satEquivalent = submittedSATEquivalent(profile)
        let curriculumIndex = curriculumPerformanceIndex(profile)
        var lines: [String] = []

        if let target = benchmark?.gpaPercentBenchmark {
            lines.append("- GPA/学术指数：申请者 \(profile.gradeScale.rawValue) 折算学术指数 \(formatNumber(gpaIndex))/100；本校基准 \(formatNumber(target))/100；\(gapText(value: gpaIndex - target, unit: "分", positiveIsGood: true, smallThreshold: 2, largeThreshold: 5))")
        } else {
            lines.append("- GPA/学术指数：申请者 \(profile.gradeScale.rawValue) 折算学术指数 \(formatNumber(gpaIndex))/100；本校未配置可比较 GPA 基准，报告只把它作为画像强度信号。")
        }

        if let target = benchmark?.classRankPercentileBenchmark {
            let gap = rank - target
            lines.append("- 班级排名：申请者前 \(formatNumber(rank))%；本校基准前 \(formatNumber(target))%；\(rankGapText(gap))")
        } else {
            lines.append("- 班级排名：申请者前 \(formatNumber(rank))%；本校未配置排名基准，排名仍进入画像分和强队列判断。")
        }

        if isTestFreeCollege(college) {
            lines.append("- 标化：该校按 test-free/test-blind 处理，SAT/ACT 不进入本校概率；语言成绩和课程体系成绩仍然重要。")
        } else if let target = benchmark?.satBenchmark {
            if let satEquivalent {
                let gap = satEquivalent - target
                lines.append("- 标化：申请者 SAT 等效 \(satEquivalent)；本校 SAT 基准 \(target)；\(gapText(value: Double(gap), unit: "分", positiveIsGood: true, smallThreshold: 30, largeThreshold: 80))")
            } else if profile.testOptional {
                lines.append("- 标化：当前选择不提交；本校 SAT 基准 \(target)。若能取得接近或高于基准的成绩，提交会改善学术匹配；若明显低于基准，继续不提交更稳妥。")
            } else {
                lines.append("- 标化：未填写 SAT/ACT；本校 SAT 基准 \(target)。若该校要求或强烈看重标化，这是短期优先补齐项。")
            }
        } else {
            lines.append("- 标化：本校未配置 SAT 基准；当前 \(profile.testOptional ? "按 Test Optional 处理" : "SAT/ACT 作为一般画像信号处理")。")
        }

        if let target = benchmark?.rigorBenchmark {
            let gap = profile.rigor - target
            lines.append("- 课程难度：申请者 \(profile.rigor)/5；本校基准 \(target)/5；\(gapText(value: Double(gap), unit: "档", positiveIsGood: true, smallThreshold: 0.5, largeThreshold: 1.5))")
        } else {
            lines.append("- 课程难度：申请者 \(profile.rigor)/5；本校未配置课程难度基准。")
        }

        lines.append("- 课程体系成绩：\(profile.curriculum.rawValue) 体系内成绩指数 \(formatNumber(curriculumIndex))/100；\(curriculumEvidenceComment(profile))")
        return lines
    }

    private static func holisticProfileLines(profile: StudentProfile, school: ChanceResult) -> [String] {
        [
            "- 活动：\(profile.activities)/5（\(profileLevelText(profile.activities))）。需要能证明持续投入、影响范围和与 \(profile.major.rawValue) 的关系。",
            "- 科研/项目：\(profile.research)/5（\(profileLevelText(profile.research))）。对 \(profile.major.rawValue) 尤其要避免只有标题，最好呈现问题、方法、产出和个人贡献。",
            "- 奖项：\(profile.honors)/5（\(profileLevelText(profile.honors))）。优先区分校级、区域级、国家/国际级，以及是否与目标专业相关。",
            "- 文书：\(profile.essay)/5（\(profileLevelText(profile.essay))）。应把学术兴趣、活动证据和学校适配连成一条主线，而不是重复简历。",
            "- 推荐信：\(profile.recommendations)/5（\(profileLevelText(profile.recommendations))）。最有价值的是能证明课堂表现、主动性、研究潜力或社区贡献的具体例子。",
            "- 高中背景：\(highSchoolName(profile.highSchoolID))。该项是校准信号，不是单独保证；如果当前为其他/手动评估学校，建议补充真实高中以减少保守处理。",
            "- 专业竞争：\(profile.major.rawValue)。本校该项影响\(school.factors.first { $0.label == "专业竞争" }.map { impactBand($0.value) } ?? "极弱")，热门专业需要更强的课程、项目和成果闭环。"
        ]
    }

    private static func schoolFactorLines(_ school: ChanceResult) -> [String] {
        let reportableLabels: Set<String> = ["学生画像", "目标校学术匹配", "高中背景", "顶尖高中强队列", "专业竞争", "申请轮次", "资助需求"]
        let materialFactors = school.factors
            .filter { reportableLabels.contains($0.label) && abs($0.value) >= 0.01 }
            .sorted { abs($0.value) > abs($1.value) }
            .prefix(5)
            .map { factor in
                "- \(factor.label)：\(impactBand(factor.value))。\(userFacingAcademicDetail(factor.detail))"
            }
        return materialFactors.isEmpty ? ["- 当前没有明显单项驱动，概率主要由基础率和整体画像共同决定。"] : Array(materialFactors)
    }

    private static func schoolActionLines(profile: StudentProfile, school: ChanceResult, benchmark: AcademicBenchmark?) -> [String] {
        var actions: [String] = []
        let college = school.college
        let gpaIndex = academicIndex(profile)
        let satEquivalent = submittedSATEquivalent(profile)

        if let target = benchmark?.gpaPercentBenchmark, gpaIndex < target - 2 {
            actions.append("- 学术匹配：短期补交最新成绩、解释课程难度和上升趋势；若离基准超过 5 分，应同步增加更稳健学校，不只靠文书弥补。")
        }
        if let target = benchmark?.classRankPercentileBenchmark, profile.classRankPercentile > target + 3 {
            actions.append("- 校内排名：突出最强课程、年级位置和相对进步；如果排名短期难改变，用课程难度、竞赛/项目产出补强学术可信度。")
        }
        if !isTestFreeCollege(college), let target = benchmark?.satBenchmark {
            if let satEquivalent, satEquivalent < target - 30 {
                actions.append("- 标化：若时间允许，优先把 SAT 等效分提升到 \(target) 附近；低于基准 80 分以上时要谨慎决定是否提交。")
            } else if satEquivalent == nil && profile.testOptional && college.rank <= 50 {
                actions.append("- 标化策略：当前不提交。若模考能达到本校基准 \(target) 附近，重新评估提交；否则把精力放到课程成绩和材料证据链。")
            }
        }
        if let target = benchmark?.rigorBenchmark, profile.rigor < target {
            actions.append("- 课程难度：补充高阶课程、AP/IB/A-Level 预测或在读证明；若申请季已无法加课，文书和推荐信要解释已选课程中的挑战度。")
        }
        if curriculumPerformanceIndex(profile) < 70 {
            actions.append("- 课程体系成绩：补齐 AP/IB/A-Level/校内成绩证据；没有课程证据时，模型会把课程体系表现保守处理。")
        }
        if profile.activities < 4 || profile.research < 4 || profile.honors < 4 {
            actions.append("- 专业证据链：选择 1-2 个最能支持 \(profile.major.rawValue) 的活动/项目深挖，明确问题、行动、产出、影响，不要平均铺开所有经历。")
        }
        if profile.essay < 4 {
            actions.append("- 文书：把“为什么这个专业、为什么这类学校、过去证据是什么、未来贡献是什么”写成一条线；每所学校补充文书要体现具体适配。")
        }
        if profile.recommendations < 4 {
            actions.append("- 推荐信：优先让老师写具体课堂/项目细节，证明学术主动性、协作和抗压，而不是泛泛夸奖。")
        }
        if profile.needsAid && profile.applicantStatus.isInternational {
            actions.append("- 资助策略：逐校核对 need-aware/limited aid 风险；对高风险学校，材料中要更清楚证明匹配度和不可替代性。")
        }
        if actions.isEmpty {
            actions.append("- 当前核心学术项接近或高于本校基准；重点转向材料质量、专业叙事、推荐信细节和选校组合平衡。")
        }
        return actions
    }

    private static func userFacingAcademicDetail(_ detail: String) -> String {
        var text = detail
        let replacements: [(String, String)] = [
            ("部分官方/部分推断基准：", ""),
            ("推断基准：", ""),
            ("官方/核验基准：", ""),
            ("缺失", "未纳入比较"),
            ("Test optional", "不提交标化")
        ]
        replacements.forEach { source, replacement in
            text = text.replacingOccurrences(of: source, with: replacement)
        }
        return text
    }

    private static func recommendationStrategySummary(result: PortfolioResult) -> String {
        switch result.selectionSource {
        case .automatic:
            guard !result.schoolResults.isEmpty else {
                return "自动推荐没有生成学校，因此没有可解释的期望值排序。"
            }
            let engine = ChanceEngine()
            let currentResultsByID = Dictionary(uniqueKeysWithValues: result.schoolResults.map { ($0.college.id, $0) })

            if !result.recommendationSteps.isEmpty {
                let lines = result.recommendationSteps.compactMap { step -> String? in
                    guard let school = currentResultsByID[step.result.college.id] else {
                        return nil
                    }
                    return "第\(step.order)顺位 \(school.college.name)：单校概率 \(percent(school.adjustedProbability))，学校价值\(rankValueBand(step.rankScore))，同层相关性影响\(strengthBand(step.sameTierDiscount))，边际贡献\(strengthBand(step.marginalExpectedValue / 100))。"
                }.joined(separator: "\n")
                return """
                自动推荐先排除硬门槛失败学校，再综合单校概率、学校价值和同层相关性边际折扣；它不是只按录取概率排序，也不会把多个同层 offer 简单相加。以下为按当前画像快照确定的入选顺序：
                \(lines)
                """
            }

            let lines = result.schoolResults
                .filter { $0.gateResult.passed }
                .sorted {
                    let lhsValue = engine.recommendationExpectedValue(for: $0)
                    let rhsValue = engine.recommendationExpectedValue(for: $1)
                    if lhsValue == rhsValue {
                        return $0.college.rank < $1.college.rank
                    }
                    return lhsValue > rhsValue
                }
                .map { school in
                    let rankScore = engine.recommendationRankScore(for: school.college)
                    return "\(school.college.name)：单校概率 \(percent(school.adjustedProbability))，学校价值\(rankValueBand(rankScore))。"
                }
                .joined(separator: "\n")
            return """
            当前组合标记为自动推荐，但学校集合与按当前画像快照重新生成的自动推荐不完全一致；以下仅解释当前入选学校的学校价值档位。自动推荐本身会综合单校概率、学校价值和同层相关性边际折扣：
            \(lines)
            """
        case .manual:
            return "当前为手动选校；报告仍展示逐校概率和组合概率，但没有自动推荐期望值排序。"
        case .none:
            return "尚未选择学校；没有自动推荐依据可展示。"
        }
    }

    private static func rankValueBand(_ value: Double) -> String {
        switch value {
        case 85...:
            return "极强"
        case 70..<85:
            return "强"
        case 50..<70:
            return "中"
        case 30..<50:
            return "弱"
        default:
            return "极弱"
        }
    }

    private static func applicationCountImpactSummary(result: PortfolioResult) -> String {
        guard !result.schoolResults.isEmpty else {
            return "尚未选择学校，无法分析申请数量对组合概率的影响。"
        }

        let marginalRows = marginalAdmissionProbabilityRows(result: result)
        let activeCount = result.schoolResults.filter { $0.adjustedProbability > 0 }.count
        let targetOrLikely = result.selectedBucketCounts.target + result.selectedBucketCounts.likely
        let blocked = result.selectedBucketCounts.blocked
        var lines: [String] = []
        lines.append("当前 \(activeCount) 所学校进入概率合成，全部已选至少一所概率为 \(percent(result.selectedAtLeastOne))。")
        lines.append("边际收益测算：逐个移除当前学校后重算组合概率，衡量该校对“至少一所录取概率”的当前贡献；这不是新增未计算学校的承诺。")
        if let strongest = marginalRows.first {
            lines.append("当前边际贡献最高的是 \(strongest.school.college.name)，约 \(percentagePoints(strongest.delta))；最低的是 \(marginalRows.last.map { "\($0.school.college.name)，约 \(percentagePoints($0.delta))" } ?? "暂无")。")
        }
        let tailRows = marginalRows.suffix(3)
        if !tailRows.isEmpty {
            lines.append("尾部边际贡献：\(tailRows.map { "\($0.school.college.name) \(percentagePoints($0.delta))" }.joined(separator: "；"))。若新增学校质量低于当前尾部，实际收益通常会更有限。")
        }
        if blocked > 0 {
            lines.append("当前有 \(blocked) 所学校被硬门槛阻断；先解决阻断项通常比单纯增加学校更有效。")
        }
        if targetOrLikely == 0 {
            lines.append("当前缺少目标/保底梯度学校；增加 3-5 所更匹配的目标校，通常比继续增加高难度争取校更能提升组合概率。")
        } else if result.selectedBucketCounts.reach > targetOrLikely {
            lines.append("当前争取校数量高于目标/保底校；继续增加申请数量时，优先补目标校和稳健梯度，边际收益会更稳定。")
        } else {
            lines.append("当前已有一定目标/保底结构；若继续增加学校，应优先选择与画像匹配、硬门槛明确通过的学校，同层相关性会让每新增一所的边际收益逐步下降。")
        }
        if activeCount >= 16 {
            lines.append("精力约束：当前申请数量已经很高，继续增加学校容易稀释文书定制、推荐信沟通和面试准备；更优策略通常是替换低边际学校，而不是继续堆数量。")
        } else if activeCount >= 12 {
            lines.append("精力约束：当前已接近常见申请负荷上限；新增学校前应确认能完成高质量补充文书和逐校适配，否则边际收益可能被材料质量下降抵消。")
        } else {
            lines.append("精力约束：申请不是越多越好；在还能保证材料质量的前提下，优先补足目标/保底梯度，比机械增加同层争取校更有效。")
        }
        return lines.joined(separator: "\n")
    }

    private static func marginalAdmissionProbabilityRows(result: PortfolioResult) -> [(school: ChanceResult, delta: Double)] {
        let engine = ChanceEngine()
        let current = result.selectedAtLeastOne
        return result.schoolResults
            .filter { $0.adjustedProbability > 0 }
            .map { school in
                let without = result.schoolResults.filter { $0.college.id != school.college.id }
                let withoutProbability = engine.atLeastOneProbability(without)
                return (school: school, delta: max(0, current - withoutProbability))
            }
            .sorted {
                if $0.delta == $1.delta {
                    return $0.school.adjustedProbability > $1.school.adjustedProbability
                }
                return $0.delta > $1.delta
            }
    }

    private static func percentagePoints(_ value: Double) -> String {
        let points = value * 100
        if points > 0, points < 0.5 {
            return "<0.5 个百分点"
        }
        return "\(points.formatted(.number.precision(.fractionLength(1)))) 个百分点"
    }

    private static func comprehensiveImprovementPlan(result: PortfolioResult) -> String {
        let profile = result.profileSnapshot
        let passed = result.schoolResults.filter(\.gateResult.passed)
        let blocked = result.schoolResults.filter { !$0.gateResult.passed }
        let negativeFactorRows = passed.flatMap(\.factors).filter { $0.value < -0.01 }
        let groupedNegativeFactors = Dictionary(grouping: negativeFactorRows, by: \.label)
        let negativeFactorAverages = groupedNegativeFactors.mapValues { factors in
            let total = factors.reduce(0.0) { $0 + $1.value }
            return total / Double(max(1, factors.count))
        }
        let negativeFactors = negativeFactorAverages
            .sorted { $0.value < $1.value }
            .prefix(4)
            .map { label, value in
                "\(label)（\(impactBand(value))）"
            }
            .joined(separator: "、")
        let factorText = negativeFactors.isEmpty ? "当前没有特别集中的负向因子，重点在材料质量和组合结构。" : "当前负向较明显的路径是：\(negativeFactors)。"

        var immediate: [String] = []
        if !blocked.isEmpty {
            immediate.append("硬门槛：先处理 \(blocked.count) 所阻断学校的 required 标化、英语、作品集或轮次问题；阻断项未解决前，其他提升不会改变这些学校的 0% 结果。")
        }
        if profile.applicantStatus.requiresEnglishProof && profile.toefl == nil && profile.ielts == nil {
            immediate.append("英语证明：补 TOEFL 或 IELTS；这是国际生最典型的硬门槛/材料完整性问题。")
        }
        if !profile.testOptional && profile.sat == nil && profile.act == nil {
            immediate.append("标化口径：决定提交 SAT/ACT 还是明确 Test Optional，避免既无成绩又未选择不提交。")
        }
        if profile.highSchoolID == "unknown" {
            immediate.append("高中背景：补真实高中；当前使用其他/手动评估学校的保守代理，会影响高中背景和强队列校准。")
        }
        if profile.essay < 4 {
            immediate.append("文书主线：先完成一版专业叙事地图，把课程、项目、活动、奖项和未来方向连成同一个申请主题。")
        }
        if immediate.isEmpty {
            immediate.append("材料核查：确认每所学校硬门槛、申请轮次、专业限制和资助策略都与当前 RD 组合一致。")
        }

        var oneToThree: [String] = []
        if profile.activities < 4 || profile.research < 4 || profile.honors < 4 {
            oneToThree.append("证据链补强：围绕 \(profile.major.rawValue) 选择 1-2 个最强项目深挖，补充可验证产出，例如论文/报告/代码/作品集/竞赛结果/社区影响数据。")
        }
        if profile.recommendations < 4 {
            oneToThree.append("推荐信：给推荐老师提供课程表现、项目贡献、困难情境和成长证据清单，让推荐信证明具体能力。")
        }
        if profile.curriculum == .ap && profile.apCourseCount == 0 {
            oneToThree.append("AP 证据：AP 门数为 0 时 AP 平均分不会计入课程体系成绩；应补充真实 AP/高级课程记录或改用更准确课程体系。")
        }
        if profile.curriculum == .alevel && profile.aLevelSubjectCount == 0 {
            oneToThree.append("A-Level 证据：补科目与预测/实考成绩；没有科目数会按缺少课程证据保守处理。")
        }
        if profile.rigor < 4 {
            oneToThree.append("课程难度：能加课则补高阶课程；不能加课时，在材料中解释选课约束，并用高质量项目证明学术挑战度。")
        }
        if oneToThree.isEmpty {
            oneToThree.append("学校适配：逐校改写 Why major / Why school，把同一条专业证据链落到不同学校的课程、研究机会和社区贡献上。")
        }

        var threeToSix: [String] = []
        if academicIndex(profile) < 94 {
            threeToSix.append("成绩趋势：继续提高或稳定核心课成绩，特别是目标专业相关课程；如果总 GPA 难快速改变，要强调最近学期和高阶课程表现。")
        }
        if let sat = submittedSATEquivalent(profile), sat < 1500, !profile.testOptional {
            threeToSix.append("标化提升：若目标校多为 T30/T50，争取把 SAT 等效提升到 1500+；若目标校基准更高，则逐校决定是否提交。")
        }
        if profile.major == .computerScience || profile.major == .engineering || profile.major == .business {
            threeToSix.append("热门专业差异化：用项目深度、真实问题、产出质量和影响力证明不是泛泛“喜欢热门专业”；避免活动列表散而浅。")
        }
        if profile.major == .arts {
            threeToSix.append("艺术方向：作品集质量优先级高于普通学术堆分；需要用作品集、艺术陈述和推荐信形成一致表达。")
        }
        if threeToSix.isEmpty {
            threeToSix.append("维持优势：当前核心硬指标较稳，后续重点是让活动、文书、推荐信与专业方向互相印证。")
        }

        var selection: [String] = []
        if result.selectedBucketCounts.likely == 0 {
            selection.append("保底不足：当前没有 >=60% 的学校；如果家庭需要更稳结果，应增加更低风险学校或扩大 T50/LAC 目标范围。")
        }
        if result.selectedBucketCounts.reach > result.selectedBucketCounts.target + result.selectedBucketCounts.likely {
            selection.append("争取校偏多：继续加校时优先补目标/稳健梯度；同层相关性会让一组高难度学校的边际收益递减。")
        }
        if result.selectionSource == .automatic {
            selection.append("自动推荐：保留单校概率、学校价值和同层边际折扣共同形成的顺位逻辑，不要只按单校概率删改。")
        } else {
            selection.append("手动选校：每新增学校先看是否硬门槛通过、是否与画像匹配、是否与已有学校同层高度相关，再判断边际收益。")
        }

        return """
        诊断：\(factorText)
        0-1 个月优先动作：
        \(numberedLines(immediate))
        1-3 个月提升动作：
        \(numberedLines(oneToThree))
        3-6 个月积累动作：
        \(numberedLines(threeToSix))
        选校组合动作：
        \(numberedLines(selection))
        """
    }

    private static func coreDeficitSummary(result: PortfolioResult) -> String {
        let profile = result.profileSnapshot
        let blocked = result.schoolResults.filter { !$0.gateResult.passed }
        let passed = result.schoolResults.filter(\.gateResult.passed)
        var mustFix: [String] = []
        var probabilityDrag: [String] = []
        var strategyRisks: [String] = []

        if !blocked.isEmpty {
            mustFix.append("硬门槛：已有 \(blocked.count) 所学校被阻断，必须先处理英语、标化、作品集或轮次要求。")
        }
        if profile.applicantStatus.requiresEnglishProof && profile.toefl == nil && profile.ielts == nil {
            mustFix.append("英语证明：未填写 TOEFL/IELTS，会直接影响国际生门槛判断。")
        }
        if !profile.testOptional && profile.sat == nil && profile.act == nil {
            mustFix.append("标化策略：未提交成绩且未选择 Test Optional，短期需要明确。")
        }
        if profile.curriculum == .ap && profile.apCourseCount == 0 {
            probabilityDrag.append("课程证据：AP 门数为 0，AP 平均分不会计入课程体系成绩。")
        }
        if profile.curriculum == .alevel && profile.aLevelSubjectCount == 0 {
            probabilityDrag.append("课程证据：A-Level 科目数为 0，课程体系表现会被保守处理。")
        }
        if profile.rigor < 4 {
            probabilityDrag.append("课程难度：高阶课程证据偏弱，需要用后续成绩、预测分或项目产出补强。")
        }
        if profile.activities < 4 || profile.research < 4 || profile.honors < 4 {
            probabilityDrag.append("专业证据链：活动、科研或奖项还不够集中，需要围绕 \(profile.major.rawValue) 收束。")
        }
        if profile.essay < 4 || profile.recommendations < 4 {
            probabilityDrag.append("材料表达：文书和推荐信需要更具体地证明学术主动性、专业动机和贡献潜力。")
        }
        if profile.highSchoolID == "unknown" {
            probabilityDrag.append("高中背景：当前使用保守代理，建议补真实高中以减少保守处理。")
        }
        if result.selectedBucketCounts.likely == 0 {
            strategyRisks.append("组合结构：没有保底档学校，家庭若需要更稳结果，应补充更低风险选择。")
        }
        if result.selectedBucketCounts.reach > result.selectedBucketCounts.target + result.selectedBucketCounts.likely {
            strategyRisks.append("组合结构：争取校密度偏高，继续加校时优先补目标/稳健梯度。")
        }
        if profile.needsAid && profile.applicantStatus.isInternational {
            strategyRisks.append("资助策略：国际生申请资助会让部分学校风险上升，需要逐校核对政策。")
        }
        if passed.isEmpty && blocked.isEmpty {
            strategyRisks.append("选校结构：尚未形成可分析学校组合。")
        }

        return """
        必须立即处理：
        \(numberedLines(mustFix.isEmpty ? ["当前没有明显硬性阻断，但仍需逐校确认 required 条件。"] : mustFix))
        明显拖累概率：
        \(numberedLines(probabilityDrag.isEmpty ? ["当前主要拖累不集中，重点转向材料表达和选校梯度。"] : probabilityDrag))
        选校与策略风险：
        \(numberedLines(strategyRisks.isEmpty ? ["当前组合风险主要来自学校自然选择性；后续关注同层相关性和边际收益。"] : strategyRisks))
        """
    }

    private static func factorHighlightSummary(result: PortfolioResult) -> String {
        let passed = result.schoolResults.filter(\.gateResult.passed)
        guard !passed.isEmpty else {
            return "当前学校均未进入完整概率计算；优先处理硬门槛。"
        }

        let factorTotals = Dictionary(grouping: passed.flatMap(\.factors), by: \.label)
            .mapValues { factors in factors.reduce(0.0) { $0 + abs($1.value) } / Double(max(1, factors.count)) }
            .sorted { $0.value > $1.value }
            .prefix(5)
        let factorLines = factorTotals.map { "\($0.key)：影响强度\(strengthBand($0.value))" }
        return factorLines.isEmpty ? "当前没有明显主导因素。" : factorLines.joined(separator: "\n")
    }

    private static func gateRuleSummary(_ rule: CollegeGateRule) -> String {
        let source = rule.isOfficial ? "官方" : "推断"
        return "\(source) \(rule.title)：\(rule.detail)"
    }

    private static func sourceAuditSummary(for schoolResults: [ChanceResult]) -> String {
        guard !schoolResults.isEmpty else {
            return "尚未选择学校。"
        }

        return schoolResults.map { result in
            sourceAuditLine(for: result.college)
        }.joined(separator: "\n")
    }

    private static func sourceAuditLine(for college: College) -> String {
        let internationalSignal = AdmissionsSeedData.internationalSignals.first { $0.collegeID == college.id }
        let chinaSignal = AdmissionsSeedData.chinaAdmissionSignals.first { $0.collegeID == college.id }
        let benchmark = AdmissionsSeedData.academicBenchmarks.first { $0.collegeID == college.id }
        let schoolRules = AdmissionsSeedData.gateRules.filter { $0.collegeID == college.id }

        let internationalNote = internationalSignal.map { "\($0.dataScope)：\($0.sourceNote)" } ?? "缺失：当前没有本科国际生代理行。"
        let chinaNote = chinaSignal.map { "\($0.dataScope)：\($0.sourceNote)" } ?? "缺失：当前没有中国本科录取人数行。"
        let benchmarkNote = benchmark.map { "\(benchmarkSourceLabel($0))：\($0.sourceNote)" } ?? "缺失：当前没有学术基准行。"
        let gateNote = schoolRules.isEmpty
            ? "未配置学校专属硬门槛；仍按适用身份/专业检查全局推断门槛。"
            : schoolRules.map(gateSourceAuditSummary).joined(separator: "、")

        return "\(college.name)：基础率 \(college.latestAvailableRate.formatted(.percent.precision(.fractionLength(1))))，\(collegeSourceLabel(college))，\(college.sourceNote)；国际生 \(internationalNote)；中国本科 \(chinaNote)；学术基准 \(benchmarkNote)；硬门槛 \(gateNote)"
    }

    private static func collegeSourceLabel(_ college: College) -> String {
        switch college.category {
        case .nationalUniversity:
            return "AdmissionSight National Universities 表"
        case .liberalArtsCollege:
            if college.sourceURL.absoluteString.hasPrefix("https://collegescorecard.ed.gov/school/?") {
                return "U.S. Department of Education College Scorecard"
            }
            if college.sourceURL.absoluteString.hasPrefix("https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx") {
                return "NCES/IPEDS DataFiles"
            }
            if college.sourceURL.absoluteString.hasPrefix("https://nces.ed.gov/ipeds/reported-data/html/") {
                return "NCES/IPEDS Reported Data Admissions"
            }
            return "已审阅 Top30 Liberal Arts Colleges 用户表"
        }
    }

    private static func gateSourceAuditSummary(_ rule: CollegeGateRule) -> String {
        let status = rule.isOfficial ? "官方" : "推断"
        let url = rule.sourceURL.map { "，来源 \($0.absoluteString)" } ?? ""
        guard rule.type == .round else {
            return "\(rule.title)（\(status)，\(rule.detail)\(url)）"
        }

        let allowed = rule.allowedRounds.isEmpty
            ? "未列"
            : rule.allowedRounds.map(\.rawValue).joined(separator: "/")
        let ea = roundAdjustmentText(rule.earlyActionAdjustment)
        let ed = roundAdjustmentText(rule.earlyDecisionAdjustment)
        return "\(rule.title)（\(status)，\(rule.detail)，允许轮次 \(allowed)，EA加分 \(ea)，ED加分 \(ed)\(url)）"
    }

    private static func roundAdjustmentText(_ value: Double?) -> String {
        value.map { signed($0) } ?? "无明确数据"
    }

    private static func benchmarkSourceLabel(_ benchmark: AcademicBenchmark) -> String {
        if benchmark.isInferred && benchmark.sourceFields.contains(where: { $0.localizedCaseInsensitiveContains("official") }) {
            return "部分官方/部分推断"
        }
        return benchmark.isInferred ? "推断值" : "官方/学校来源"
    }

    private static func warningSummary(result: PortfolioResult) -> String {
        var lines: [String] = []
        lines.append(contentsOf: result.selectionWarnings)
        if result.selectionSource == .automatic {
            lines.append(contentsOf: result.recommendationWarnings)
        }
        for school in result.schoolResults {
            let warnings = unique(school.warnings)
            guard !warnings.isEmpty else {
                continue
            }
            lines.append("\(school.college.name)：\(warnings.joined(separator: "；"))")
        }
        let uniqueLines = unique(lines)
        return uniqueLines.isEmpty ? "未发现额外模型提示。" : uniqueLines.joined(separator: "\n")
    }

    private static func missingInputSummary(profile: StudentProfile, selectedCollegeIDs: Set<String>) -> String {
        let prompts = profile.completionPrompts(selectedCollegeIDs: selectedCollegeIDs)
        guard !prompts.isEmpty else {
            return "当前画像没有明显需要补充的资料。"
        }
        return prompts.map { "\($0.title)（\($0.impact.rawValue)）：\($0.detail)" }.joined(separator: "\n")
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func numberedLines(_ values: [String]) -> String {
        values.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    private static func formatNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private static func gapText(value: Double, unit: String, positiveIsGood: Bool, smallThreshold: Double, largeThreshold: Double) -> String {
        let adjusted = positiveIsGood ? value : -value
        let absolute = abs(value)
        let raw = "\(value >= 0 ? "+" : "")\(formatNumber(value))\(unit)"
        if adjusted >= largeThreshold {
            return "高于基准 \(raw)，属于明显优势。"
        }
        if adjusted >= smallThreshold {
            return "略高于基准 \(raw)，属于小幅优势。"
        }
        if adjusted <= -largeThreshold {
            return "低于基准 \(raw)，是主要差距。"
        }
        if adjusted <= -smallThreshold {
            return "略低于基准 \(raw)，需要在材料中补强。"
        }
        return "与基准接近（差距约 \(formatNumber(absolute))\(unit)）。"
    }

    private static func rankGapText(_ gap: Double) -> String {
        if gap <= -5 {
            return "明显优于本校排名基准，是强优势。"
        }
        if gap <= -2 {
            return "略优于本校排名基准。"
        }
        if gap >= 8 {
            return "明显低于本校排名基准，是重要风险。"
        }
        if gap >= 3 {
            return "略低于本校排名基准，需要用课程难度和专业证据补强。"
        }
        return "与本校排名基准接近。"
    }

    private static func profileLevelText(_ value: Int) -> String {
        switch value {
        case ...1:
            return "明显偏弱"
        case 2:
            return "偏弱"
        case 3:
            return "中等"
        case 4:
            return "较强"
        default:
            return "很强"
        }
    }

    private static func curriculumEvidenceComment(_ profile: StudentProfile) -> String {
        switch profile.curriculum {
        case .ap:
            if profile.apCourseCount == 0 {
                return "AP 门数为 0，AP 平均分不会计入课程体系成绩，是可补资料项。"
            }
            return "AP \(profile.apCourseCount) 门，平均 \(profile.apAverageScore.formatted(.number.precision(.fractionLength(1))))，重点看高阶课程数量与目标专业相关性。"
        case .ib:
            return "IB 预估 \(profile.ibPredictedScore)，重点看 HL 科目是否支撑目标专业。"
        case .alevel:
            let capped = profile.cappedALevelGradeCounts
            if profile.aLevelSubjectCount == 0 {
                return "A-Level 科目数为 0，课程体系成绩按缺少证据保守处理。"
            }
            return "A-Level 按最多 5 门计入：A* \(capped.aStar) 门，A \(capped.a) 门，B \(capped.b) 门。"
        case .chinese:
            return "中国课程体系成绩按所选成绩制折算为内部指数，重点看核心课和目标专业相关课。"
        }
    }

    private static func academicIndex(_ profile: StudentProfile) -> Double {
        gradeScaleScore(
            scale: profile.gradeScale,
            percent: profile.gpaPercent,
            fourPoint: profile.gpaFourPoint,
            fivePoint: profile.gpaFivePoint,
            letterGrade: profile.letterGrade
        )
    }

    private static func curriculumPerformanceIndex(_ profile: StudentProfile) -> Double {
        switch profile.curriculum {
        case .chinese:
            return gradeScaleScore(
                scale: profile.curriculumGradeScale,
                percent: profile.chineseCurriculumScore,
                fourPoint: profile.chineseCurriculumGPAFourPoint,
                fivePoint: profile.chineseCurriculumGPAFivePoint,
                letterGrade: profile.chineseCurriculumLetterGrade
            )
        case .ap:
            guard profile.apCourseCount > 0 else {
                return 0
            }
            let scoreComponent = piecewiseScore(
                profile.apAverageScore,
                points: [(1.0, 12), (2.0, 24), (3.0, 40), (4.0, 58), (4.5, 68), (5.0, 76)]
            )
            let firstFive = min(profile.apCourseCount, 5) * 4
            let nextThree = max(0, min(profile.apCourseCount - 5, 3)) * 2
            let finalTwo = max(0, min(profile.apCourseCount - 8, 2))
            return clamp(scoreComponent + Double(firstFive + nextThree + finalTwo), min: 0, max: 100)
        case .ib:
            return piecewiseScore(
                Double(profile.ibPredictedScore),
                points: [(24, 36), (28, 46), (30, 55), (34, 68), (38, 82), (42, 94), (45, 100)]
            )
        case .alevel:
            let capped = profile.cappedALevelGradeCounts
            let courseCount = capped.aStar + capped.a + capped.b
            let raw = Double(capped.aStar) * 32 + Double(capped.a) * 24 + Double(capped.b) * 14
            let coursePenalty = max(0, 3 - courseCount) * 12
            return clamp(raw - Double(coursePenalty), min: 0, max: 100)
        }
    }

    private static func gradeScaleScore(
        scale: GradeScale,
        percent: Double,
        fourPoint: Double,
        fivePoint: Double,
        letterGrade: LetterGradeBand
    ) -> Double {
        switch scale {
        case .percent:
            return clamp(percent, min: 0, max: 100)
        case .fourPoint:
            return piecewiseScore(
                fourPoint,
                points: [(0, 0), (1.0, 45), (2.0, 70), (2.7, 78), (3.0, 82), (3.3, 87), (3.5, 90), (3.7, 93), (3.9, 97), (4.0, 100)]
            )
        case .fivePoint:
            return piecewiseScore(
                fivePoint,
                points: [(0, 0), (1.0, 40), (2.5, 68), (3.0, 74), (3.5, 80), (3.7, 83), (4.0, 87), (4.2, 90), (4.5, 93), (4.7, 96), (5.0, 100)]
            )
        case .letter:
            switch letterGrade {
            case .aPlus: return 98
            case .a: return 95
            case .aMinus: return 91
            case .bPlus: return 87
            case .b: return 83
            case .bMinus: return 79
            case .cPlus: return 74
            case .c: return 70
            case .d: return 55
            case .f: return 25
            case .cOrBelow: return 60
            }
        }
    }

    private static func submittedSATEquivalent(_ profile: StudentProfile) -> Int? {
        guard !profile.testOptional else {
            return nil
        }
        return [profile.sat, actToSat(profile.act)].compactMap { $0 }.max()
    }

    private static func actToSat(_ act: Int?) -> Int? {
        guard let act else {
            return nil
        }
        let concordance = [
            36: 1590, 35: 1540, 34: 1500, 33: 1460, 32: 1430, 31: 1400,
            30: 1370, 29: 1340, 28: 1310, 27: 1280, 26: 1240, 25: 1210,
            24: 1180, 23: 1140, 22: 1110, 21: 1080, 20: 1040, 19: 1010,
            18: 970, 17: 930, 16: 890, 15: 850, 14: 800, 13: 760,
            12: 710, 11: 670, 10: 630, 9: 590
        ]
        return concordance[act] ?? concordance[min(36, max(9, act))]
    }

    private static func piecewiseScore(_ value: Double, points: [(Double, Double)]) -> Double {
        guard let first = points.first else {
            return 0
        }
        if value <= first.0 {
            return first.1
        }
        for index in 1..<points.count {
            let lower = points[index - 1]
            let upper = points[index]
            if value <= upper.0 {
                let progress = (value - lower.0) / (upper.0 - lower.0)
                return lower.1 + progress * (upper.1 - lower.1)
            }
        }
        return points.last?.1 ?? first.1
    }

    private static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.min(maxValue, Swift.max(minValue, value))
    }

    private static func isTestFreeCollege(_ college: College) -> Bool {
        ["uc_berkeley", "ucla", "ucsd", "uc_davis", "uc_irvine"].contains(college.id)
    }

    private static func highSchoolName(_ id: String) -> String {
        AdmissionsSeedData.highSchools.first { $0.id == id }?.name ?? "其他/手动评估学校"
    }
}
