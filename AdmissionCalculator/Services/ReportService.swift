import Foundation
import StoreKit

@MainActor
final class ReportPurchaseState: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var statusText = "综合报告未解锁"

    let productID = "admission_calculator_ai_report"

    func unlockForPrototype() {
        isUnlocked = true
        statusText = "已解锁报告预览"
    }
}

enum GateRuleDisplay {
    static func failureSummary(_ rule: CollegeGateRule) -> String {
        let source = rule.isOfficial ? "官方" : "推断"
        let url = rule.sourceURL.map { " 来源：\($0.absoluteString)" } ?? ""
        return "\(source) \(rule.title)：\(rule.detail)\(url)"
    }
}

enum ReportService {
    static func makeReport(result: PortfolioResult) -> String {
        let profile = result.profileSnapshot
        let blocked = result.schoolResults.filter { !$0.gateResult.passed }
        let schoolResults = result.schoolResults
        let probabilities = schoolResults.isEmpty
            ? "尚未选择学校。"
            : schoolResults.map { "\($0.college.name)：\(Self.percent($0.adjustedProbability))（\($0.bucket.rawValue)，置信度 \($0.confidence.rawValue)）" }.joined(separator: "\n")
        let academicFit = schoolResults.isEmpty ? "尚未选择学校。" : schoolResults.map { school in
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
        let missingInputNotes = missingInputSummary(profile: profile, selectedCollegeIDs: result.selectedCollegeIDs)
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

        画像摘要：\(profile.applicantStatus.rawValue)，\(profile.curriculum.rawValue) 课程，目标专业 \(profile.major.rawValue)，申请轮次 \(profile.round.rawValue)，高中背景 \(highSchoolName(profile.highSchoolID))。总体画像分 \(Int(result.profileScore))/100；逐校概率会按学校政策重算标化影响。

        当前组合内至少一所录取概率：
        T10：\(percent(result.t10AtLeastOne))
        T30：\(percent(result.t30AtLeastOne))
        T50：\(percent(result.t50AtLeastOne))
        当前组合：\(percent(result.selectedAtLeastOne))

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

    private static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
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
        return prompts.map { "\($0.title)：\($0.detail)" }.joined(separator: "\n")
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func highSchoolName(_ id: String) -> String {
        AdmissionsSeedData.highSchools.first { $0.id == id }?.name ?? "其他/手动评估学校"
    }
}
