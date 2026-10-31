import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1
    @ObservedObject private var wishlist = WishlistManager.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Shop", systemImage: "bag.fill")
                }
                .tag(0)

            SearchView()
                .tabItem {
                    Label("Cerca Prezzo", systemImage: "magnifyingglass")
                }
                .tag(1)

            DealsView()
                .tabItem {
                    Label("Offerte", systemImage: "flame.fill")
                }
                .tag(2)

            WishlistView()
                .tabItem {
                    Label("Preferiti", systemImage: "heart.fill")
                }
                .badge(wishlist.items.isEmpty ? 0 : wishlist.items.count)
                .tag(3)
        }
        .tint(.shopPurple)
    }
}
