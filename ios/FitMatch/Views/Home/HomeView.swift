import SwiftUI

enum HomeSubTab: Int, CaseIterable, Identifiable {
    case perTe = 0
    case offerte = 1
    case seguiGia = 2
    case salvati = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .perTe: return "Per te"
        case .offerte: return "Offerte"
        case .seguiGia: return "Segui già"
        case .salvati: return "Salvati"
        }
    }
}

struct HomeView: View {
    @Binding var selectedTab: Int
    var initialSubTab: HomeSubTab = .perTe
    @State private var activeSubTab: HomeSubTab

    init(selectedTab: Binding<Int>, initialSubTab: HomeSubTab = .perTe) {
        self._selectedTab = selectedTab
        self.initialSubTab = initialSubTab
        self._activeSubTab = State(initialValue: initialSubTab)

        let cached = APIService.shared.cachedHomeShowcases() ?? []
        self._showcases = State(initialValue: cached)
        self._isLoading = State(initialValue: cached.isEmpty)
        if !cached.isEmpty {
            let initialRanked = Self.computeRankedShowcases(from: cached)
            self._rankedShowcases = State(initialValue: initialRanked)
        }
    }

    @StateObject private var api = APIService.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var recentManager = RecentActivityManager.shared
    @ObservedObject private var notifManager = NotificationManager.shared
    @ObservedObject private var prefsManager = UserPreferencesManager.shared

    @State private var showcases: [StoreShowcase] = []
    @State private var rankedShowcases: [StoreShowcase] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var showingAccountSheet = false
    @State private var showingNotificationsSheet = false

    // Interactive Menu States (Screenshot 3)
    @State private var reportingStore: StoreShowcase? = nil
    @State private var showingReportAlert = false
    @State private var toastMessage: String? = nil
    @State private var hiddenStoreIdToUndo: String? = nil
    @State private var navigatingStore: StoreShowcase? = nil
    @State private var subTabDirection: Int = 1
    @Namespace private var subTabNamespace

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // MARK: - 1. Pinned Top Header: Avatar "L" | Search Bar "Cerca" | Bell
                    topHeaderBar
                        .shopHeaderBarPadding()

                    if isLoading && showcases.isEmpty {
                        // MARK: - Shopify Shop Skeleton Loading Screen
                        ShopHomeSkeletonView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                    } else {
                        // MARK: - 2. Sub-Navigation Pills: Per te | Offerte | Segui già | Salvati
                        subNavigationPills
                            .padding(.bottom, ShopLayout.compactSpacing)

                        // MARK: - 3. Content Area based on Active Sub-Tab
                        ZStack {
                            switch activeSubTab {
                            case .perTe:
                                perTeContent
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(edge: subTabDirection >= 0 ? .trailing : .leading).combined(with: .opacity),
                                            removal: .move(edge: subTabDirection >= 0 ? .leading : .trailing).combined(with: .opacity)
                                        )
                                    )
                            case .offerte:
                                DealsView(embedded: true, onSelectPerTe: {
                                    subTabDirection = -1
                                    withAnimation(ShopMotion.pillSlide) {
                                        activeSubTab = .perTe
                                    }
                                })
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: subTabDirection >= 0 ? .trailing : .leading).combined(with: .opacity),
                                        removal: .move(edge: subTabDirection >= 0 ? .leading : .trailing).combined(with: .opacity)
                                    )
                                )
                            case .seguiGia:
                                FollowingView(onGoShopping: {
                                    subTabDirection = -1
                                    withAnimation(ShopMotion.pillSlide) {
                                        activeSubTab = .perTe
                                    }
                                })
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: subTabDirection >= 0 ? .trailing : .leading).combined(with: .opacity),
                                        removal: .move(edge: subTabDirection >= 0 ? .leading : .trailing).combined(with: .opacity)
                                    )
                                )
                            case .salvati:
                                WishlistView(selectedTab: $selectedTab, embedded: true, onSelectPerTe: {
                                    subTabDirection = -1
                                    withAnimation(ShopMotion.pillSlide) {
                                        activeSubTab = .perTe
                                    }
                                })
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: subTabDirection >= 0 ? .trailing : .leading).combined(with: .opacity),
                                        removal: .move(edge: subTabDirection >= 0 ? .leading : .trailing).combined(with: .opacity)
                                    )
                                )
                            }
                        }
                        .animation(ShopMotion.pillSlide, value: activeSubTab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .animation(.easeOut(duration: 0.28), value: isLoading)
                .background(Color.shopSurface.ignoresSafeArea())

                // MARK: - Floating Toast Notification (Undo Hide Store, Confirmation)
                if let msg = toastMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)

                        Text(msg)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        if let undoId = hiddenStoreIdToUndo {
                            Button(action: {
                                followedManager.unhideStore(storeId: undoId)
                                withAnimation {
                                    hiddenStoreIdToUndo = nil
                                    toastMessage = nil
                                }
                            }) {
                                Text("Annulla")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 196/255, green: 181/255, blue: 253/255))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(red: 28/255, green: 28/255, blue: 34/255))
                    .cornerRadius(18)
                    .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 4)
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.bottom, ShopLayout.toastBottomOffset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $navigatingStore) { sc in
                StoreDetailView(storeId: sc.store_id, initialStoreName: sc.store_name)
            }
            .sheet(isPresented: $showingAccountSheet) {
                AccountView()
            }
            .sheet(isPresented: $showingNotificationsSheet) {
                NotificationsView()
            }
            .alert("Segnala Negozio", isPresented: $showingReportAlert, presenting: reportingStore) { store in
                Button("Invia Segnalazione", role: .destructive) {
                    followedManager.reportStore(storeId: store.store_id, storeName: store.store_name)
                    withAnimation {
                        toastMessage = "Grazie per la segnalazione su \(store.store_name)."
                        hiddenStoreIdToUndo = nil
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        withAnimation { toastMessage = nil }
                    }
                }
                Button("Annulla", role: .cancel) { }
            } message: { store in
                Text("Vuoi segnalare '\(store.store_name)' al team di FitMatch per prezzi non aggiornati o violazioni?")
            }
            .task {
                if showcases.isEmpty || !api.isHomeCacheFresh() {
                    await fetchShowcases(forceRefresh: !showcases.isEmpty)
                } else {
                    recomputeRankedShowcases()
                    Task { await api.prefetchDefaultDealsIfNeeded() }
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
                await notifManager.checkIntelligentNotifications()
            }
            .onChange(of: personalizationSignature) { _ in
                recomputeRankedShowcases()
            }
        }
    }

    // MARK: - Top Header Bar (Screenshot 1: Avatar "L" | Search "Cerca" | Bell)

    private var topHeaderBar: some View {
        HStack(spacing: 12) {
            // User Avatar (Purple circle with 'L')
            Button(action: { showingAccountSheet = true }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 196/255, green: 181/255, blue: 253/255))
                        .frame(width: 42, height: 42)

                    Text("L")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)

            // Search Bar Capsule ("Cerca")
            Button(action: {
                TabCoordinator.shared.selectTab(1, focusSearch: true, fromSource: "home")
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(red: 135/255, green: 135/255, blue: 145/255))

                    Text("Cerca")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(Color(red: 135/255, green: 135/255, blue: 145/255))

                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: ShopLayout.searchPillHeight)
                .background(Color.white)
                .cornerRadius(ShopLayout.searchPillHeight / 2)
                .overlay(
                    RoundedRectangle(cornerRadius: ShopLayout.searchPillHeight / 2)
                        .stroke(Color.shopBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Bell Notifications Button
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                showingNotificationsSheet = true
            }) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 42, height: 42)
                        .overlay(
                            Circle()
                                .stroke(Color.shopBorder, lineWidth: 1)
                        )

                    Image(systemName: "bell.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                        .frame(width: 42, height: 42)

                    if notifManager.unreadCount > 0 {
                        Text("\(min(notifManager.unreadCount, 99))")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 2)
                            .background(Color(red: 228/255, green: 42/255, blue: 38/255))
                            .clipShape(Capsule())
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sub-Navigation Pills (Per te | Offerte | Segui già | Salvati)

    private var subNavigationPills: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HomeSubTab.allCases) { tab in
                        let isSelected = activeSubTab == tab

                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.impactOccurred()
                            if tab == .salvati {
                                withAnimation(ShopMotion.tabSwitch) {
                                    selectedTab = 2
                                }
                            } else if activeSubTab == tab {
                                TabCoordinator.shared.triggerScrollToTop(for: 0)
                            } else {
                                subTabDirection = tab.rawValue >= activeSubTab.rawValue ? 1 : -1
                                withAnimation(ShopMotion.pillSlide) {
                                    activeSubTab = tab
                                    scrollProxy.scrollTo(tab.id, anchor: .center)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                // Subtle flame icon for deals
                                if tab == .offerte {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color(red: 245/255, green: 75/255, blue: 45/255))
                                }

                                Text(tab.title)
                                    .font(.system(size: 13.5, weight: isSelected ? .bold : .semibold, design: .rounded))
                                    .foregroundColor(isSelected ? Color(red: 18/255, green: 18/255, blue: 24/255) : Color(red: 95/255, green: 98/255, blue: 110/255))

                                // Dynamic badge for Salvati
                                if tab == .salvati && wishlist.items.count > 0 {
                                    Text("\(wishlist.items.count)")
                                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                        .foregroundColor(isSelected ? .white : Color(red: 95/255, green: 98/255, blue: 110/255))
                                        .padding(.horizontal, 5.5)
                                        .padding(.vertical, 1.5)
                                        .background(
                                            isSelected ?
                                                Color.shopPurple :
                                                Color.black.opacity(0.08)
                                        )
                                        .clipShape(Capsule())
                                }

                                // Dynamic badge for Segui già
                                if tab == .seguiGia && followedManager.followedStores.count > 0 {
                                    Text("\(followedManager.followedStores.count)")
                                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                        .foregroundColor(isSelected ? .white : Color(red: 95/255, green: 98/255, blue: 110/255))
                                        .padding(.horizontal, 5.5)
                                        .padding(.vertical, 1.5)
                                        .background(
                                            isSelected ?
                                                Color.shopDark :
                                                Color.black.opacity(0.08)
                                        )
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8.5)
                            .background(
                                ZStack {
                                    Capsule()
                                        .fill(Color.white.opacity(0.68))

                                    if isSelected {
                                        Capsule()
                                            .fill(Color.white)
                                            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                                            .matchedGeometryEffect(id: "home_subtab_pill", in: subTabNamespace)
                                    }
                                }
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isSelected ?
                                            Color(red: 226/255, green: 228/255, blue: 236/255) :
                                            Color(red: 234/255, green: 235/255, blue: 240/255),
                                        lineWidth: 1
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.96, pressedOpacity: 0.92))
                        .id(tab.id)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - "Per te" Feed Content (Personalized & Ranked)

    private var personalizationSignature: String {
        let followed = followedManager.followedStores.map(\.store_id).joined(separator: ",")
        let hidden = followedManager.hiddenStoreIds.sorted().joined(separator: ",")
        let sports = prefsManager.preferences.selectedSports.joined(separator: ",")
        let brands = prefsManager.preferences.favoriteBrands.joined(separator: ",")
        return "\(showcases.count)|\(prefsManager.preferences.preferredShoeSize)|\(prefsManager.preferences.preferredApparelSize)|\(sports)|\(brands)|\(followed)|\(hidden)|\(recentManager.activities.count)|\(wishlist.items.count)"
    }

    private static func computeRankedShowcases(from source: [StoreShowcase]) -> [StoreShowcase] {
        let followedManager = FollowedStoresManager.shared
        let prefsManager = UserPreferencesManager.shared
        let recentManager = RecentActivityManager.shared
        let wishlist = WishlistManager.shared
        let active = source.filter {
            !$0.products.isEmpty && !followedManager.isStoreHidden(storeId: $0.store_id)
        }
        return prefsManager.personalizeShowcases(
            active,
            followedStoreIds: Set(followedManager.followedStores.map { $0.store_id.lowercased() }),
            recentStoreIds: Set(recentManager.activities.compactMap { $0.storeId?.lowercased() }),
            wishlistStoreNames: Set(wishlist.items.compactMap { $0.bestStore?.lowercased() })
        )
    }

    private func recomputeRankedShowcases() {
        rankedShowcases = Self.computeRankedShowcases(from: showcases)
    }

    private var perTeContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: ShopLayout.sectionSpacing) {
                    // MARK: 1. Top Carousel of Summary Cards: "Visti di recente" & "Elementi salvati" (Screenshots 1 & 2)
                    topSummaryCardsCarousel
                        .padding(.top, 2)

                // MARK: 2. Real Database Partner Stores (Ranked & Personalized, Lazily Rendered)
                let currentShowcases = rankedShowcases.isEmpty && !showcases.isEmpty ? Self.computeRankedShowcases(from: showcases) : rankedShowcases

                if isLoading && currentShowcases.isEmpty {
                    VStack(spacing: ShopLayout.cardSpacing) {
                        ShopSkeletonBlock(
                            cornerRadius: ShopLayout.largeCardRadius,
                            width: UIScreen.main.bounds.width - (ShopLayout.screenPadding * 2),
                            height: 390
                        )
                        ShopSkeletonBlock(
                            cornerRadius: ShopLayout.largeCardRadius,
                            width: UIScreen.main.bounds.width - (ShopLayout.screenPadding * 2),
                            height: 220
                        )
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
                } else {
                    LazyVStack(spacing: ShopLayout.sectionSpacing) {
                        ForEach(Array(currentShowcases.enumerated()), id: \.element.id) { index, sc in
                            if sc.card_theme == "olive" || sc.card_theme == "colored" || (sc.accent_color != nil && sc.card_theme != "grid" && sc.card_theme != "white") || (sc.card_theme == nil && index % 4 == 0) {
                                // Accent / Colored Card (driven by database card_theme or accent_color)
                                oliveShopStoreCard(showcase: sc)
                                    .padding(.horizontal, ShopLayout.screenPadding)
                            } else if sc.card_theme == "grid" || (sc.card_theme == nil && index % 4 == 2 && sc.products.count >= 4) {
                                // 2-Column Grid Card (driven by database card_theme == "grid")
                                gridShopStoreCard(showcase: sc)
                                    .padding(.horizontal, ShopLayout.screenPadding)
                            } else {
                                // Clean White Horizontal Carousel Card (driven by database card_theme == "white")
                                whiteShopStoreCard(showcase: sc)
                                    .padding(.horizontal, ShopLayout.screenPadding)
                            }
                        }
                    }
                }

                Spacer(minLength: ShopLayout.bottomDockClearance)
            }
            .animation(.easeOut(duration: 0.24), value: isLoading)
            .id("home_per_te_top")
        }
        .refreshable {
            await fetchShowcases(forceRefresh: true)
            await recentManager.syncFromDatabase()
        }
        .onReceive(TabCoordinator.shared.$scrollToTopEvent) { event in
            guard let event, event.tab == 0, activeSubTab == .perTe else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                scrollProxy.scrollTo("home_per_te_top", anchor: .top)
            }
        }
        }
    }

    // MARK: - 1. Top Summary Cards Carousel (Screenshots 1 & 2: Visti di recente | Elementi salvati)

    private var topSummaryCardsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Card 1: "Visti di recente"
                recentlyViewedSummaryCard

                // Card 2: "Elementi salvati"
                savedItemsSummaryCard
            }
            .padding(.horizontal, 16)
        }
    }

    // Card 1: Visti di recente (Screenshot 1)
    private var summaryCardWidth: CGFloat {
        max(UIScreen.main.bounds.width - 56, 310)
    }

    private var summaryThumbSize: CGFloat {
        (summaryCardWidth - (ShopLayout.cardPadding * 2) - 20) / 3
    }

    private var summaryCardHeight: CGFloat {
        max(164, summaryThumbSize + (ShopLayout.cardPadding * 2) + 14 + 32)
    }

    private var recentlyViewedSummaryCard: some View {
        let cardWidth = summaryCardWidth
        let thumbSize = summaryThumbSize

        return VStack(alignment: .leading, spacing: 14) {
            // Header: Title + Circular Chevron Button (Pushes RecentlyViewedView)
            NavigationLink(destination: RecentlyViewedView()) {
                HStack {
                    Text("Visti di recente")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Spacer()

                    Circle()
                        .fill(Color.shopSurface)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.shopTextMuted)
                        )
                }
            }
            .buttonStyle(.plain)

            // Thumbnails of real recently viewed items
            let items = previewRecentProducts
            if items.isEmpty {
                FitMatchInlineEmptyRow(
                    icon: "clock.arrow.circlepath",
                    illustrationName: "empty_recently_viewed",
                    accentColor: .shopPurple,
                    title: "Nessun modello consultato",
                    subtitle: "Scarpe da running, smartwatch GPS e attrezzatura visti appariranno qui"
                )
            } else {
                HStack(spacing: 10) {
                    ForEach(items) { prod in
                        NavigationLink(destination: ProductDetailView(product: prod)) {
                            ZStack {
                                RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                                    .fill(Color.shopSurface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                                            .stroke(Color.shopBorder, lineWidth: 1)
                                    )

                                if let imgUrl = prod.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                                    ShopCachedAsyncImage(url: url) { phase in
                                        if let img = phase.image {
                                            img
                                                .resizable()
                                                .scaledToFit()
                                                .padding(6)
                                        } else {
                                            ShopSkeletonBlock(cornerRadius: 12)
                                        }
                                    }
                                } else {
                                    Image(systemName: "clock")
                                        .font(.system(size: 22))
                                        .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                }
                            }
                            .frame(width: thumbSize, height: thumbSize)
                            .clipShape(RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: cardWidth, height: summaryCardHeight - (ShopLayout.cardPadding * 2), alignment: .topLeading)
        .shopCard(padding: ShopLayout.cardPadding, cornerRadius: ShopLayout.largeCardRadius, shadowOpacity: 0.03, shadowRadius: 8, shadowY: 2)
    }

    // Card 2: Elementi salvati (Screenshot 2)
    private var savedItemsSummaryCard: some View {
        let cardWidth = summaryCardWidth
        let thumbSize = summaryThumbSize

        return VStack(alignment: .leading, spacing: 14) {
            // Header: Title + Circular Chevron Button (switches to Salvati tab)
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    selectedTab = 2
                }
            }) {
                HStack {
                    Text("Elementi salvati")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Spacer()

                    Circle()
                        .fill(Color.shopSurface)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.shopTextMuted)
                        )
                }
            }
            .buttonStyle(.plain)

            // Thumbnails of real saved items
            let saved = Array(wishlist.items.prefix(3))
            if saved.isEmpty {
                Button(action: {
                    let gen = UIImpactFeedbackGenerator(style: .light)
                    gen.impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        selectedTab = 2
                    }
                }) {
                    FitMatchInlineEmptyRow(
                        icon: "heart",
                        illustrationName: "empty_wishlist",
                        accentColor: .shopRed,
                        title: "Nessun modello monitorato",
                        subtitle: "Salva scarpe o orologi GPS per seguire taglie e cali di prezzo",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    ForEach(saved) { item in
                        NavigationLink(destination: ProductDetailView(product: item.toMatchedProduct())) {
                            ZStack {
                                RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                                    .fill(Color.shopSurface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                                            .stroke(Color.shopBorder, lineWidth: 1)
                                    )

                                if let imgUrl = item.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                                    ShopCachedAsyncImage(url: url) { phase in
                                        if let img = phase.image {
                                            img
                                                .resizable()
                                                .scaledToFit()
                                                .padding(6)
                                        } else {
                                            ShopSkeletonBlock(cornerRadius: 12)
                                        }
                                    }
                                } else {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(Color.shopRed.opacity(0.4))
                                }
                            }
                            .frame(width: thumbSize, height: thumbSize)
                            .clipShape(RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: cardWidth, height: summaryCardHeight - (ShopLayout.cardPadding * 2), alignment: .topLeading)
        .shopCard(padding: ShopLayout.cardPadding, cornerRadius: ShopLayout.largeCardRadius, shadowOpacity: 0.03, shadowRadius: 8, shadowY: 2)
    }

    // MARK: - Shared Store Card Chrome

    private func shopStoreCardHeader(showcase: StoreShowcase, isDarkBackground: Bool) -> some View {
        HStack(spacing: 12) {
            NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                HStack(spacing: 12) {
                    ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 44, logoURL: showcase.logo_url)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(showcase.store_name)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(isDarkBackground ? .white : .shopDark)

                            if followedManager.isFollowing(storeId: showcase.store_id) {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9.5, weight: .bold))
                                    Text("Segui già")
                                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isDarkBackground ? Color.white.opacity(0.22) : Color.shopPurple.opacity(0.12))
                                .foregroundColor(isDarkBackground ? .white : .shopPurple)
                                .clipShape(Capsule())
                            }
                        }

                        Text(showcase.formattedRatingWithReviews)
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundColor(isDarkBackground ? .white.opacity(0.92) : .shopTextMuted)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            storeContextMenu(showcase: showcase, isDarkBackground: isDarkBackground)
        }
        .padding(.horizontal, ShopLayout.cardPadding)
        .padding(.top, ShopLayout.cardPadding)
    }

    private func shopStoreCardFooter(showcase: StoreShowcase, isDarkBackground: Bool) -> some View {
        NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
            HStack {
                Text("Acquista tutto")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(isDarkBackground ? .white : .shopDark)

                Spacer()

                Circle()
                    .fill(isDarkBackground ? Color.white.opacity(0.24) : Color.shopSurfaceElevated)
                    .frame(width: ShopLayout.navButtonSize, height: ShopLayout.navButtonSize)
                    .overlay(
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(isDarkBackground ? .white : .shopDark)
                    )
            }
            .padding(.horizontal, ShopLayout.cardPadding)
            .padding(.bottom, ShopLayout.cardPadding)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Olive / Accent Shop Store Card (Driven by Database card_theme & accent_color)

    private func oliveShopStoreCard(showcase: StoreShowcase) -> some View {
        let cardBgColor: Color = {
            if let hex = showcase.accent_color, let c = Color(hex: hex) {
                return c
            }
            if let registryHex = (DynamicCatalogRegistry.shared.storeItem(for: showcase.store_id)
                ?? DynamicCatalogRegistry.shared.storeItem(for: showcase.store_name))?.accent_color,
               let c = Color(hex: registryHex) {
                return c
            }
            return Color(red: 98/255, green: 125/255, blue: 86/255) // #627D56 authentic olive fallback
        }()
        let stops = cardBgColor.cardGradientStops()

        return VStack(alignment: .leading, spacing: ShopLayout.cardSpacing) {
            shopStoreCardHeader(showcase: showcase, isDarkBackground: true)

            // Horizontal Carousel of Pure White Product Cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ShopLayout.compactSpacing) {
                    ForEach(showcase.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                        cleanProductCard(product: prod, matchedProduct: matched, cardBg: .white)
                            .shopCarouselTransition()
                    }
                }
                .padding(.horizontal, ShopLayout.cardPadding)
            }

            shopStoreCardFooter(showcase: showcase, isDarkBackground: true)
        }
        .background(
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: stops.start, location: 0.0),
                        .init(color: stops.mid, location: 0.46),
                        .init(color: stops.end, location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color.white.opacity(0.14),
                        Color.white.opacity(0.03),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 12,
                    endRadius: 260
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: ShopLayout.largeCardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ShopLayout.largeCardRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.24), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: cardBgColor.opacity(0.22), radius: 12, x: 0, y: 5)
    }

    // MARK: - 3. Clean White Horizontal Carousel Store Card (Screenshots 1 & 5: PeakPulse / dripuniqueuk)

    private func whiteShopStoreCard(showcase: StoreShowcase) -> some View {
        VStack(alignment: .leading, spacing: ShopLayout.cardSpacing) {
            shopStoreCardHeader(showcase: showcase, isDarkBackground: false)

            // Horizontal Carousel of Clean Light Neutral Product Cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ShopLayout.compactSpacing) {
                    ForEach(showcase.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                        cleanProductCard(product: prod, matchedProduct: matched, cardBg: Color.shopSurface)
                            .shopCarouselTransition()
                    }
                }
                .padding(.horizontal, ShopLayout.cardPadding)
            }

            shopStoreCardFooter(showcase: showcase, isDarkBackground: false)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: ShopLayout.largeCardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ShopLayout.largeCardRadius, style: .continuous)
                .stroke(Color.shopBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 3)
    }

    // MARK: - 4. 2-Column Grid Store Card (Screenshot 4: il Numero Diez Style)

    private func gridShopStoreCard(showcase: StoreShowcase) -> some View {
        VStack(alignment: .leading, spacing: ShopLayout.cardSpacing) {
            shopStoreCardHeader(showcase: showcase, isDarkBackground: false)

            // 2-Column Grid of 6 Items (Screenshot 4)
            let items = Array(showcase.products.prefix(6))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(items) { prod in
                    let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                    cleanProductGridItem(product: prod, matchedProduct: matched)
                }
            }
            .padding(.horizontal, ShopLayout.cardPadding)

            shopStoreCardFooter(showcase: showcase, isDarkBackground: false)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: ShopLayout.largeCardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ShopLayout.largeCardRadius, style: .continuous)
                .stroke(Color.shopBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 3)
    }

    // MARK: - Store Context Menu (Screenshot 3: Visita il negozio | Segui | Non mi interessa | Segnala negozio)

    private func storeContextMenu(showcase: StoreShowcase, isDarkBackground: Bool) -> some View {
        Menu {
            // 1. Visita il negozio
            Button {
                navigatingStore = showcase
            } label: {
                Label("Visita il negozio", systemImage: "storefront")
            }

            // 2. Segui / Smetti di seguire
            Button {
                followedManager.toggleFollow(storeId: showcase.store_id, storeName: showcase.store_name)
            } label: {
                if followedManager.isFollowing(storeId: showcase.store_id) {
                    Label("Smetti di seguire", systemImage: "checkmark.circle.fill")
                } else {
                    Label("Segui", systemImage: "plus.circle")
                }
            }

            // 3. Non mi interessa
            Button {
                followedManager.hideStore(storeId: showcase.store_id, storeName: showcase.store_name)
                hiddenStoreIdToUndo = showcase.store_id
                withAnimation {
                    toastMessage = "Hai nascosto \(showcase.store_name) dai consigli."
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    withAnimation {
                        if hiddenStoreIdToUndo == showcase.store_id {
                            toastMessage = nil
                        }
                    }
                }
            } label: {
                Label("Non mi interessa", systemImage: "hand.thumbsdown")
            }

            // 4. Segnala negozio (Destructive in Red)
            Button(role: .destructive) {
                reportingStore = showcase
                showingReportAlert = true
            } label: {
                Label("Segnala negozio", systemImage: "exclamationmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(isDarkBackground ? .white : Color(red: 45/255, green: 45/255, blue: 50/255))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
    }

    // MARK: - Minimal Clean Product Card (Screenshots 1, 2, 5: Image + Top-Left Price + Bottom-Left Size + Bottom-Right Heart)

    @ViewBuilder
    private func productSizeMatchBadge(size: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(red: 22/255, green: 163/255, blue: 74/255))
                .frame(width: 5.5, height: 5.5)

            Text("EU \(size)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
        }
        .padding(.horizontal, 7.5)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.94))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color(red: 22/255, green: 163/255, blue: 74/255).opacity(0.28), lineWidth: 0.9)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1.5)
    }

    private func cleanProductCard(product: StoreShowcaseProduct, matchedProduct: MatchedProduct, cardBg: Color) -> some View {
        NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            ZStack(alignment: .topLeading) {
                // Card Box
                RoundedRectangle(cornerRadius: 18)
                    .fill(cardBg)
                    .frame(width: 138, height: 178)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                    )

                // Product Image Centered with Fixed Frame Height
                VStack {
                    Spacer()
                    if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                        ShopCachedAsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120, height: 120)
                                    .clipped()
                                    .transition(.opacity)
                            } else {
                                ShopSkeletonBlock(cornerRadius: 12, width: 120, height: 120)
                            }
                        }
                    } else {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 26))
                            .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                            .frame(width: 120, height: 120)
                    }
                    Spacer()
                }
                .frame(width: 138, height: 178)

                // Top-Left Translucent Price Capsule
                HStack(spacing: 4) {
                    Text(String(format: "%.2f €", product.current_price).replacingOccurrences(of: ".", with: ","))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let orig = product.original_price, orig > product.current_price {
                        Text(String(format: "%.2f €", orig).replacingOccurrences(of: ".", with: ","))
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.65))
                            .strikethrough()
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
                .padding([.top, .leading], 8)

                // Bottom Bar: Size Match Badge (Bottom-Left) + Heart Button (Bottom-Right)
                VStack {
                    Spacer()
                    HStack(alignment: .center) {
                        if prefsManager.matchesUserShoeSize(availableSizes: product.available_sizes) {
                            productSizeMatchBadge(size: prefsManager.preferences.preferredShoeSize)
                        }

                        Spacer()

                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .medium)
                            gen.impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                wishlist.toggleFavorite(product: matchedProduct)
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.35))
                                    .frame(width: 30, height: 30)

                                Image(systemName: wishlist.isFavorite(matchedProduct.canonical_name) ? "heart.fill" : "heart")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundColor(wishlist.isFavorite(matchedProduct.canonical_name) ? Color(red: 239/255, green: 68/255, blue: 68/255) : .white)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .frame(width: 138, height: 178)
            }
            .frame(width: 138, height: 178)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(ShopCardPressStyle())
    }

    // MARK: - 2-Column Grid Product Item (Screenshot 4)

    private func cleanProductGridItem(product: StoreShowcaseProduct, matchedProduct: MatchedProduct) -> some View {
        NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            ZStack(alignment: .topLeading) {
                // Card Box
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 242/255, green: 243/255, blue: 246/255))
                    .frame(height: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                    )

                // Product Image Centered with Fixed Height
                VStack {
                    Spacer()
                    if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                        ShopCachedAsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: 118)
                                    .clipped()
                                    .transition(.opacity)
                            } else {
                                ShopSkeletonBlock(cornerRadius: 12)
                                    .frame(maxWidth: .infinity, maxHeight: 118)
                            }
                        }
                    } else {
                        Image(systemName: "tshirt.fill")
                            .font(.system(size: 26))
                            .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                            .frame(maxWidth: .infinity, maxHeight: 118)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)

                // Top-Left Translucent Price Capsule
                HStack(spacing: 4) {
                    Text(String(format: "%.2f €", product.current_price).replacingOccurrences(of: ".", with: ","))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let orig = product.original_price, orig > product.current_price {
                        Text(String(format: "%.2f €", orig).replacingOccurrences(of: ".", with: ","))
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.65))
                            .strikethrough()
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
                .padding([.top, .leading], 8)

                // Bottom Bar: Size Match Badge (Bottom-Left) + Heart Button (Bottom-Right)
                VStack {
                    Spacer()
                    HStack(alignment: .center) {
                        if prefsManager.matchesUserShoeSize(availableSizes: product.available_sizes) {
                            productSizeMatchBadge(size: prefsManager.preferences.preferredShoeSize)
                        }

                        Spacer()

                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .medium)
                            gen.impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                wishlist.toggleFavorite(product: matchedProduct)
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.35))
                                    .frame(width: 30, height: 30)

                                Image(systemName: wishlist.isFavorite(matchedProduct.canonical_name) ? "heart.fill" : "heart")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundColor(wishlist.isFavorite(matchedProduct.canonical_name) ? Color(red: 239/255, green: 68/255, blue: 68/255) : .white)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            }
        }
        .buttonStyle(ShopCardPressStyle())
    }

    // MARK: - Helpers

    private var previewRecentProducts: [MatchedProduct] {
        recentManager.recentlyViewedProducts.prefix(3).map { enrichMatchedProduct($0) }
    }

    private func enrichMatchedProduct(_ prod: MatchedProduct) -> MatchedProduct {
        if !prod.offers.isEmpty { return prod }
        for sc in showcases {
            if let found = sc.products.first(where: {
                $0.canonical_name.caseInsensitiveCompare(prod.canonical_name) == .orderedSame || $0.id == prod.id
            }) {
                return found.toMatchedProduct(storeId: sc.store_id, storeName: sc.store_name)
            }
        }
        return prod
    }

    private func fetchShowcases(forceRefresh: Bool = false) async {
        if showcases.isEmpty {
            isLoading = true
        }
        defer {
            withAnimation(.easeInOut(duration: 0.24)) {
                isLoading = false
            }
        }
        do {
            let sc = try await api.getStoreShowcases(forceRefresh: forceRefresh)
            let ranked = Self.computeRankedShowcases(from: sc)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.24)) {
                    self.showcases = sc
                    self.rankedShowcases = ranked
                }
            }
            // Prioritize visible top-4 stores' images & store logos first, then prefetch the remaining feed
            let logoUrls = ranked.compactMap { URL(string: $0.logo_url ?? "") }
            ImageCacheManager.shared.prefetch(urls: logoUrls, maxPixelSize: 300)
            let topUrls = ranked.prefix(4).flatMap { $0.products.prefix(4) }.compactMap { URL(string: $0.image_url ?? "") }
            ImageCacheManager.shared.prefetch(urls: topUrls)
            let remainingUrls = ranked.dropFirst(4).flatMap { $0.products.prefix(3) }.compactMap { URL(string: $0.image_url ?? "") }
            ImageCacheManager.shared.prefetch(urls: remainingUrls)

            // Warm default Deals ("Offerte") cache in the background so switching tab is instant
            Task {
                await api.prefetchDefaultDealsIfNeeded()
            }
        } catch {
            print("HomeView fetchShowcases error: \(error)")
        }
    }
}
