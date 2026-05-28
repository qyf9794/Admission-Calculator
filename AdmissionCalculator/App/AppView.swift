import SwiftUI

struct AppView: View {
    @State private var profile = StudentProfile.sample
    @State private var selectedCollegeIDs: Set<String> = []
    @State private var selectionSource: PortfolioSelectionSource = .none
    @State private var latestResult: PortfolioResult?
    @StateObject private var purchaseState = ReportPurchaseState()

    private let engine = ChanceEngine()

    var body: some View {
        TabView {
            NavigationStack {
                CalculatorView(
                    profile: $profile,
                    selectedCollegeIDs: $selectedCollegeIDs,
                    selectionSource: $selectionSource,
                    hasExistingResult: latestResult != nil,
                    onAutoRecommend: autoRecommend,
                    onEvaluate: evaluate
                )
                .navigationTitle("录取概率")
            }
            .tabItem {
                Label("计算", systemImage: "function")
            }

            NavigationStack {
                ResultsView(result: latestResult, isStale: resultIsStale)
                    .navigationTitle("结果")
            }
            .tabItem {
                Label("结果", systemImage: "chart.bar.xaxis")
            }

            NavigationStack {
                ReportView(result: latestResult, purchaseState: purchaseState, isStale: resultIsStale)
                    .navigationTitle("报告")
            }
            .tabItem {
                Label("报告", systemImage: "doc.text.magnifyingglass")
            }
        }
    }

    private func evaluate() {
        latestResult = engine.evaluate(profile: profile, selectedCollegeIDs: selectedCollegeIDs, selectionSource: selectionSource)
    }

    private func autoRecommend() {
        let result = engine.evaluateAutomaticRecommendation(profile: profile)
        selectedCollegeIDs = Set(result.recommendedSchools.map(\.id))
        selectionSource = .automatic
        latestResult = result
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
