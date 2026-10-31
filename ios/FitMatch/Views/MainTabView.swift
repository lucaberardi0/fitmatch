import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int = 0
    @ObservedObject private var wishlist = WishlistManager.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Tab Screen
            Group {
                switch selectedTab {
                case 0:
                    HomeView(selectedTab: $selectedTab)
                case 1:
                    SearchView()
                case 2:
                    WishlistView()
                case 3:
                    DealsView()
                default:
                    HomeView(selectedTab: $selectedTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating Island Dock (Exact match to User Screenshot)
            ShopFloatingIslandDock(selectedTab: $selectedTab)
                .padding(.bottom, 14)
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Floating Island Dock Component

struct ShopFloatingIslandDock: View {
    @Binding var selectedTab: Int
    @ObservedObject private var wishlist = WishlistManager.shared

    var body: some View {
        HStack(spacing: 20) {
            // 1. Home Button (house.fill)
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    selectedTab = 0
                }
            }) {
                ZStack {
                    if selectedTab == 0 {
                        Circle()
                            .fill(Color(red: 26/255, green: 26/255, blue: 28/255))
                            .frame(width: 44, height: 44)
                            .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
                    }

                    Image(systemName: "house.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(selectedTab == 0 ? .white : Color(red: 90/255, green: 90/255, blue: 95/255))
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            // 2. Search Button (magnifyingglass)
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    selectedTab = 1
                }
            }) {
                ZStack {
                    if selectedTab == 1 {
                        Circle()
                            .fill(Color(red: 26/255, green: 26/255, blue: 28/255))
                            .frame(width: 44, height: 44)
                            .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
                    }

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(selectedTab == 1 ? .white : Color(red: 90/255, green: 90/255, blue: 95/255))
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            // 3. Heart / Wishlist Button (heart.fill)
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    selectedTab = 2
                }
            }) {
                ZStack {
                    if selectedTab == 2 {
                        Circle()
                            .fill(Color(red: 26/255, green: 26/255, blue: 28/255))
                            .frame(width: 44, height: 44)
                            .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
                    }

                    Image(systemName: "heart.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(selectedTab == 2 ? .white : Color(red: 85/255, green: 85/255, blue: 90/255))
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(red: 228/255, green: 232/255, blue: 240/255).opacity(0.94))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 4)
    }
}
