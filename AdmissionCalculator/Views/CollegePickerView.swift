import SwiftUI

struct CollegePickerView: View {
    static let lastCardIndex = 1

    let initialCardIndex: Int
    @Binding var profile: StudentProfile
    @Binding var selectedCollegeIDs: Set<String>
    @Binding var selectionSource: PortfolioSelectionSource
    let includeLiberalArtsColleges: Bool
    let applicationRound: ApplicationRound
    @Binding var requestedSchoolCount: Int
    let currentResult: PortfolioResult?
    let completedSchoolSetupAnimationIDs: Set<String>
    let completedAutomaticSummaryAnimationIDs: Set<String>
    let onSchoolSetupAnimationCompleted: (String) -> Void
    let onAutomaticSummaryAnimationCompleted: (String) -> Void
    let onAutoRecommend: () -> Void
    let onBackToProfile: () -> Void
    let onShowExistingResults: () -> Void
    let onEvaluate: () -> Void
    @State private var searchText = ""
    @State private var filter: CollegePickerFilter = .selected
    @State private var cardIndex = 0
    @State private var swipeCommand: AdmissionCardSwipeCommand?
    @State private var hasAppliedInitialCardIndex = false
    private let colleges = AdmissionsSeedData.colleges
    private let cardCount = 2

    private var availableColleges: [College] {
        colleges.filter { college in
            (includeLiberalArtsColleges || college.category != .liberalArtsCollege) &&
                allowsCurrentRound(college)
        }
        .sorted(by: collegeRankSort)
    }

    private var filteredColleges: [College] {
        availableColleges.filter { college in
            filter.includes(college: college, selectedIDs: selectedCollegeIDs) &&
            college.matchesPickerQuery(searchText)
        }
    }

    var body: some View {
        ZStack {
            AdmissionPageBackground()
            VStack(spacing: 14) {
                SchoolSelectionHeader(
                    selectedCount: selectedCollegeIDs.count,
                    showsEvaluateButton: cardIndex == cardCount - 1,
                    canEvaluate: !selectedCollegeIDs.isEmpty,
                    onEvaluate: onEvaluate
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)

                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Spacer(minLength: 0)
                            AdmissionSwipeableCard(
                                swipeCommand: $swipeCommand,
                                canSwipeBack: true,
                                canSwipeForward: cardIndex < cardCount - 1 || canSwipeForwardToResults,
                                onSwipeBack: {
                                    if cardIndex > 0 {
                                        moveCard(by: -1)
                                    } else {
                                        onBackToProfile()
                                    }
                                },
                                onSwipeForward: {
                                    if cardIndex < cardCount - 1 {
                                        moveCard(by: 1)
                                    } else if canSwipeForwardToResults {
                                        onShowExistingResults()
                                    }
                                },
                                previousPreview: {
                                    if cardIndex > 0 {
                                        selectionCard(at: cardIndex - 1)
                                    } else {
                                        ProfileSelectionSettingsCard(
                                            profile: $profile,
                                            fixedHeight: CalculatorView.profileCardHeight,
                                            completedAutomaticSummaryAnimationIDs: completedAutomaticSummaryAnimationIDs,
                                            onAutomaticSummaryAnimationCompleted: onAutomaticSummaryAnimationCompleted
                                        )
                                    }
                                },
                                nextPreview: {
                                    if cardIndex < cardCount - 1 {
                                        selectionCard(at: cardIndex + 1)
                                    } else if let currentResult {
                                        ResultsFixedSnapshotContent(result: currentResult)
                                    }
                                }
                            ) {
                                selectionCard(at: cardIndex)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: proxy.size.height, alignment: .center)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索学校、排名或分层")

                CardNavigationBar(
                    currentIndex: cardIndex,
                    totalCount: cardCount,
                    canGoBack: true,
                    canGoForward: cardIndex < cardCount - 1 || canSwipeForwardToResults,
                    back: { requestCardSwipe(.back) },
                    forward: { requestCardSwipe(.forward) }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .onAppear {
            applyInitialCardIndexIfNeeded()
        }
    }

    private var selectedColleges: [College] {
        availableColleges.filter { selectedCollegeIDs.contains($0.id) }
    }

    private var canSwipeForwardToResults: Bool {
        currentResult != nil && !selectedCollegeIDs.isEmpty
    }

    @ViewBuilder
    private func selectionCard(at index: Int) -> some View {
        if index == 0 {
            SchoolSetupCard(
                selectedCount: selectedCollegeIDs.count,
                selectedColleges: selectedColleges,
                requestedSchoolCount: $requestedSchoolCount,
                includeLiberalArtsColleges: includeLiberalArtsColleges,
                applicationRound: applicationRound,
                hasCompletedCountAnimation: completedSchoolSetupAnimationIDs.contains(
                    SchoolSetupCard.animationID(
                        selectedCount: selectedCollegeIDs.count,
                        selectedColleges: selectedColleges,
                        includeLiberalArtsColleges: includeLiberalArtsColleges,
                        applicationRound: applicationRound
                    )
                ),
                onCountAnimationCompleted: onSchoolSetupAnimationCompleted,
                onAutoRecommend: {
                    onAutoRecommend()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        filter = .selected
                    }
                }
            )
        } else {
            AdmissionGradientCard(
                title: "学校列表",
                subtitle: "列表按 U.S. News 排名排列；未选学校可点击加入，其他标签页中的已选学校可取消。",
                systemImage: "building.columns",
                colors: AdmissionStyle.softGray,
                foreground: AdmissionStyle.darkTextPrimary,
                secondary: AdmissionStyle.darkTextSecondary
            ) {
                CollegeFilterBar(
                    filter: $filter,
                    colleges: availableColleges,
                    selectedIDs: selectedCollegeIDs,
                    includeLiberalArtsColleges: includeLiberalArtsColleges
                )

                if filteredColleges.isEmpty {
                    ContentUnavailableView("没有匹配学校", systemImage: "magnifyingglass", description: Text("调整搜索词、筛选范围或申请轮次。"))
                }

                ForEach(filteredColleges) { college in
                    CollegeSelectionCard(
                        college: college,
                        chanceResult: currentResult?.schoolResults.first { $0.college.id == college.id },
                        isSelected: selectedCollegeIDs.contains(college.id),
                        allowsRemoval: filter != .selected,
                        select: { select(college.id) },
                        remove: { remove(college.id) }
                    )
                }
            }
        }
    }

    private func moveCard(by delta: Int) {
        cardIndex = min(max(cardIndex + delta, 0), cardCount - 1)
    }

    private func applyInitialCardIndexIfNeeded() {
        guard !hasAppliedInitialCardIndex else {
            return
        }
        cardIndex = min(max(initialCardIndex, 0), cardCount - 1)
        hasAppliedInitialCardIndex = true
    }

    private func requestCardSwipe(_ direction: AdmissionCardSwipeDirection) {
        swipeCommand = AdmissionCardSwipeCommand(direction: direction)
    }

    private func collegeRankSort(_ lhs: College, _ rhs: College) -> Bool {
        if lhs.rank != rhs.rank {
            return lhs.rank < rhs.rank
        }
        if lhs.category != rhs.category {
            return lhs.category == .nationalUniversity
        }
        return lhs.name < rhs.name
    }

    private func allowsCurrentRound(_ college: College) -> Bool {
        let rules = AdmissionsSeedData.gateRules.filter { $0.collegeID == college.id && $0.type == .round }
        guard !rules.isEmpty else {
            return applicationRound == .regularDecision
        }
        return rules.contains { rule in
            if !rule.allowedRounds.isEmpty {
                return rule.allowedRounds.contains(applicationRound)
            }
            if let requiredRound = rule.requiredRound {
                return requiredRound == applicationRound
            }
            return applicationRound == .regularDecision
        }
    }

    private func select(_ id: String) {
        guard !selectedCollegeIDs.contains(id) else {
            return
        }
        if applicationRound == .earlyDecision {
            selectedCollegeIDs = Set([id])
        } else {
            selectedCollegeIDs.insert(id)
        }
        selectionSource = selectedCollegeIDs.isEmpty ? .none : .manual
    }

    private func remove(_ id: String) {
        guard selectedCollegeIDs.contains(id) else {
            return
        }
        selectedCollegeIDs.remove(id)
        selectionSource = selectedCollegeIDs.isEmpty ? .none : .manual
    }
}

private enum CollegePickerFilter: String, CaseIterable, Identifiable {
    case selected = "已选学校"
    case all = "全部学校"
    case nationalUniversities = "只看综合大学"
    case liberalArtsColleges = "只看文理学院"

    var id: String { rawValue }

    static func availableCases(includeLiberalArtsColleges: Bool) -> [CollegePickerFilter] {
        let base: [CollegePickerFilter] = [.selected, .all, .nationalUniversities]
        guard includeLiberalArtsColleges else {
            return base
        }
        return base + [.liberalArtsColleges]
    }

    var systemImage: String {
        switch self {
        case .selected:
            return "checkmark.seal"
        case .all:
            return "square.grid.2x2"
        case .nationalUniversities:
            return "building.columns"
        case .liberalArtsColleges:
            return "graduationcap"
        }
    }

    var tint: Color {
        switch self {
        case .selected:
            return .green
        case .all:
            return .indigo
        case .nationalUniversities:
            return .blue
        case .liberalArtsColleges:
            return .orange
        }
    }

    func includes(college: College, selectedIDs: Set<String>) -> Bool {
        switch self {
        case .selected:
            return selectedIDs.contains(college.id)
        case .all:
            return true
        case .nationalUniversities:
            return college.category == .nationalUniversity
        case .liberalArtsColleges:
            return college.category == .liberalArtsCollege
        }
    }
}

private struct SchoolSelectionHeader: View {
    let selectedCount: Int
    let showsEvaluateButton: Bool
    let canEvaluate: Bool
    let onEvaluate: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(selectedCount)")
                .font(.system(size: 42, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.black.opacity(0.88))
            Text("所已选")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Color.black.opacity(0.56))
            Spacer()
            if showsEvaluateButton {
                Button(action: onEvaluate) {
                    Label("开始计算概率", systemImage: "function")
                }
                .buttonStyle(AdmissionSoftButtonStyle(colors: canEvaluate ? AdmissionStyle.blackGlass : [Color.gray.opacity(0.58), Color.gray.opacity(0.32)]))
                .disabled(!canEvaluate)
                .opacity(canEvaluate ? 1 : 0.58)
            }
        }
    }
}

struct SchoolSetupCard: View {
    let selectedCount: Int
    let selectedColleges: [College]
    @Binding var requestedSchoolCount: Int
    let includeLiberalArtsColleges: Bool
    let applicationRound: ApplicationRound
    let hasCompletedCountAnimation: Bool
    let onCountAnimationCompleted: (String) -> Void
    let onAutoRecommend: () -> Void

    @State private var showsSelectionNotes = false

    static func animationID(
        selectedCount: Int,
        selectedColleges: [College],
        includeLiberalArtsColleges: Bool,
        applicationRound: ApplicationRound
    ) -> String {
        let selectedIDs = selectedColleges.map(\.id).joined(separator: ",")
        return "\(selectedCount)-\(includeLiberalArtsColleges)-\(applicationRound.rawValue)-\(selectedIDs)"
    }

    private var selectionResetID: String {
        Self.animationID(
            selectedCount: selectedCount,
            selectedColleges: selectedColleges,
            includeLiberalArtsColleges: includeLiberalArtsColleges,
            applicationRound: applicationRound
        )
    }

    var body: some View {
        AdmissionGradientCard(
            title: "选校设置",
            subtitle: applicationRound == .earlyDecision ? "ED/ED2 是绑定申请；同一轮只保留 1 所。" : "先确定拟选数量，也可以让系统按当前画像自动推荐。",
            systemImage: "rectangle.stack.badge.plus",
            colors: AdmissionStyle.lilac
        ) {
            VStack(alignment: .leading, spacing: 8) {
                AdmissionAnimatedCountText(
                    value: selectedCount,
                    font: .system(size: 58, weight: .black, design: .rounded),
                    foreground: .white,
                    animates: !hasCompletedCountAnimation,
                    onSettled: {
                        withAnimation(.easeOut(duration: 0.28)) {
                            showsSelectionNotes = true
                        }
                        onCountAnimationCompleted(selectionResetID)
                    }
                )
                .id(selectionResetID)
                if showsSelectionNotes {
                    Text("已选学校数量")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.78))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            UnboundedCountStepper(title: "拟选数量", value: $requestedSchoolCount)

            Button(action: onAutoRecommend) {
                Label("自动推荐", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AdmissionSoftButtonStyle(colors: AdmissionStyle.mintNight))
            .disabled(requestedSchoolCount == 0)

            if showsSelectionNotes {
                VStack(alignment: .leading, spacing: 6) {
                    if selectedColleges.isEmpty {
                        Text("下一张卡片默认显示已选学校；尚未选择时列表为空，可切换到全部学校。")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    } else {
                        Text(selectedColleges.prefix(4).map(\.name).joined(separator: "、"))
                            .font(.subheadline.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        if selectedColleges.count > 4 {
                            Text("另有 \(selectedColleges.count - 4) 所已选学校。")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }

                    Text(includeLiberalArtsColleges ? "当前选校范围包含综合大学与文理学院。" : "当前选校范围只包含综合大学。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            showsSelectionNotes = hasCompletedCountAnimation
        }
        .onChange(of: selectionResetID) { _, _ in
            showsSelectionNotes = hasCompletedCountAnimation
        }
        .onChange(of: hasCompletedCountAnimation) { _, completed in
            if completed {
                showsSelectionNotes = true
            }
        }
    }
}

private struct CollegeFilterBar: View {
    @Binding var filter: CollegePickerFilter
    let colleges: [College]
    let selectedIDs: Set<String>
    let includeLiberalArtsColleges: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CollegePickerFilter.availableCases(includeLiberalArtsColleges: includeLiberalArtsColleges)) { item in
                    Button {
                        filter = item
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.systemImage)
                                .font(.caption.weight(.semibold))
                            Text(item.rawValue)
                                .font(.subheadline.weight(.semibold))
                            Text("\(count(for: item))")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((filter == item ? Color.white : item.tint).opacity(filter == item ? 0.22 : 0.14), in: Capsule())
                        }
                        .foregroundStyle(filter == item ? .white : item.tint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            filter == item
                                ? LinearGradient(colors: [item.tint, .black.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.black.opacity(0.08), Color.black.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke((filter == item ? Color.white : Color.black).opacity(filter == item ? 0.20 : 0.10), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.rawValue)筛选，\(count(for: item))所学校")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func count(for item: CollegePickerFilter) -> Int {
        colleges.filter { item.includes(college: $0, selectedIDs: selectedIDs) }.count
    }
}

private struct CollegePickerHero: View {
    let selectedCount: Int
    let totalCount: Int
    let filteredCount: Int
    let includeLiberalArtsColleges: Bool
    let applicationRound: ApplicationRound

    var body: some View {
        AdmissionHeroCard(colors: AdmissionStyle.blackGlass) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<8, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(heroColor(index))
                        .frame(width: 20, height: CGFloat(42 + index % 4 * 22))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .opacity(0.58)
            .padding(.trailing, 18)

            VStack(alignment: .leading, spacing: 14) {
                Label("手动选校组合", systemImage: "rectangle.stack.badge.plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("\(selectedCount) 所已选")
                    .font(AdmissionStyle.titleFont(36))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(heroDetail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    AdmissionMetricPill(title: "数据集", value: "\(totalCount)")
                    AdmissionMetricPill(title: "当前", value: "\(filteredCount)")
                    AdmissionMetricPill(title: "来源", value: "v1")
                }
            }
        }
    }

    private func heroColor(_ index: Int) -> Color {
        let colors: [Color] = [.cyan, .mint, .yellow, .orange, .pink, .purple, .blue, .green]
        return colors[index % colors.count]
    }

    private var heroDetail: String {
        if applicationRound == .earlyDecision {
            return "ED/ED2 为绑定申请；选择新学校会替换当前 ED 学校。"
        }
        let categoryText = includeLiberalArtsColleges ? "综合大学与文理学院" : "综合大学"
        return "当前只显示开放 \(applicationRound.rawValue) 轮次的\(categoryText)；计算只使用这一轮次概率。"
    }
}

private struct SelectedPortfolioCard: View {
    let selectedCount: Int
    let selectedColleges: [College]
    let applicationRound: ApplicationRound

    var body: some View {
        AdmissionGradientCard(
            title: "当前组合",
            systemImage: "checkmark.seal.fill",
            colors: AdmissionStyle.mintNight
        ) {
            Text(selectedCount == 0 ? "尚未选择学校" : selectedColleges.prefix(4).map(\.name).joined(separator: "、"))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(selectionNote)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
            if selectedColleges.count > 4 {
                Text("另有 \(selectedColleges.count - 4) 所已选学校。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }

    private var selectionNote: String {
        if applicationRound == .earlyDecision {
            return "ED/ED2 同一轮只保留 1 所；手动选择新学校会替换原 ED 学校。"
        }
        return "手动改动会把组合来源切换为手动选择；自动推荐缺口提示只会出现在自动推荐组合里。"
    }
}

private struct CollegeSelectionCard: View {
    let college: College
    let chanceResult: ChanceResult?
    let isSelected: Bool
    let allowsRemoval: Bool
    let select: () -> Void
    let remove: () -> Void

    var body: some View {
        Group {
            if isSelected {
                cardContent
            } else {
                Button(action: select) {
                    cardContent
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("#\(college.rank)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tierColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(tierColor)
                    Text(college.tierDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tierColor)
                }
                Text(college.name)
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 12) {
                    MetricPill(title: "学生概率", value: studentProbabilityText, color: .blue)
                    MetricPill(title: "目标分类", value: planningBucketText, color: .purple)
                }
            }
            Spacer()
            if isSelected, allowsRemoval {
                Button(action: remove) {
                    Text("取消")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消选择\(college.name)")
            } else if !isSelected {
                Image(systemName: "square")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.70))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(14)
        .background(
            LinearGradient(colors: cardColors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.34) : Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var tierColor: Color {
        switch college.rank {
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

    private var cardColors: [Color] {
        if isSelected {
            return [tierColor.opacity(0.98), Color.black.opacity(0.76)]
        }
        return [Color.white.opacity(0.11), tierColor.opacity(0.30), Color.black.opacity(0.72)]
    }

    private var studentProbabilityText: String {
        guard let chanceResult else {
            return "待计算"
        }
        return chanceResult.adjustedProbability.formatted(.percent.precision(.fractionLength(1)))
    }

    private var planningBucketText: String {
        guard let chanceResult else {
            return "先计算"
        }
        switch chanceResult.bucket {
        case .blocked:
            return "门槛未满足"
        case .reach, .target, .likely:
            return chanceResult.bucket.rawValue
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.64))
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
