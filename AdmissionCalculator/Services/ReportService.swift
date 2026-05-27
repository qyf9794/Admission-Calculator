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

enum ReportService {
    static func makeReport(result: PortfolioResult) -> String {
        let profile = result.profileSnapshot
        let blocked = result.schoolResults.filter { !$0.gateResult.passed }
        let top = result.schoolResults.prefix(5)
        let probabilities = top.map { "\($0.college.name)：\(Self.percent($0.adjustedProbability))（\($0.bucket.rawValue)）" }.joined(separator: "\n")
        let academicFit = top.map { school in
            let factor = school.factors.first { $0.label == "目标校学术匹配" }
            let value = factor.map { Self.signed($0.value) } ?? "缺失"
            return "\(school.college.name)：\(value)"
        }.joined(separator: "\n")
        let gates = blocked.isEmpty
            ? "未发现已选学校的硬门槛失败项。"
            : blocked.map { "\($0.college.name)：\($0.gateResult.failedRules.map(\.title).joined(separator: "、"))" }.joined(separator: "\n")
        let recommendationNotes = result.recommendationWarnings.isEmpty
            ? "自动推荐三档数量可满足当前请求。"
            : result.recommendationWarnings.joined(separator: "\n")
        return """
        综合选校报告

        画像摘要：\(profile.applicantStatus.rawValue)，\(profile.curriculum.rawValue) 课程，目标专业 \(profile.major.rawValue)，申请轮次 \(profile.round.rawValue)。模型画像分 \(Int(result.profileScore))/100。

        当前组合内至少一所录取概率：
        T10：\(percent(result.t10AtLeastOne))
        T30：\(percent(result.t30AtLeastOne))
        T50：\(percent(result.t50AtLeastOne))
        当前组合：\(percent(result.selectedAtLeastOne))

        当前组合结构：
        来源：\(result.selectionSource.rawValue)。
        保底 \(result.selectedBucketCounts.likely) 所，目标 \(result.selectedBucketCounts.target) 所，争取 \(result.selectedBucketCounts.reach) 所，硬门槛未满足 \(result.selectedBucketCounts.blocked) 所。

        自动推荐提示：
        \(recommendationNotes)

        逐校重点：
        \(probabilities)

        学术匹配修正：
        \(academicFit)

        硬门槛：
        \(gates)

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
}
