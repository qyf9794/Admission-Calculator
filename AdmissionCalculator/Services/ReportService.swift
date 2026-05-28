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

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 OPENAI_API_KEY。Debug 环境可通过 Scheme 环境变量配置；正式上架应改由服务端代理调用 OpenAI。"
        case .invalidResponse:
            return "OpenAI 返回格式无法解析。"
        case .requestFailed(let detail):
            return detail
        }
    }
}

struct OpenAIReportClient {
    var model = "gpt-5.2"
    var apiKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
    var session: URLSession = .shared

    func generateReport(prompt: String) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else {
            throw OpenAIReportError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenAIResponseRequest(
            model: model,
            instructions: ReportService.openAIInstructions,
            input: prompt,
            reasoning: OpenAIReasoning(effort: "low"),
            text: OpenAITextOptions(verbosity: "high")
        ))

        let (data, response) = try await session.data(for: request)
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
    - 报告重点必须放在用户有用的申请策略上，不展开系统缺失数据、来源审计或置信度说明。
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
        let probabilities = schoolResults.isEmpty
            ? "尚未选择学校。"
            : schoolResults.map { "\($0.college.name)：\(Self.percent($0.adjustedProbability))（\($0.bucket.rawValue)）" }.joined(separator: "\n")
        let academicFit = schoolResults.isEmpty ? "尚未选择学校。" : schoolResults.map { school in
            academicFitSummary(for: school)
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

        画像摘要：\(profile.applicantStatus.rawValue)，\(profile.curriculum.rawValue) 课程，目标专业 \(profile.major.rawValue)，申请轮次 \(profile.round.rawValue)，高中背景 \(highSchoolName(profile.highSchoolID))。总体画像分 \(Int(result.profileScore))/100；逐校概率会按学校政策重算标化影响。

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

        提高申请数量对概率的影响：
        \(applicationCountImpact)

        自动推荐提示：
        \(recommendationNotes)

        自动推荐依据：
        \(recommendationStrategySummary(result: result))

        逐校重点：
        \(probabilities)

        逐校差距与优势：
        \(academicFit)

        目前影响概率较大的因素：
        \(factorHighlights)

        硬门槛：
        \(gates)

        建议：
        1. 先补齐所有 required 标化、英语或作品集门槛，再优化概率。
        2. 对低概率但未被阻断的学校，先看 GPA/排名/标化/课程难度是否低于目标校基准，再决定是补学术、换梯度，还是加强专业叙事。
        3. 若组合概率主要受申请数量限制，可优先增加同梯度目标校，而不是只增加极高难度学校。
        4. 若组合中阻断学校较多，先解决硬门槛，再增加学校数量。
        5. 该报告只解释计算结果，不改变概率，也不承诺录取。
        """
    }

    static func makeOpenAIReportPrompt(result: PortfolioResult) -> String {
        guard result.profileSnapshot.round == .regularDecision else {
            return makeReport(result: result)
        }
        return """
        请根据以下已计算结果生成一份付费版详细选校报告。报告必须包含这些章节：
        全文必须遵守：不得修改、重算、覆盖或美化输入中的概率、分档和硬门槛；不得承诺录取；不得添加输入中没有的学校；不要展开系统缺失数据、来源审计或置信度说明。

        1. 执行摘要
        - 用 3-5 条说明当前申请组合的整体风险、最重要阻断项、最优先提升方向。
        - 明确“全部已选至少一所”概率不是单校录取概率，也不是录取承诺。

        2. 测算结果总览
        - 原样列出综合大学 T10/T11-T30/T30/T50、文理学院 T10/T30、全部已选的至少一所概率。
        - 解释组合概率已使用同层相关性折扣，不能把所有学校当作完全独立事件相乘；综合大学 T10 与文理学院 T10 共享同一个极端选择性相关性层。

        3. 逐校概率与风险表
        - 每所学校单独一行或一段，必须包含：学校名、排名层级、单校概率、分档、硬门槛是否通过、主要正向因素、主要负向因素。
        - 被硬门槛阻断的学校必须说明为什么是 0%，并列出失败规则。

        4. 差距分析
        - 分析 GPA/排名/标化/课程难度/课程体系成绩/活动/科研/奖项/文书/推荐信/高中背景/专业竞争/轮次/资助需求分别如何影响结果。
        - 对比学生画像与目标校中位水平或内部基准，明确优势和差距。

        5. 提高概率的努力方向
        - 给出按优先级排序的行动清单，分为 0-1 个月、1-3 个月、3-6 个月。
        - 每条行动必须说明会影响哪个模型路径：硬门槛、学术匹配、画像分、专业竞争、选校结构。

        6. 选校组合策略
        - 基于当前保底/目标/争取/阻断结构，给出是否需要增加目标校、降低争取校密度、处理保底不足等建议。
        - 必须说明提高申请数量对“至少一所录取概率”的影响：增加相近梯度学校通常比只增加极高难度学校更有效；同时提醒同层相关性会让边际收益递减。
        - 若组合来自自动推荐，必须解释自动推荐按“单校概率 × 排名价值分 × 同层相关性边际折扣”筛选，并用“预期最佳录取结果价值”处理多 offer 不重复计值；不是只按录取概率排序。
        - 若输入中包含自动推荐顺位，必须引用组合最佳录取期望值，并逐项引用顺位、排名价值分、概率×排名价值、同层折扣和边际期望值；不得重新排序或重算。
        - 强调“保底”只是规划标签，不代表保证。

        7. 申请数量情景分析
        - 基于当前组合结构，说明如果增加 3 所、5 所、8 所同梯度或更低风险学校，组合概率的方向性变化和边际收益。
        - 不要自行发明未计算学校的精确概率；可以给方向性策略。

        8. 家庭沟通版结论
        - 用清楚、克制的语言总结可执行策略，避免制造焦虑或确定性承诺。

        以下是离线概率引擎的原始报告数据，必须作为唯一事实来源：

        \(makeReport(result: result))
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
        return "\(school.college.name)：学术匹配 \(signed(factor.value))。\(direction) \(userFacingAcademicDetail(factor.detail))"
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
                    return "第\(step.order)顺位 \(school.college.name)：单校概率 \(percent(school.adjustedProbability))，排名价值分 \(step.rankScore.formatted(.number.precision(.fractionLength(0))))/100，概率×排名价值 \(step.baseExpectedValue.formatted(.number.precision(.fractionLength(2))))，同层边际折扣 \(step.sameTierDiscount.formatted(.percent.precision(.fractionLength(0))))，边际期望值 \(step.marginalExpectedValue.formatted(.number.precision(.fractionLength(2))))。"
                }.joined(separator: "\n")
                return """
                自动推荐先排除硬门槛失败学校，再按单校概率 × 排名价值分计算基础期望值，并在推荐价值中加入同层相关性边际折扣；文理学院 T10 的排名价值对齐到综合大学 T20-T30 价值带，而不是综合大学 T10 价值带。综合大学 T10 与文理学院 T10 共享同一个极端选择性相关性层，不会因为学校类别不同而被当作完全独立。为保证手机端响应速度，请求数量较小且组合总空间仍在较小上限内时才确定性穷举；组合空间较大时采用有界快速近似。组合层面按“若获得多个录取，通常选择最高价值 offer”估算预期最佳录取结果价值，并把每所新增学校的同层折扣固定为入选时的边际贡献，避免把多个 offer 的排名价值简单相加。组合最佳录取期望值使用 0-100 排名价值尺度，不是录取概率，也不是至少一所概率。以下为按当前画像快照确定的入选顺序：
                组合最佳录取期望值：\(result.recommendationExpectedValueTotal.formatted(.number.precision(.fractionLength(2)))) / 100 排名价值尺度。
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
                    let expectedValue = engine.recommendationExpectedValue(for: school)
                    return "\(school.college.name)：单校概率 \(percent(school.adjustedProbability))，排名价值分 \(rankScore.formatted(.number.precision(.fractionLength(0))))/100，概率×排名价值 \(expectedValue.formatted(.number.precision(.fractionLength(2))))。"
                }
                .joined(separator: "\n")
            return """
            当前组合标记为自动推荐，但学校集合与按当前画像快照重新生成的自动推荐不完全一致；以下仅解释当前入选学校的基础期望值。自动推荐本身会按单校概率 × 排名价值分，并加入同层相关性边际折扣；这里的期望值是 0-100 排名价值尺度，不是录取概率：
            \(lines)
            """
        case .manual:
            return "当前为手动选校；报告仍展示逐校概率和组合概率，但没有自动推荐期望值排序。"
        case .none:
            return "尚未选择学校；没有自动推荐依据可展示。"
        }
    }

    private static func applicationCountImpactSummary(result: PortfolioResult) -> String {
        guard !result.schoolResults.isEmpty else {
            return "尚未选择学校，无法分析申请数量对组合概率的影响。"
        }

        let activeCount = result.schoolResults.filter { $0.adjustedProbability > 0 }.count
        let targetOrLikely = result.selectedBucketCounts.target + result.selectedBucketCounts.likely
        let blocked = result.selectedBucketCounts.blocked
        var lines: [String] = []
        lines.append("当前 \(activeCount) 所学校进入概率合成，全部已选至少一所概率为 \(percent(result.selectedAtLeastOne))。")
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
        return lines.joined(separator: "\n")
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
        let factorLines = factorTotals.map { "\($0.key)：平均影响强度 \($0.value.formatted(.number.precision(.fractionLength(2))))" }
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

    private static func highSchoolName(_ id: String) -> String {
        AdmissionsSeedData.highSchools.first { $0.id == id }?.name ?? "其他/手动评估学校"
    }
}
