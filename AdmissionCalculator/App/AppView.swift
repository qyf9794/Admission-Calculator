import SwiftUI

private enum AdmissionFlowStage {
    case hero
    case profile
    case schools
    case results
    case report
}

struct AppView: View {
    @State private var profile = StudentProfile.formDefault
    @State private var profileCompletionState = ProfileFormCompletionState()
    @State private var selectedCollegeIDs: Set<String> = []
    @State private var selectionSource: PortfolioSelectionSource = .none
    @State private var latestResult: PortfolioResult?
    @State private var selectionProfileSnapshot: StudentProfile?
    @State private var completedResultAnimationDates: Set<Date> = []
    @State private var stage: AdmissionFlowStage = .hero
    @State private var profileInitialCardIndex = 0
    @State private var schoolInitialCardIndex = 0
    @StateObject private var purchaseState = ReportPurchaseState()

    private let engine = ChanceEngine()

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .hero:
                    LandingHeroView {
                        profileInitialCardIndex = 0
                        stage = .profile
                    }
                case .profile:
                    CalculatorView(
                        initialCardIndex: profileInitialCardIndex,
                        profile: $profile,
                        completionState: $profileCompletionState,
                        selectedCollegeIDs: $selectedCollegeIDs,
                        selectionSource: $selectionSource,
                        canSwipeToCollegeSelection: selectionIsCurrentForProfile,
                        onOpenCollegeSelection: openCollegeSelection
                    )
                case .schools:
                    CollegePickerView(
                        initialCardIndex: schoolInitialCardIndex,
                        profile: $profile,
                        selectedCollegeIDs: $selectedCollegeIDs,
                        selectionSource: $selectionSource,
                        includeLiberalArtsColleges: profile.includeLiberalArtsColleges,
                        applicationRound: profile.round,
                        requestedSchoolCount: $profile.requestedSchoolCount,
                        currentResult: currentResultForNavigation,
                        onAutoRecommend: autoRecommendForSelection,
                        onBackToProfile: {
                            profileInitialCardIndex = CalculatorView.lastProfileCardIndex
                            stage = .profile
                        },
                        onShowExistingResults: {
                            stage = .results
                        },
                        onEvaluate: evaluateAndShowResults
                    )
                case .results:
                    ResultsView(
                        result: latestResult,
                        isStale: resultIsStale,
                        hasCompletedInitialAnimation: latestResult.map { completedResultAnimationDates.contains($0.generatedAt) } ?? false,
                        onInitialAnimationCompleted: markCurrentResultAnimationCompleted,
                        onBackToSchools: {
                            schoolInitialCardIndex = CollegePickerView.lastCardIndex
                            stage = .schools
                        },
                        onAnalyze: {
                            stage = .report
                        }
                    )
                case .report:
                    ReportView(
                        result: latestResult,
                        purchaseState: purchaseState,
                        isStale: resultIsStale,
                        onBackToResults: {
                            stage = .results
                        },
                        onStartOver: resetAndGoBackToHero
                    )
                }
            }
            .id(stage)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.black)
        .preferredColorScheme(.light)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(AdmissionStyle.pageBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func evaluateAndShowResults() {
        latestResult = engine.evaluate(profile: profile, selectedCollegeIDs: selectedCollegeIDs, selectionSource: selectionSource)
        selectionProfileSnapshot = profile
        stage = .results
    }

    private func autoRecommendForSelection() {
        let result = engine.evaluateAutomaticRecommendation(profile: profile)
        selectedCollegeIDs = Set(result.recommendedSchools.map(\.id))
        selectionSource = .automatic
        latestResult = nil
        selectionProfileSnapshot = profile
    }

    private func openCollegeSelection() {
        saveProfileLocally()
        selectionProfileSnapshot = profile
        schoolInitialCardIndex = 0
        stage = .schools
    }

    private func goBackToHero() {
        stage = .hero
    }

    private func resetAndGoBackToHero() {
        selectedCollegeIDs = []
        selectionSource = .none
        latestResult = nil
        selectionProfileSnapshot = nil
        completedResultAnimationDates = []
        profileInitialCardIndex = 0
        schoolInitialCardIndex = 0
        purchaseState.resetForNewCalculation()
        goBackToHero()
    }

    private func saveProfileLocally() {
        guard let data = try? JSONEncoder().encode(profile) else {
            return
        }
        UserDefaults.standard.set(data, forKey: "AdmissionCalculator.savedStudentProfile")
    }

    private var resultIsStale: Bool {
        guard let latestResult else {
            return false
        }
        return !resultMatchesCurrentState(latestResult)
    }

    private var selectionIsCurrentForProfile: Bool {
        guard let selectionProfileSnapshot else {
            return false
        }
        return selectionProfileSnapshot == profile
    }

    private var currentResultForNavigation: PortfolioResult? {
        guard let latestResult, resultMatchesCurrentState(latestResult) else {
            return nil
        }
        return latestResult
    }

    private func resultMatchesCurrentState(_ result: PortfolioResult) -> Bool {
        result.profileSnapshot == profile &&
            result.selectedCollegeIDs == selectedCollegeIDs &&
            result.selectionSource == selectionSource
    }

    private func markCurrentResultAnimationCompleted() {
        guard let latestResult else {
            return
        }
        completedResultAnimationDates.insert(latestResult.generatedAt)
    }
}

private struct LandingHeroView: View {
    let onStart: () -> Void

    var body: some View {
        ZStack {
            AdmissionPageBackground()
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 18)
                AdmissionHeroCard(colors: AdmissionStyle.blackGlass) {
                    ZStack(alignment: .bottomLeading) {
                        LandingHeroCircleGrid()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .allowsHitTesting(false)

                        VStack(alignment: .leading, spacing: 18) {
                            Label("中国学生美本录取概率规划", systemImage: "sparkle.magnifyingglass")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.82))
                            Text("美本录取计算器")
                                .font(AdmissionStyle.titleFont(44))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Text("基于学术匹配、国际生数据和中国本科录取容量，估算当前选校组合的录取机会。")
                                .font(.system(.body, design: .rounded).weight(.medium))
                                .foregroundStyle(.white.opacity(0.84))
                                .fixedSize(horizontal: false, vertical: true)
                            Button(action: onStart) {
                                Label("开始", systemImage: "arrow.right.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AdmissionSoftButtonStyle(colors: AdmissionStyle.pinkMist))
                            .controlSize(.large)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 420, alignment: .bottomLeading)
                }
                .frame(maxHeight: 520)
                Spacer(minLength: 18)
            }
            .padding(16)
        }
    }
}

private struct LandingHeroCircleGrid: View {
    private let columns = 5
    private let rows = 4
    private let inset: CGFloat = 30
    private let circleSize: CGFloat = 55

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, proxy.size.width - inset * 2)
            let height = max(0, proxy.size.height * 0.50 - inset * 2)
            let xStep = columns > 1 ? width / CGFloat(columns - 1) : 0
            let yStep = rows > 1 ? height / CGFloat(rows - 1) : 0

            ForEach(0..<(rows * columns), id: \.self) { index in
                let row = index / columns
                let column = index % columns
                Circle()
                    .fill(Color(red: 0.10, green: 0.11, blue: 0.12).opacity(0.50))
                    .frame(width: circleSize, height: circleSize)
                    .position(
                        x: inset + CGFloat(column) * xStep,
                        y: inset + CGFloat(row) * yStep
                    )
            }
        }
    }

}
