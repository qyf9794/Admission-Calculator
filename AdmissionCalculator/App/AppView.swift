import SwiftUI

private enum AdmissionFlowStage {
    case hero
    case profile
    case schools
    case results
    case report
}

struct AppView: View {
    @State private var profile = StudentProfile.sample
    @State private var selectedCollegeIDs: Set<String> = []
    @State private var selectionSource: PortfolioSelectionSource = .none
    @State private var latestResult: PortfolioResult?
    @State private var stage: AdmissionFlowStage = .hero
    @StateObject private var purchaseState = ReportPurchaseState()

    private let engine = ChanceEngine()

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .hero:
                    LandingHeroView {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                            stage = .profile
                        }
                    }
                case .profile:
                CalculatorView(
                    profile: $profile,
                    selectedCollegeIDs: $selectedCollegeIDs,
                    selectionSource: $selectionSource,
                    hasExistingResult: latestResult != nil,
                        onOpenCollegeSelection: openCollegeSelection
                )
                case .schools:
                    CollegePickerView(
                        selectedCollegeIDs: $selectedCollegeIDs,
                        selectionSource: $selectionSource,
                        includeLiberalArtsColleges: profile.includeLiberalArtsColleges,
                        applicationRound: profile.round,
                        requestedSchoolCount: $profile.requestedSchoolCount,
                        onAutoRecommend: autoRecommendForSelection,
                        onBackToProfile: { withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { stage = .profile } },
                        onEvaluate: evaluateAndShowResults
                    )
                case .results:
                    ResultsView(
                        result: latestResult,
                        isStale: resultIsStale,
                        onAnalyze: { withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { stage = .report } }
                    )
                case .report:
                    ReportView(
                        result: latestResult,
                        purchaseState: purchaseState,
                        isStale: resultIsStale,
                        onBackToResults: { withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { stage = .results } }
                    )
                }
            }
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
        withAnimation(.spring(response: 0.44, dampingFraction: 0.88)) {
            stage = .results
        }
    }

    private func autoRecommendForSelection() {
        let result = engine.evaluateAutomaticRecommendation(profile: profile)
        selectedCollegeIDs = Set(result.recommendedSchools.map(\.id))
        selectionSource = .automatic
        latestResult = nil
    }

    private func openCollegeSelection() {
        saveProfileLocally()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            stage = .schools
        }
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
        return latestResult.profileSnapshot != profile ||
            latestResult.selectedCollegeIDs != selectedCollegeIDs ||
            latestResult.selectionSource != selectionSource
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
                    VStack(alignment: .leading, spacing: 18) {
                        Label("中国学生美本录取概率规划", systemImage: "sparkle.magnifyingglass")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                        Text("Admit Chance")
                            .font(AdmissionStyle.titleFont(44))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text("按硬门槛、学术匹配、国际生数据和中国本科录取容量，估算当前选校组合的录取机会。结果用于规划，不是承诺。")
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
                }
                .frame(maxHeight: 520)
                Spacer(minLength: 18)
            }
            .padding(16)
        }
    }
}
