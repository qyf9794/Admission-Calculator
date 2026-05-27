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
                    onAutoRecommend: autoRecommend,
                    onEvaluate: evaluate
                )
                .navigationTitle("录取概率")
            }
            .tabItem {
                Label("计算", systemImage: "function")
            }

            NavigationStack {
                ResultsView(result: latestResult, purchaseState: purchaseState, profile: profile)
                    .navigationTitle("结果")
            }
            .tabItem {
                Label("结果", systemImage: "chart.bar.xaxis")
            }

            NavigationStack {
                DataSourcesView()
                    .navigationTitle("数据")
            }
            .tabItem {
                Label("数据", systemImage: "tablecells")
            }
        }
        .onAppear(perform: evaluate)
    }

    private func evaluate() {
        latestResult = engine.evaluate(profile: profile, selectedCollegeIDs: selectedCollegeIDs, selectionSource: selectionSource)
    }

    private func autoRecommend() {
        let recommended = engine.recommendedColleges(
            for: profile,
            reachCount: profile.requestedReachCount,
            targetCount: profile.requestedTargetCount,
            likelyCount: profile.requestedLikelyCount
        )
        let recommendedIDs = Set(recommended.map(\.id))
        selectedCollegeIDs = recommendedIDs
        selectionSource = recommendedIDs.isEmpty ? .none : .automatic
        latestResult = engine.evaluate(profile: profile, selectedCollegeIDs: recommendedIDs, selectionSource: selectionSource)
    }
}
