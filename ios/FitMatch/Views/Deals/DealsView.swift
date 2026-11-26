import SwiftUI

struct DealCategoryFilter: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let accentColor: Color
    let bgTint: Color
}

enum DealsViewMode: String, CaseIterable, Identifiable {
    case topDeals = "top_deals"
    case byStore = "by_store"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topDeals: return "Top Offerte"
        case .byStore: return "Per Negozio"
        }
    }
}

struct DealsView: View {
    var embedded: Bool = false
    var onSelectPerTe: (() -> Void)? = nil

    @StateObject private var api = APIService.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var prefs = UserPreferencesManager.shared

    @State private var viewMode: DealsViewMode = .topDeals
    @State private var showcases: [StoreShowcase] = []
    @State private var topDeals: [StoreShowcaseProduct] = []
    @State private var totalTopDealsMatching: Int = 0
    @State private var isLoadingMoreTopDeals = false
    @State private var hasReachedEndOfTopDeals = false
    private let topDealsPageSize: Int = 40

    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var selectedCategory: String = "tutti"
    @State private var filters = DealsFilterOptions()
    @State private var isSwitchingQuery = false
    @State private var showingFilterSheet = false
    @State private var activeLoadTask: Task<Void, Never>? = nil

    @Namespace private var dealsCatNamespace
    @Namespace private var dealsModeNamespace

    init(embedded: Bool = false, onSelectPerTe: (() -> Void)? = nil) {
        self.embedded = embedded
        self.onSelectPerTe = onSelectPerTe
        if let initialTop = APIService.shared.cachedTopDealsCrossStore(for: "tutti") {
            self._topDeals = State(initialValue: initialTop.deals)
            self._totalTopDealsMatching = State(initialValue: initialTop.total)
        }
        if let initialCached = APIService.shared.cachedDealsShowcases(for: "tutti") {
            self._showcases = State(initialValue: initialCached)
        }
    }

    // MARK: - Derived Data

    private var displayedShowcases: [StoreShowcase] {
        let visible = showcases.filter {
            !$0.products.isEmpty && !followedManager.isStoreHidden(storeId: $0.store_id)
        }
        let followedIds = Set(followedManager.followedStores.map { $0.store_id.lowercased() })
        guard !followedIds.isEmpty else { return visible }
        let followed = visible.filter { followedIds.contains($0.store_id.lowercased()) && $0.products.count >= 2 }
        let rest = visible.filter { !(followedIds.contains($0.store_id.lowercased()) && $0.products.count >= 2) }
        return followed + rest
    }

    private var displayedTopDeals: [StoreShowcaseProduct] {
        topDeals.filter { prod in
            guard let sid = prod.store_id, !sid.isEmpty else { return true }
            return !followedManager.isStoreHidden(storeId: sid)
        }
    }

    private var isCurrentViewEmpty: Bool {
        switch viewMode {
        case .topDeals: return displayedTopDeals.isEmpty
        case .byStore: return displayedShowcases.isEmpty
        }
    }

    private var activeFilterChips: [(id: String, label: String, remove: () -> Void)] {
        var chips: [(String, String, () -> Void)] = []
        if let g = filters.gender, !g.isEmpty {
            chips.append(("gender", g.capitalized, {
                var next = filters; next.gender = nil
                applyQuery(category: selectedCategory, filters: next)
            }))
        }
        if let sz = filters.size, !sz.isEmpty {
            chips.append(("size", "Tg. \(sz)", {
                var next = filters; next.size = nil
                applyQuery(category: selectedCategory, filters: next)
            }))
        }
        if let mp = filters.maxPrice {
            chips.append(("price", "≤ \(Int(mp)) €", {
                var next = filters; next.maxPrice = nil
                applyQuery(category: selectedCategory, filters: next)
            }))
        }
        if let md = filters.minDiscount {
            chips.append(("disc", "≥ \(Int(md))%", {
                var next = filters; next.minDiscount = nil
                applyQuery(category: selectedCategory, filters: next)
            }))
        }
        if let br = filters.brand, !br.isEmpty {
            chips.append(("brand", br, {
                var next = filters; next.brand = nil
                applyQuery(category: selectedCategory, filters: next)
            }))
        }
        if filters.freeShippingOnly {
            chips.append(("ship", "Sped. gratis", {
                var next = filters; next.freeShippingOnly = false
                applyQuery(category: selectedCategory, filters: next)
            }))
        }
        if filters.includeKids {
            chips.append(("kids", "Incl. Bambino", {
                var next = filters; next.includeKids = false
                applyQuery(category: selectedCategory, filters: next)
            }))
        }
        return chips
    }

    private let defaultCategories: [DealCategoryFilter] = [
        DealCategoryFilter(id: "tutti", name: "Tutte", icon: "flame", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "donna", name: "Donna", icon: "figure.walk", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "uomo", name: "Uomo", icon: "figure.stand", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "running", name: "Scarpe Running", icon: "figure.run", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "abbigliamento", name: "Abbigliamento", icon: "tshirt", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "smartwatch", name: "Smartwatch & GPS", icon: "applewatch", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "accessori", name: "Accessori", icon: "bag", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "outdoor", name: "Outdoor & Trail", icon: "mountain.2", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "padel", name: "Padel", icon: "tennisball", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "cycling", name: "Ciclismo", icon: "bicycle", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "fitness", name: "Fitness & Gym", icon: "dumbbell", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "calcio", name: "Calcio & Calcetto", icon: "soccerball", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "tennis", name: "Tennis", icon: "tennis.racket", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "basket", name: "Basket", icon: "basketball", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "sci", name: "Sci & Neve", icon: "snowflake", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "nuoto", name: "Nuoto", icon: "figure.pool.swim", accentColor: .shopDark, bgTint: .shopSurfaceElevated),
        DealCategoryFilter(id: "nutrizione", name: "Nutrizione", icon: "bolt.heart", accentColor: .shopDark, bgTint: .shopSurfaceElevated)
    ]

    private var categories: [DealCategoryFilter] {
        guard !prefs.dynamicCategories.isEmpty else { return defaultCategories }
        return prefs.dynamicCategories.map { item in
            DealCategoryFilter(
                id: item.id,
                name: item.name,
                icon: (item.icon?.isEmpty == false ? item.icon! : "tag"),
                accentColor: .shopDark,
                bgTint: .shopSurfaceElevated
            )
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // MARK: - 1. Single Clean Category Row
                        categoryPillsBar
                            .padding(.top, 2)

                        // MARK: - 2. Quiet Mode Switcher + Inline Sort Text Menu
                        modeAndSortBar

                        // MARK: - 3. Active Filters Summary (Shown ONLY when filters are applied)
                        if !activeFilterChips.isEmpty {
                            activeFiltersBar
                        }

                        // MARK: - 4. Products Grid or Clean Store Cards
                        Group {
                            if isSwitchingQuery || (isLoading && isCurrentViewEmpty) {
                                ShopDealsSkeletonView(showStoreHeaders: viewMode == .byStore)
                                    .shopFadeScaleTransition()
                            } else if let err = loadError, isCurrentViewEmpty {
                                errorStateView(message: err)
                                    .shopFadeScaleTransition()
                            } else if isCurrentViewEmpty {
                                emptyStateView
                                    .shopFadeScaleTransition()
                            } else if viewMode == .topDeals {
                                topDealsGridSection
                                    .shopFadeScaleTransition()
                            } else {
                                LazyVStack(spacing: ShopLayout.sectionSpacing) {
                                    ForEach(displayedShowcases) { showcase in
                                        storeDealsCard(showcase: showcase)
                                    }
                                }
                                .padding(.top, 2)
                                .shopFadeScaleTransition()
                            }
                        }
                        .animation(ShopMotion.gridReflow, value: selectedCategory)
                        .animation(ShopMotion.gridReflow, value: viewMode)
                        .animation(ShopMotion.gridReflow, value: filters.cacheKeySuffix)
                        .animation(.easeOut(duration: 0.2), value: isSwitchingQuery)

                        Color.clear.frame(height: ShopLayout.bottomFilterDockClearance)
                    }
                    .id("deals_top")
                }
                .refreshable {
                    await loadCurrentMode(category: selectedCategory, filters: filters, mode: viewMode, forceRefresh: true)
                }
                .onReceive(TabCoordinator.shared.$scrollToTopEvent) { event in
                    guard let event, event.tab == 0 else { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        scrollProxy.scrollTo("deals_top", anchor: .top)
                    }
                }
            }

            // MARK: - 5. Single Floating "Filtra" Pill
            floatingFilterButton
        }
        .sheet(isPresented: $showingFilterSheet) {
            DealsFilterSheetView(
                categories: categories,
                selectedCategory: selectedCategory,
                filters: filters,
                preferredShoeSize: prefs.preferences.preferredShoeSize,
                preferredApparelSize: prefs.preferences.preferredApparelSize,
                favoriteBrands: prefs.preferences.favoriteBrands,
                onApply: { newCategory, newFilters in
                    applyQuery(category: newCategory, filters: newFilters)
                }
            )
        }
        .task {
            if prefs.dynamicCategories.isEmpty {
                Task {
                    await prefs.fetchActiveStores(apiService: api)
                }
            }
            if isCurrentViewEmpty {
                applyQuery(category: selectedCategory, filters: filters)
            }
            if selectedCategory == "tutti" && filters.isDefault {
                Task {
                    if viewMode == .topDeals && api.cachedDealsShowcases(for: "tutti") == nil {
                        if let sc = try? await api.getDealsShowcases(category: nil, filters: DealsFilterOptions()) {
                            await MainActor.run {
                                if self.showcases.isEmpty && self.selectedCategory == "tutti" && self.filters.isDefault {
                                    self.showcases = sc
                                }
                            }
                        }
                    } else if viewMode == .byStore && api.cachedTopDealsCrossStore(for: "tutti") == nil {
                        if let res = try? await api.getTopDealsCrossStore(category: nil, filters: DealsFilterOptions(), limit: 40) {
                            await MainActor.run {
                                if self.topDeals.isEmpty && self.selectedCategory == "tutti" && self.filters.isDefault {
                                    self.topDeals = res.deals
                                    self.totalTopDealsMatching = res.totalMatching
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 1. Clean Category Pills Bar

    private var categoryPillsBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { cat in
                        let isSelected = selectedCategory == cat.id

                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            var nextFilters = filters
                            if cat.id == "uomo" || cat.id == "donna" {
                                nextFilters.gender = nil
                            }
                            applyQuery(category: cat.id, filters: nextFilters)
                        }) {
                            Text(cat.name)
                                .font(.system(size: 13.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundColor(isSelected ? .white : .shopDark)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    ZStack {
                                        Capsule().fill(Color.white)
                                        if isSelected {
                                            Capsule()
                                                .fill(Color.shopDark)
                                                .matchedGeometryEffect(id: "deals_cat_pill", in: dealsCatNamespace)
                                        }
                                    }
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? Color.clear : Color.shopBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.96, pressedOpacity: 0.92))
                        .id(cat.id)
                    }
                }
                .padding(.horizontal, ShopLayout.screenPadding)
            }
            .onAppear {
                proxy.scrollTo(selectedCategory, anchor: .center)
            }
            .onChange(of: selectedCategory) { _, newValue in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onChange(of: showingFilterSheet) { _, isPresented in
                if !isPresented {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            proxy.scrollTo(selectedCategory, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 2. Quiet Mode Switcher + Clean Text Sort Menu

    private var modeAndSortBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(DealsViewMode.allCases) { mode in
                    let isSelected = viewMode == mode
                    Button(action: {
                        guard viewMode != mode else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        switchViewMode(to: mode)
                    }) {
                        Text(mode.title)
                            .font(.system(size: 12.5, weight: isSelected ? .bold : .medium, design: .rounded))
                            .foregroundColor(isSelected ? .shopDark : .shopTextMuted)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6.5)
                            .background(
                                ZStack {
                                    if isSelected {
                                        Capsule()
                                            .fill(Color.white)
                                            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                                            .matchedGeometryEffect(id: "deals_mode_pill", in: dealsModeNamespace)
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.shopSurfaceElevated)
            .clipShape(Capsule())

            Spacer(minLength: 4)

            Menu {
                ForEach(DealsSortOption.allCases) { option in
                    Button(action: {
                        guard filters.sort != option else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        var next = filters
                        next.sort = option
                        applyQuery(category: selectedCategory, filters: next)
                    }) {
                        Label(option.title, systemImage: filters.sort == option ? "checkmark" : option.icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(filters.sort.shortTitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(filters.sort == .quality ? .shopTextMuted : .shopPurple)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, ShopLayout.screenPadding)
    }

    // MARK: - 3. Active Filters Bar (Only Rendered When Filters Are Active)

    private var activeFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(activeFilterChips, id: \.id) { chip in
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        chip.remove()
                    }) {
                        HStack(spacing: 4) {
                            Text(chip.label)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Image(systemName: "xmark")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .foregroundColor(.shopPurple)
                        .padding(.horizontal, 10.5)
                        .padding(.vertical, 5.5)
                        .background(Color.shopPurpleLight)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    applyQuery(category: selectedCategory, filters: DealsFilterOptions())
                }) {
                    Text("Cancella")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.shopTextMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5.5)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, ShopLayout.screenPadding)
        }
    }

    // MARK: - 4. Top Offerte Cross-Store Grid

    private var topDealsGridSection: some View {
        let deals = displayedTopDeals
        let total = max(totalTopDealsMatching, deals.count)
        let hasMore = !hasReachedEndOfTopDeals && topDeals.count < total && topDeals.count < 400
        let triggerIndex = max(0, deals.count - 6)

        return VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 16
            ) {
                ForEach(Array(deals.enumerated()), id: \.element.id) { idx, prod in
                    let matched = prod.toMatchedProduct(
                        storeId: prod.store_id ?? "",
                        storeName: prod.store_name ?? "Store Partner"
                    )
                    ShopDealGridCard(
                        product: prod,
                        matchedProduct: matched,
                        showStorePill: true,
                        highlightedSize: filters.size
                    )
                    .onAppear {
                        if hasMore && !isLoadingMoreTopDeals && idx >= triggerIndex {
                            loadMoreTopDeals()
                        }
                    }
                }
            }
            .padding(.horizontal, ShopLayout.screenPadding)
            .padding(.top, 2)

            if hasMore || isLoadingMoreTopDeals {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.shopTextMuted)
                        .padding(.vertical, 12)
                    Spacer()
                }
                .onAppear {
                    if hasMore && !isLoadingMoreTopDeals {
                        loadMoreTopDeals()
                    }
                }
            }
        }
    }

    // MARK: - 5. Per Negozio Clean White Store Cards (Matching HomeView 1-to-1)

    private func storeDealsCard(showcase: StoreShowcase) -> some View {
        let promoText = showcase.dynamicPromoSubtitle(category: selectedCategory)
        let isFollowed = followedManager.isFollowing(storeId: showcase.store_id)
        let visibleProducts = Array(showcase.products.prefix(4))

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(
                            storeName: showcase.store_name,
                            showVerified: false,
                            showLabel: false,
                            size: 42,
                            hasRedRing: false,
                            logoURL: showcase.logo_url
                        )

                        VStack(alignment: .leading, spacing: 2.5) {
                            HStack(spacing: 6) {
                                Text(showcase.store_name)
                                    .font(.system(size: 16.5, weight: .bold, design: .rounded))
                                    .foregroundColor(.shopDark)
                                    .lineLimit(1)

                                if isFollowed {
                                    Text("Segui già")
                                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopPurple)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.shopPurpleLight)
                                        .clipShape(Capsule())
                                }
                            }

                            HStack(spacing: 5) {
                                Text(showcase.formattedRatingWithReviews)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.shopTextMuted)
                                Text("·")
                                    .foregroundColor(.shopTextMuted)
                                Text(promoText)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.shopTextMuted)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                Menu {
                    Button(action: {
                        followedManager.toggleFollow(storeId: showcase.store_id, storeName: showcase.store_name)
                    }) {
                        Label(
                            isFollowed ? "Smetti di seguire" : "Segui",
                            systemImage: isFollowed ? "checkmark.circle.fill" : "plus.circle"
                        )
                    }

                    NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                        Label("Visita il negozio", systemImage: "storefront")
                    }

                    Button(role: .destructive, action: {
                        withAnimation(ShopMotion.gridReflow) {
                            followedManager.hideStore(storeId: showcase.store_id)
                        }
                    }) {
                        Label("Nascondi questo negozio", systemImage: "eye.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.shopTextMuted)
                        .frame(width: 32, height: 32)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 14
            ) {
                ForEach(visibleProducts) { prod in
                    let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                    ShopDealGridCard(
                        product: prod,
                        matchedProduct: matched,
                        imageBackground: Color.shopSurface,
                        highlightedSize: filters.size
                    )
                }
            }

            // Single Clean Footer CTA (Exact HomeView Pattern)
            NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                HStack {
                    Text(showcase.total_offers > visibleProducts.count
                         ? "Tutte le \(showcase.total_offers) offerte"
                         : "Acquista tutto")
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Spacer()

                    Circle()
                        .fill(Color.shopSurfaceElevated)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.shopDark)
                        )
                }
                .padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
        .shopCard(padding: ShopLayout.cardPadding, cornerRadius: ShopLayout.largeCardRadius, shadowOpacity: 0.03, shadowRadius: 8, shadowY: 2)
        .padding(.horizontal, ShopLayout.screenPadding)
    }

    // MARK: - 6. Floating "Filtra" Pill

    private var floatingFilterButton: some View {
        let activeCount = filters.activeFilterCount
        return VStack {
            Spacer()
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showingFilterSheet = true
            }) {
                HStack(spacing: 7) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .bold))

                    Text("Filtra")
                        .font(.system(size: 14, weight: .bold, design: .rounded))

                    if activeCount > 0 {
                        Text("\(activeCount)")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .frame(minWidth: 19, minHeight: 19)
                            .padding(.horizontal, 4)
                            .background(Color.shopPurple)
                            .clipShape(Capsule())
                    }
                }
                .foregroundColor(activeCount > 0 ? .white : .shopDark)
                .padding(.horizontal, activeCount > 0 ? 18 : 20)
                .padding(.vertical, 11.5)
                .background(activeCount > 0 ? Color.shopDark : Color.white)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(activeCount > 0 ? 0.18 : 0.10), radius: 10, x: 0, y: 4)
                .overlay(
                    Capsule().stroke(activeCount > 0 ? Color.clear : Color.shopBorder, lineWidth: 1)
                )
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.96, pressedOpacity: 0.94))
            .padding(.bottom, ShopLayout.toastBottomOffset)
        }
    }

    // MARK: - Error & Empty States

    private func errorStateView(message: String) -> some View {
        FitMatchEmptyStateView(
            icon: "wifi.exclamationmark",
            accentColor: .shopRed,
            title: "Impossibile caricare le offerte",
            subtitle: message,
            primaryTitle: "Riprova",
            primaryIcon: "arrow.clockwise",
            onPrimaryTap: {
                Task {
                    await loadCurrentMode(category: selectedCategory, filters: filters, mode: viewMode, forceRefresh: true)
                }
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyStateView: some View {
        if !filters.isDefault {
            return FitMatchEmptyStateView(
                icon: "line.3.horizontal.decrease.circle",
                title: "Nessuna offerta con questi filtri",
                subtitle: "Prova a rimuovere o modificare uno dei filtri attivi.",
                primaryTitle: "Rimuovi filtri",
                primaryIcon: "arrow.counterclockwise",
                onPrimaryTap: {
                    applyQuery(category: selectedCategory, filters: DealsFilterOptions())
                }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        return FitMatchEmptyStateView(
            icon: "tag",
            title: "Nessuna offerta in \(categoryTitle(for: selectedCategory))",
            subtitle: "Al momento non ci sono ribassi in questa categoria.",
            primaryTitle: "Tutte le offerte",
            primaryIcon: "arrow.uturn.backward",
            onPrimaryTap: {
                applyQuery(category: "tutti", filters: DealsFilterOptions())
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func categoryTitle(for id: String) -> String {
        categories.first(where: { $0.id == id })?.name ?? "offerte"
    }

    // MARK: - Query & Mode Coordination

    private func switchViewMode(to newMode: DealsViewMode) {
        activeLoadTask?.cancel()
        loadError = nil
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            viewMode = newMode
        }
        let catParam: String? = selectedCategory == "tutti" ? nil : selectedCategory
        switch newMode {
        case .topDeals:
            if let cached = api.cachedTopDealsCrossStore(for: catParam, filters: filters) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    self.topDeals = cached.deals
                    self.totalTopDealsMatching = cached.total
                    self.isSwitchingQuery = false
                    self.isLoading = false
                }
                return
            }
        case .byStore:
            if let cached = api.cachedDealsShowcases(for: catParam, filters: filters) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    self.showcases = cached
                    self.isSwitchingQuery = false
                    self.isLoading = false
                }
                return
            }
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            isSwitchingQuery = true
        }
        let targetCat = selectedCategory
        let targetFilters = filters
        activeLoadTask = Task {
            await loadCurrentMode(category: targetCat, filters: targetFilters, mode: newMode)
        }
    }

    private func applyQuery(category newCategory: String, filters newFilters: DealsFilterOptions) {
        activeLoadTask?.cancel()
        loadError = nil
        hasReachedEndOfTopDeals = false
        isLoadingMoreTopDeals = false

        var normalizedFilters = newFilters
        if newCategory == "uomo" || newCategory == "donna" {
            normalizedFilters.gender = nil
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.74)) {
            self.selectedCategory = newCategory
            self.filters = normalizedFilters
        }

        let catParam: String? = newCategory == "tutti" ? nil : newCategory
        switch viewMode {
        case .topDeals:
            if let cached = api.cachedTopDealsCrossStore(for: catParam, filters: normalizedFilters) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.topDeals = cached.deals
                    self.totalTopDealsMatching = cached.total
                    self.isSwitchingQuery = false
                    self.isLoading = false
                }
                return
            }
        case .byStore:
            if let cached = api.cachedDealsShowcases(for: catParam, filters: normalizedFilters) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.showcases = cached
                    self.isSwitchingQuery = false
                    self.isLoading = false
                }
                return
            }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            self.isSwitchingQuery = true
        }
        let activeMode = viewMode
        activeLoadTask = Task {
            await loadCurrentMode(category: newCategory, filters: normalizedFilters, mode: activeMode)
        }
    }

    private func loadCurrentMode(
        category: String,
        filters: DealsFilterOptions,
        mode: DealsViewMode,
        forceRefresh: Bool = false
    ) async {
        isLoading = true
        loadError = nil
        defer {
            if selectedCategory == category && self.filters == filters && self.viewMode == mode {
                isLoading = false
                isSwitchingQuery = false
            }
        }

        let catParam: String? = category == "tutti" ? nil : category
        do {
            switch mode {
            case .topDeals:
                let result = try await api.getTopDealsCrossStore(
                    category: catParam,
                    filters: filters,
                    limit: topDealsPageSize,
                    offset: 0,
                    forceRefresh: forceRefresh
                )
                if Task.isCancelled { return }
                let prefetchUrls = result.deals.prefix(16).compactMap { URL(string: $0.image_url ?? "") }
                ImageCacheManager.shared.prefetch(urls: prefetchUrls)
                await MainActor.run {
                    guard self.selectedCategory == category, self.filters == filters, self.viewMode == mode else { return }
                    self.loadError = nil
                    self.hasReachedEndOfTopDeals = result.deals.count < topDealsPageSize
                    withAnimation(ShopMotion.gridReflow) {
                        self.topDeals = result.deals
                        self.totalTopDealsMatching = result.totalMatching
                    }
                }

            case .byStore:
                let sc = try await api.getDealsShowcases(
                    category: catParam,
                    filters: filters,
                    forceRefresh: forceRefresh
                )
                if Task.isCancelled { return }
                let prefetchUrls = sc.flatMap { $0.products.prefix(6) }.compactMap { URL(string: $0.image_url ?? "") }
                ImageCacheManager.shared.prefetch(urls: prefetchUrls)
                await MainActor.run {
                    guard self.selectedCategory == category, self.filters == filters, self.viewMode == mode else { return }
                    self.loadError = nil
                    withAnimation(ShopMotion.gridReflow) {
                        self.showcases = sc
                    }
                }
            }
        } catch is CancellationError {
            // Ignored when switching categories/filters rapidly
        } catch {
            print("DealsView loadCurrentMode error: \(error)")
            await MainActor.run {
                guard self.selectedCategory == category, self.filters == filters, self.viewMode == mode else { return }
                self.loadError = "Verifica la connessione di rete e riprova a sincronizzare le offerte."
            }
        }
    }

    private func loadMoreTopDeals() {
        guard !isLoadingMoreTopDeals, !hasReachedEndOfTopDeals else { return }
        isLoadingMoreTopDeals = true
        let nextOffset = topDeals.count
        let targetCat = selectedCategory
        let targetFilters = filters
        let catParam: String? = targetCat == "tutti" ? nil : targetCat

        Task {
            defer {
                Task { @MainActor in
                    self.isLoadingMoreTopDeals = false
                }
            }
            do {
                let res = try await api.getTopDealsCrossStore(
                    category: catParam,
                    filters: targetFilters,
                    limit: topDealsPageSize,
                    offset: nextOffset,
                    forceRefresh: true
                )
                let newUrls = res.deals.prefix(16).compactMap { URL(string: $0.image_url ?? "") }
                ImageCacheManager.shared.prefetch(urls: newUrls)
                await MainActor.run {
                    guard self.selectedCategory == targetCat, self.filters == targetFilters, self.viewMode == .topDeals else { return }
                    var seenIds = Set(self.topDeals.map(\.id))
                    let uniqueNew = res.deals.filter { seenIds.insert($0.id).inserted }
                    if uniqueNew.isEmpty || res.deals.count < topDealsPageSize {
                        self.hasReachedEndOfTopDeals = true
                    }
                    if !uniqueNew.isEmpty {
                        self.topDeals.append(contentsOf: uniqueNew)
                    }
                    self.totalTopDealsMatching = max(self.totalTopDealsMatching, res.totalMatching)
                }
            } catch {
                print("DealsView loadMoreTopDeals error: \(error)")
            }
        }
    }
}

// MARK: - Minimal Product Grid Card (Cohesive with HomeView & StoreDetailView)

struct ShopDealGridCard: View {
    let product: StoreShowcaseProduct
    let matchedProduct: MatchedProduct
    var showStorePill: Bool = false
    var imageBackground: Color = .white
    var highlightedSize: String? = nil

    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var prefs = UserPreferencesManager.shared

    private var discountBadgeText: String? {
        product.discountBadge
    }

    private var matchedPreferredSize: String? {
        if let active = highlightedSize?.trimmingCharacters(in: .whitespacesAndNewlines),
           !active.isEmpty,
           prefs.isSizeAvailable(active, in: product.available_sizes) {
            return active
        }
        let shoePref = prefs.preferences.preferredShoeSize.trimmingCharacters(in: .whitespacesAndNewlines)
        if !shoePref.isEmpty && prefs.isSizeAvailable(shoePref, in: product.available_sizes) {
            return shoePref
        }
        let appPref = prefs.preferences.preferredApparelSize.trimmingCharacters(in: .whitespacesAndNewlines)
        if !appPref.isEmpty && prefs.isSizeAvailable(appPref, in: product.available_sizes) {
            return appPref
        }
        return nil
    }

    private var eyebrowText: String {
        let b = product.effectiveBrand.trimmingCharacters(in: .whitespacesAndNewlines)
        let brandPart = b.isEmpty ? "SPORT" : b.uppercased()
        if showStorePill, let sName = product.store_name, !sName.isEmpty {
            return "\(brandPart) · \(sName)"
        }
        return brandPart
    }

    var body: some View {
        NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            VStack(alignment: .leading, spacing: 5.5) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                        .fill(imageBackground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 170)

                    if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 520) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 170)
                                    .padding(10)
                                    .transition(.opacity)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 170)
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: ShopLayout.mediumRadius, height: 170)
                                    .frame(maxWidth: .infinity)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "tag")
                            .font(.system(size: 26))
                            .foregroundColor(Color(red: 215/255, green: 215/255, blue: 222/255))
                            .frame(maxWidth: .infinity)
                            .frame(height: 170)
                    }

                    RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                        .stroke(Color.shopBorder, lineWidth: 1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 170)

                    HStack(alignment: .top, spacing: 4) {
                        if let disc = discountBadgeText {
                            Text(disc)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.shopRed)
                                .clipShape(Capsule())
                        }

                        Spacer(minLength: 2)

                        if product.isVerifiedAllTimeLow {
                            Text("Minimo")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopGreen)
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 3)
                                .background(Color.shopGreenLight)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(8)

                    VStack {
                        Spacer()
                        HStack(alignment: .bottom) {
                            if let stores = product.multi_store_count, stores > 1 {
                                Text("\(stores) negozi")
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(.shopDark)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.92))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.shopBorder, lineWidth: 0.7))
                            }

                            Spacer()

                            Button(action: {
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

                                    Image(systemName: wishlist.isFavorite(matchedProduct.canonical_name) ? "heart.fill" : "heart")
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundColor(wishlist.isFavorite(matchedProduct.canonical_name) ? .shopRed : .shopDark)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                    }
                    .frame(height: 170)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 170)

                Text(eyebrowText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.shopTextMuted)
                    .lineLimit(1)
                    .padding(.top, 2)

                Text(product.titleWithoutLeadingBrand)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.shopDark)
                    .lineLimit(2)
                    .lineSpacing(1.1)
                    .frame(height: 33, alignment: .topLeading)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(format: "%.2f €", product.current_price).replacingOccurrences(of: ".", with: ","))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    if let orig = product.original_price, orig > product.current_price {
                        Text(String(format: "%.2f €", orig).replacingOccurrences(of: ".", with: ","))
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundColor(.shopTextMuted)
                            .strikethrough()
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 6) {
                    if let matchedSize = matchedPreferredSize {
                        Text("✓ Tg. \(matchedSize)")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.shopPurple)
                            .lineLimit(1)
                    }

                    if product.effectiveFreeShipping {
                        Text(matchedPreferredSize == nil ? "Sped. gratis" : "· Gratis")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(.shopGreen)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .frame(height: 14)
            }
        }
        .buttonStyle(ShopCardPressStyle())
        .contextMenu {
            let isSaved = wishlist.isFavorite(matchedProduct.canonical_name)
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                wishlist.toggleFavorite(product: matchedProduct)
            }) {
                Label(
                    isSaved ? "Rimuovi dai preferiti" : "Salva nei preferiti",
                    systemImage: isSaved ? "heart.slash" : "heart.fill"
                )
            }

            if let url = URL(string: product.product_url) {
                Button(action: {
                    UIApplication.shared.open(url)
                }) {
                    Label("Apri offerta sullo store", systemImage: "arrow.up.right.square")
                }
            }
        }
    }
}

// MARK: - Clean Native Grouped Filter Sheet (Zero Pill Overload)

struct DealsFilterSheetView: View {
    let categories: [DealCategoryFilter]
    let preferredShoeSize: String
    let preferredApparelSize: String
    let favoriteBrands: [String]
    var onApply: (String, DealsFilterOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftCategory: String
    @State private var draftFilters: DealsFilterOptions

    private let maxPriceChoices: [(label: String, value: Double?)] = [
        ("Qualsiasi", nil),
        ("Fino a 50 €", 50),
        ("Fino a 80 €", 80),
        ("Fino a 100 €", 100),
        ("Fino a 150 €", 150),
        ("Fino a 200 €", 200)
    ]

    private let minDiscountChoices: [(label: String, value: Double?)] = [
        ("Qualsiasi", nil),
        ("Almeno 20%", 20),
        ("Almeno 30%", 30),
        ("Almeno 40%", 40),
        ("Almeno 50%", 50)
    ]

    private static let topBrandsList: [String] = [
        "Nike", "Adidas", "Asics", "Hoka", "Brooks", "Saucony",
        "Garmin", "Salomon", "New Balance", "On", "Puma",
        "Under Armour", "Polar", "Mizuno", "Bullpadel", "Head"
    ]

    init(
        categories: [DealCategoryFilter],
        selectedCategory: String,
        filters: DealsFilterOptions,
        preferredShoeSize: String,
        preferredApparelSize: String,
        favoriteBrands: [String],
        onApply: @escaping (String, DealsFilterOptions) -> Void
    ) {
        self.categories = categories
        self.preferredShoeSize = preferredShoeSize
        self.preferredApparelSize = preferredApparelSize
        self.favoriteBrands = favoriteBrands
        self.onApply = onApply
        self._draftCategory = State(initialValue: selectedCategory)
        self._draftFilters = State(initialValue: filters)
    }

    private var availableBrands: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for b in favoriteBrands + Self.topBrandsList {
            let trimmed = b.trimmingCharacters(in: .whitespacesAndNewlines)
            let low = trimmed.lowercased()
            if !trimmed.isEmpty && !seen.contains(low) {
                seen.insert(low)
                result.append(trimmed)
            }
        }
        return result
    }

    private var hasAnyResettableState: Bool {
        draftCategory != "tutti" || !draftFilters.isDefault
    }

    private var selectedCategoryName: String {
        categories.first(where: { $0.id == draftCategory })?.name ?? "Tutte"
    }

    private var selectedMaxPriceLabel: String {
        maxPriceChoices.first(where: { $0.value == draftFilters.maxPrice })?.label ?? "Qualsiasi"
    }

    private var selectedMinDiscountLabel: String {
        minDiscountChoices.first(where: { $0.value == draftFilters.minDiscount })?.label ?? "Qualsiasi"
    }

    private var genderBinding: Binding<String> {
        Binding(
            get: {
                if draftCategory == "uomo" { return "uomo" }
                if draftCategory == "donna" { return "donna" }
                return draftFilters.gender ?? "tutti"
            },
            set: { newVal in
                if draftCategory == "uomo" || draftCategory == "donna" {
                    draftCategory = "tutti"
                }
                draftFilters.gender = (newVal == "tutti") ? nil : newVal
            }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Group 1: Ordina, Categoria, Brand
                        groupedCard {
                            pickerRow(title: "Ordina per", value: draftFilters.sort.title, isHighlighted: draftFilters.sort != .quality) {
                                ForEach(DealsSortOption.allCases) { option in
                                    Button(action: { draftFilters.sort = option }) {
                                        Label(option.title, systemImage: draftFilters.sort == option ? "checkmark" : option.icon)
                                    }
                                }
                            }

                            Divider().padding(.leading, 16)

                            pickerRow(title: "Categoria", value: selectedCategoryName, isHighlighted: draftCategory != "tutti") {
                                ForEach(categories) { cat in
                                    Button(action: {
                                        draftCategory = cat.id
                                        if cat.id == "uomo" || cat.id == "donna" {
                                            draftFilters.gender = nil
                                        }
                                    }) {
                                        if draftCategory == cat.id {
                                            Label(cat.name, systemImage: "checkmark")
                                        } else {
                                            Text(cat.name)
                                        }
                                    }
                                }
                            }

                            Divider().padding(.leading, 16)

                            pickerRow(title: "Brand", value: draftFilters.brand ?? "Tutti", isHighlighted: draftFilters.brand != nil) {
                                Button(action: { draftFilters.brand = nil }) {
                                    if draftFilters.brand == nil {
                                        Label("Tutti", systemImage: "checkmark")
                                    } else {
                                        Text("Tutti")
                                    }
                                }
                                ForEach(availableBrands, id: \.self) { brandName in
                                    Button(action: { draftFilters.brand = brandName }) {
                                        if draftFilters.brand?.caseInsensitiveCompare(brandName) == .orderedSame {
                                            Label(brandName, systemImage: "checkmark")
                                        } else {
                                            Text(brandName)
                                        }
                                    }
                                }
                            }
                        }

                        // Group 2: Genere & Taglia
                        groupedCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Genere")
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundColor(.shopDark)

                                Picker("Genere", selection: genderBinding) {
                                    Text("Tutti").tag("tutti")
                                    Text("Uomo").tag("uomo")
                                    Text("Donna").tag("donna")
                                    Text("Unisex").tag("unisex")
                                }
                                .pickerStyle(.segmented)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Divider().padding(.leading, 16)

                            pickerRow(
                                title: "Taglia",
                                value: draftFilters.size.map { "Taglia \($0)" } ?? "Tutte",
                                isHighlighted: draftFilters.size != nil
                            ) {
                                Button(action: { draftFilters.size = nil }) {
                                    if draftFilters.size == nil {
                                        Label("Tutte", systemImage: "checkmark")
                                    } else {
                                        Text("Tutte")
                                    }
                                }

                                let shoePref = preferredShoeSize.trimmingCharacters(in: .whitespacesAndNewlines)
                                let appPref = preferredApparelSize.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !shoePref.isEmpty || !appPref.isEmpty {
                                    Section("Le mie taglie") {
                                        if !shoePref.isEmpty {
                                            Button(action: { draftFilters.size = shoePref }) {
                                                Label("Scarpe: \(shoePref)", systemImage: draftFilters.size == shoePref ? "checkmark" : "star")
                                            }
                                        }
                                        if !appPref.isEmpty {
                                            Button(action: { draftFilters.size = appPref }) {
                                                Label("Abbigliamento: \(appPref)", systemImage: draftFilters.size == appPref ? "checkmark" : "star")
                                            }
                                        }
                                    }
                                }

                                Section("Scarpe (EU)") {
                                    ForEach(UserPreferencesManager.shoeSizes, id: \.self) { sz in
                                        Button(action: { draftFilters.size = sz }) {
                                            if draftFilters.size == sz {
                                                Label(sz, systemImage: "checkmark")
                                            } else {
                                                Text(sz)
                                            }
                                        }
                                    }
                                }

                                Section("Abbigliamento") {
                                    ForEach(UserPreferencesManager.apparelSizes, id: \.self) { sz in
                                        Button(action: { draftFilters.size = sz }) {
                                            if draftFilters.size == sz {
                                                Label(sz, systemImage: "checkmark")
                                            } else {
                                                Text(sz)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Group 3: Budget, Sconto & Opzioni
                        groupedCard {
                            pickerRow(title: "Prezzo massimo", value: selectedMaxPriceLabel, isHighlighted: draftFilters.maxPrice != nil) {
                                ForEach(maxPriceChoices, id: \.label) { item in
                                    Button(action: { draftFilters.maxPrice = item.value }) {
                                        if draftFilters.maxPrice == item.value {
                                            Label(item.label, systemImage: "checkmark")
                                        } else {
                                            Text(item.label)
                                        }
                                    }
                                }
                            }

                            Divider().padding(.leading, 16)

                            pickerRow(title: "Sconto minimo", value: selectedMinDiscountLabel, isHighlighted: draftFilters.minDiscount != nil) {
                                ForEach(minDiscountChoices, id: \.label) { item in
                                    Button(action: { draftFilters.minDiscount = item.value }) {
                                        if draftFilters.minDiscount == item.value {
                                            Label(item.label, systemImage: "checkmark")
                                        } else {
                                            Text(item.label)
                                        }
                                    }
                                }
                            }

                            Divider().padding(.leading, 16)

                            Toggle("Solo spedizione gratuita", isOn: $draftFilters.freeShippingOnly)
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundColor(.shopDark)
                                .tint(.shopPurple)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                            Divider().padding(.leading, 16)

                            Toggle("Includi Bambino / Junior", isOn: $draftFilters.includeKids)
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundColor(.shopDark)
                                .tint(.shopPurple)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }

                // Single Clean Primary CTA
                VStack(spacing: 0) {
                    Divider()
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onApply(draftCategory, draftFilters)
                        dismiss()
                    }) {
                        let count = draftFilters.activeFilterCount
                        Text(count > 0 ? "Applica filtri (\(count))" : "Mostra offerte")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.shopDark)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .background(Color.white)
                }
            }
            .background(Color.shopSurface)
            .navigationTitle("Filtra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if hasAnyResettableState {
                        Button("Ripristina") {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            draftCategory = "tutti"
                            draftFilters = DealsFilterOptions()
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.shopPurple)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.shopDark)
                            .frame(width: 30, height: 30)
                            .background(Color.shopSurfaceElevated)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func groupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.shopBorder, lineWidth: 1)
        )
    }

    private func pickerRow<MenuContent: View>(
        title: String,
        value: String,
        isHighlighted: Bool,
        @ViewBuilder menu: () -> MenuContent
    ) -> some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(.shopDark)

                Spacer()

                HStack(spacing: 5) {
                    Text(value)
                        .font(.system(size: 14, weight: isHighlighted ? .semibold : .regular))
                        .foregroundColor(isHighlighted ? .shopPurple : .shopTextMuted)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.shopTextMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }
}
