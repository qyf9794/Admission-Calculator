import SwiftUI

struct CalculatorView: View {
    static let lastProfileCardIndex = 4
    static let profileCardHeight: CGFloat = 502

    let initialCardIndex: Int
    @Binding var profile: StudentProfile
    @Binding var completionState: ProfileFormCompletionState
    @Binding var selectedCollegeIDs: Set<String>
    @Binding var selectionSource: PortfolioSelectionSource
    let canSwipeToCollegeSelection: Bool
    let completedSchoolSetupAnimationIDs: Set<String>
    let completedAutomaticSummaryAnimationIDs: Set<String>
    let onSchoolSetupAnimationCompleted: (String) -> Void
    let onAutomaticSummaryAnimationCompleted: (String) -> Void
    let onOpenCollegeSelection: () -> Void
    @State private var cardIndex = 0
    @State private var maxVisitedCardIndex = 0
    @State private var showingMajorSelection = false
    @State private var showingHighSchoolSearch = false
    @State private var swipeCommand: AdmissionCardSwipeCommand?
    @State private var hasAppliedInitialCardIndex = false

    private let profileCardCount = 5

    var body: some View {
        ZStack {
            AdmissionPageBackground()
            VStack(spacing: 14) {
                ProfileTopBar(
                    progressSegments: profileCompletionProgresses,
                    canOpenSelection: canOpenSelection,
                    selectedCount: selectedCollegeIDs.count,
                    action: onOpenCollegeSelection
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)

                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Spacer(minLength: 0)
                            AdmissionSwipeableCard(
                                swipeCommand: $swipeCommand,
                                canSwipeBack: cardIndex > 0,
                                canSwipeForward: cardIndex < profileCardCount - 1 || canSwipeForwardToSelection,
                                onSwipeBack: { moveCard(by: -1) },
                                onSwipeForward: {
                                    if cardIndex < profileCardCount - 1 {
                                        moveCard(by: 1)
                                    } else if canSwipeForwardToSelection {
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
                                    } else if canSwipeForwardToSelection {
                                        SchoolSetupCard(
                                            selectedCount: selectedCollegeIDs.count,
                                            selectedColleges: selectedColleges,
                                            requestedSchoolCount: $profile.requestedSchoolCount,
                                            includeLiberalArtsColleges: profile.includeLiberalArtsColleges,
                                            applicationRound: profile.round,
                                            hasCompletedCountAnimation: completedSchoolSetupAnimationIDs.contains(
                                                SchoolSetupCard.animationID(
                                                    selectedCount: selectedCollegeIDs.count,
                                                    selectedColleges: selectedColleges,
                                                    includeLiberalArtsColleges: profile.includeLiberalArtsColleges,
                                                    applicationRound: profile.round
                                                )
                                            ),
                                            onCountAnimationCompleted: onSchoolSetupAnimationCompleted,
                                            onAutoRecommend: {},
                                            isTransitionPreview: true
                                        )
                                    }
                                }
                            ) {
                                profileCard(at: cardIndex)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: proxy.size.height, alignment: .center)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                }

                CardNavigationBar(
                    currentIndex: cardIndex,
                    totalCount: profileCardCount,
                    canGoBack: cardIndex > 0,
                    canGoForward: cardIndex < profileCardCount - 1 || canSwipeForwardToSelection,
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
        .onChange(of: profile) { _, _ in
            if selectionSource == .automatic {
                selectionSource = selectionSource.afterProfileEdit(selectedCollegeIDs: selectedCollegeIDs)
            }
        }
        .onChange(of: profile.includeLiberalArtsColleges) { _, _ in
            applyLiberalArtsSelectionConstraint()
            selectionSource = selectionSource.afterProfileEdit(selectedCollegeIDs: selectedCollegeIDs)
        }
        .onChange(of: profile.round) { _, _ in
            applyRoundSelectionConstraint()
            selectionSource = selectionSource.afterProfileEdit(selectedCollegeIDs: selectedCollegeIDs)
        }
        .sheet(isPresented: $showingHighSchoolSearch) {
            HighSchoolSearchSheet(
                selectedHighSchoolID: highSchoolSelectionBinding,
                highSchools: AdmissionsSeedData.highSchools
            )
        }
        .sheet(isPresented: $showingMajorSelection) {
            MajorSelectionSheet(selectedMajor: $profile.major)
        }
    }

    @ViewBuilder
    private func profileCard(at index: Int) -> some View {
        switch index {
        case 0:
            CardSection(title: "学生画像", subtitle: "先确定目标方向与校内成绩基准。", systemImage: "person.text.rectangle", colors: AdmissionStyle.profileCalm, minHeight: Self.profileCardHeight) {
                HStack(spacing: 12) {
                    MajorSelectionButton(major: profile.major) {
                        showingMajorSelection = true
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 8)

                    Picker("成绩方式", selection: $profile.gradeScale) {
                        ForEach(GradeScale.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                }
                GradeValueInput(
                    title: "GPA / 校内成绩",
                    scale: $profile.gradeScale,
                    percent: $profile.gpaPercent,
                    fourPoint: $profile.gpaFourPoint,
                    fivePoint: $profile.gpaFivePoint,
                    letterGrade: $profile.letterGrade,
                    isFilled: completionBinding(.academicGrade)
                )
	                DecimalSliderInput(
	                    title: "年级排名百分位",
	                    value: $profile.classRankPercentile,
	                    range: 1...100,
	                    step: 1,
	                    displayValue: { "前 \(Int($0))%" },
                        isFilled: completionBinding(.classRank)
	                )
                Picker("课程体系", selection: $profile.curriculum) {
                    ForEach(CurriculumType.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                CurriculumPerformanceInputs(profile: $profile, completionState: $completionState)
            }
        case 1:
            CardSection(title: "标准化成绩", subtitle: "标化和语言成绩会进入资格校验，并参与概率修正。", systemImage: "target", colors: AdmissionStyle.bluePulse, minHeight: Self.profileCardHeight, contentVerticalAlignment: .center) {
                Toggle("Test Optional / 不提交标化", isOn: testOptionalBinding)
                    .tint(AdmissionStyle.controlBlue)
                ScoreField(title: "SAT", value: $profile.sat, range: 400...1600, disabled: profile.testOptional)
                ScoreField(title: "ACT", value: $profile.act, range: 1...36, disabled: profile.testOptional)
                ScoreField(title: "TOEFL", value: $profile.toefl, range: 0...120, disabled: false)
                DecimalScoreField(title: "IELTS", value: $profile.ielts, range: 0...9.0, step: 0.5)
                if !profile.applicantStatus.requiresEnglishProof {
                    Text("当前申请身份通常不触发国际生英语硬门槛；语言成绩仍可作为学术证明。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                }
	                IntArrowInput(title: "课程难度", value: $profile.rigor, range: 1...5, suffix: "/5", isFilled: completionBinding(.rigor))
            }
        case 2:
            CardSection(title: "软实力", subtitle: "顶尖校不能只看 GPA，活动、奖项、文书和推荐信会影响画像分。", systemImage: "sparkles", colors: AdmissionStyle.pinkMist, minHeight: Self.profileCardHeight, contentVerticalAlignment: .center) {
                BandStepper(title: "活动影响力", value: $profile.activities, isFilled: completionBinding(.activities))
                BandStepper(title: "科研 / 夏校", value: $profile.research, isFilled: completionBinding(.research))
                BandStepper(title: "奖项区分度", value: $profile.honors, isFilled: completionBinding(.honors))
                BandStepper(title: "文书成熟度", value: $profile.essay, isFilled: completionBinding(.essay))
                BandStepper(title: "推荐信强度", value: $profile.recommendations, isFilled: completionBinding(.recommendations))
                Toggle("艺术作品集已准备", isOn: $profile.hasPortfolio)
                    .tint(AdmissionStyle.controlBlue)
            }
        case 3:
            CardSection(title: "高中背景与身份", subtitle: "确认是否中国籍国际生，并选择高中背景；两者都会影响中国申请者容量代理。", systemImage: "graduationcap.fill", colors: AdmissionStyle.citrus, minHeight: Self.profileCardHeight, contentVerticalAlignment: .center) {
                Picker("申请身份 / 是否中国籍", selection: $profile.applicantStatus) {
                    ForEach(ApplicantStatus.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                HighSchoolSearchButton(
                    school: selectedHighSchool,
                    openSearch: { showingHighSchoolSearch = true }
                )
                Text("打开后可按学校名称搜索；当前默认项会固定在列表最上方。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
                Text(profile.applicantStatus.usesChinaProxy
                     ? "中国籍国际生会启用本科中国录取容量代理；高中背景仅作为 AdmitRanking 风格校准，不代表个人录取证明。"
                     : "当前身份不启用中国录取容量代理；高中背景仍只作为申请环境参考。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
            }
        default:
            ProfileSelectionSettingsCard(
                profile: $profile,
                fixedHeight: Self.profileCardHeight,
                completedAutomaticSummaryAnimationIDs: completedAutomaticSummaryAnimationIDs,
                onAutomaticSummaryAnimationCompleted: onAutomaticSummaryAnimationCompleted
            )
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
        cardIndex = nextIndex
        maxVisitedCardIndex = max(maxVisitedCardIndex, nextIndex)
    }

    private func applyInitialCardIndexIfNeeded() {
        guard !hasAppliedInitialCardIndex else {
            return
        }
        let initialIndex = clamped(initialCardIndex, range: 0...(profileCardCount - 1))
        cardIndex = initialIndex
        maxVisitedCardIndex = max(maxVisitedCardIndex, initialIndex)
        hasAppliedInitialCardIndex = true
    }

    private func requestCardSwipe(_ direction: AdmissionCardSwipeDirection) {
        swipeCommand = AdmissionCardSwipeCommand(direction: direction)
    }

    private func applyLiberalArtsSelectionConstraint() {
        guard !profile.includeLiberalArtsColleges else {
            return
        }
        selectedCollegeIDs = selectedCollegeIDs.filter { id in
            guard let college = AdmissionsSeedData.colleges.first(where: { $0.id == id }) else {
                return true
            }
            return college.category != .liberalArtsCollege
        }
    }

    private func applyRoundSelectionConstraint() {
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
    }

    private var canOpenSelection: Bool {
        maxVisitedCardIndex >= profileCardCount - 1 &&
            profileBlockingPrompts.isEmpty &&
            profileCompletionProgresses.allSatisfy { $0 >= 1 }
    }

    private var canSwipeForwardToSelection: Bool {
        canSwipeToCollegeSelection && canOpenSelection
    }

    private var profileCompletionProgresses: [Double] {
        (0..<profileCardCount).map { index in
            guard index <= maxVisitedCardIndex else {
                return 0
            }
            return profileCompletionProgress(for: index)
        }
    }

    private func profileCompletionProgress(for index: Int) -> Double {
        switch index {
        case 0:
            return completionRatio([
                profile.major != .undecided,
                completionState.isFilled(.academicGrade),
                completionState.isFilled(.classRank),
                curriculumEvidenceIsComplete
            ])
        case 1:
            return completionRatio([
                profile.testOptional || profile.sat != nil || profile.act != nil,
                !profile.applicantStatus.requiresEnglishProof || profile.toefl != nil || profile.ielts != nil,
                completionState.isFilled(.rigor)
            ])
        case 2:
            var fields = [
                completionState.isFilled(.activities),
                completionState.isFilled(.research),
                completionState.isFilled(.honors),
                completionState.isFilled(.essay),
                completionState.isFilled(.recommendations)
            ]
            if profile.major == .arts {
                fields.append(profile.hasPortfolio)
            }
            return completionRatio(fields)
        case 3:
            return completionRatio([
                completionState.isFilled(.highSchool)
            ])
        default:
            return completionRatio([
                profile.requestedSchoolCount > 0,
                true,
                true,
                true
            ])
        }
    }

    private var curriculumEvidenceIsComplete: Bool {
        switch profile.curriculum {
        case .chinese:
            return completionState.isFilled(.curriculumPrimary)
        case .ap:
            return completionState.isFilled(.curriculumPrimary) &&
                profile.apCourseCount > 0 &&
                completionState.isFilled(.curriculumSecondary)
        case .ib:
            return completionState.isFilled(.curriculumPrimary)
        case .alevel:
            return completionState.isFilled(.aLevelAStar) &&
                completionState.isFilled(.aLevelA) &&
                completionState.isFilled(.aLevelB) &&
                profile.aLevelSubjectCount > 0
        }
    }

    private func completionRatio(_ fields: [Bool]) -> Double {
        guard !fields.isEmpty else {
            return 1
        }
        return Double(fields.filter { $0 }.count) / Double(fields.count)
    }

    private func completionBinding(_ field: ProfileCompletionField) -> Binding<Bool> {
        Binding(
            get: { completionState.isFilled(field) },
            set: { completionState.set(field, isFilled: $0) }
        )
    }

    private var highSchoolSelectionBinding: Binding<String> {
        Binding(
            get: { profile.highSchoolID },
            set: { id in
                profile.highSchoolID = id
                completionState.set(.highSchool, isFilled: true)
            }
        )
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

    private var selectedColleges: [College] {
        AdmissionsSeedData.colleges
            .filter { college in
                selectedCollegeIDs.contains(college.id) &&
                    (profile.includeLiberalArtsColleges || college.category != .liberalArtsCollege) &&
                    allowsCurrentRound(college)
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }
                if lhs.category != rhs.category {
                    return lhs.category == .nationalUniversity
                }
                return lhs.name < rhs.name
            }
    }

    private var completionPrompts: [ProfileCompletionPrompt] {
        profile.completionPrompts(selectedCollegeIDs: selectedCollegeIDs)
    }

    private var profileBlockingPrompts: [ProfileCompletionPrompt] {
        completionPrompts.filter(\.blocksProfileCompletion)
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

private struct MajorSelectionButton: View {
    let major: MajorCategory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("目标专业")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                    Text(major.rawValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.13), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("目标专业，当前选择 \(major.rawValue)")
    }
}

private struct MajorSelectionSheet: View {
    @Binding var selectedMajor: MajorCategory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(MajorCategory.allCases) { major in
                    Button {
                        selectedMajor = major
                        dismiss()
                    } label: {
                        MajorSelectionRow(
                            major: major,
                            isSelected: major == selectedMajor
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("选择专业")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct MajorSelectionRow: View {
    let major: MajorCategory
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.bold))
                .foregroundStyle(isSelected ? AdmissionStyle.controlBlue : .secondary)
            Text(major.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct HighSchoolSearchSheet: View {
    @Binding var selectedHighSchoolID: String
    private let rows: [HighSchoolSearchItem]

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    init(selectedHighSchoolID: Binding<String>, highSchools: [HighSchoolContext]) {
        _selectedHighSchoolID = selectedHighSchoolID
        rows = highSchools.map(HighSchoolSearchItem.init)
    }

    private var filteredRows: [HighSchoolSearchItem] {
        let query = HighSchoolSearchItem.normalized(searchText)
        guard !query.isEmpty else {
            return rows
        }
        return rows.filter { $0.matches(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredRows) { row in
                        Button {
                            selectedHighSchoolID = row.id
                            dismiss()
                        } label: {
                            HighSchoolSearchRow(
                                school: row.school,
                                isSelected: row.id == selectedHighSchoolID
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("默认项固定在最上方，其余学校按首字母顺序显示")
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

private struct HighSchoolSearchItem: Identifiable {
    let school: HighSchoolContext
    let searchableText: String

    var id: String { school.id }

    init(_ school: HighSchoolContext) {
        self.school = school
        searchableText = [
            school.name,
            school.city,
            school.id
        ]
        .map(Self.normalized)
        .joined(separator: " ")
    }

    func matches(_ query: String) -> Bool {
        searchableText.contains(query)
    }

    static func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
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
                Text(school.city)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct ProfileTopBar: View {
    let progressSegments: [Double]
    let canOpenSelection: Bool
    let selectedCount: Int
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Spacer()
                Button(action: action) {
                    Label(selectedCount == 0 ? "选校" : "选校 \(selectedCount)", systemImage: "building.columns.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(AdmissionSoftButtonStyle(colors: canOpenSelection ? AdmissionStyle.mintNight : [Color.gray.opacity(0.58), Color.gray.opacity(0.34)]))
                .disabled(!canOpenSelection)
                .opacity(canOpenSelection ? 1 : 0.58)
            }

            ProfileCompletionBar(progressSegments: progressSegments)
        }
    }
}

private struct ProfileCompletionBar: View {
    let progressSegments: [Double]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(progressSegments.enumerated()), id: \.offset) { _, progress in
                ProfileCompletionSegment(progress: progress)
            }
        }
        .frame(height: 9)
    }
}

private struct ProfileCompletionSegment: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(1, max(0, progress))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.10))
                if clampedProgress > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AdmissionStyle.controlBlue, Color.cyan.opacity(0.86)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(7, proxy.size.width * clampedProgress))
                }
            }
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
            .foregroundStyle(Color.black.opacity(0.82))
            .opacity(canGoBack ? 1 : 0)
            .disabled(!canGoBack)
            .accessibilityHidden(!canGoBack)

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
            .foregroundStyle(Color.black.opacity(0.82))
            .opacity(canGoForward ? 1 : 0)
            .disabled(!canGoForward)
            .accessibilityHidden(!canGoForward)
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
                Text("美本录取计算器")
                    .font(AdmissionStyle.titleFont(36))
                    .foregroundStyle(.white)
                Text("结合学术匹配、国际生数据和中国本科录取容量，生成可解释的选校估算。")
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
    let subtitle: String?
    let systemImage: String
    let colors: [Color]
    let minHeight: CGFloat?
    let contentVerticalAlignment: VerticalAlignment
    private let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        colors: [Color],
        minHeight: CGFloat? = nil,
        contentVerticalAlignment: VerticalAlignment = .top,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.colors = colors
        self.minHeight = minHeight
        self.contentVerticalAlignment = contentVerticalAlignment
        self.content = content()
    }

    var body: some View {
        AdmissionGradientCard(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            colors: colors,
            fixedHeight: minHeight,
            contentVerticalAlignment: contentVerticalAlignment
        ) {
            content
        }
    }
}

struct ProfileSelectionSettingsCard: View {
    @Binding var profile: StudentProfile
    var fixedHeight: CGFloat? = nil
    let completedAutomaticSummaryAnimationIDs: Set<String>
    let onAutomaticSummaryAnimationCompleted: (String) -> Void

    var body: some View {
        CardSection(
            title: "轮次、资助与选校数量",
            subtitle: selectionCountSubtitle,
            systemImage: "slider.horizontal.3",
            colors: AdmissionStyle.lilac,
            minHeight: fixedHeight,
            contentVerticalAlignment: .center
        ) {
            Picker("申请轮次", selection: $profile.round) {
                ForEach(ApplicationRound.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            Toggle("申请资助", isOn: $profile.needsAid)
                .tint(AdmissionStyle.controlBlue)
            Toggle("纳入文理学院", isOn: $profile.includeLiberalArtsColleges)
                .tint(AdmissionStyle.controlBlue)
            UnboundedCountStepper(title: "计划选择大学", value: $profile.requestedSchoolCount)
            AutomaticGeneratedSchoolSummary(
                count: automaticGeneratedCount,
                scopeNote: automaticGenerationScopeNote,
                generationNote: automaticGenerationNote,
                hasCompletedAnimation: completedAutomaticSummaryAnimationIDs.contains(
                    AutomaticGeneratedSchoolSummary.animationID(
                        count: automaticGeneratedCount,
                        scopeNote: automaticGenerationScopeNote,
                        generationNote: automaticGenerationNote
                    )
                ),
                onAnimationCompleted: onAutomaticSummaryAnimationCompleted
            )
        }
    }

    private var selectionCountSubtitle: String {
        if profile.round == .earlyDecision {
            return "ED/ED2 是绑定申请；同一轮只能保留 1 所。"
        }
        return "设置计划申请数量；EA/RD 和手动选校可多所。"
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

    private var automaticGenerationScopeNote: String {
        profile.includeLiberalArtsColleges
            ? "自动推荐和手动目录会同时包含综合大学与文理学院。"
            : "关闭后，自动推荐、手动目录和至少一所概率都只考虑综合大学。"
    }
}

private struct AutomaticGeneratedSchoolSummary: View {
    let count: Int
    let scopeNote: String
    let generationNote: String
    let hasCompletedAnimation: Bool
    let onAnimationCompleted: (String) -> Void

    @State private var showsNotes = false

    static func animationID(count: Int, scopeNote: String, generationNote: String) -> String {
        "\(count)-\(scopeNote)-\(generationNote)"
    }

    private var resetID: String {
        Self.animationID(count: count, scopeNote: scopeNote, generationNote: generationNote)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("自动生成数量")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 10)
                AdmissionAnimatedCountText(
                    value: count,
                    unit: "所",
                    font: .system(size: 26, weight: .black, design: .rounded),
                    foreground: .white,
                    animates: !hasCompletedAnimation,
                    onSettled: {
                        withAnimation(.easeOut(duration: 0.28)) {
                            showsNotes = true
                        }
                        onAnimationCompleted(resetID)
                    }
                )
                .id(resetID)
            }

            if showsNotes {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scopeNote)
                    Text(generationNote)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.70))
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            showsNotes = hasCompletedAnimation
        }
        .onChange(of: resetID) { _, _ in
            showsNotes = hasCompletedAnimation
        }
        .onChange(of: hasCompletedAnimation) { _, completed in
            if completed {
                showsNotes = true
            }
        }
    }
}

private struct CurriculumPerformanceInputs: View {
    @Binding var profile: StudentProfile
    @Binding var completionState: ProfileFormCompletionState

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
                    letterGrade: $profile.chineseCurriculumLetterGrade,
                    isFilled: completionBinding(.curriculumPrimary)
                )
            case .ap:
	                IntSliderInput(title: "AP / 高级课程门数", value: $profile.apCourseCount, range: 0...12, step: 1, isFilled: completionBinding(.curriculumPrimary))
	                if profile.apCourseCount > 0 {
	                    DecimalSliderInput(
	                        title: "AP 平均分",
	                        value: $profile.apAverageScore,
	                        range: 1...5,
	                        step: 0.5,
	                        displayValue: { String(format: "%.1f", $0) },
                            isFilled: completionBinding(.curriculumSecondary)
	                    )
	                } else {
                    Text("AP 课程门数为 0 时，AP 平均分不会计入课程体系成绩。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                }
            case .ib:
	                IntSliderInput(title: "IB 预估总分", value: $profile.ibPredictedScore, range: 24...45, step: 1, isFilled: completionBinding(.curriculumPrimary))
	            case .alevel:
	                IntArrowInput(title: "A-Level A* 科目", value: $profile.aLevelAStarCount, range: aLevelRange(for: profile.aLevelAStarCount), isFilled: completionBinding(.aLevelAStar))
	                IntArrowInput(title: "A-Level A 科目", value: $profile.aLevelACount, range: aLevelRange(for: profile.aLevelACount), isFilled: completionBinding(.aLevelA))
	                IntArrowInput(title: "A-Level B 科目", value: $profile.aLevelBCount, range: aLevelRange(for: profile.aLevelBCount), isFilled: completionBinding(.aLevelB))
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

    private func completionBinding(_ field: ProfileCompletionField) -> Binding<Bool> {
        Binding(
            get: { completionState.isFilled(field) },
            set: { completionState.set(field, isFilled: $0) }
        )
    }
}

private struct GradeScaleInputs: View {
    let title: String
    @Binding var scale: GradeScale
    @Binding var percent: Double
    @Binding var fourPoint: Double
    @Binding var fivePoint: Double
    @Binding var letterGrade: LetterGradeBand
    var isFilled: Binding<Bool>? = nil

    var body: some View {
        Picker("\(title)方式", selection: $scale) {
            ForEach(GradeScale.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }

        GradeValueInput(
            title: title,
            scale: $scale,
            percent: $percent,
            fourPoint: $fourPoint,
            fivePoint: $fivePoint,
            letterGrade: $letterGrade,
            isFilled: isFilled
        )
    }
}

private struct GradeValueInput: View {
    let title: String
    @Binding var scale: GradeScale
    @Binding var percent: Double
    @Binding var fourPoint: Double
    @Binding var fivePoint: Double
    @Binding var letterGrade: LetterGradeBand
    var isFilled: Binding<Bool>? = nil

    var body: some View {
        switch scale {
        case .percent:
            DecimalSliderInput(title: title, value: $percent, range: 0...100, step: 1, displayValue: { "\(Int($0))" }, isFilled: isFilled)
        case .fourPoint:
            DecimalSliderInput(title: title, value: $fourPoint, range: 0...4, step: 0.1, displayValue: { String(format: "%.1f", $0) }, isFilled: isFilled)
        case .fivePoint:
            DecimalSliderInput(title: title, value: $fivePoint, range: 0...5, step: 0.1, displayValue: { String(format: "%.1f", $0) }, isFilled: isFilled)
        case .letter:
            OptionArrowInput(title: title, selection: $letterGrade, options: LetterGradeBand.allCases, isFilled: isFilled) { $0.rawValue }
        }
    }
}

private struct DecimalSliderInput: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let displayValue: (Double) -> String
    var isFilled: Binding<Bool>? = nil

    var body: some View {
        LabeledContent {
            SliderControl(
                value: valueBinding,
                range: range,
                step: step,
                displayText: displayText
            )
        } label: {
            Text(title)
        }
    }

    private var displayText: String {
        if isFilled?.wrappedValue == false {
            return "-"
        }
        return displayValue(value)
    }

    private var valueBinding: Binding<Double> {
        Binding(
            get: { value },
            set: {
                isFilled?.wrappedValue = true
                value = snapped($0, range: range, step: step)
            }
        )
    }
}

private struct IntSliderInput: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var isFilled: Binding<Bool>? = nil

    var body: some View {
        LabeledContent {
            SliderControl(
                value: valueBinding,
                range: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step),
                displayText: displayText
            )
        } label: {
            Text(title)
        }
    }

    private var displayText: String {
        if isFilled?.wrappedValue == false {
            return "-"
        }
        return "\(value)"
    }

    private var valueBinding: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: {
                isFilled?.wrappedValue = true
                value = clamped(Int($0.rounded()), range: range)
            }
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
            displayText: value.map(String.init),
            disabled: disabled
        )
        .accessibilityLabel(title)
        .accessibilityValue(value.map(String.init) ?? "空")
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
            displayText: value.map(displayValue)
        )
        .accessibilityLabel(title)
        .accessibilityValue(value.map(displayValue) ?? "空")
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
    let displayText: String?
    var disabled = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let displayText {
                Text(displayText)
                    .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.black))
                    .foregroundStyle(disabled ? .secondary : .primary)
                    .frame(minWidth: 58, alignment: .trailing)
            }

            HStack(spacing: 8) {
                IconAdjustButton(systemImage: "minus.circle.fill", disabled: disabled || value <= range.lowerBound) {
                    value = snapped(value - step, range: range, step: step)
                }

                Slider(value: $value, in: range, step: step)
                    .disabled(disabled)
                    .frame(minWidth: 112)

                IconAdjustButton(systemImage: "plus.circle.fill", disabled: disabled || value >= range.upperBound) {
                    value = snapped(value + step, range: range, step: step)
                }
            }
        }
        .frame(maxWidth: 238)
    }
}

private struct IntArrowInput: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var suffix = ""
    var isFilled: Binding<Bool>? = nil

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                IconAdjustButton(systemImage: "chevron.left.circle.fill", disabled: value <= range.lowerBound) {
                    isFilled?.wrappedValue = true
                    value = max(range.lowerBound, value - 1)
                }

                Text(displayText)
                    .font(.system(.headline, design: .rounded).monospacedDigit().weight(.black))
                    .frame(minWidth: 54)

                IconAdjustButton(systemImage: "chevron.right.circle.fill", disabled: value >= range.upperBound) {
                    isFilled?.wrappedValue = true
                    value = min(range.upperBound, value + 1)
                }
            }
        } label: {
            Text(title)
        }
    }

    private var displayText: String {
        if isFilled?.wrappedValue == false {
            return "-"
        }
        return "\(value)\(suffix)"
    }
}

private struct OptionArrowInput<Option: Equatable>: View {
    let title: String
    @Binding var selection: Option
    let options: [Option]
    var isFilled: Binding<Bool>? = nil
    let displayValue: (Option) -> String

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                IconAdjustButton(systemImage: "chevron.left.circle.fill", disabled: currentIndex <= 0) {
                    move(by: -1)
                }

                Text(displayText)
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
        isFilled?.wrappedValue = true
        selection = options[clamped(currentIndex + delta, range: 0...(options.count - 1))]
    }

    private var displayText: String {
        if isFilled?.wrappedValue == false {
            return "-"
        }
        return displayValue(selection)
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
        ScoreSliderRow(title: title, canClear: value != nil && !disabled, clearAction: { value = nil }) {
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

private struct DecimalScoreField: View {
    let title: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        ScoreSliderRow(title: title, canClear: value != nil, clearAction: { value = nil }) {
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

private struct ScoreSliderRow<Control: View>: View {
    let title: String
    let canClear: Bool
    let clearAction: () -> Void
    let control: Control

    init(title: String, canClear: Bool, clearAction: @escaping () -> Void, @ViewBuilder control: () -> Control) {
        self.title = title
        self.canClear = canClear
        self.clearAction = clearAction
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text(title)
                .frame(width: 54, height: 34, alignment: .leading)

            Button(action: clearAction) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 28, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canClear ? Color.white.opacity(0.78) : Color.white.opacity(0.24))
            .disabled(!canClear)

            control
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BandStepper: View {
    let title: String
    @Binding var value: Int
    var isFilled: Binding<Bool>? = nil

    var body: some View {
	        IntArrowInput(title: title, value: $value, range: 1...5, suffix: "/5", isFilled: isFilled)
	    }
	}
