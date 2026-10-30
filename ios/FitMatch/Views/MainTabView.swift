import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Confronto", systemImage: "magnifyingglass")
                }
                .tag(0)

            AIAdvisorView()
                .tabItem {
                    Label("Coach IA", systemImage: "sparkles")
                }
                .tag(1)

            DealsView()
                .tabItem {
                    Label("Top Risparmi", systemImage: "flame.fill")
                }
                .tag(2)
        }
        .tint(.blue)
    }
}
