import SwiftUI

// MARK: - Tab Bar Visibility Manager

final class TabBarVisibilityManager: ObservableObject {
    static let shared = TabBarVisibilityManager()
    @Published var isHidden: Bool = false
    private var hideCount: Int = 0

    func hide() {
        hideCount += 1
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            isHidden = true
        }
    }

    func show() {
        hideCount = max(0, hideCount - 1)
        if hideCount == 0 {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                isHidden = false
            }
        }
    }

    func reset() {
        hideCount = 0
        isHidden = false
    }
}

struct MainTabView: View {
    @State private var selectedTab: Int
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var tabVisibility = TabBarVisibilityManager.shared

    init(initialTab: Int = 0) {
        _selectedTab = State(initialValue: initialTab)
    }

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
                    WishlistView(selectedTab: $selectedTab)
                default:
                    HomeView(selectedTab: $selectedTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating Island Dock (Hidden when entering Detail pages to prevent overlapping purchase buttons)
            if !tabVisibility.isHidden {
                ShopFloatingIslandDock(selectedTab: $selectedTab)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Floating Island Dock Component (Home, Search, Saved)

struct ShopFloatingIslandDock: View {
    @Binding var selectedTab: Int
    @ObservedObject private var wishlist = WishlistManager.shared

    var body: some View {
        HStack(spacing: 50) {
            // 1. Home
            dockButton(
                index: 0,
                icon: "house.fill",
                size: 21
            )

            // 2. Search
            dockButton(
                index: 1,
                icon: "magnifyingglass",
                size: 21
            )

            // 3. Saved (Heart Icon)
            dockButton(
                index: 2,
                icon: selectedTab == 2 ? "heart.fill" : "heart",
                size: 21
            )
        }
        .padding(.horizontal, 34)
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
