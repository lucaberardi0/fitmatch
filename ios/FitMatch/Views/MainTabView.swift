import SwiftUI

// MARK: - Tab Bar Visibility Manager

@MainActor
final class TabBarVisibilityManager: ObservableObject {
    static let shared = TabBarVisibilityManager()
    @Published var isHidden: Bool = false
    private var activeReasons = Set<String>()

    func setHidden(_ hidden: Bool, for reason: String = "default") {
        if hidden {
            activeReasons.insert(reason)
        } else {
            activeReasons.remove(reason)
        }
        let shouldHide = !activeReasons.isEmpty
        if isHidden != shouldHide {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                isHidden = shouldHide
            }
        }
    }

    func hide(for reason: String = "default") {
        setHidden(true, for: reason)
    }

    func show(for reason: String = "default") {
        setHidden(false, for: reason)
    }

    func reset() {
        activeReasons.removeAll()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            isHidden = false
        }
    }
}

// MARK: - Tab Coordinator (Preserves tab state and manages seamless cross-tab navigation)

@MainActor
final class TabCoordinator: ObservableObject {
    static let shared = TabCoordinator()

    @Published var selectedTab: Int = 0
    @Published var previousTab: Int? = nil
    @Published var searchSource: String? = nil

    func selectTab(_ index: Int, focusSearch: Bool = false, fromSource: String? = nil) {
        if selectedTab != index {
            previousTab = selectedTab
            searchSource = fromSource
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                selectedTab = index
            }
        }
        if index == 1 && focusSearch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                NotificationCenter.default.post(name: NSNotification.Name("FitMatchFocusSearch"), object: nil)
            }
        }
    }

    func returnToPreviousTab() {
        let target = previousTab ?? 0
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            selectedTab = target
        }
        previousTab = nil
        searchSource = nil
    }
}

struct MainTabView: View {
    @ObservedObject private var coordinator = TabCoordinator.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var tabVisibility = TabBarVisibilityManager.shared
    @ObservedObject private var notifManager = NotificationManager.shared

    init(initialTab: Int = 0) {
        TabCoordinator.shared.selectedTab = initialTab
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Tab Screens (Kept alive in a ZStack so navigation stack & scroll position are never destroyed)
            ZStack {
                HomeView(selectedTab: $coordinator.selectedTab)
                    .opacity(coordinator.selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == 0)

                SearchView()
                    .opacity(coordinator.selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == 1)

                WishlistView(selectedTab: $coordinator.selectedTab)
                    .opacity(coordinator.selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(coordinator.selectedTab == 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating Island Dock (Hidden when entering Detail pages or when typing in search)
            if !tabVisibility.isHidden {
                ShopFloatingIslandDock(selectedTab: $coordinator.selectedTab)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $notifManager.deepLinkProduct) { prod in
            ProductDetailView(product: prod)
        }
        .sheet(item: $notifManager.deepLinkStore) { store in
            NavigationStack {
                StoreDetailView(storeId: store.id, initialStoreName: store.name)
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Floating Island Dock Component (Premium 3-Tab Floating Glass Pill)

struct ShopFloatingIslandDock: View {
    @Binding var selectedTab: Int
    @ObservedObject private var wishlist = WishlistManager.shared

    var body: some View {
        HStack(spacing: 34) {
            // 1. Home
            dockButton(
                index: 0,
                content: AnyView(
                    Image(systemName: "house.fill")
                        .font(.system(size: 21, weight: .semibold))
                )
            )

            // 2. Search & Assistant (Speech bubble with sparkle)
            dockButton(
                index: 1,
                content: AnyView(
                    ZStack {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 21, weight: .bold))

                        Image(systemName: "sparkle")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(selectedTab == 1 ? .white : Color(red: 245/255, green: 245/255, blue: 248/255))
                            .offset(x: -1, y: -1)
                    }
                )
            )

            // 3. Salvati (Heart with Wishlist Notification Dot)
            dockButton(
                index: 2,
                content: AnyView(
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: selectedTab == 2 ? "heart.fill" : "heart")
                            .font(.system(size: 21, weight: selectedTab == 2 ? .bold : .medium))

                        if wishlist.items.count > 0 {
                            Circle()
                                .fill(Color.shopPurple)
                                .frame(width: 7, height: 7)
                                .offset(x: 3, y: -2)
                        }
                    }
                )
            )
        }
        .padding(.horizontal, 28)
        .frame(height: 58)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(Color.white.opacity(0.86))
                )
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.95),
                                    Color.white.opacity(0.35),
                                    Color.black.opacity(0.06)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.09), radius: 18, x: 0, y: 7)
        .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
    }

    private func dockButton(index: Int, content: AnyView) -> some View {
        Button(action: {
            let isSwitchingToSearch = (index == 1)
            TabCoordinator.shared.selectTab(index, focusSearch: isSwitchingToSearch, fromSource: "dock")
            if !isSwitchingToSearch {
                TabCoordinator.shared.previousTab = nil
            }
        }) {
            ZStack {
                if selectedTab == index {
                    Circle()
                        .fill(Color.black.opacity(0.04))
                        .frame(width: 44, height: 44)
                        .transition(.scale.combined(with: .opacity))
                }

                content
                    .foregroundColor(selectedTab == index ? Color(red: 20/255, green: 20/255, blue: 24/255) : Color(red: 140/255, green: 140/255, blue: 150/255))
                    .scaleEffect(selectedTab == index ? 1.06 : 1.0)
            }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
