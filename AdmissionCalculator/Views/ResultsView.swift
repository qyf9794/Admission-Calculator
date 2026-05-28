import SwiftUI

struct ResultsView: View {
    let result: PortfolioResult?
    let isStale: Bool
    @State private var showingDataSources = false

    var body: some View {
        ScrollView {
            if let result {
                VStack(alignment: .leading, spacing: 16) {
                    ResultsHero(result: result)
                    if isStale {
                        Label("当前结果基于上一次提交的画像或选校；请回到计算页重新计算后再用于决策。", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                    SummaryBand(result: result)
                    MissingInputCard(
                        prompts: result.profileSnapshot.completionPrompts(selectedCollegeIDs: result.calculatedCollegeIDs)
                    )
                    DataExplanationLink {
                        showingDataSources = true
                    }
                }
                .padding()
            } else {
                ContentUnavailableView("尚未计算", systemImage: "chart.bar", description: Text("请先在计算页提交学生画像。"))
            }
        }
        .sheet(isPresented: $showingDataSources) {
            NavigationStack {
                DataSourcesView()
                    .navigationTitle("数据与模型说明")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") {
                                showingDataSources = false
                            }
                        }
                    }
            }
        }
    }
}

private struct ResultsHero: View {
    let result: PortfolioResult

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.07, green: 0.13, blue: 0.27)
            HStack(alignment: .bottom, spacing: 8) {
                ResultBar(color: .green, count: result.selectedBucketCounts.likely, height: 78)
                ResultBar(color: .blue, count: result.selectedBucketCounts.target, height: 112)
                ResultBar(color: .orange, count: result.selectedBucketCounts.reach, height: 94)
                ResultBar(color: .red, count: result.selectedBucketCounts.blocked, height: 54)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .opacity(0.72)
            .padding(.trailing, 18)

            VStack(alignment: .leading, spacing: 14) {
                Label("\(result.selectionSource.rawValue) · \(result.profileSnapshot.round.rawValue) 轮次", systemImage: "chart.bar.xaxis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text(result.selectedAtLeastOne.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(result.profileSnapshot.round.rawValue) 轮次当前学校中，至少被一所录取的估算概率")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("这是本轮次组合的至少一所概率，不混合其他轮次，不是单校概率或录取承诺。逐校概率请到报告页查看。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
                Text("生成时间 \(result.generatedAt.formatted(date: .numeric, time: .shortened)) · 基于提交快照")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.74))
                HStack(spacing: 10) {
                    HeroMetric(title: "学校", value: "\(result.schoolResults.count)")
                    HeroMetric(title: "阻断", value: "\(result.selectedBucketCounts.blocked)")
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 270)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ResultBar: View {
    let color: Color
    let count: Int
    let height: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 24, height: min(150, max(24, height + CGFloat(count * 8))))
        }
    }
}

private struct HeroMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(minWidth: 56, alignment: .leading)
    }
}

private struct MissingInputCard: View {
    let prompts: [ProfileCompletionPrompt]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(prompts.isEmpty ? "待补资料已清空" : "待补资料清单", systemImage: prompts.isEmpty ? "checkmark.seal.fill" : "square.and.pencil")
                .font(.headline)
                .foregroundStyle(prompts.isEmpty ? .green : .orange)
            if prompts.isEmpty {
                Text("当前画像没有明显需要补充的资料。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("以下信息会影响硬门槛、画像分、自动推荐或选校策略；补齐后请重新计算。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(prompts) { prompt in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prompt.impact.rawValue)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(promptImpactColor(prompt.impact).opacity(0.14), in: Capsule())
                                .foregroundStyle(promptImpactColor(prompt.impact))
                            Text(prompt.title)
                                .font(.subheadline.weight(.semibold))
                            Text(prompt.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: prompt.systemImage)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((prompts.isEmpty ? Color.green : Color.orange).opacity(0.18), lineWidth: 1)
        )
    }

    private func promptImpactColor(_ impact: ProfileCompletionImpact) -> Color {
        switch impact {
        case .gate:
            return .red
        case .probability:
            return .blue
        case .confidence:
            return .blue
        case .portfolio:
            return .purple
        }
    }
}

private struct SummaryBand: View {
    let result: PortfolioResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("至少一所录取概率概览", systemImage: "chart.pie.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            Text("本次结果仅针对 \(result.profileSnapshot.round.rawValue) 轮次；未开放该轮次的学校不会进入计算。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCell(title: "综大T10", value: result.t10AtLeastOne, count: tierCount(category: .nationalUniversity, maxRank: 10), tint: .purple)
                MetricCell(title: "综大T11-T30", value: result.t11T30AtLeastOne, count: tierCount(category: .nationalUniversity, minRankExclusive: 10, maxRank: 30), tint: .blue)
                MetricCell(title: "综大T30", value: result.t30AtLeastOne, count: tierCount(category: .nationalUniversity, maxRank: 30), tint: .indigo)
                MetricCell(title: "综大T50", value: result.t50AtLeastOne, count: tierCount(category: .nationalUniversity, maxRank: 50), tint: .teal)
                MetricCell(title: "文理T10", value: result.liberalArtsT10AtLeastOne, count: tierCount(category: .liberalArtsCollege, maxRank: 10), tint: .pink)
                MetricCell(title: "文理T30", value: result.liberalArtsT30AtLeastOne, count: tierCount(category: .liberalArtsCollege, maxRank: 30), tint: .orange)
                MetricCell(title: "全部已选", value: result.selectedAtLeastOne, count: result.schoolResults.count, tint: .green)
            }
            ForEach(result.selectionWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Text("组合结构：保底 \(result.selectedBucketCounts.likely) 所，目标 \(result.selectedBucketCounts.target) 所，争取 \(result.selectedBucketCounts.reach) 所，硬门槛未满足 \(result.selectedBucketCounts.blocked) 所。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.16), lineWidth: 1)
        )
    }

    private func tierCount(category: CollegeCategory, minRankExclusive: Int = 0, maxRank: Int) -> Int {
        result.schoolResults.filter { $0.college.category == category && $0.college.rank > minRankExclusive && $0.college.rank <= maxRank }.count
    }
}

private struct MetricCell: View {
    let title: String
    let value: Double
    let count: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.formatted(.percent.precision(.fractionLength(0))))
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
            Text(count == 0 ? "未包含该层级" : "当前组合 \(count) 所")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct DataExplanationLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("查看数据与模型说明", systemImage: "info.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
