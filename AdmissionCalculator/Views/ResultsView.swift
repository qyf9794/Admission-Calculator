import SwiftUI

struct ResultsView: View {
    let result: PortfolioResult?
    @ObservedObject var purchaseState: ReportPurchaseState
    let isStale: Bool

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
                    ResultPriorityCard(result: result)
                    ApplicantDisclosure(profile: result.profileSnapshot)
                    MissingInputCard(
                        prompts: result.profileSnapshot.completionPrompts(selectedCollegeIDs: result.selectedCollegeIDs)
                    )
                    SchoolResultsList(
                        results: result.schoolResults,
                        selectionSource: result.selectionSource,
                        recommendationWarnings: result.recommendationWarnings
                    )
                    ReportPanel(result: result, purchaseState: purchaseState)
                }
                .padding()
            } else {
                ContentUnavailableView("尚未计算", systemImage: "chart.bar", description: Text("请先在计算页提交学生画像。"))
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
                Label(result.selectionSource.rawValue, systemImage: "chart.bar.xaxis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text(result.selectedAtLeastOne.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("当前组合至少一所录取估算")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("这是用于规划的区间判断，不是录取承诺；硬门槛、置信度和数据来源仍需逐校查看。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    HeroMetric(title: "学校", value: "\(result.schoolResults.count)")
                    HeroMetric(title: "阻断", value: "\(result.selectedBucketCounts.blocked)")
                    HeroMetric(title: "画像", value: "\(Int(result.profileScore))")
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

private struct ApplicantDisclosure: View {
    let profile: StudentProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("申请身份", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
                .foregroundStyle(.indigo)
            Text(profile.applicantStatus.rawValue)
                .font(.title3.weight(.semibold))
            Text(profile.applicantStatus.isInternational
                 ? "国际生修正只使用本科口径；中国籍申请者会使用普通申请池先验和中国学生本科录取容量约束，缺少申请人数分母时不会计算精确中国录取率。"
                 : "当前身份不使用国际生代理修正，英语硬门槛也不会作为国际生要求触发。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.indigo.opacity(0.16), lineWidth: 1)
        )
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
                Text("当前已选组合和学生画像没有明显缺失项；仍需逐校查看数据置信度、硬门槛和来源审计。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("以下信息会影响硬门槛、画像分、自动推荐或置信度；补齐后请重新计算。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(prompts) { prompt in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
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
}

private struct SummaryBand: View {
    let result: PortfolioResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("组合概率概览", systemImage: "chart.pie.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCell(title: "T10", value: result.t10AtLeastOne, count: tierCount(maxRank: 10), tint: .purple)
                MetricCell(title: "T30", value: result.t30AtLeastOne, count: tierCount(maxRank: 30), tint: .blue)
                MetricCell(title: "T50", value: result.t50AtLeastOne, count: tierCount(maxRank: 50), tint: .teal)
                MetricCell(title: "当前组合", value: result.selectedAtLeastOne, count: result.schoolResults.count, tint: .green)
            }
            Text("组合来源：\(result.selectionSource.rawValue)。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(result.selectionWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Text("组合结构：保底 \(result.selectedBucketCounts.likely) 所，目标 \(result.selectedBucketCounts.target) 所，争取 \(result.selectedBucketCounts.reach) 所，硬门槛未满足 \(result.selectedBucketCounts.blocked) 所。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("分档规则：争取 <20%，目标 20%-60%，保底 >=60%。保底是相对规划标签，不代表录取保证。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(result.recommendationWarnings, id: \.self) { warning in
                Label(warning, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("总体画像分 \(Int(result.profileScore))/100；逐校概率会按学校政策重算标化影响。T10/T30/T50 仅统计当前组合内学校，多校概率已使用同层相关性折扣。")
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

    private func tierCount(maxRank: Int) -> Int {
        result.schoolResults.filter { $0.college.rank <= maxRank }.count
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

private struct ResultPriorityCard: View {
    let result: PortfolioResult

    private var actions: [PriorityAction] {
        var items: [PriorityAction] = []
        if result.selectedBucketCounts.blocked > 0 {
            items.append(PriorityAction(
                title: "先处理硬门槛",
                detail: "\(result.selectedBucketCounts.blocked) 所学校当前被硬门槛阻断，补齐 required 标化、英语、轮次或作品集后再看概率。",
                systemImage: "exclamationmark.triangle.fill",
                color: .red
            ))
        }

        let lowConfidenceCount = result.schoolResults.filter { $0.confidence == .low }.count
        if lowConfidenceCount > 0 {
            items.append(PriorityAction(
                title: "复核低置信度学校",
                detail: "\(lowConfidenceCount) 所学校数据缺口较大，优先核对官方 CDS、class profile 或国际生本科数据。",
                systemImage: "questionmark.diamond.fill",
                color: .orange
            ))
        }

        let prompts = result.profileSnapshot.completionPrompts(selectedCollegeIDs: result.selectedCollegeIDs)
        if let prompt = prompts.first {
            items.append(PriorityAction(
                title: prompt.title,
                detail: prompt.detail,
                systemImage: prompt.systemImage,
                color: .blue
            ))
        }

        if result.selectionSource == .automatic, let warning = result.recommendationWarnings.first {
            items.append(PriorityAction(
                title: "调整自动推荐数量",
                detail: warning,
                systemImage: "slider.horizontal.3",
                color: .purple
            ))
        }

        if items.isEmpty {
            items.append(PriorityAction(
                title: "可以进入逐校复核",
                detail: "当前组合没有优先级更高的阻断项；下一步看学术匹配、置信度和来源审计。",
                systemImage: "checkmark.seal.fill",
                color: .green
            ))
        }
        return Array(items.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("下一步优先级", systemImage: "flag.checkered")
                .font(.headline)
                .foregroundStyle(.orange)
            ForEach(actions) { action in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.subheadline.weight(.semibold))
                        Text(action.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: action.systemImage)
                        .foregroundStyle(action.color)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct PriorityAction: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
}

private struct SchoolResultsList: View {
    let results: [ChanceResult]
    let selectionSource: PortfolioSelectionSource
    let recommendationWarnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("逐校结果", systemImage: "building.2.crop.circle")
                .font(.headline)
                .foregroundStyle(.indigo)
            if results.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySystemImage, description: Text(emptyDescription))
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
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(result.gateResult.failedRules) { rule in
                                Label(GateRuleDisplay.failureSummary(rule), systemImage: "exclamationmark.triangle.fill")
                            }
                        }
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
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(bucketColor(result.bucket))
                        .frame(width: 5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var emptyTitle: String {
        switch selectionSource {
        case .automatic:
            return "自动推荐暂无可用学校"
        case .manual, .none:
            return "尚未选择学校"
        }
    }

    private var emptySystemImage: String {
        selectionSource == .automatic ? "wand.and.stars.inverse" : "building.columns"
    }

    private var emptyDescription: String {
        switch selectionSource {
        case .automatic:
            if recommendationWarnings.isEmpty {
                return "当前自动推荐没有生成学校；请调整三档数量、学生画像，或改为手动选校。"
            }
            return recommendationWarnings.joined(separator: " ")
        case .manual:
            return "手动组合当前为空；请回到计算页选择学校后重新计算。"
        case .none:
            return "请在计算页手选学校，或点击自动推荐组合。"
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
    @ObservedObject var purchaseState: ReportPurchaseState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI 综合报告", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
                .foregroundStyle(.purple)
            if purchaseState.isUnlocked {
                Text(ReportService.makeReport(result: result))
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
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.16), lineWidth: 1)
        )
    }
}
