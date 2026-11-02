import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int
    @ObservedObject private var wishlist = WishlistManager.shared

    init(initialTab: Int = 0) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Tab Screen
            Group {
                switch selectedTab {
                case 0:
                    HomeView(selectedTab: $selectedTab, initialSubTab: .perTe)
                case 1:
                    SearchView()
                case 2:
                    HomeView(selectedTab: $selectedTab, initialSubTab: .offerte)
                case 3:
                    WishlistView(selectedTab: $selectedTab)
                default:
                    HomeView(selectedTab: $selectedTab, initialSubTab: .offerte)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating Island Dock (Clean White Pill matching Shop Screenshot 2)
            ShopFloatingIslandDock(selectedTab: $selectedTab)
                .padding(.bottom, 16)
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Floating Island Dock Component (Shopify Shop Style)

struct ShopFloatingIslandDock: View {
    @Binding var selectedTab: Int
    @ObservedObject private var wishlist = WishlistManager.shared

    var body: some View {
        HStack(spacing: 38) {
            // 1. Home
            dockButton(
                index: 0,
                icon: "house.fill",
                size: 21
            )

            // 2. AI Assistant / Search (Speech bubble with sparkle cutout)
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                    selectedTab = 1
                }
            }) {
                ZStack {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(selectedTab == 1 ? Color(red: 24/255, green: 24/255, blue: 27/255) : Color(red: 175/255, green: 175/255, blue: 185/255))

                    Image(systemName: "sparkle")
                        .font(.system(size: 9.5, weight: .heavy))
                        .foregroundColor(selectedTab == 1 ? .white : Color(red: 240/255, green: 240/255, blue: 245/255))
                        .offset(x: -0.5, y: -2)
                }
                .scaleEffect(selectedTab == 1 ? 1.08 : 1.0)
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            // 3. Catalog / Explore
            dockButton(
                index: 2,
                icon: "square.grid.2x2.fill",
                size: 19
            )

            // 4. Saved / Bag
            dockButton(
                index: 3,
                icon: "bag.fill",
                size: 20
            )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(Color.white)
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 5)
    }

    private func dockButton(index: Int, icon: String, size: CGFloat) -> some View {
        Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                selectedTab = index
            }
        }) {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundColor(selectedTab == index ? Color(red: 24/255, green: 24/255, blue: 27/255) : Color(red: 175/255, green: 175/255, blue: 185/255))
                    .scaleEffect(selectedTab == index ? 1.08 : 1.0)
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }
}
