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
    - 不得修改、重算、覆盖或美化输入中的概率、分档、置信度、硬门槛、来源审计和警告。
    - 不得承诺录取，不得把估算称为预测或保证。
    - 必须明确所有概率都是估算；组合概率是“当前选择学校中至少被一所录取”的概率。
    - 必须披露国际生、中国学生、本科口径、推断基准、缺少分母和数据质量限制。
    - 不得添加输入中没有的学校；不得建议学生申请数据范围外学校作为本报告计算的一部分。
    - 用中文输出，结构清晰，面向中国高中生家庭，语气务实、细致、可执行。
    """

    static func makeReport(result: PortfolioResult) -> String {
        let profile = result.profileSnapshot
        let blocked = result.schoolResults.filter { !$0.gateResult.passed }
        let schoolResults = result.schoolResults
        let probabilities = schoolResults.isEmpty
            ? "尚未选择学校。"
            : schoolResults.map { "\($0.college.name)：\(Self.percent($0.adjustedProbability))（\($0.bucket.rawValue)，置信度 \($0.confidence.rawValue)）" }.joined(separator: "\n")
        let academicFit = schoolResults.isEmpty ? "尚未选择学校。" : schoolResults.map { school in
            guard school.gateResult.passed else {
                return "\(school.college.name)：硬门槛未通过，未进入目标校学术匹配计算。"
            }
            let factor = school.factors.first { $0.label == "目标校学术匹配" }
            let value = factor.map { Self.signed($0.value) } ?? "缺失"
            return "\(school.college.name)：\(value)"
        }.joined(separator: "\n")
        let gates = blocked.isEmpty
            ? "未发现已选学校的硬门槛失败项。"
            : blocked.map { "\($0.college.name)：\($0.gateResult.failedRules.map(Self.gateRuleSummary).joined(separator: "；"))" }.joined(separator: "\n")
        let sourceAudit = sourceAuditSummary(for: schoolResults)
        let selectionNotes = result.selectionWarnings.isEmpty
            ? "当前组合内学校均来自 v1 数据集。"
            : result.selectionWarnings.joined(separator: "\n")
        let missingInputNotes = missingInputSummary(profile: profile, selectedCollegeIDs: result.calculatedCollegeIDs)
        let recommendationNotes: String
        switch result.selectionSource {
        case .automatic:
            recommendationNotes = result.recommendationWarnings.isEmpty
                ? "自动推荐三档数量可满足当前请求。"
                : result.recommendationWarnings.joined(separator: "\n")
        case .manual:
            recommendationNotes = "当前为手动选校，未触发自动推荐缺口判断。"
        case .none:
            recommendationNotes = "尚未选择学校，未触发自动推荐。"
        }
        let warningNotes = warningSummary(result: result)
        return """
        综合选校报告

        生成时间：\(generatedAtText(result.generatedAt))
        快照说明：本报告只解释该次提交的学生画像和选校组合；后续修改表单或选校后需要重新计算。

        画像摘要：\(profile.applicantStatus.rawValue)，\(profile.curriculum.rawValue) 课程，目标专业 \(profile.major.rawValue)，申请轮次 \(profile.round.rawValue)，高中背景 \(highSchoolName(profile.highSchoolID))。总体画像分 \(Int(result.profileScore))/100；逐校概率会按学校政策重算标化影响。

        当前选择学校中至少被一所录取的估算概率：
        综合大学 T10 至少一所（当前组合 \(tierCount(in: result, maxRank: 10)) 所）：\(percent(result.t10AtLeastOne))
        综合大学 T30 至少一所（当前组合 \(tierCount(in: result, maxRank: 30)) 所）：\(percent(result.t30AtLeastOne))
        综合大学 T50 至少一所（当前组合 \(tierCount(in: result, maxRank: 50)) 所）：\(percent(result.t50AtLeastOne))
        全部已选至少一所（\(result.schoolResults.count) 所）：\(percent(result.selectedAtLeastOne))

        当前组合结构：
        来源：\(result.selectionSource.rawValue)。
        保底 \(result.selectedBucketCounts.likely) 所，目标 \(result.selectedBucketCounts.target) 所，争取 \(result.selectedBucketCounts.reach) 所，硬门槛未满足 \(result.selectedBucketCounts.blocked) 所。
        分档规则：争取 <20%，目标 20%-60%，保底 >=60%；保底是相对规划标签，不代表录取保证。
        \(selectionNotes)

        待补资料：
        \(missingInputNotes)

        自动推荐提示：
        \(recommendationNotes)

        逐校重点：
        \(probabilities)

        学术匹配修正：
        \(academicFit)

        硬门槛：
        \(gates)

        数据限制与警告：
        \(warningNotes)

        逐校数据来源审计：
        \(sourceAudit)

        建议：
        1. 先补齐所有 required 标化、英语或作品集门槛，再优化概率。
        2. 对低概率但未被阻断的学校，先看 GPA/排名/标化/课程难度是否低于目标校基准，再决定是补学术、换梯度，还是加强专业叙事。
        3. 国际生和中国学生数据只使用本科口径；中国录取人数缺少申请人数分母时，作为普通申请池先验、容量约束和趋势信号，不计算精确中国录取率。
        4. 目标校学术基准若标记为推断值，不应当视作官方录取均值。
        5. 该报告只解释计算结果，不改变概率，也不承诺录取。
        """
    }

    static func makeOpenAIReportPrompt(result: PortfolioResult) -> String {
        """
        请根据以下已计算结果生成一份付费版详细选校报告。报告必须包含这些章节：
        全文必须遵守：不得修改、重算、覆盖或美化输入中的概率、分档、置信度、硬门槛、来源审计和警告；不得承诺录取；不得添加输入中没有的学校。

        1. 执行摘要
        - 用 3-5 条说明当前申请组合的整体风险、最重要阻断项、最优先提升方向。
        - 明确“全部已选至少一所”概率不是单校录取概率，也不是录取承诺。

        2. 测算结果总览
        - 原样列出综合大学 T10/T30/T50/全部已选的至少一所概率。
        - 解释组合概率已使用同层相关性折扣，不能把所有学校当作完全独立事件相乘。

        3. 逐校概率与风险表
        - 每所学校单独一行或一段，必须包含：学校名、排名层级、单校概率、分档、置信度、硬门槛是否通过、主要正向因素、主要负向因素、数据限制。
        - 被硬门槛阻断的学校必须说明为什么是 0%，并列出失败规则。

        4. 差距分析
        - 分析 GPA/排名/标化/课程难度/课程体系成绩/活动/科研/奖项/文书/推荐信/高中背景/专业竞争/轮次/资助需求分别如何影响结果。
        - 对推断学术基准要明确说“不是官方录取均值”。

        5. 提高概率的努力方向
        - 给出按优先级排序的行动清单，分为 0-1 个月、1-3 个月、3-6 个月。
        - 每条行动必须说明会影响哪个模型路径：硬门槛、学术匹配、画像分、专业竞争、数据置信度、选校结构。

        6. 选校组合策略
        - 基于当前保底/目标/争取/阻断结构，给出是否需要增加目标校、降低争取校密度、处理保底不足等建议。
        - 强调“保底”只是规划标签，不代表保证。

        7. 数据来源与可信度
        - 汇总来源审计、缺失数据、推断代理、中国本科录取人数缺少申请人数分母等限制。
        - 说明哪些信息需要用户或顾问继续补充核验。

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

    private static func tierCount(in result: PortfolioResult, maxRank: Int) -> Int {
        result.schoolResults.filter { $0.college.rank <= maxRank }.count
    }

    private static func signed(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(2))))"
    }

    private static func gateRuleSummary(_ rule: CollegeGateRule) -> String {
        GateRuleDisplay.failureSummary(rule)
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

        return "\(college.name)：录取率 \(college.latestAvailableClassYear) 届，AdmissionSight National Universities 表；国际生 \(internationalNote)；中国本科 \(chinaNote)；学术基准 \(benchmarkNote)；硬门槛 \(gateNote)"
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
        return uniqueLines.isEmpty ? "未发现额外数据限制或模型警告。" : uniqueLines.joined(separator: "\n")
    }

    private static func missingInputSummary(profile: StudentProfile, selectedCollegeIDs: Set<String>) -> String {
        let prompts = profile.completionPrompts(selectedCollegeIDs: selectedCollegeIDs)
        guard !prompts.isEmpty else {
            return "当前画像没有明显缺失项；仍需逐校查看数据置信度、硬门槛和来源审计。"
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
