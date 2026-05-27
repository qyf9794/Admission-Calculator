import SwiftUI

struct ResultsView: View {
    let result: PortfolioResult?
    @ObservedObject var purchaseState: ReportPurchaseState
    let profile: StudentProfile

    var body: some View {
        ScrollView {
            if let result {
                VStack(alignment: .leading, spacing: 16) {
                    SummaryBand(result: result)
                    ApplicantDisclosure(profile: profile)
                    SchoolResultsList(results: result.schoolResults)
                    ReportPanel(result: result, profile: profile, purchaseState: purchaseState)
                }
                .padding()
            } else {
                ContentUnavailableView("尚未计算", systemImage: "chart.bar", description: Text("请先在计算页提交学生画像。"))
            }
        }
    }
}

private struct ApplicantDisclosure: View {
    let profile: StudentProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("申请身份")
                .font(.headline)
            Text(profile.applicantStatus.rawValue)
                .font(.subheadline.weight(.medium))
            Text(profile.applicantStatus.isInternational
                 ? "国际生修正只使用本科口径；中国籍申请者会使用普通申请池先验和中国学生本科录取容量约束，缺少申请人数分母时不会计算精确中国录取率。"
                 : "当前身份不使用国际生代理修正，英语硬门槛也不会作为国际生要求触发。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SummaryBand: View {
    let result: PortfolioResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("至少一所录取概率")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCell(title: "T10", value: result.t10AtLeastOne)
                MetricCell(title: "T30", value: result.t30AtLeastOne)
                MetricCell(title: "T50", value: result.t50AtLeastOne)
                MetricCell(title: "当前组合", value: result.selectedAtLeastOne)
            }
            Text("组合来源：\(result.selectionSource.rawValue)。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("组合结构：保底 \(result.selectedBucketCounts.likely) 所，目标 \(result.selectedBucketCounts.target) 所，争取 \(result.selectedBucketCounts.reach) 所，硬门槛未满足 \(result.selectedBucketCounts.blocked) 所。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(result.recommendationWarnings, id: \.self) { warning in
                Label(warning, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("画像分 \(Int(result.profileScore))/100。T10/T30/T50 仅统计当前组合内学校，多校概率已使用同层相关性折扣。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MetricCell: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.formatted(.percent.precision(.fractionLength(0))))
                .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SchoolResultsList: View {
    let results: [ChanceResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("逐校结果")
                .font(.headline)
            if results.isEmpty {
                ContentUnavailableView("尚未选择学校", systemImage: "building.columns", description: Text("请在计算页手选学校，或点击自动推荐组合。"))
                    .frame(maxWidth: .infinity)
            }
            ForEach(results) { result in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading) {
                            Text(result.college.name)
                                .font(.headline)
                            Text("#\(result.college.rank) · \(result.college.tierName) · 置信度 \(result.confidence.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(result.adjustedProbability.formatted(.percent.precision(.fractionLength(0))))
                            .font(.title3.weight(.bold))
                    }
                    Text(result.bucket.rawValue)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(bucketColor(result.bucket).opacity(0.16), in: Capsule())
                        .foregroundStyle(bucketColor(result.bucket))

                    if !result.gateResult.failedRules.isEmpty {
                        Label(result.gateResult.failedRules.map(\.title).joined(separator: "、"), systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    DisclosureGroup("影响因素") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(result.factors) { factor in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(factor.label)
                                        Spacer()
                                        Text(factorValue(factor))
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.caption.weight(.medium))
                                    Text(factor.detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    .font(.footnote)
                    ForEach(result.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func factorValue(_ factor: ChanceFactor) -> String {
        if factor.label == "学校基础率" || factor.label == "普通申请池先验" {
            return factor.value.formatted(.percent.precision(.fractionLength(1)))
        }
        let sign = factor.value >= 0 ? "+" : ""
        return "\(sign)\(factor.value.formatted(.number.precision(.fractionLength(2))))"
    }

    private func bucketColor(_ bucket: RecommendationBucket) -> Color {
        switch bucket {
        case .reach: .orange
        case .target: .blue
        case .likely: .green
        case .blocked: .red
        }
    }
}

private struct ReportPanel: View {
    let result: PortfolioResult
    let profile: StudentProfile
    @ObservedObject var purchaseState: ReportPurchaseState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI 综合报告")
                .font(.headline)
            if purchaseState.isUnlocked {
                Text(ReportService.makeReport(profile: profile, result: result))
                    .font(.callout)
                    .textSelection(.enabled)
            } else {
                Text("报告会解释选校策略、硬门槛、概率与提升建议。AI 只能解释结果，不能改写概率。")
                    .foregroundStyle(.secondary)
                Button {
                    purchaseState.unlockForPrototype()
                } label: {
                    Label("解锁报告预览", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
