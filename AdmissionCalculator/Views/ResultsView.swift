import SwiftUI

struct ResultsView: View {
    let result: PortfolioResult?
    let isStale: Bool
    let hasCompletedInitialAnimation: Bool
    let onInitialAnimationCompleted: () -> Void
    let onBackToSchools: () -> Void
    let onAnalyze: () -> Void
    @State private var revealedResultCount = 0
    @State private var settledResultIDs: Set<String> = []
    @State private var showAnalyzeButton = false
    @State private var swipeCommand: AdmissionCardSwipeCommand?

    private let resultRevealIDs: Set<String> = ["top10", "top11to30", "top30", "top50", "total"]

    var body: some View {
        ZStack {
            AdmissionPageBackground()
            if let result {
                AdmissionSwipeableCard(
                    swipeCommand: $swipeCommand,
                    canSwipeBack: true,
                    canSwipeForward: showAnalyzeButton && !isStale,
                    onSwipeBack: onBackToSchools,
                    onSwipeForward: onAnalyze,
                    previousPreview: {
                        SchoolListSnapshotCard(result: result)
                    },
                    nextPreview: {
                        if showAnalyzeButton && !isStale {
                            AdmissionPreviewCard(
                                title: "分析报告",
                                subtitle: "进入报告页查看逐校差距和提升建议。",
                                systemImage: "doc.text.magnifyingglass",
                                colors: AdmissionStyle.pinkMist
                            )
                        }
                    }
                ) {
                    resultContent(result)
                }
                .padding(16)
                .task(id: "\(result.generatedAt.timeIntervalSinceReferenceDate)-\(hasCompletedInitialAnimation)") {
                    await revealResultsInOrder()
                }
            } else {
                ContentUnavailableView("尚未计算", systemImage: "chart.bar", description: Text("请先在计算页提交学生画像。"))
            }
        }
    }

    @ViewBuilder
    private func resultContent(_ result: PortfolioResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if isStale {
                Label("当前结果基于上一次提交的画像或选校；请回到计算页重新计算后再用于决策。", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous))
            }

            ResultRevealCard(
                title: "Total",
                subtitle: "全部已选至少一所",
                value: result.selectedAtLeastOne,
                colors: AdmissionStyle.blackGlass,
                countText: "\(result.schoolResults.count) 所学校",
                isRevealed: revealedResultCount >= 5,
                animatesValue: !hasCompletedInitialAnimation,
                fontSize: 64,
                onSettled: { markResultSettled("total") }
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ResultRevealCard(
                    title: "Top10",
                    subtitle: "综大 T10 至少一所",
                    value: result.t10AtLeastOne,
                    colors: [Color.purple.opacity(0.94), Color.black.opacity(0.82)],
                    countText: "\(tierCount(in: result, maxRank: 10)) 所",
                    isRevealed: revealedResultCount >= 1,
                    animatesValue: !hasCompletedInitialAnimation,
                    fontSize: 30,
                    onSettled: { markResultSettled("top10") }
                )
                ResultRevealCard(
                    title: "T11-T30",
                    subtitle: "综大 T11-T30 至少一所",
                    value: result.t11T30AtLeastOne,
                    colors: [Color.indigo.opacity(0.94), Color.black.opacity(0.82)],
                    countText: "\(tierCount(in: result, minRankExclusive: 10, maxRank: 30)) 所",
                    isRevealed: revealedResultCount >= 2,
                    animatesValue: !hasCompletedInitialAnimation,
                    fontSize: 30,
                    onSettled: { markResultSettled("top11to30") }
                )
                ResultRevealCard(
                    title: "Top30",
                    subtitle: "综大 T30 至少一所",
                    value: result.t30AtLeastOne,
                    colors: [Color.blue.opacity(0.94), Color.black.opacity(0.82)],
                    countText: "\(tierCount(in: result, maxRank: 30)) 所",
                    isRevealed: revealedResultCount >= 3,
                    animatesValue: !hasCompletedInitialAnimation,
                    fontSize: 30,
                    onSettled: { markResultSettled("top30") }
                )
                ResultRevealCard(
                    title: "Top50",
                    subtitle: "综大 T50 至少一所",
                    value: result.t50AtLeastOne,
                    colors: [Color.teal.opacity(0.94), Color.black.opacity(0.82)],
                    countText: "\(tierCount(in: result, maxRank: 50)) 所",
                    isRevealed: revealedResultCount >= 4,
                    animatesValue: !hasCompletedInitialAnimation,
                    fontSize: 30,
                    onSettled: { markResultSettled("top50") }
                )
            }

            Spacer(minLength: 6)

            if showAnalyzeButton && !isStale {
                Button(action: { requestSwipe(.forward) }) {
                    Label("分析结果", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AdmissionSoftButtonStyle(colors: AdmissionStyle.pinkMist))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Text("估算结果用于申请规划，不代表录取承诺。逐校概率与具体建议会在付费报告中显示。")
                .font(.caption)
                .foregroundStyle(Color.black.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor
    private func revealResultsInOrder() async {
        if hasCompletedInitialAnimation {
            revealedResultCount = 5
            settledResultIDs = resultRevealIDs
            showAnalyzeButton = true
            return
        }

        revealedResultCount = 0
        settledResultIDs = []
        showAnalyzeButton = false
        for nextCount in 1...5 {
            try? await Task.sleep(nanoseconds: nextCount == 1 ? 260_000_000 : 1_250_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                revealedResultCount = nextCount
            }
        }
    }

    @MainActor
    private func markResultSettled(_ id: String) {
        guard resultRevealIDs.contains(id) else {
            return
        }
        settledResultIDs.insert(id)
        guard settledResultIDs == resultRevealIDs, !showAnalyzeButton else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard settledResultIDs == resultRevealIDs else {
                return
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                showAnalyzeButton = true
            }
            onInitialAnimationCompleted()
        }
    }

    private func tierCount(in result: PortfolioResult, minRankExclusive: Int = 0, maxRank: Int) -> Int {
        result.schoolResults.filter { $0.college.category == .nationalUniversity && $0.college.rank > minRankExclusive && $0.college.rank <= maxRank }.count
    }

    private func requestSwipe(_ direction: AdmissionCardSwipeDirection) {
        swipeCommand = AdmissionCardSwipeCommand(direction: direction)
    }
}

struct SchoolListSnapshotCard: View {
    let result: PortfolioResult

    var body: some View {
        AdmissionGradientCard(
            title: "学校列表",
            subtitle: "列表按 U.S. News 排名排列；未选学校可点击加入，已选学校保持选中。",
            systemImage: "building.columns",
            colors: AdmissionStyle.softGray,
            foreground: AdmissionStyle.darkTextPrimary,
            secondary: AdmissionStyle.darkTextSecondary
        ) {
            HStack(spacing: 8) {
                Label("已选学校", systemImage: "checkmark.seal")
                    .font(.subheadline.weight(.semibold))
                Text("\(result.schoolResults.count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.22), in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                LinearGradient(colors: [Color.green, .black.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule()
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 1))

            if result.schoolResults.isEmpty {
                Text("尚未选择学校。")
                    .font(.caption)
                    .foregroundStyle(AdmissionStyle.darkTextSecondary)
            } else {
                ForEach(Array(result.schoolResults.prefix(5).enumerated()), id: \.element.college.id) { index, schoolResult in
                    SchoolListSnapshotRow(index: index + 1, result: schoolResult)
                }
                if result.schoolResults.count > 5 {
                    Text("另有 \(result.schoolResults.count - 5) 所学校。")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AdmissionStyle.darkTextSecondary)
                }
            }
        }
    }
}

private struct SchoolListSnapshotRow: View {
    let index: Int
    let result: ChanceResult

    private var rankAndBucketText: String {
        "#\(result.college.rank) · \(result.bucket.rawValue)"
    }

    private var probabilityText: String {
        result.adjustedProbability.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.caption.weight(.black))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.14), in: Circle())
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.college.name)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(rankAndBucketText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer()

            Text(probabilityText)
                .font(.headline.monospacedDigit().weight(.black))
        }
        .padding(10)
        .background(
            LinearGradient(colors: [tierColor.opacity(0.98), Color.black.opacity(0.76)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .foregroundStyle(.white)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        )
    }

    private var tierColor: Color {
        switch result.college.rank {
        case ...10:
            return .purple
        case 11...30:
            return .blue
        case 31...50:
            return .teal
        default:
            return .secondary
        }
    }
}

struct ResultsSnapshotCard: View {
    let result: PortfolioResult
    var onStartOver: (() -> Void)? = nil
    var showsSubtitle = true

    var body: some View {
        AdmissionGradientCard(
            title: "概率计算结果",
            subtitle: showsSubtitle ? "上一页组合概率快照；结果基于提交时的画像和选校。" : nil,
            systemImage: "chart.bar.xaxis",
            colors: AdmissionStyle.blackGlass
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(result.selectedAtLeastOne.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 4) {
                    Text("全部已选至少一所")
                        .font(.headline.weight(.bold))
                    Text("\(result.schoolResults.count) 所学校 · \(result.selectionSource.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                SnapshotMetric(title: "Top10", value: result.t10AtLeastOne)
                SnapshotMetric(title: "T11-T30", value: result.t11T30AtLeastOne)
                SnapshotMetric(title: "Top30", value: result.t30AtLeastOne)
                SnapshotMetric(title: "Top50", value: result.t50AtLeastOne)
            }

        }
        .overlay(alignment: .topTrailing) {
            if let onStartOver {
                Button(action: onStartOver) {
                    Text("重新开始")
                }
                .buttonStyle(AdmissionSoftButtonStyle(colors: AdmissionStyle.pinkMist))
                .controlSize(.large)
                .padding(.top, 14)
                .padding(.trailing, 14)
            }
        }
    }
}

struct ResultsFixedSnapshotContent: View {
    let result: PortfolioResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResultRevealCard(
                title: "Total",
                subtitle: "全部已选至少一所",
                value: result.selectedAtLeastOne,
                colors: AdmissionStyle.blackGlass,
                countText: "\(result.schoolResults.count) 所学校",
                isRevealed: true,
                animatesValue: false,
                fontSize: 64,
                onSettled: {}
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ResultRevealCard(
                    title: "Top10",
                    subtitle: "综大 T10 至少一所",
                    value: result.t10AtLeastOne,
                    colors: [Color.purple.opacity(0.94), Color.black.opacity(0.82)],
                    countText: "\(tierCount(in: result, maxRank: 10)) 所",
                    isRevealed: true,
                    animatesValue: false,
                    fontSize: 30,
                    onSettled: {}
                )
                ResultRevealCard(
                    title: "T11-T30",
                    subtitle: "综大 T11-T30 至少一所",
                    value: result.t11T30AtLeastOne,
                    colors: [Color.indigo.opacity(0.94), Color.black.opacity(0.82)],
                    countText: "\(tierCount(in: result, minRankExclusive: 10, maxRank: 30)) 所",
                    isRevealed: true,
                    animatesValue: false,
                    fontSize: 30,
                    onSettled: {}
                )
                ResultRevealCard(
                    title: "Top30",
                    subtitle: "综大 T30 至少一所",
                    value: result.t30AtLeastOne,
                    colors: [Color.blue.opacity(0.94), Color.black.opacity(0.82)],
                    countText: "\(tierCount(in: result, maxRank: 30)) 所",
                    isRevealed: true,
                    animatesValue: false,
                    fontSize: 30,
                    onSettled: {}
                )
                ResultRevealCard(
                    title: "Top50",
                    subtitle: "综大 T50 至少一所",
                    value: result.t50AtLeastOne,
                    colors: [Color.teal.opacity(0.94), Color.black.opacity(0.82)],
                    countText: "\(tierCount(in: result, maxRank: 50)) 所",
                    isRevealed: true,
                    animatesValue: false,
                    fontSize: 30,
                    onSettled: {}
                )
            }

            Text("估算结果用于申请规划，不代表录取承诺。逐校概率与具体建议会在付费报告中显示。")
                .font(.caption)
                .foregroundStyle(Color.black.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tierCount(in result: PortfolioResult, minRankExclusive: Int = 0, maxRank: Int) -> Int {
        result.schoolResults.filter { $0.college.category == .nationalUniversity && $0.college.rank > minRankExclusive && $0.college.rank <= maxRank }.count
    }
}

private struct SnapshotMetric: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.66))
            Text(value.formatted(.percent.precision(.fractionLength(0))))
                .font(.headline.monospacedDigit().weight(.black))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ResultRevealCard: View {
    let title: String
    let subtitle: String
    let value: Double
    let colors: [Color]
    let countText: String
    let isRevealed: Bool
    let animatesValue: Bool
    let fontSize: CGFloat
    let onSettled: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(fontSize > 40 ? .title : .headline, design: .rounded).weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            if isRevealed {
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(2)
                if animatesValue {
                    AdmissionAnimatedPercentText(
                        value: value,
                        font: .system(size: fontSize, weight: .black, design: .rounded),
                        foreground: .white,
                        finalLabel: countText,
                        onSettled: onSettled
                    )
                } else {
                    StaticResultPercentText(
                        value: value,
                        countText: countText,
                        fontSize: fontSize
                    )
                }
            } else {
                Spacer(minLength: fontSize > 40 ? 80 : 42)
            }
        }
        .frame(maxWidth: .infinity, minHeight: fontSize > 40 ? 210 : 170, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }
}

private struct StaticResultPercentText: View {
    let value: Double
    let countText: String
    let fontSize: CGFloat

    private var percentText: String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(percentText)
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(countText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.70))
        }
    }
}

private struct ResultsHero: View {
    let result: PortfolioResult

    var body: some View {
        AdmissionHeroCard(colors: AdmissionStyle.blackGlass) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Label("\(result.selectionSource.rawValue) · \(result.profileSnapshot.round.rawValue) 轮次", systemImage: "chart.bar.xaxis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer(minLength: 8)
                    ResultBarsSummary(counts: result.selectedBucketCounts)
                }
                AdmissionProbabilityCard(
                    title: "全部已选",
                    subtitle: "至少一所录取估算",
                    value: result.selectedAtLeastOne,
                    colors: [Color.green.opacity(0.92), Color.black.opacity(0.84)],
                    countText: "当前组合 \(result.schoolResults.count) 所",
                    delayIndex: 0,
                    symbolName: "sparkles",
                    fontSize: 52
                )
                Text("\(result.profileSnapshot.round.rawValue) 轮次当前学校中，至少被一所录取的估算概率")
                    .font(AdmissionStyle.sectionFont())
                    .foregroundStyle(.white)
                Text("这是本轮次组合的至少一所概率，不混合其他轮次，不是单校概率或录取承诺。逐校概率请到报告页查看。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
                Text("生成时间 \(result.generatedAt.formatted(date: .numeric, time: .shortened)) · 基于提交快照")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.74))
                HStack(spacing: 10) {
                    AdmissionMetricPill(title: "学校", value: "\(result.schoolResults.count)")
                    AdmissionMetricPill(title: "阻断", value: "\(result.selectedBucketCounts.blocked)")
                }
            }
        }
    }
}

private struct ResultBarsSummary: View {
    let counts: PortfolioBucketCounts

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ResultBar(color: .green, count: counts.likely, height: 26)
            ResultBar(color: .blue, count: counts.target, height: 40)
            ResultBar(color: .orange, count: counts.reach, height: 34)
            ResultBar(color: .red, count: counts.blocked, height: 22)
        }
        .padding(8)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ResultBar: View {
    let color: Color
    let count: Int
    let height: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 12, height: min(56, max(14, height + CGFloat(count * 3))))
        }
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
                    .foregroundStyle(.white.opacity(0.70))
            } else {
                Text("以下信息会影响硬门槛、画像分、自动推荐或选校策略；补齐后请重新计算。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.70))
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
                                .foregroundStyle(.white.opacity(0.70))
                        }
                    } icon: {
                        Image(systemName: prompt.systemImage)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .admissionSmallCard(colors: prompts.isEmpty ? AdmissionStyle.mintNight : AdmissionStyle.citrus)
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
        AdmissionGradientCard(
            title: "至少一所录取概率概览",
            subtitle: "本次结果仅针对 \(result.profileSnapshot.round.rawValue) 轮次；未开放该轮次的学校不会进入计算。",
            systemImage: "chart.pie.fill",
            colors: AdmissionStyle.lilac
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCell(title: "综大T10", value: result.t10AtLeastOne, count: tierCount(category: .nationalUniversity, maxRank: 10), tint: .purple, delayIndex: 1)
                MetricCell(title: "综大T11-T30", value: result.t11T30AtLeastOne, count: tierCount(category: .nationalUniversity, minRankExclusive: 10, maxRank: 30), tint: .blue, delayIndex: 2)
                MetricCell(title: "综大T30", value: result.t30AtLeastOne, count: tierCount(category: .nationalUniversity, maxRank: 30), tint: .indigo, delayIndex: 3)
                MetricCell(title: "综大T50", value: result.t50AtLeastOne, count: tierCount(category: .nationalUniversity, maxRank: 50), tint: .teal, delayIndex: 4)
                MetricCell(title: "文理T10", value: result.liberalArtsT10AtLeastOne, count: tierCount(category: .liberalArtsCollege, maxRank: 10), tint: .pink, delayIndex: 5)
                MetricCell(title: "文理T30", value: result.liberalArtsT30AtLeastOne, count: tierCount(category: .liberalArtsCollege, maxRank: 30), tint: .orange, delayIndex: 6)
                MetricCell(title: "全部已选", value: result.selectedAtLeastOne, count: result.schoolResults.count, tint: .green, delayIndex: 7)
            }
            ForEach(result.selectionWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Text("组合结构：保底 \(result.selectedBucketCounts.likely) 所，目标 \(result.selectedBucketCounts.target) 所，争取 \(result.selectedBucketCounts.reach) 所，硬门槛未满足 \(result.selectedBucketCounts.blocked) 所。")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.76))
        }
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
    let delayIndex: Int

    var body: some View {
        AdmissionProbabilityCard(
            title: title,
            subtitle: "单项概率生成",
            value: value,
            colors: cellColors,
            countText: count == 0 ? "未包含该层级" : "当前组合 \(count) 所",
            delayIndex: delayIndex,
            symbolName: count == 0 ? "minus.circle" : "chart.line.uptrend.xyaxis",
            fontSize: 30
        )
    }

    private var cellColors: [Color] {
        [tint.opacity(0.95), Color.black.opacity(0.82)]
    }
}

private struct DataExplanationLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("查看数据与模型说明", systemImage: "info.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AdmissionQuietButtonStyle())
    }
}
