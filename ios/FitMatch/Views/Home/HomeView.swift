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

private enum HomeStoreCardStyle {
    case colored
    case grid
    case white
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

        let prefs = UserPreferencesManager.shared.preferences
        let hidden = Array(FollowedStoresManager.shared.hiddenStoreIds)
        let hlKey = APIService.shared.homeHighlightsCacheKey(
            shoeSize: prefs.preferredShoeSize,
            apparelSize: prefs.preferredApparelSize,
            sports: prefs.selectedSports,
            brands: prefs.favoriteBrands,
            hiddenStores: hidden
        )
        let cachedHL = APIService.shared.cachedHomeHighlights(for: hlKey) ?? .empty
        self._highlights = State(initialValue: cachedHL)
    }

    @StateObject private var api = APIService.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var recentManager = RecentActivityManager.shared
    @ObservedObject private var notifManager = NotificationManager.shared
    @ObservedObject private var prefsManager = UserPreferencesManager.shared
    @ObservedObject private var supabase = SupabaseManager.shared

    @State private var showcases: [StoreShowcase] = []
    @State private var rankedShowcases: [StoreShowcase] = []
    @State private var highlights: HomeHighlightsBundle = .empty
    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var visibleStoresCount = 8
    @State private var showingAccountSheet = false
    @State private var showingNotificationsSheet = false

    // Interactive Menu States
    @State private var reportingStore: StoreShowcase? = nil
    @State private var showingReportAlert = false
    @State private var toastMessage: String? = nil
    @State private var hiddenStoreIdToUndo: String? = nil
    @State private var navigatingStore: StoreShowcase? = nil
    @State private var subTabDirection: Int = 1
    @Namespace private var subTabNamespace

    private static let italianCountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "it_IT")
        return f
    }()

    private var userInitial: String {
        let trimmed = prefsManager.preferences.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, !trimmed.isEmpty, trimmed.lowercased() != "ospite" {
            return String(first).uppercased()
        }
        if let emailFirst = supabase.currentUserEmail?.first {
            return String(emailFirst).uppercased()
        }
        return "F"
    }

    private var highlightsCacheKey: String {
        let p = prefsManager.preferences
        return api.homeHighlightsCacheKey(
            shoeSize: p.preferredShoeSize,
            apparelSize: p.preferredApparelSize,
            sports: p.selectedSports,
            brands: p.favoriteBrands,
            hiddenStores: Array(followedManager.hiddenStoreIds)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // MARK: - 1. Pinned Top Header: Avatar | Search + Visual Search | Bell
                    topHeaderBar
                        .shopHeaderBarPadding()

                    if isLoading && showcases.isEmpty && highlights.isEmpty {
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

                // MARK: - Floating Toast Notification
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
                async let showcasesTask: Void = {
                    if showcases.isEmpty || !api.isHomeCacheFresh() {
                        await fetchShowcases(forceRefresh: !showcases.isEmpty)
                    } else {
                        recomputeRankedShowcases()
                        Task { await api.prefetchDefaultDealsIfNeeded() }
                    }
                }()
                async let highlightsTask: Void = {
                    let key = highlightsCacheKey
                    if highlights.isEmpty || !api.isHomeHighlightsCacheFresh(for: key) {
                        await fetchHighlights(forceRefresh: !highlights.isEmpty)
                    }
                }()
                _ = await (showcasesTask, highlightsTask)

                try? await Task.sleep(nanoseconds: 800_000_000)
                await notifManager.checkIntelligentNotifications()
            }
            .onChange(of: personalizationSignature) { _ in
                recomputeRankedShowcases()
            }
            .onChange(of: highlightsCacheKey) { _ in
                Task {
                    await fetchHighlights(forceRefresh: false)
                }
            }
        }
    }

    // MARK: - Top Header Bar

    private var topHeaderBar: some View {
        HStack(spacing: 12) {
            // Dynamic User Avatar
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingAccountSheet = true
            }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 196/255, green: 181/255, blue: 253/255))
                        .frame(width: 42, height: 42)

                    Text(userInitial)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account")

            // Search Bar Capsule (Balanced left search prompt + concentric right camera button)
            HStack(spacing: 6) {
                Button(action: {
                    TabCoordinator.shared.selectTab(1, focusSearch: true, fromSource: "home")
                }) {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundColor(Color(red: 130/255, green: 130/255, blue: 140/255))

                        Text("Cerca o chiedi...")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(Color(red: 142/255, green: 142/255, blue: 152/255))
                            .lineLimit(1)

                        Spacer(minLength: 4)
                    }
                    .padding(.leading, 15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    TabCoordinator.shared.openVisualSearch(fromSource: "home_camera")
                }) {
                    Image(systemName: "camera")
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.045))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .accessibilityLabel("Ricerca visiva")
            }
            .frame(height: 44)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)

            // Bell Notifications Button
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
            .accessibilityLabel("Notifiche")
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
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                                if tab == .offerte {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color(red: 245/255, green: 75/255, blue: 45/255))
                                }

                                Text(tab.title)
                                    .font(.system(size: 13.5, weight: isSelected ? .bold : .semibold, design: .rounded))
                                    .foregroundColor(isSelected ? Color(red: 18/255, green: 18/255, blue: 24/255) : Color(red: 95/255, green: 98/255, blue: 110/255))

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

    // MARK: - "Per te" Feed Content

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

    private var hasPersonalHistory: Bool {
        !previewRecentProducts.isEmpty || !wishlist.items.isEmpty
    }

    private var perTeContent: some View {
        let currentShowcases = rankedShowcases.isEmpty && !showcases.isEmpty
            ? Self.computeRankedShowcases(from: showcases)
            : rankedShowcases
        let visibleShowcases = Array(currentShowcases.prefix(visibleStoresCount))
        let hasMoreStores = visibleShowcases.count < currentShowcases.count
        let cardStyles = computeBalancedCardStyles(for: visibleShowcases)

        let topHighlightProductIds = Set(highlights.personalizedDeals.prefix(4).compactMap { $0.product_id?.lowercased() })
        let topHighlightOfferIds = Set(highlights.personalizedDeals.prefix(4).map { $0.id })
        let firstBatch = Array(visibleShowcases.prefix(2)).map { sc -> StoreShowcase in
            guard !topHighlightOfferIds.isEmpty else { return sc }
            let fresh = sc.products.filter { prod in
                !topHighlightOfferIds.contains(prod.id)
                    && !(prod.product_id.map { topHighlightProductIds.contains($0.lowercased()) } ?? false)
            }
            let repeated = sc.products.filter { prod in
                topHighlightOfferIds.contains(prod.id)
                    || (prod.product_id.map { topHighlightProductIds.contains($0.lowercased()) } ?? false)
            }
            guard !fresh.isEmpty else { return sc }
            return StoreShowcase(
                store_id: sc.store_id,
                store_name: sc.store_name,
                total_offers: sc.total_offers,
                avg_discount: sc.avg_discount,
                rating: sc.rating,
                review_count: sc.review_count,
                card_theme: sc.card_theme,
                accent_color: sc.accent_color,
                logo_url: sc.logo_url,
                promo_text: sc.promo_text,
                products: fresh + repeated
            )
        }
        let secondBatch = visibleShowcases.count > 2 ? Array(visibleShowcases.dropFirst(2).prefix(3)) : []
        let remainingBatch = visibleShowcases.count > 5 ? Array(visibleShowcases.dropFirst(5)) : []

        return ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: ShopLayout.sectionSpacing) {
                    // 1. Personal Summary Cards (only when user has recent or saved items)
                    if hasPersonalHistory {
                        topSummaryCardsCarousel
                    }

                    // 2. Error / Empty State
                    if currentShowcases.isEmpty && highlights.isEmpty && !isLoading {
                        if let err = loadError {
                            homeErrorStateView(message: err)
                        } else if !followedManager.hiddenStoreIds.isEmpty {
                            allStoresHiddenEmptyState
                        } else {
                            homeErrorStateView(message: "Controlla la connessione e riprova.")
                        }
                    } else {
                        // 3. Personalized Picks / Nella tua taglia
                        if !highlights.personalizedDeals.isEmpty {
                            personalizedHighlightsSection
                        }

                        // 4. Top Ranked Stores (#1–#2)
                        if !firstBatch.isEmpty {
                            LazyVStack(spacing: ShopLayout.sectionSpacing) {
                                ForEach(Array(firstBatch.enumerated()), id: \.element.id) { idx, sc in
                                    storeCardView(showcase: sc, style: cardStyles[idx])
                                        .padding(.horizontal, ShopLayout.screenPadding)
                                }
                            }
                        }

                        // 5. Compare & Save (Multi-store)
                        if !highlights.compareSaveDeals.isEmpty {
                            compareAndSaveSection
                        }

                        // 6. Mid Ranked Stores (#3–#5)
                        if !secondBatch.isEmpty {
                            LazyVStack(spacing: ShopLayout.sectionSpacing) {
                                ForEach(Array(secondBatch.enumerated()), id: \.element.id) { offset, sc in
                                    storeCardView(showcase: sc, style: cardStyles[2 + offset])
                                        .padding(.horizontal, ShopLayout.screenPadding)
                                }
                            }
                        }

                        // 7. All-Time Lows
                        if !highlights.priceDropDeals.isEmpty {
                            priceDropsSection
                        }

                        // 8. Remaining Partner Stores (Auto-loads next batch while scrolling)
                        if !remainingBatch.isEmpty {
                            LazyVStack(spacing: ShopLayout.sectionSpacing) {
                                ForEach(Array(remainingBatch.enumerated()), id: \.element.id) { offset, sc in
                                    storeCardView(showcase: sc, style: cardStyles[5 + offset])
                                        .padding(.horizontal, ShopLayout.screenPadding)
                                        .onAppear {
                                            if hasMoreStores && offset >= max(0, remainingBatch.count - 2) {
                                                loadMoreHomeStores(totalCount: currentShowcases.count, source: currentShowcases)
                                            }
                                        }
                                }
                            }
                        }

                        if hasMoreStores {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(.shopTextMuted)
                                    .padding(.vertical, 10)
                                Spacer()
                            }
                            .onAppear {
                                loadMoreHomeStores(totalCount: currentShowcases.count, source: currentShowcases)
                            }
                        }
                    }

                    Spacer(minLength: ShopLayout.bottomDockClearance)
                }
                .padding(.top, 2)
                .animation(.easeOut(duration: 0.24), value: isLoading)
                .id("home_per_te_top")
            }
            .refreshable {
                async let scTask: Void = fetchShowcases(forceRefresh: true)
                async let hlTask: Void = fetchHighlights(forceRefresh: true)
                async let recTask: Void = recentManager.syncFromDatabase()
                _ = await (scTask, hlTask, recTask)
            }
            .onReceive(TabCoordinator.shared.$scrollToTopEvent) { event in
                guard let event, event.tab == 0, activeSubTab == .perTe else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    scrollProxy.scrollTo("home_per_te_top", anchor: .top)
                }
            }
        }
    }

    /// Alternates card styles so heavy gradient cards never stack consecutively.
    private func computeBalancedCardStyles(for list: [StoreShowcase]) -> [HomeStoreCardStyle] {
        var styles: [HomeStoreCardStyle] = []
        var previousWasColored = false

        for (index, sc) in list.enumerated() {
            let dbTheme = sc.card_theme?.lowercased()
            let wantsGrid = (dbTheme == "grid") && sc.products.count >= 4
            let wantsColored = dbTheme == "olive" || dbTheme == "colored" || dbTheme == "dark"
                || (sc.accent_color != nil && dbTheme != "grid" && dbTheme != "white")
                || (dbTheme == nil && index % 4 == 0)

            let resolved: HomeStoreCardStyle
            if wantsGrid {
                resolved = .grid
                previousWasColored = false
            } else if wantsColored && !previousWasColored {
                resolved = .colored
                previousWasColored = true
            } else if !previousWasColored && index % 3 == 2 && sc.products.count >= 4 {
                resolved = .grid
                previousWasColored = false
            } else {
                resolved = .white
                previousWasColored = false
            }
            styles.append(resolved)
        }
        return styles
    }

    @ViewBuilder
    private func storeCardView(showcase: StoreShowcase, style: HomeStoreCardStyle) -> some View {
        switch style {
        case .colored:
            oliveShopStoreCard(showcase: showcase)
        case .grid:
            gridShopStoreCard(showcase: showcase)
        case .white:
            whiteShopStoreCard(showcase: showcase)
        }
    }

    // MARK: - 1. Top Summary Cards Carousel (Clean Minimal Thumbnails)

    private var topSummaryCardsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                recentlyViewedSummaryCard
                savedItemsSummaryCard
            }
            .padding(.horizontal, 16)
        }
    }

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
            NavigationLink(destination: RecentlyViewedView()) {
                HStack {
                    Text("Visti di recente")
                        .font(.system(size: 17.5, weight: .bold, design: .rounded))
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

            let items = previewRecentProducts
            if items.isEmpty {
                FitMatchInlineEmptyRow(
                    icon: "clock",
                    title: "Nessun prodotto visto",
                    subtitle: "I modelli aperti appariranno qui"
                )
            } else {
                HStack(spacing: 10) {
                    ForEach(items) { prod in
                        NavigationLink(destination: ProductDetailView(product: prod)) {
                            summaryThumbnailTile(
                                imageUrl: prod.image_url,
                                fallbackIcon: "clock",
                                size: thumbSize
                            )
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.96, pressedOpacity: 0.92))
                    }
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: cardWidth - (ShopLayout.cardPadding * 2), height: summaryCardHeight - (ShopLayout.cardPadding * 2), alignment: .topLeading)
        .shopCard(padding: ShopLayout.cardPadding, cornerRadius: ShopLayout.largeCardRadius, shadowOpacity: 0.03, shadowRadius: 8, shadowY: 2)
    }

    private var savedItemsSummaryCard: some View {
        let cardWidth = summaryCardWidth
        let thumbSize = summaryThumbSize
        let priceDropCount = wishlist.items.filter { ($0.lastPriceDrop ?? 0) > 0.5 }.count

        return VStack(alignment: .leading, spacing: 14) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    selectedTab = 2
                }
            }) {
                HStack(spacing: 8) {
                    Text("Elementi salvati")
                        .font(.system(size: 17.5, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    if priceDropCount > 0 {
                        Text(priceDropCount == 1 ? "1 ribasso" : "\(priceDropCount) ribassi")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.shopGreen)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.shopGreenLight)
                            .clipShape(Capsule())
                    }

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

            let saved = Array(wishlist.items.prefix(3))
            if saved.isEmpty {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        selectedTab = 2
                    }
                }) {
                    FitMatchInlineEmptyRow(
                        icon: "heart",
                        title: "Nessun articolo salvato",
                        subtitle: "Salva i prodotti per seguire i prezzi",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    ForEach(saved) { item in
                        NavigationLink(destination: ProductDetailView(product: item.toMatchedProduct())) {
                            summaryThumbnailTile(
                                imageUrl: item.image_url,
                                fallbackIcon: "heart.fill",
                                size: thumbSize
                            )
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.96, pressedOpacity: 0.92))
                    }
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: cardWidth - (ShopLayout.cardPadding * 2), height: summaryCardHeight - (ShopLayout.cardPadding * 2), alignment: .topLeading)
        .shopCard(padding: ShopLayout.cardPadding, cornerRadius: ShopLayout.largeCardRadius, shadowOpacity: 0.03, shadowRadius: 8, shadowY: 2)
    }

    private func summaryThumbnailTile(imageUrl: String?, fallbackIcon: String, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                .fill(Color.shopSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                        .stroke(Color.shopBorder, lineWidth: 1)
                )

            if let imgUrl = imageUrl, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                ShopCachedAsyncImage(url: url, maxPixelSize: 320) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                            .frame(width: size, height: size)
                    case .failure:
                        Image(systemName: fallbackIcon)
                            .font(.system(size: 20))
                            .foregroundColor(Color(red: 205/255, green: 205/255, blue: 215/255))
                            .frame(width: size, height: size)
                    case .empty:
                        ShopSkeletonBlock(cornerRadius: 12)
                            .frame(width: size, height: size)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: fallbackIcon)
                    .font(.system(size: 20))
                    .foregroundColor(Color(red: 205/255, green: 205/255, blue: 215/255))
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous))
    }

    // MARK: - 2. Minimal Cross-Store Highlight Carousels

    private var personalizedHighlightsSection: some View {
        let isSizeBased = highlights.personalizedSectionKey == "for_your_size" && prefsManager.preferences.hasAnySize
        let headerTitle = isSizeBased ? "Nella tua taglia" : (!prefsManager.preferences.selectedSports.isEmpty || !prefsManager.preferences.favoriteBrands.isEmpty ? "Scelti per te" : "In evidenza")

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(headerTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)

                if isSizeBased {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingAccountSheet = true
                    }) {
                        Text(prefsManager.preferences.formattedSizeSummary)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.shopGreen)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.shopGreenLight)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, ShopLayout.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(highlights.personalizedDeals) { prod in
                        minimalHighlightCard(product: prod, emphasis: .personalized)
                            .shopCarouselTransition()
                    }
                }
                .padding(.horizontal, ShopLayout.screenPadding)
            }
        }
    }

    private var compareAndSaveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Confronta e risparmia")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                Spacer()
            }
            .padding(.horizontal, ShopLayout.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(highlights.compareSaveDeals) { prod in
                        minimalHighlightCard(product: prod, emphasis: .compareSave)
                            .shopCarouselTransition()
                    }
                }
                .padding(.horizontal, ShopLayout.screenPadding)
            }
        }
    }

    private var priceDropsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Minimi storici")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)

                Spacer()

                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    subTabDirection = 1
                    withAnimation(ShopMotion.pillSlide) {
                        activeSubTab = .offerte
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.shopTextMuted)
                        .frame(width: 30, height: 30)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.shopBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, ShopLayout.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(highlights.priceDropDeals) { prod in
                        minimalHighlightCard(product: prod, emphasis: .priceDrop)
                            .shopCarouselTransition()
                    }
                }
                .padding(.horizontal, ShopLayout.screenPadding)
            }
        }
    }

    private enum HighlightCardEmphasis {
        case personalized
        case compareSave
        case priceDrop
    }

    /// Minimal, airy card aligned with DealsView & FollowingView: crisp image + 1-line title + price.
    private func minimalHighlightCard(product: StoreShowcaseProduct, emphasis: HighlightCardEmphasis) -> some View {
        let matched = product.toMatchedProduct(
            storeId: product.store_id ?? "",
            storeName: product.store_name ?? "Partner Store"
        )
        let cardWidth: CGFloat = 156
        let matchedSize = prefsManager.matchedPreferredSizeBadge(for: product)

        return NavigationLink(destination: ProductDetailView(product: matched)) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                        .fill(Color.white)
                        .frame(width: cardWidth, height: 152)

                    if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 420) { phase in
                            switch phase {
                            case .success(let img):
                                img
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: cardWidth - 20, height: 132)
                                    .frame(width: cardWidth, height: 152)
                                    .transition(.opacity)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                    .frame(width: cardWidth, height: 152)
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: ShopLayout.mediumRadius, width: cardWidth, height: 152)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "tag")
                            .font(.system(size: 24))
                            .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                            .frame(width: cardWidth, height: 152)
                    }

                    RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                        .stroke(Color.shopBorder, lineWidth: 1)
                        .frame(width: cardWidth, height: 152)

                    // Single clean top-left badge
                    Group {
                        if emphasis == .compareSave, let savings = product.cross_store_savings, savings >= 10 {
                            Text("-\(Int(savings.rounded())) €")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.shopPurple)
                                .clipShape(Capsule())
                        } else if emphasis == .priceDrop && product.isVerifiedAllTimeLow {
                            Text("Minimo")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.shopGreen)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.shopGreenLight)
                                .clipShape(Capsule())
                        } else if let disc = product.discountBadge {
                            Text(disc)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.shopRed)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(8)

                    // Bottom bar: single subtle pill + white-ringed heart (matching DealsView)
                    VStack {
                        Spacer()
                        HStack(alignment: .bottom) {
                            if emphasis == .compareSave, let stores = product.multi_store_count, stores >= 2 {
                                Text("\(stores) negozi")
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(.shopDark)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.94))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.shopBorder, lineWidth: 0.7))
                            } else if let sz = matchedSize {
                                productSizeMatchBadge(label: sz)
                            }
                            Spacer()
                            dealsStyleHeartButton(for: matched)
                        }
                        .padding(8)
                    }
                    .frame(width: cardWidth, height: 152)
                }

                // Only 2 clean lines below image: 1-line title + price
                Text(product.cleanDisplayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 1)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(formatItalianPrice(product.current_price))
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    if emphasis == .compareSave, let maxP = product.market_max_price, maxP > product.current_price + 1 {
                        Text(formatCompactPrice(maxP))
                            .font(.system(size: 11, weight: .regular))
                            .strikethrough()
                            .foregroundColor(.shopTextMuted)
                            .lineLimit(1)
                    } else if let orig = product.original_price, orig > product.current_price {
                        Text(formatCompactPrice(orig))
                            .font(.system(size: 11, weight: .regular))
                            .strikethrough()
                            .foregroundColor(.shopTextMuted)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .buttonStyle(ShopCardPressStyle())
    }

    // MARK: - Shared Store Card Chrome (Quiet & Clean)

    private func storeHeaderSubtitle(for showcase: StoreShowcase) -> String {
        let numericRating = Double(showcase.rating.replacingOccurrences(of: ",", with: ".")) ?? 0
        let sid = showcase.store_id.lowercased()
        let isOfficialFlagship = (sid == "nike" || sid == "adidas" || sid == "decathlon")

        let maxDisc = Int((showcase.products.compactMap { $0.discount_pct }.max() ?? showcase.avg_discount).rounded())
        let discText = maxDisc >= 10 ? "Fino \(IntelligentPromoGenerator.upToPercent(maxDisc))" : "\(formattedOfferCount(showcase.total_offers)) articoli"

        if numericRating >= 4.0 && !isOfficialFlagship {
            return "\(showcase.rating.replacingOccurrences(of: ".", with: ",")) ★ · \(discText)"
        } else if isOfficialFlagship {
            return "Store ufficiale · \(discText)"
        } else {
            return discText
        }
    }

    private func shopStoreCardHeader(showcase: StoreShowcase, isDarkBackground: Bool) -> some View {
        HStack(spacing: 12) {
            NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                HStack(spacing: 12) {
                    ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 42, logoURL: showcase.logo_url)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(showcase.store_name)
                                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                                .foregroundColor(isDarkBackground ? .white : .shopDark)
                                .lineLimit(1)

                            if followedManager.isFollowing(storeId: showcase.store_id) {
                                Text("Segui già")
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isDarkBackground ? Color.white.opacity(0.22) : Color.shopPurpleLight)
                                    .foregroundColor(isDarkBackground ? .white : .shopPurple)
                                    .clipShape(Capsule())
                            }
                        }

                        Text(storeHeaderSubtitle(for: showcase))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(isDarkBackground ? .white.opacity(0.86) : .shopTextMuted)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            storeContextMenu(showcase: showcase, isDarkBackground: isDarkBackground)
        }
        .padding(.horizontal, ShopLayout.cardPadding)
        .padding(.top, ShopLayout.cardPadding)
    }

    private func formattedOfferCount(_ count: Int) -> String {
        Self.italianCountFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func shopStoreCardFooter(showcase: StoreShowcase, isDarkBackground: Bool) -> some View {
        let footerTitle = showcase.total_offers > showcase.products.count
            ? "Tutte le \(formattedOfferCount(showcase.total_offers)) offerte"
            : "Vedi tutto"

        return NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
            HStack {
                Text(footerTitle)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundColor(isDarkBackground ? .white : .shopDark)

                Spacer()

                Circle()
                    .fill(isDarkBackground ? Color.white.opacity(0.24) : Color.shopSurfaceElevated)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(isDarkBackground ? .white : .shopDark)
                    )
            }
            .padding(.horizontal, ShopLayout.cardPadding)
            .padding(.bottom, ShopLayout.cardPadding)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3A. Colored / Gradient Shop Store Card (Pure Visual Shop-Style Tiles)

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
            return Color(red: 98/255, green: 125/255, blue: 86/255)
        }()
        let stops = cardBgColor.cardGradientStops()

        return VStack(alignment: .leading, spacing: ShopLayout.cardSpacing) {
            shopStoreCardHeader(showcase: showcase, isDarkBackground: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ShopLayout.compactSpacing) {
                    ForEach(showcase.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                        cleanVisualProductTile(product: prod, matchedProduct: matched, cardBg: .white)
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
        .shadow(color: cardBgColor.opacity(0.20), radius: 12, x: 0, y: 5)
    }

    // MARK: - 3B. Clean White Horizontal Carousel Store Card

    private func whiteShopStoreCard(showcase: StoreShowcase) -> some View {
        VStack(alignment: .leading, spacing: ShopLayout.cardSpacing) {
            shopStoreCardHeader(showcase: showcase, isDarkBackground: false)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ShopLayout.compactSpacing) {
                    ForEach(showcase.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                        cleanVisualProductTile(product: prod, matchedProduct: matched, cardBg: Color.shopSurface)
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

    // MARK: - 3C. 2-Column Grid Store Card

    private func gridShopStoreCard(showcase: StoreShowcase) -> some View {
        VStack(alignment: .leading, spacing: ShopLayout.cardSpacing) {
            shopStoreCardHeader(showcase: showcase, isDarkBackground: false)

            let items = Array(showcase.products.prefix(4))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(items) { prod in
                    let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                    cleanVisualGridTile(product: prod, matchedProduct: matched)
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

    // MARK: - Store Context Menu

    private func storeContextMenu(showcase: StoreShowcase, isDarkBackground: Bool) -> some View {
        Menu {
            Button {
                navigatingStore = showcase
            } label: {
                Label("Visita il negozio", systemImage: "storefront")
            }

            Button {
                followedManager.toggleFollow(storeId: showcase.store_id, storeName: showcase.store_name)
            } label: {
                if followedManager.isFollowing(storeId: showcase.store_id) {
                    Label("Smetti di seguire", systemImage: "checkmark.circle.fill")
                } else {
                    Label("Segui", systemImage: "plus.circle")
                }
            }

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

    // MARK: - Minimal Visual Product Tiles (True Shop-Style Simplicity)

    private func productSizeMatchBadge(label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(red: 22/255, green: 163/255, blue: 74/255))
                .frame(width: 5.5, height: 5.5)

            Text(label)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(Color.white.opacity(0.95))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color(red: 22/255, green: 163/255, blue: 74/255).opacity(0.28), lineWidth: 0.8)
        )
    }

    private func dealsStyleHeartButton(for matchedProduct: MatchedProduct) -> some View {
        let isFav = wishlist.isFavorite(matchedProduct.canonical_name)
        return Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                wishlist.toggleFavorite(product: matchedProduct)
            }
        }) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.94))
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Color.shopBorder.opacity(0.8), lineWidth: 0.7))

                Image(systemName: isFav ? "heart.fill" : "heart")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(isFav ? .shopRed : .shopDark)
            }
        }
        .buttonStyle(.plain)
    }

    private func translucentHeartButton(for matchedProduct: MatchedProduct) -> some View {
        let isFav = wishlist.isFavorite(matchedProduct.canonical_name)
        return Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                wishlist.toggleFavorite(product: matchedProduct)
            }
        }) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: 30, height: 30)

                Image(systemName: isFav ? "heart.fill" : "heart")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(isFav ? .shopRed : .white)
            }
        }
        .buttonStyle(.plain)
    }

    private func cleanVisualProductTile(product: StoreShowcaseProduct, matchedProduct: MatchedProduct, cardBg: Color) -> some View {
        let matchedSize = prefsManager.matchedPreferredSizeBadge(for: product)

        return NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(cardBg)
                    .frame(width: 138, height: 174)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                    )

                VStack {
                    Spacer()
                    if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 380) { phase in
                            switch phase {
                            case .success(let img):
                                img
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 118, height: 118)
                                    .clipped()
                                    .transition(.opacity)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                    .frame(width: 118, height: 118)
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: 12, width: 118, height: 118)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "tag")
                            .font(.system(size: 24))
                            .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                            .frame(width: 118, height: 118)
                    }
                    Spacer()
                }
                .frame(width: 138, height: 174)

                // Top-Left Price Capsule
                HStack(spacing: 4) {
                    Text(formatItalianPrice(product.current_price))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let orig = product.original_price, orig > product.current_price {
                        Text(formatCompactPrice(orig))
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.68))
                            .strikethrough()
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
                .padding([.top, .leading], 8)

                // Bottom Bar: Size Badge (if matches user size) + Heart
                VStack {
                    Spacer()
                    HStack(alignment: .center) {
                        if let sz = matchedSize {
                            productSizeMatchBadge(label: sz)
                        }
                        Spacer()
                        translucentHeartButton(for: matchedProduct)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .frame(width: 138, height: 174)
            }
            .frame(width: 138, height: 174)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(ShopCardPressStyle())
    }

    private func cleanVisualGridTile(product: StoreShowcaseProduct, matchedProduct: MatchedProduct) -> some View {
        let matchedSize = prefsManager.matchedPreferredSizeBadge(for: product)

        return NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.shopSurface)
                    .frame(height: 172)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                    )

                VStack {
                    Spacer()
                    if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 400) { phase in
                            switch phase {
                            case .success(let img):
                                img
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: 116)
                                    .padding(.horizontal, 10)
                                    .transition(.opacity)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                    .frame(maxWidth: .infinity, maxHeight: 116)
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: 12)
                                    .frame(maxWidth: .infinity, maxHeight: 116)
                                    .padding(.horizontal, 12)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "tag")
                            .font(.system(size: 24))
                            .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                            .frame(maxWidth: .infinity, maxHeight: 116)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 172)

                HStack(spacing: 4) {
                    Text(formatItalianPrice(product.current_price))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let orig = product.original_price, orig > product.current_price {
                        Text(formatCompactPrice(orig))
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.68))
                            .strikethrough()
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
                .padding([.top, .leading], 8)

                VStack {
                    Spacer()
                    HStack(alignment: .center) {
                        if let sz = matchedSize {
                            productSizeMatchBadge(label: sz)
                        }
                        Spacer()
                        translucentHeartButton(for: matchedProduct)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 172)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(ShopCardPressStyle())
    }

    // MARK: - Error & Empty States

    private func homeErrorStateView(message: String) -> some View {
        FitMatchEmptyStateView(
            icon: "wifi.exclamationmark",
            accentColor: .shopRed,
            title: "Impossibile caricare la Home",
            subtitle: message,
            primaryTitle: "Riprova",
            primaryIcon: "arrow.clockwise",
            onPrimaryTap: {
                Task {
                    async let s: Void = fetchShowcases(forceRefresh: true)
                    async let h: Void = fetchHighlights(forceRefresh: true)
                    _ = await (s, h)
                }
            }
        )
        .padding(.horizontal, ShopLayout.screenPadding)
        .padding(.top, 8)
    }

    private var allStoresHiddenEmptyState: some View {
        FitMatchEmptyStateView(
            icon: "eye.slash",
            title: "Tutti i negozi sono nascosti",
            subtitle: "Ripristinali per tornare a vedere la tua Home.",
            primaryTitle: "Ripristina negozi",
            primaryIcon: "arrow.counterclockwise",
            onPrimaryTap: {
                let ids = Array(followedManager.hiddenStoreIds)
                for id in ids {
                    followedManager.unhideStore(storeId: id)
                }
                recomputeRankedShowcases()
                Task { await fetchHighlights(forceRefresh: true) }
            }
        )
        .padding(.horizontal, ShopLayout.screenPadding)
        .padding(.top, 8)
    }

    // MARK: - Helpers & Data Fetching

    private func loadMoreHomeStores(totalCount: Int, source: [StoreShowcase]) {
        guard visibleStoresCount < totalCount else { return }
        let startIdx = visibleStoresCount
        let nextCount = min(visibleStoresCount + 6, totalCount)
        visibleStoresCount = nextCount

        let nextBatchUrls = source[startIdx..<nextCount]
            .flatMap { $0.products.prefix(4) }
            .compactMap { URL(string: $0.image_url ?? "") }
        ImageCacheManager.shared.prefetch(urls: nextBatchUrls)
    }

    private func formatItalianPrice(_ value: Double) -> String {
        String(format: "%.2f €", value).replacingOccurrences(of: ".", with: ",")
    }

    private func formatCompactPrice(_ value: Double) -> String {
        if value >= 1000 || value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value.rounded())) €"
        }
        return String(format: "%.2f €", value).replacingOccurrences(of: ".", with: ",")
    }

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
                self.loadError = nil
                withAnimation(.easeInOut(duration: 0.24)) {
                    self.showcases = sc
                    self.rankedShowcases = ranked
                }
            }
            let logoUrls = ranked.compactMap { URL(string: $0.logo_url ?? "") }
            ImageCacheManager.shared.prefetch(urls: logoUrls, maxPixelSize: 300)
            let topUrls = ranked.prefix(4).flatMap { $0.products.prefix(4) }.compactMap { URL(string: $0.image_url ?? "") }
            ImageCacheManager.shared.prefetch(urls: topUrls)
            let remainingUrls = ranked.dropFirst(4).flatMap { $0.products.prefix(3) }.compactMap { URL(string: $0.image_url ?? "") }
            ImageCacheManager.shared.prefetch(urls: remainingUrls)

            Task {
                await api.prefetchDefaultDealsIfNeeded()
            }
        } catch {
            print("HomeView fetchShowcases error: \(error)")
            await MainActor.run {
                if self.showcases.isEmpty {
                    self.loadError = "Verifica la connessione di rete e riprova."
                }
            }
        }
    }

    private func fetchHighlights(forceRefresh: Bool = false) async {
        let p = prefsManager.preferences
        let hidden = Array(followedManager.hiddenStoreIds)

        do {
            let bundle = try await api.getHomeHighlights(
                shoeSize: p.preferredShoeSize,
                apparelSize: p.preferredApparelSize,
                sports: p.selectedSports,
                brands: p.favoriteBrands,
                hiddenStores: hidden,
                limitPerSection: 10,
                forceRefresh: forceRefresh
            )
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.24)) {
                    self.highlights = bundle
                }
            }
            let hlUrls = (bundle.personalizedDeals.prefix(5) + bundle.compareSaveDeals.prefix(4) + bundle.priceDropDeals.prefix(4))
                .compactMap { URL(string: $0.image_url ?? "") }
            ImageCacheManager.shared.prefetch(urls: hlUrls)
        } catch {
            print("HomeView fetchHighlights error: \(error)")
        }
    }
}
