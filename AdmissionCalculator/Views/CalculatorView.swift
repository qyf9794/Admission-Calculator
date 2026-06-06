import SwiftUI

struct CalculatorView: View {
    @Binding var profile: StudentProfile
    @Binding var selectedCollegeIDs: Set<String>
    @Binding var selectionSource: PortfolioSelectionSource
    let hasExistingResult: Bool
    let onOpenCollegeSelection: () -> Void
    @State private var cardIndex = 0
    @State private var maxVisitedCardIndex = 0
    @State private var showingHighSchoolSearch = false

    private let profileCardCount = 5

    var body: some View {
        ZStack {
            AdmissionPageBackground()
            VStack(spacing: 14) {
                ProfileTopBar(
                    progress: profileCompletionProgress,
                    canOpenSelection: canOpenSelection,
                    selectedCount: selectedCollegeIDs.count,
                    action: onOpenCollegeSelection
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        AdmissionSwipeableCard(
                            canSwipeBack: cardIndex > 0,
                            canSwipeForward: cardIndex < profileCardCount - 1 || canOpenSelection,
                            onSwipeBack: { moveCard(by: -1) },
                            onSwipeForward: {
                                if cardIndex < profileCardCount - 1 {
                                    moveCard(by: 1)
                                } else if canOpenSelection {
                                    onOpenCollegeSelection()
                                }
                            },
                            previousPreview: {
                                if cardIndex > 0 {
                                    profileCard(at: cardIndex - 1)
                                }
                            },
                            nextPreview: {
                                if cardIndex < profileCardCount - 1 {
                                    profileCard(at: cardIndex + 1)
                                } else if canOpenSelection {
                                    AdmissionPreviewCard(
                                        title: "选校设置",
                                        subtitle: "进入下一页后设置自动推荐或手动学校列表。",
                                        systemImage: "building.columns.fill",
                                        colors: AdmissionStyle.roseSlate
                                    )
                                }
                            }
                        ) {
                            profileCard(at: cardIndex)
                        }
                            .id(cardIndex)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                CardNavigationBar(
                    currentIndex: cardIndex,
                    totalCount: profileCardCount,
                    canGoBack: cardIndex > 0,
                    canGoForward: cardIndex < profileCardCount - 1,
                    back: { moveCard(by: -1) },
                    forward: { moveCard(by: 1) }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .onChange(of: profile) { _, _ in
            if !profile.includeLiberalArtsColleges {
                selectedCollegeIDs = selectedCollegeIDs.filter { id in
                    guard let college = AdmissionsSeedData.colleges.first(where: { $0.id == id }) else {
                        return true
                    }
                    return college.category != .liberalArtsCollege
                }
            }
            selectedCollegeIDs = selectedCollegeIDs.filter { id in
                guard let college = AdmissionsSeedData.colleges.first(where: { $0.id == id }) else {
                    return true
                }
                return allowsCurrentRound(college)
            }
            if profile.round == .earlyDecision, selectedCollegeIDs.count > 1 {
                let firstSelected = AdmissionsSeedData.colleges
                    .map(\.id)
                    .first { selectedCollegeIDs.contains($0) }
                selectedCollegeIDs = firstSelected.map { Set([$0]) } ?? []
            }
            selectionSource = selectionSource.afterProfileEdit(selectedCollegeIDs: selectedCollegeIDs)
        }
        .sheet(isPresented: $showingHighSchoolSearch) {
            HighSchoolSearchSheet(
                selectedHighSchoolID: $profile.highSchoolID,
                highSchools: AdmissionsSeedData.highSchools
            )
        }
    }

    @ViewBuilder
    private func profileCard(at index: Int) -> some View {
        switch index {
        case 0:
            CardSection(title: "学生画像", subtitle: "先确定身份、成绩口径、课程体系和申请方向。", systemImage: "person.text.rectangle", colors: AdmissionStyle.mintNight) {
                Picker("申请身份", selection: $profile.applicantStatus) {
                    ForEach(ApplicantStatus.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)
                GradeScaleInputs(
                    title: "GPA / 校内成绩",
                    scale: $profile.gradeScale,
                    percent: $profile.gpaPercent,
                    fourPoint: $profile.gpaFourPoint,
                    fivePoint: $profile.gpaFivePoint,
                    letterGrade: $profile.letterGrade
                )
	                DecimalSliderInput(
	                    title: "年级排名百分位",
	                    value: $profile.classRankPercentile,
	                    range: 1...100,
	                    step: 1,
	                    displayValue: { "前 \(Int($0))%" }
	                )
                Picker("课程体系", selection: $profile.curriculum) {
                    ForEach(CurriculumType.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)
                CurriculumPerformanceInputs(profile: $profile)
                Picker("目标专业", selection: $profile.major) {
                    ForEach(MajorCategory.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)
                Picker("申请轮次", selection: $profile.round) {
                    ForEach(ApplicationRound.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("申请资助", isOn: $profile.needsAid)
            }
        case 1:
            CardSection(title: "硬指标", subtitle: "标化和语言成绩会先经过硬门槛，再进入概率修正。", systemImage: "target", colors: AdmissionStyle.bluePulse) {
                Toggle("Test Optional / 不提交标化", isOn: testOptionalBinding)
                ScoreField(title: "SAT", value: $profile.sat, range: 400...1600, disabled: profile.testOptional)
                ScoreField(title: "ACT", value: $profile.act, range: 1...36, disabled: profile.testOptional)
                ScoreField(title: "TOEFL", value: $profile.toefl, range: 0...120, disabled: false)
                DecimalScoreField(title: "IELTS", value: $profile.ielts, range: 0...9.0, step: 0.5)
                if !profile.applicantStatus.requiresEnglishProof {
                    Text("当前申请身份通常不触发国际生英语硬门槛；语言成绩仍可作为学术证明。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                }
	                IntArrowInput(title: "课程难度", value: $profile.rigor, range: 1...5, suffix: "/5")
            }
        case 2:
            CardSection(title: "软实力", subtitle: "顶尖校不能只看 GPA，活动、奖项、文书和推荐信会影响画像分。", systemImage: "sparkles", colors: AdmissionStyle.pinkMist) {
                BandStepper(title: "活动影响力", value: $profile.activities)
                BandStepper(title: "科研 / 夏校", value: $profile.research)
                BandStepper(title: "奖项区分度", value: $profile.honors)
                BandStepper(title: "文书成熟度", value: $profile.essay)
                BandStepper(title: "推荐信强度", value: $profile.recommendations)
                Toggle("艺术作品集已准备", isOn: $profile.hasPortfolio)
            }
        case 3:
            CardSection(title: "中国高中背景", subtitle: "高中背景只是代理校准，不是个人录取证明。", systemImage: "graduationcap.fill", colors: AdmissionStyle.citrus) {
                HighSchoolSearchButton(
                    school: selectedHighSchool,
                    openSearch: { showingHighSchoolSearch = true }
                )
                Text("打开后可按学校名称搜索；当前默认项会固定在列表最上方。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
                Text("高中背景仅作为 AdmitRanking 风格代理校准；不确定时请选择“其他/手动评估学校”，避免默认名校背景抬高估算。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
            }
        default:
            CardSection(title: "选校数量", subtitle: selectionCountSubtitle, systemImage: "slider.horizontal.3", colors: AdmissionStyle.lilac) {
                Toggle("纳入文理学院", isOn: $profile.includeLiberalArtsColleges)
                UnboundedCountStepper(title: "计划选择大学", value: $profile.requestedSchoolCount)
                LabeledContent("自动生成数量", value: "\(automaticGeneratedCount) 所")
                Text(profile.includeLiberalArtsColleges
                     ? "自动推荐和手动目录会同时包含综合大学与文理学院。"
                     : "关闭后，自动推荐、手动目录和至少一所概率都只考虑综合大学。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
                Text(automaticGenerationNote)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
            }
        }
    }

    private var selectedHighSchool: HighSchoolContext {
        AdmissionsSeedData.highSchools.first { $0.id == profile.highSchoolID } ??
            AdmissionsSeedData.highSchools.first { $0.id == "unknown" } ??
            HighSchoolContext(
                id: "unknown",
                name: "其他/手动评估学校",
                city: "未知",
                admitRankingBand: 3,
                resources: 3,
                counseling: 3,
                top30TrackRecord: 2,
                transparency: 3
            )
    }

    private func moveCard(by delta: Int) {
        let nextIndex = clamped(cardIndex + delta, range: 0...(profileCardCount - 1))
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            cardIndex = nextIndex
            maxVisitedCardIndex = max(maxVisitedCardIndex, nextIndex)
        }
    }

    private var canOpenSelection: Bool {
        maxVisitedCardIndex >= profileCardCount - 1 && completionPrompts.isEmpty
    }

    private var profileCompletionProgress: Double {
        Double(maxVisitedCardIndex + 1) / Double(profileCardCount)
    }

    private var selectionCountSubtitle: String {
        if profile.round == .earlyDecision {
            return "ED/ED2 是绑定申请；同一轮只能保留 1 所。"
        }
        return "设置计划申请数量；EA/RD 和手动选校可多所。"
    }

    private var requestedRecommendationTotal: Int {
        automaticGeneratedCount
    }

    private var automaticGeneratedCount: Int {
        guard profile.round == .earlyDecision else {
            return profile.requestedSchoolCount
        }
        return min(profile.requestedSchoolCount, 1)
    }

    private var automaticGenerationNote: String {
        if profile.round == .earlyDecision {
            return "ED/ED2 是绑定申请；自动推荐同一轮最多生成 1 所 ED 学校。EA 可以多所，手动选校没有数量上限但会提示无效 ED 组合。"
        }
        return "自动推荐会尽量生成与计划选择数量一致的学校组合；若当前画像下合格学校不足，会在结果中披露缺口。"
    }

    private func allowsCurrentRound(_ college: College) -> Bool {
        let rules = AdmissionsSeedData.gateRules.filter { $0.collegeID == college.id && $0.type == .round }
        guard !rules.isEmpty else {
            return profile.round == .regularDecision
        }
        return rules.contains { rule in
            if !rule.allowedRounds.isEmpty {
                return rule.allowedRounds.contains(profile.round)
            }
            if let requiredRound = rule.requiredRound {
                return requiredRound == profile.round
            }
            return profile.round == .regularDecision
        }
    }

    private var completionPrompts: [ProfileCompletionPrompt] {
        profile.completionPrompts(selectedCollegeIDs: selectedCollegeIDs)
    }

    private var testOptionalBinding: Binding<Bool> {
        Binding(
            get: { profile.testOptional },
            set: { isOptional in
                profile.testOptional = isOptional
                if isOptional {
                    profile.sat = nil
                    profile.act = nil
                }
            }
        )
    }
}

private struct HighSchoolSearchButton: View {
    let school: HighSchoolContext
    let openSearch: () -> Void

    var body: some View {
        Button(action: openSearch) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 3) {
                    Text("高中学校")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.66))
                    Text(school.name)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(school.city)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .padding(12)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdmissionStyle.compactRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("高中学校，当前选择 \(school.name)，点击搜索")
    }
}

private struct HighSchoolSearchSheet: View {
    @Binding var selectedHighSchoolID: String
    let highSchools: [HighSchoolContext]

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var orderedHighSchools: [HighSchoolContext] {
        let filtered = highSchools.filter { school in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                return true
            }
            return school.name.localizedCaseInsensitiveContains(query) ||
                school.city.localizedCaseInsensitiveContains(query) ||
                school.id.localizedCaseInsensitiveContains(query)
        }
        return filtered.sorted { lhs, rhs in
            if lhs.id == selectedHighSchoolID {
                return true
            }
            if rhs.id == selectedHighSchoolID {
                return false
            }
            if lhs.id == "unknown" {
                return true
            }
            if rhs.id == "unknown" {
                return false
            }
            if lhs.admitRankingBand != rhs.admitRankingBand {
                return lhs.admitRankingBand < rhs.admitRankingBand
            }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(orderedHighSchools) { school in
                        Button {
                            selectedHighSchoolID = school.id
                            dismiss()
                        } label: {
                            HighSchoolSearchRow(
                                school: school,
                                isSelected: school.id == selectedHighSchoolID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("当前/默认项固定在最上方，可按学校名称搜索")
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索高中名称")
            .navigationTitle("选择高中")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct HighSchoolSearchRow: View {
    let school: HighSchoolContext
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.bold))
                .foregroundStyle(isSelected ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(school.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(school.city) · 背景档 \(school.admitRankingBand)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileTopBar: View {
    let progress: Double
    let canOpenSelection: Bool
    let selectedCount: Int
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.10))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: canOpenSelection ? [Color.green, Color.teal] : [Color.gray.opacity(0.58), Color.gray.opacity(0.36)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, proxy.size.width * min(1, max(0, progress))))
                }
            }
            .frame(height: 9)

            Button(action: action) {
                Label(selectedCount == 0 ? "选校" : "选校 \(selectedCount)", systemImage: "building.columns.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(AdmissionSoftButtonStyle(colors: canOpenSelection ? AdmissionStyle.mintNight : [Color.gray.opacity(0.58), Color.gray.opacity(0.34)]))
            .disabled(!canOpenSelection)
            .opacity(canOpenSelection ? 1 : 0.58)
        }
    }
}

struct CardNavigationBar: View {
    let currentIndex: Int
    let totalCount: Int
    let canGoBack: Bool
    let canGoForward: Bool
    let back: () -> Void
    let forward: () -> Void

    var body: some View {
        HStack {
            Button(action: back) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 38, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canGoBack ? Color.black.opacity(0.82) : Color.black.opacity(0.22))
            .disabled(!canGoBack)

            Spacer()

            Text("\(currentIndex + 1) / \(totalCount)")
                .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.bold))
                .foregroundStyle(Color.black.opacity(0.58))

            Spacer()

            Button(action: forward) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 38, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canGoForward ? Color.black.opacity(0.82) : Color.black.opacity(0.22))
            .disabled(!canGoForward)
        }
        .frame(height: 46)
    }
}

private struct CalculatorHero: View {
    let selectedCount: Int
    let promptCount: Int
    let requestedTotal: Int

    var body: some View {
        AdmissionHeroCard(colors: AdmissionStyle.blackGlass) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<8, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(heroBlockColor(index))
                        .frame(width: 14, height: CGFloat(28 + index % 4 * 18))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .opacity(0.36)
            .padding(.trailing, 18)

            VStack(alignment: .leading, spacing: 14) {
                Label("中国学生美本录取概率规划", systemImage: "sparkle.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("Admit Chance")
                    .font(AdmissionStyle.titleFont(36))
                    .foregroundStyle(.white)
                Text("用硬门槛、学术匹配、国际生数据和中国本科录取容量，生成可解释的选校估算。")
                    .font(AdmissionStyle.bodyFont())
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    AdmissionMetricPill(title: "已选", value: "\(selectedCount)")
                    AdmissionMetricPill(title: "待补", value: "\(promptCount)")
                    AdmissionMetricPill(title: "计划", value: "\(requestedTotal)")
                }
            }
        }
    }

    private func heroBlockColor(_ index: Int) -> Color {
        let colors: [Color] = [.cyan, .mint, .yellow, .orange, .pink, .purple, .blue, .green, .red]
        return colors[index % colors.count]
    }
}

struct UnboundedCountStepper: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Button {
                    value = max(0, value - 1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                }
                .disabled(value == 0)

                Text("\(value) 所")
                    .font(.system(.headline, design: .rounded).monospacedDigit().weight(.black))
                    .frame(minWidth: 64)

                Button {
                    value += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
    }
}

private struct ProfileReadinessCard: View {
    let prompts: [ProfileCompletionPrompt]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: prompts.isEmpty ? "checkmark.seal.fill" : "exclamationmark.bubble.fill")
                    .foregroundStyle(prompts.isEmpty ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompts.isEmpty ? "关键资料已就绪" : "需要补充的关键信息")
                        .font(.headline)
                    Text(prompts.isEmpty ? "可以直接计算，也可以继续微调选校组合。" : "这些信息会影响硬门槛、概率或推荐组合。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                }
            }

            if prompts.isEmpty {
                Text("结果页会显示组合概率；逐校概率和提升建议在报告页查看。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.70))
            } else {
                ForEach(prompts.prefix(4)) { prompt in
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
                if prompts.count > 4 {
                    Text("还有 \(prompts.count - 4) 项可补充信息会在后续细化中影响判断。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
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

private struct CardSection<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let colors: [Color]
    private let content: Content

    init(title: String, subtitle: String, systemImage: String, colors: [Color], @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.colors = colors
        self.content = content()
    }

    var body: some View {
        AdmissionGradientCard(title: title, subtitle: subtitle, systemImage: systemImage, colors: colors) {
            content
        }
    }
}

private struct CurriculumPerformanceInputs: View {
    @Binding var profile: StudentProfile

    var body: some View {
        Group {
            switch profile.curriculum {
            case .chinese:
                GradeScaleInputs(
                    title: "核心课程成绩",
                    scale: $profile.curriculumGradeScale,
                    percent: $profile.chineseCurriculumScore,
                    fourPoint: $profile.chineseCurriculumGPAFourPoint,
                    fivePoint: $profile.chineseCurriculumGPAFivePoint,
                    letterGrade: $profile.chineseCurriculumLetterGrade
                )
            case .ap:
	                IntSliderInput(title: "AP / 高级课程门数", value: $profile.apCourseCount, range: 0...12, step: 1)
	                if profile.apCourseCount > 0 {
	                    DecimalSliderInput(
	                        title: "AP 平均分",
	                        value: $profile.apAverageScore,
	                        range: 1...5,
	                        step: 0.5,
	                        displayValue: { String(format: "%.1f", $0) }
	                    )
	                } else {
                    Text("AP 课程门数为 0 时，AP 平均分不会计入课程体系成绩。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                }
            case .ib:
	                IntSliderInput(title: "IB 预估总分", value: $profile.ibPredictedScore, range: 24...45, step: 1)
	            case .alevel:
	                IntArrowInput(title: "A-Level A* 科目", value: $profile.aLevelAStarCount, range: aLevelRange(for: profile.aLevelAStarCount))
	                IntArrowInput(title: "A-Level A 科目", value: $profile.aLevelACount, range: aLevelRange(for: profile.aLevelACount))
	                IntArrowInput(title: "A-Level B 科目", value: $profile.aLevelBCount, range: aLevelRange(for: profile.aLevelBCount))
                Text("A*/A/B 合计最多 \(StudentProfile.maximumALevelSubjectCount) 门；超出上限不会提高课程体系成绩。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
            }
        }
        .onAppear(perform: clampALevelSubjectsIfNeeded)
    }

    private func aLevelRange(for currentValue: Int) -> ClosedRange<Int> {
        let otherSubjects = profile.aLevelSubjectCount - currentValue
        let upperBound = max(0, StudentProfile.maximumALevelSubjectCount - otherSubjects)
        return 0...upperBound
    }

    private func clampALevelSubjectsIfNeeded() {
        guard profile.curriculum == .alevel, profile.aLevelSubjectCount > StudentProfile.maximumALevelSubjectCount else {
            return
        }
        var updated = profile
        updated.clampALevelSubjectCounts()
        profile = updated
    }
}

private struct GradeScaleInputs: View {
    let title: String
    @Binding var scale: GradeScale
    @Binding var percent: Double
    @Binding var fourPoint: Double
    @Binding var fivePoint: Double
    @Binding var letterGrade: LetterGradeBand

    var body: some View {
        Picker("\(title)方式", selection: $scale) {
            ForEach(GradeScale.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }

        switch scale {
        case .percent:
	            DecimalSliderInput(title: title, value: $percent, range: 0...100, step: 1) { "\(Int($0))" }
	        case .fourPoint:
	            DecimalSliderInput(title: title, value: $fourPoint, range: 0...4, step: 0.1) { String(format: "%.1f", $0) }
	        case .fivePoint:
	            DecimalSliderInput(title: title, value: $fivePoint, range: 0...5, step: 0.1) { String(format: "%.1f", $0) }
	        case .letter:
	            OptionArrowInput(title: title, selection: $letterGrade, options: LetterGradeBand.allCases) { $0.rawValue }
	        }
	}
}

private struct DecimalSliderInput: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let displayValue: (Double) -> String

    var body: some View {
        LabeledContent {
            SliderControl(
                value: valueBinding,
                range: range,
                step: step,
                displayText: displayValue(value)
            )
        } label: {
            Text(title)
        }
    }

    private var valueBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { value = snapped($0, range: range, step: step) }
        )
    }
}

private struct IntSliderInput: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        LabeledContent {
            SliderControl(
                value: valueBinding,
                range: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step),
                displayText: "\(value)"
            )
        } label: {
            Text(title)
        }
    }

    private var valueBinding: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { value = clamped(Int($0.rounded()), range: range) }
        )
    }
}

private struct OptionalIntSliderInput: View {
    let title: String
    @Binding var value: Int?
    let range: ClosedRange<Int>
    let step: Int
    let disabled: Bool

    var body: some View {
        SliderControl(
            value: valueBinding,
            range: Double(range.lowerBound)...Double(range.upperBound),
            step: Double(step),
            displayText: value.map(String.init) ?? "未填写",
            disabled: disabled
        )
        .accessibilityLabel(title)
    }

    private var valueBinding: Binding<Double> {
        Binding(
            get: { Double(value ?? midpoint(range)) },
            set: { value = clamped(Int($0.rounded()), range: range) }
        )
    }
}

private struct OptionalDecimalSliderInput: View {
    let title: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double
    let displayValue: (Double) -> String

    var body: some View {
        SliderControl(
            value: valueBinding,
            range: range,
            step: step,
            displayText: value.map(displayValue) ?? "未填写"
        )
        .accessibilityLabel(title)
    }

    private var valueBinding: Binding<Double> {
        Binding(
            get: { value ?? midpoint(range) },
            set: { value = snapped($0, range: range, step: step) }
        )
    }
}

private struct SliderControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let displayText: String
    var disabled = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(displayText)
                .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.black))
                .foregroundStyle(disabled ? .secondary : .primary)
                .frame(minWidth: 58, alignment: .trailing)

            HStack(spacing: 8) {
                IconAdjustButton(systemImage: "minus.circle.fill", disabled: disabled || value <= range.lowerBound) {
                    value = snapped(value - step, range: range, step: step)
                }

                Slider(value: $value, in: range, step: step)
                    .disabled(disabled)
                    .frame(minWidth: 126)

                IconAdjustButton(systemImage: "plus.circle.fill", disabled: disabled || value >= range.upperBound) {
                    value = snapped(value + step, range: range, step: step)
                }
            }
        }
        .frame(maxWidth: 260)
    }
}

private struct IntArrowInput: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var suffix = ""

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                IconAdjustButton(systemImage: "chevron.left.circle.fill", disabled: value <= range.lowerBound) {
                    value = max(range.lowerBound, value - 1)
                }

                Text("\(value)\(suffix)")
                    .font(.system(.headline, design: .rounded).monospacedDigit().weight(.black))
                    .frame(minWidth: 54)

                IconAdjustButton(systemImage: "chevron.right.circle.fill", disabled: value >= range.upperBound) {
                    value = min(range.upperBound, value + 1)
                }
            }
        } label: {
            Text(title)
        }
    }
}

private struct OptionArrowInput<Option: Equatable>: View {
    let title: String
    @Binding var selection: Option
    let options: [Option]
    let displayValue: (Option) -> String

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                IconAdjustButton(systemImage: "chevron.left.circle.fill", disabled: currentIndex <= 0) {
                    move(by: -1)
                }

                Text(displayValue(selection))
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .frame(minWidth: 72)

                IconAdjustButton(systemImage: "chevron.right.circle.fill", disabled: currentIndex >= options.count - 1) {
                    move(by: 1)
                }
            }
        } label: {
            Text(title)
        }
    }

    private var currentIndex: Int {
        options.firstIndex(of: selection) ?? 0
    }

    private func move(by delta: Int) {
        guard !options.isEmpty else { return }
        selection = options[clamped(currentIndex + delta, range: 0...(options.count - 1))]
    }
}

private struct IconAdjustButton: View {
    let systemImage: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.white.opacity(0.28) : Color.white)
        .background((disabled ? Color.white.opacity(0.06) : Color.white.opacity(0.14)), in: Circle())
        .disabled(disabled)
    }
}

private func snapped(_ rawValue: Double, range: ClosedRange<Double>, step: Double) -> Double {
    guard step > 0 else {
        return min(max(rawValue, range.lowerBound), range.upperBound)
    }
    let steps = ((rawValue - range.lowerBound) / step).rounded()
    let snappedValue = range.lowerBound + steps * step
    return min(max(snappedValue, range.lowerBound), range.upperBound)
}

private func clamped(_ value: Int, range: ClosedRange<Int>) -> Int {
    min(max(value, range.lowerBound), range.upperBound)
}

private func midpoint(_ range: ClosedRange<Int>) -> Int {
    let rawMidpoint = (Double(range.lowerBound) + Double(range.upperBound)) / 2.0
    return Int(rawMidpoint.rounded())
}

private func midpoint(_ range: ClosedRange<Double>) -> Double {
    (range.lowerBound + range.upperBound) / 2.0
}

private struct ScoreField: View {
    let title: String
    @Binding var value: Int?
    let range: ClosedRange<Int>
    let disabled: Bool

    var body: some View {
        LabeledContent(title) {
	            HStack {
	                Button {
	                    value = nil
	                } label: {
	                    Image(systemName: "xmark.circle")
	                }
	                .disabled(value == nil || disabled)

	                OptionalIntSliderInput(
	                    title: title,
	                    value: $value,
	                    range: range,
	                    step: title == "SAT" ? 10 : 1,
	                    disabled: disabled
	                )
	            }
	        }
	    }
}

private struct DecimalScoreField: View {
    let title: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledContent(title) {
	            HStack {
	                Button {
	                    value = nil
	                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(value == nil)

	                OptionalDecimalSliderInput(
	                    title: title,
	                    value: $value,
	                    range: range,
	                    step: step,
	                    displayValue: { String(format: "%.1f", $0) }
	                )
	            }
	        }
	    }
}

private struct BandStepper: View {
    let title: String
    @Binding var value: Int

    var body: some View {
	        IntArrowInput(title: title, value: $value, range: 1...5, suffix: "/5")
	    }
	}
