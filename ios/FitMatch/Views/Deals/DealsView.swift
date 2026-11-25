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

    var icon: String {
        switch self {
        case .topDeals: return "flame.fill"
        case .byStore: return "storefront.fill"
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
    @State private var topDealsLimit: Int = 40
    @State private var isLoadingMoreTopDeals = false

    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var selectedCategory: String = "tutti"
    @State private var filters = DealsFilterOptions()
    @State private var expandedStoreIds: Set<String> = []
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

    // MARK: - Derived Data & Metrics

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

    private var activeProductsForMetrics: [StoreShowcaseProduct] {
        switch viewMode {
        case .topDeals:
            return displayedTopDeals.isEmpty ? displayedShowcases.flatMap { $0.products } : displayedTopDeals
        case .byStore:
            return displayedShowcases.isEmpty ? displayedTopDeals : displayedShowcases.flatMap { $0.products }
        }
    }

    private var realMaxDiscountPct: Int {
        let allDiscs = activeProductsForMetrics.compactMap { $0.discount_pct }.filter { $0 > 0 }
        return Int((allDiscs.max() ?? 0).rounded())
    }

    private var verifiedHighlightsCount: Int {
        activeProductsForMetrics.filter { $0.isVerifiedAllTimeLow || $0.isVerifiedBestMarketPrice }.count
    }

    private var totalCategoryDealsCount: Int {
        switch viewMode {
        case .topDeals:
            return max(totalTopDealsMatching, displayedTopDeals.count)
        case .byStore:
            return displayedShowcases.reduce(0) { $0 + max($1.total_offers, $1.products.count) }
        }
    }

    private var activeStoreCount: Int {
        switch viewMode {
        case .topDeals:
            return Set(displayedTopDeals.compactMap { $0.store_id?.lowercased() }).count
        case .byStore:
            return displayedShowcases.count
        }
    }

    private var isCurrentViewEmpty: Bool {
        switch viewMode {
        case .topDeals: return displayedTopDeals.isEmpty
        case .byStore: return displayedShowcases.isEmpty
        }
    }

    private var showHeroAndSpotlight: Bool {
        selectedCategory == "tutti" && filters.isDefault
    }

    private var preferredSizeForActiveCategory: String? {
        let nonSized: Set<String> = ["smartwatch", "padel", "nutrizione", "accessori"]
        if nonSized.contains(selectedCategory) { return nil }
        let apparelCats: Set<String> = ["abbigliamento", "fitness", "nuoto"]
        let shoe = prefs.preferences.preferredShoeSize.trimmingCharacters(in: .whitespacesAndNewlines)
        let apparel = prefs.preferences.preferredApparelSize.trimmingCharacters(in: .whitespacesAndNewlines)
        if apparelCats.contains(selectedCategory) {
            return apparel.isEmpty ? (shoe.isEmpty ? nil : shoe) : apparel
        }
        return shoe.isEmpty ? (apparel.isEmpty ? nil : apparel) : shoe
    }

    private var isGenderCategorySelected: Bool {
        selectedCategory == "uomo" || selectedCategory == "donna"
    }

    // Fallback categories when offline before first /api/stores sync
    private let defaultCategories: [DealCategoryFilter] = [
        DealCategoryFilter(
            id: "tutti",
            name: "Tutte",
            icon: "flame.fill",
            accentColor: Color(red: 245/255, green: 75/255, blue: 45/255),
            bgTint: Color(red: 254/255, green: 242/255, blue: 240/255)
        ),
        DealCategoryFilter(
            id: "donna",
            name: "Donna",
            icon: "figure.walk",
            accentColor: Color(red: 235/255, green: 65/255, blue: 85/255),
            bgTint: Color(red: 253/255, green: 240/255, blue: 244/255)
        ),
        DealCategoryFilter(
            id: "uomo",
            name: "Uomo",
            icon: "figure.stand",
            accentColor: Color(red: 35/255, green: 115/255, blue: 235/255),
            bgTint: Color(red: 238/255, green: 246/255, blue: 255/255)
        ),
        DealCategoryFilter(
            id: "running",
            name: "Scarpe Running",
            icon: "figure.run",
            accentColor: Color(red: 20/255, green: 160/255, blue: 120/255),
            bgTint: Color(red: 236/255, green: 250/255, blue: 245/255)
        ),
        DealCategoryFilter(
            id: "abbigliamento",
            name: "Abbigliamento",
            icon: "tshirt.fill",
            accentColor: Color(red: 120/255, green: 60/255, blue: 215/255),
            bgTint: Color(red: 246/255, green: 240/255, blue: 254/255)
        ),
        DealCategoryFilter(
            id: "smartwatch",
            name: "Smartwatch & GPS",
            icon: "applewatch",
            accentColor: Color(red: 15/255, green: 140/255, blue: 195/255),
            bgTint: Color(red: 238/255, green: 248/255, blue: 253/255)
        ),
        DealCategoryFilter(
            id: "accessori",
            name: "Accessori",
            icon: "bag.fill",
            accentColor: Color(red: 225/255, green: 145/255, blue: 20/255),
            bgTint: Color(red: 254/255, green: 248/255, blue: 238/255)
        ),
        DealCategoryFilter(
            id: "outdoor",
            name: "Outdoor & Trail",
            icon: "mountain.2.fill",
            accentColor: Color(red: 45/255, green: 135/255, blue: 75/255),
            bgTint: Color(red: 240/255, green: 249/255, blue: 242/255)
        ),
        DealCategoryFilter(
            id: "padel",
            name: "Padel",
            icon: "tennisball.fill",
            accentColor: Color(red: 135/255, green: 185/255, blue: 25/255),
            bgTint: Color(red: 248/255, green: 252/255, blue: 238/255)
        ),
        DealCategoryFilter(
            id: "cycling",
            name: "Ciclismo",
            icon: "bicycle",
            accentColor: Color(red: 70/255, green: 75/255, blue: 210/255),
            bgTint: Color(red: 242/255, green: 243/255, blue: 254/255)
        ),
        DealCategoryFilter(
            id: "fitness",
            name: "Fitness & Gym",
            icon: "dumbbell.fill",
            accentColor: Color(red: 215/255, green: 50/255, blue: 120/255),
            bgTint: Color(red: 253/255, green: 240/255, blue: 248/255)
        ),
        DealCategoryFilter(
            id: "calcio",
            name: "Calcio & Calcetto",
            icon: "soccerball",
            accentColor: Color(red: 22/255, green: 145/255, blue: 70/255),
            bgTint: Color(red: 238/255, green: 250/255, blue: 242/255)
        ),
        DealCategoryFilter(
            id: "tennis",
            name: "Tennis",
            icon: "tennis.racket",
            accentColor: Color(red: 215/255, green: 115/255, blue: 15/255),
            bgTint: Color(red: 255/255, green: 247/255, blue: 236/255)
        ),
        DealCategoryFilter(
            id: "basket",
            name: "Basket",
            icon: "basketball.fill",
            accentColor: Color(red: 225/255, green: 82/255, blue: 25/255),
            bgTint: Color(red: 255/255, green: 242/255, blue: 235/255)
        ),
        DealCategoryFilter(
            id: "sci",
            name: "Sci & Neve",
            icon: "snowflake",
            accentColor: Color(red: 14/255, green: 125/255, blue: 205/255),
            bgTint: Color(red: 238/255, green: 247/255, blue: 255/255)
        ),
        DealCategoryFilter(
            id: "nuoto",
            name: "Nuoto",
            icon: "figure.pool.swim",
            accentColor: Color(red: 0/255, green: 155/255, blue: 185/255),
            bgTint: Color(red: 236/255, green: 251/255, blue: 254/255)
        ),
        DealCategoryFilter(
            id: "nutrizione",
            name: "Nutrizione",
            icon: "bolt.heart.fill",
            accentColor: Color(red: 150/255, green: 65/255, blue: 200/255),
            bgTint: Color(red: 248/255, green: 240/255, blue: 255/255)
        )
    ]

    private var categories: [DealCategoryFilter] {
        guard !prefs.dynamicCategories.isEmpty else { return defaultCategories }
        return prefs.dynamicCategories.map { item in
            DealCategoryFilter(
                id: item.id,
                name: item.name,
                icon: (item.icon?.isEmpty == false ? item.icon! : "tag.fill"),
                accentColor: item.accent_hex.flatMap { Color(hex: $0) } ?? .shopPurple,
                bgTint: item.bg_hex.flatMap { Color(hex: $0) } ?? .shopPurpleLight
            )
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // MARK: - 1. Category Filter Pills Bar
                        categoryPillsBar
                            .padding(.top, 4)

                        // MARK: - 2. Dynamic Hero / Editorial (Default "Tutte") OR Compact Context Banner
                        if showHeroAndSpotlight {
                            heroBannerSection
                            dealsSpotlightCarousel
                        } else {
                            compactContextBanner
                        }

                        // MARK: - 3. View Mode Switcher ("Top Offerte" vs "Per Negozio") + Inline Sort
                        modeAndSortBar

                        // MARK: - 4. Real Quick Filter Chips (Mia taglia, Sped. gratis, Uomo/Donna, Budget, Sconto, Active pills)
                        quickFilterChipsBar

                        // MARK: - 5. Main Results Area
                        Group {
                            if isSwitchingQuery || (isLoading && isCurrentViewEmpty) {
                                ShopDealsSkeletonView()
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
                                LazyVStack(spacing: 22) {
                                    ForEach(displayedShowcases) { showcase in
                                        storeDealsSection(showcase: showcase)
                                    }
                                }
                                .shopFadeScaleTransition()
                            }
                        }
                        .animation(ShopMotion.gridReflow, value: selectedCategory)
                        .animation(ShopMotion.gridReflow, value: viewMode)
                        .animation(ShopMotion.gridReflow, value: filters.cacheKeySuffix)
                        .animation(.easeOut(duration: 0.22), value: isSwitchingQuery)

                        // Spacer for bottom dock and floating filter pill
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

            // MARK: - 6. Floating "Filtra" Pill with Active Count Badge
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
            // Warm the secondary mode in background for instant switching on default "Tutte"
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

    // MARK: - 1. Dynamic Hero Promo Banner (Compact, Data-Grounded)

    private var heroBannerSection: some View {
        let maxDisc = realMaxDiscountPct
        let verified = verifiedHighlightsCount
        let subtitleText: String = {
            if maxDisc >= 10 && verified > 0 {
                return "Sconti verificati fino \(IntelligentPromoGenerator.upToPercent(maxDisc)) • \(verified) minimi storici e miglior prezzo"
            } else if maxDisc >= 10 {
                return "Ribassi verificati fino \(IntelligentPromoGenerator.upToPercent(maxDisc)) sui migliori negozi sportivi"
            } else {
                return "Confronto in tempo reale tra i migliori negozi sportivi partner"
            }
        }()

        return ZStack(alignment: .bottomLeading) {
            if UIImage(named: "deals_hero_banner") != nil {
                Image("deals_hero_banner")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 154)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color(red: 168/255, green: 34/255, blue: 74/255).opacity(0.84),
                                Color(red: 185/255, green: 42/255, blue: 82/255).opacity(0.38),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 245/255, green: 85/255, blue: 72/255),
                        Color(red: 220/255, green: 52/255, blue: 88/255),
                        Color(red: 145/255, green: 34/255, blue: 98/255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.white)
                    Text("OFFERTE VERIFICATE")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .tracking(0.8)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.22))
                .clipShape(Capsule())

                Text("I migliori affari,\nconfrontati davvero")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitleText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(2)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .padding(.trailing, 76)
        }
        .frame(height: 154)
        .clipShape(RoundedRectangle(cornerRadius: ShopLayout.largeCardRadius, style: .continuous))
        .padding(.horizontal, ShopLayout.screenPadding)
        .shadow(color: Color(red: 220/255, green: 52/255, blue: 88/255).opacity(0.18), radius: 12, x: 0, y: 5)
    }

    // MARK: - 1b. Compact Context Header (Category or Active Filters -> Products Immediately Above the Fold)

    private var compactContextBanner: some View {
        let activeCat = categories.first(where: { $0.id == selectedCategory })
        let accent = activeCat?.accentColor ?? .shopPurple
        let tint = activeCat?.bgTint ?? .shopPurpleLight
        let maxDisc = realMaxDiscountPct
        let storesCnt = activeStoreCount
        let totalDeals = totalCategoryDealsCount
        let titleText: String = {
            if selectedCategory == "tutti" {
                return "Offerte filtrate"
            }
            return activeCat?.name ?? selectedCategory.capitalized
        }()

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint)
                    .frame(width: 42, height: 42)
                Image(systemName: activeCat?.icon ?? "slider.horizontal.3")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(titleText)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)
                        .lineLimit(1)

                    if filters.activeFilterCount > 0 {
                        Text("\(filters.activeFilterCount) \(filters.activeFilterCount == 1 ? "filtro" : "filtri")")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(.shopPurple)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.shopPurpleLight)
                            .clipShape(Capsule())
                    }
                }

                if totalDeals > 0 {
                    let discSuffix = maxDisc >= 10 ? " • fino \(IntelligentPromoGenerator.upToPercent(maxDisc))" : ""
                    let storePart = storesCnt > 0 ? " in \(storesCnt) \(storesCnt == 1 ? "negozio" : "negozi")" : ""
                    Text("\(totalDeals) offerte\(storePart)\(discSuffix)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                        .lineLimit(1)
                } else if isLoading || isSwitchingQuery {
                    Text("Ricerca migliori sconti in corso...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                } else {
                    Text("Nessuna offerta trovata con questa combinazione")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                applyQuery(category: "tutti", filters: DealsFilterOptions())
            }) {
                Text(!filters.isDefault ? "Reset" : "Tutte")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.shopSurfaceElevated)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.shopBorder, lineWidth: 1)
        )
        .padding(.horizontal, ShopLayout.screenPadding)
    }

    // MARK: - 2. Category Filter Pills Bar

    private var categoryPillsBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { cat in
                        let isSelected = selectedCategory == cat.id

                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            var nextFilters = filters
                            // Prevent contradictory category ("donna") + gender filter ("uomo")
                            if cat.id == "uomo" || cat.id == "donna" {
                                nextFilters.gender = nil
                            }
                            applyQuery(category: cat.id, filters: nextFilters)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(isSelected ? .white : cat.accentColor)

                                Text(cat.name)
                                    .font(.system(size: 13.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .foregroundColor(isSelected ? .white : Color(red: 35/255, green: 38/255, blue: 46/255))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8.5)
                            .background(
                                ZStack {
                                    Capsule()
                                        .fill(Color.white)

                                    if isSelected {
                                        Capsule()
                                            .fill(Color(red: 22/255, green: 22/255, blue: 26/255))
                                            .shadow(color: Color.black.opacity(0.12), radius: 5, x: 0, y: 2)
                                            .matchedGeometryEffect(id: "deals_cat_pill", in: dealsCatNamespace)
                                    }
                                }
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isSelected ? Color.clear : Color(red: 228/255, green: 230/255, blue: 236/255),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.96, pressedOpacity: 0.92))
                        .id(cat.id)
                    }
                }
                .padding(.horizontal, 16)
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

    // MARK: - 3. View Mode Switcher ("Top Offerte" vs "Per Negozio") + Inline Sort

    private var modeAndSortBar: some View {
        HStack(spacing: 10) {
            // Segmented Mode Pill
            HStack(spacing: 2) {
                ForEach(DealsViewMode.allCases) { mode in
                    let isSelected = viewMode == mode
                    Button(action: {
                        guard viewMode != mode else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        switchViewMode(to: mode)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11, weight: .bold))
                            Text(mode.title)
                                .font(.system(size: 12.5, weight: isSelected ? .bold : .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundColor(isSelected ? .white : .shopDark)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7.5)
                        .background(
                            ZStack {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.shopDark)
                                        .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)
                                        .matchedGeometryEffect(id: "deals_mode_pill", in: dealsModeNamespace)
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.shopBorder, lineWidth: 1))

            Spacer(minLength: 4)

            // Quick Sort Menu Pill
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
                let isCustomSort = filters.sort != .quality
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 10.5, weight: .bold))
                    Text(filters.sort.shortTitle)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(isCustomSort ? .shopPurple : .shopDark)
                .padding(.horizontal, 11)
                .padding(.vertical, 8.5)
                .background(isCustomSort ? Color.shopPurpleLight : Color.white)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isCustomSort ? Color.shopPurple.opacity(0.35) : Color.shopBorder, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, ShopLayout.screenPadding)
    }

    // MARK: - 4. Quick Filter Chips Bar (One-Tap Real Server Filters)

    private var quickFilterChipsBar: some View {
        let prefSize = preferredSizeForActiveCategory
        let isUsingPrefSize = (prefSize != nil && filters.size?.caseInsensitiveCompare(prefSize!) == .orderedSame)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 1. "Mia taglia" one-tap toggle
                if let sz = prefSize {
                    quickToggleChip(
                        title: "Mia taglia (\(sz))",
                        icon: "ruler",
                        isActive: isUsingPrefSize,
                        activeColor: .shopPurple,
                        activeBg: .shopPurpleLight
                    ) {
                        var next = filters
                        next.size = isUsingPrefSize ? nil : sz
                        applyQuery(category: selectedCategory, filters: next)
                    }
                }

                // Custom size pill if user selected a size different from their saved preferred size
                if let activeSz = filters.size, !activeSz.isEmpty, !isUsingPrefSize {
                    removableFilterChip(label: "Tg. \(activeSz)") {
                        var next = filters
                        next.size = nil
                        applyQuery(category: selectedCategory, filters: next)
                    }
                }

                // 2. "Sped. gratis" one-tap toggle
                quickToggleChip(
                    title: "Sped. gratis",
                    icon: "box.truck.fill",
                    isActive: filters.freeShippingOnly,
                    activeColor: .shopGreen,
                    activeBg: .shopGreenLight
                ) {
                    var next = filters
                    next.freeShippingOnly.toggle()
                    applyQuery(category: selectedCategory, filters: next)
                }

                // 3. Combinable Gender chips (hidden when already in Donna/Uomo category)
                if !isGenderCategorySelected {
                    quickToggleChip(
                        title: "Uomo",
                        icon: "figure.stand",
                        isActive: filters.gender == "uomo",
                        activeColor: Color(red: 35/255, green: 115/255, blue: 235/255),
                        activeBg: Color(red: 238/255, green: 246/255, blue: 255/255)
                    ) {
                        var next = filters
                        next.gender = (next.gender == "uomo") ? nil : "uomo"
                        applyQuery(category: selectedCategory, filters: next)
                    }

                    quickToggleChip(
                        title: "Donna",
                        icon: "figure.walk",
                        isActive: filters.gender == "donna",
                        activeColor: Color(red: 235/255, green: 65/255, blue: 85/255),
                        activeBg: Color(red: 253/255, green: 240/255, blue: 244/255)
                    ) {
                        var next = filters
                        next.gender = (next.gender == "donna") ? nil : "donna"
                        applyQuery(category: selectedCategory, filters: next)
                    }

                    if filters.gender == "unisex" {
                        removableFilterChip(label: "Unisex") {
                            var next = filters
                            next.gender = nil
                            applyQuery(category: selectedCategory, filters: next)
                        }
                    }
                }

                // 4. Quick High Discount chip (≥ 40%)
                let isQuickDisc = filters.minDiscount == 40
                quickToggleChip(
                    title: "≥ 40%",
                    icon: "percent",
                    isActive: isQuickDisc,
                    activeColor: .shopRed,
                    activeBg: Color(red: 254/255, green: 242/255, blue: 242/255)
                ) {
                    var next = filters
                    next.minDiscount = isQuickDisc ? nil : 40
                    applyQuery(category: selectedCategory, filters: next)
                }

                // Custom discount pill if set via Filter Sheet to another value (20, 30, 50...)
                if let customDisc = filters.minDiscount, customDisc != 40 {
                    removableFilterChip(label: "≥ \(Int(customDisc))%") {
                        var next = filters
                        next.minDiscount = nil
                        applyQuery(category: selectedCategory, filters: next)
                    }
                }

                // 5. Quick Budget chip (≤ 100 €)
                let isQuickBudget = filters.maxPrice == 100
                quickToggleChip(
                    title: "≤ 100 €",
                    icon: "eurosign.circle",
                    isActive: isQuickBudget,
                    activeColor: .shopPurple,
                    activeBg: .shopPurpleLight
                ) {
                    var next = filters
                    next.maxPrice = isQuickBudget ? nil : 100
                    applyQuery(category: selectedCategory, filters: next)
                }

                // Custom max price pill from Filter Sheet
                if let customPrice = filters.maxPrice, customPrice != 100 {
                    removableFilterChip(label: "≤ \(Int(customPrice)) €") {
                        var next = filters
                        next.maxPrice = nil
                        applyQuery(category: selectedCategory, filters: next)
                    }
                }

                // Active Brand pill from Filter Sheet
                if let activeBrand = filters.brand, !activeBrand.isEmpty {
                    removableFilterChip(label: activeBrand) {
                        var next = filters
                        next.brand = nil
                        applyQuery(category: selectedCategory, filters: next)
                    }
                }

                // Active Kids pill if enabled
                if filters.includeKids {
                    removableFilterChip(label: "Incl. Bambino") {
                        var next = filters
                        next.includeKids = false
                        applyQuery(category: selectedCategory, filters: next)
                    }
                }

                // Reset all filters chip
                if !filters.isDefault {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        applyQuery(category: selectedCategory, filters: DealsFilterOptions())
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10, weight: .bold))
                            Text("Reset")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.shopRed)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Color(red: 254/255, green: 242/255, blue: 242/255))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ShopLayout.screenPadding)
        }
    }

    private func quickToggleChip(
        title: String,
        icon: String,
        isActive: Bool,
        activeColor: Color,
        activeBg: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .bold : .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(isActive ? activeColor : Color(red: 55/255, green: 58/255, blue: 68/255))
            .padding(.horizontal, 11.5)
            .padding(.vertical, 7)
            .background(isActive ? activeBg : Color.white)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    isActive ? activeColor.opacity(0.42) : Color.shopBorder,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(ShopCardPressStyle(scale: 0.96, pressedOpacity: 0.92))
    }

    private func removableFilterChip(label: String, onRemove: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onRemove()
        }) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .black))
            }
            .foregroundColor(.shopPurple)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.shopPurpleLight)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.shopPurple.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 5. Editorial Collections Carousel (Default "Tutte")

    private var dealsSpotlightCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                spotlightCollectionCard(
                    title: "Top Saldi Running",
                    subtitle: "Super-scarpe e modelli gara al miglior prezzo",
                    icon: "figure.run",
                    imageName: "deals_running_spotlight",
                    gradientColors: [
                        Color(red: 16/255, green: 30/255, blue: 62/255),
                        Color(red: 36/255, green: 68/255, blue: 122/255)
                    ],
                    targetCategory: "running"
                )

                spotlightCollectionCard(
                    title: "Smartwatch & GPS",
                    subtitle: "Garmin, Polar e Suunto scontati",
                    icon: "applewatch",
                    imageName: nil,
                    gradientColors: [
                        Color(red: 10/255, green: 72/255, blue: 108/255),
                        Color(red: 16/255, green: 122/255, blue: 158/255)
                    ],
                    targetCategory: "smartwatch"
                )

                spotlightCollectionCard(
                    title: "Fitness & Palestra",
                    subtitle: "Metcon, Dropset, Nano e training",
                    icon: "dumbbell.fill",
                    imageName: nil,
                    gradientColors: [
                        Color(red: 64/255, green: 26/255, blue: 112/255),
                        Color(red: 126/255, green: 46/255, blue: 152/255)
                    ],
                    targetCategory: "fitness"
                )
            }
            .padding(.horizontal, ShopLayout.screenPadding)
        }
    }

    private func spotlightCollectionCard(
        title: String,
        subtitle: String,
        icon: String,
        imageName: String?,
        gradientColors: [Color],
        targetCategory: String
    ) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            applyQuery(category: targetCategory, filters: filters)
        }) {
            ZStack(alignment: .bottomLeading) {
                if let img = imageName, UIImage(named: img) != nil {
                    Image(img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 282, height: 92)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [
                                    gradientColors[0].opacity(0.84),
                                    gradientColors[0].opacity(0.32),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                } else {
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    HStack {
                        Spacer()
                        Image(systemName: icon)
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(.white.opacity(0.14))
                            .padding(.trailing, 18)
                    }
                }

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 15.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)

                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .frame(width: 282, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: gradientColors[0].opacity(0.16), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(ShopCardPressStyle(scale: 0.97, pressedOpacity: 0.94))
    }

    // MARK: - 6. Top Offerte Cross-Store 2-Column Grid

    private var topDealsGridSection: some View {
        let deals = displayedTopDeals
        let total = max(totalTopDealsMatching, deals.count)
        let hasMore = deals.count < total && topDealsLimit < 80 && deals.count < 80

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedCategory == "tutti" ? "Migliori offerte cross-store" : "Migliori offerte · \(categoryTitle(for: selectedCategory))")
                        .font(.system(size: 16.5, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)
                        .lineLimit(1)

                    Text("\(total) offerte verificate • miglior prezzo tra tutti gli store")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, ShopLayout.screenPadding)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 16
            ) {
                ForEach(deals) { prod in
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
                }
            }
            .padding(.horizontal, ShopLayout.screenPadding)

            if hasMore {
                HStack {
                    Spacer()
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        loadMoreTopDeals()
                    }) {
                        HStack(spacing: 8) {
                            if isLoadingMoreTopDeals {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.shopDark)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.shopPurple)
                            }
                            Text(isLoadingMoreTopDeals ? "Caricamento..." : "Carica altre offerte")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.shopBorder, lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingMoreTopDeals)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - 7. Store Deals Section ("Per Negozio")

    private func storeDealsSection(showcase: StoreShowcase) -> some View {
        let promoText = showcase.dynamicPromoSubtitle(category: selectedCategory)
        let reviewCount = showcase.review_count ?? StoreRatingHelper.reviewCount(for: showcase.store_name, storeId: showcase.store_id)
        let rating = !showcase.rating.isEmpty ? showcase.rating.replacingOccurrences(of: ".", with: ",") : StoreRatingHelper.rating(for: showcase.store_name, storeId: showcase.store_id)
        let isFollowed = followedManager.isFollowing(storeId: showcase.store_id)
        let isExpanded = expandedStoreIds.contains(showcase.store_id)
        let visibleProducts = isExpanded ? showcase.products : Array(showcase.products.prefix(4))
        let hiddenCount = max(0, showcase.products.count - 4)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 44, hasRedRing: true, logoURL: showcase.logo_url)

                        VStack(alignment: .leading, spacing: 2.5) {
                            HStack(spacing: 6) {
                                Text(showcase.store_name)
                                    .font(.system(size: 16.5, weight: .bold, design: .rounded))
                                    .foregroundColor(.shopDark)
                                    .lineLimit(1)

                                HStack(spacing: 2.5) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundColor(.shopOrange)
                                    Text(rating)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopDark)
                                    Text("(\(reviewCount))")
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundColor(.shopTextMuted)
                                }
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 2)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.shopBorder, lineWidth: 0.8))

                                if isFollowed {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.shopPurple)
                                }
                            }

                            Text(promoText)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(Color(red: 220/255, green: 50/255, blue: 35/255))
                                .lineLimit(1)
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
                            isFollowed ? "Non seguire più" : "Segui negozio",
                            systemImage: isFollowed ? "person.badge.minus" : "person.badge.plus"
                        )
                    }

                    NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                        Label("Visualizza negozio", systemImage: "arrow.right.circle")
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
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(red: 120/255, green: 120/255, blue: 125/255))
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 16)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 16
            ) {
                ForEach(visibleProducts) { prod in
                    let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                    ShopDealGridCard(
                        product: prod,
                        matchedProduct: matched,
                        highlightedSize: filters.size
                    )
                }
            }
            .padding(.horizontal, 16)

            if hiddenCount > 0 || showcase.total_offers > visibleProducts.count {
                HStack(spacing: 10) {
                    if hiddenCount > 0 {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(ShopMotion.gridReflow) {
                                if isExpanded {
                                    expandedStoreIds.remove(showcase.store_id)
                                } else {
                                    expandedStoreIds.insert(showcase.store_id)
                                }
                            }
                        }) {
                            HStack(spacing: 5) {
                                Text(isExpanded ? "Mostra meno" : "Altre \(hiddenCount) offerte")
                                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.shopDark)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.shopBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                        HStack(spacing: 4) {
                            Text(showcase.total_offers > showcase.products.count
                                 ? "Tutte le \(showcase.total_offers) su \(showcase.store_name)"
                                 : "Vai allo store")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10.5, weight: .bold))
                        }
                        .foregroundColor(.shopPurple)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, -2)
            }
        }
    }

    // MARK: - 8. Floating "Filtra" Button with Active Filter Badge

    private var floatingFilterButton: some View {
        let activeCount = filters.activeFilterCount
        return VStack {
            Spacer()
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showingFilterSheet = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13.5, weight: .bold))

                    Text("Filtra")
                        .font(.system(size: 14, weight: .bold, design: .rounded))

                    if activeCount > 0 {
                        Text("\(activeCount)")
                            .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .padding(.horizontal, 4)
                            .background(Color.shopPurple)
                            .clipShape(Capsule())
                    }
                }
                .foregroundColor(activeCount > 0 ? .white : Color(red: 25/255, green: 25/255, blue: 30/255))
                .padding(.horizontal, activeCount > 0 ? 18 : 22)
                .padding(.vertical, 12)
                .background(activeCount > 0 ? Color.shopDark : Color.white)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(activeCount > 0 ? 0.22 : 0.12), radius: 12, x: 0, y: 5)
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
            badgeText: "CONNESSIONE",
            title: "Impossibile caricare le offerte",
            subtitle: message,
            primaryTitle: "Riprova",
            primaryIcon: "arrow.clockwise",
            primaryColor: .shopDark,
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
        let activeCategory = categories.first(where: { $0.id == selectedCategory })
        if !filters.isDefault {
            return FitMatchEmptyStateView(
                icon: "line.3.horizontal.decrease.circle",
                illustrationName: "empty_deals",
                accentColor: .shopPurple,
                badgeText: "FILTRI ATTIVI",
                title: "Nessuna offerta con questi filtri",
                subtitle: "Prova ad allargare il budget, cambiare taglia o rimuovere uno dei filtri selezionati.",
                primaryTitle: "Rimuovi filtri",
                primaryIcon: "arrow.counterclockwise",
                primaryColor: .shopPurple,
                onPrimaryTap: {
                    applyQuery(category: selectedCategory, filters: DealsFilterOptions())
                }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        return FitMatchEmptyStateView(
            icon: activeCategory?.icon ?? "tag.slash",
            illustrationName: "empty_deals",
            accentColor: activeCategory?.accentColor ?? .shopPurple,
            badgeText: "STATO CATEGORIA",
            title: "Nessuno sconto attivo in \(categoryTitle(for: selectedCategory))",
            subtitle: "Al momento gli store partner non hanno ribassi verificati in questa categoria. Esplora tutte le offerte o torna più tardi per i nuovi drop.",
            primaryTitle: "Vedi tutte le offerte",
            primaryIcon: "sparkles",
            primaryColor: .shopPurple,
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
        expandedStoreIds.removeAll()
        topDealsLimit = 40

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
                    limit: topDealsLimit,
                    forceRefresh: forceRefresh
                )
                if Task.isCancelled { return }
                let prefetchUrls = result.deals.prefix(16).compactMap { URL(string: $0.image_url ?? "") }
                ImageCacheManager.shared.prefetch(urls: prefetchUrls)
                await MainActor.run {
                    guard self.selectedCategory == category, self.filters == filters, self.viewMode == mode else { return }
                    self.loadError = nil
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
        guard !isLoadingMoreTopDeals else { return }
        isLoadingMoreTopDeals = true
        let nextLimit = min(80, topDealsLimit + 40)
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
                    limit: nextLimit,
                    forceRefresh: true
                )
                await MainActor.run {
                    guard self.selectedCategory == targetCat, self.filters == targetFilters, self.viewMode == .topDeals else { return }
                    self.topDealsLimit = nextLimit
                    withAnimation(ShopMotion.gridReflow) {
                        self.topDeals = res.deals
                        self.totalTopDealsMatching = res.totalMatching
                    }
                }
            } catch {
                print("DealsView loadMoreTopDeals error: \(error)")
            }
        }
    }
}

// MARK: - Redesigned Deal Product Grid Card (Data-Rich, Honest Signals, 2-Line Title)

struct ShopDealGridCard: View {
    let product: StoreShowcaseProduct
    let matchedProduct: MatchedProduct
    var showStorePill: Bool = false
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

    private var cleanBrandLabel: String {
        let b = product.effectiveBrand.trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? "SPORT" : b.uppercased()
    }

    var body: some View {
        NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            VStack(alignment: .leading, spacing: 6) {
                // 1. Image Container with Crisp Compact Badges
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 176)
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)

                    if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 520) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 176)
                                    .padding(10)
                                    .transition(.opacity)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 176)
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: 18, height: 176)
                                    .frame(maxWidth: .infinity)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Color(red: 220/255, green: 220/255, blue: 225/255))
                            .frame(maxWidth: .infinity)
                            .frame(height: 176)
                    }

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.9)
                        .frame(maxWidth: .infinity)
                        .frame(height: 176)

                    // Top Overlays: Compact "-55%" Badge + Optional Verified Trust Pill (Max 1)
                    HStack(alignment: .top, spacing: 5) {
                        if let disc = discountBadgeText {
                            Text(disc)
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7.5)
                                .padding(.vertical, 3.5)
                                .background(Color(red: 228/255, green: 42/255, blue: 38/255))
                                .clipShape(Capsule())
                        }

                        Spacer(minLength: 2)

                        if product.isVerifiedAllTimeLow {
                            HStack(spacing: 2.5) {
                                Image(systemName: "arrow.down.right")
                                    .font(.system(size: 8.5, weight: .black))
                                Text("Minimo")
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.shopGreen)
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 3.5)
                            .background(Color.shopGreenLight.opacity(0.96))
                            .clipShape(Capsule())
                        } else if product.isVerifiedBestMarketPrice {
                            HStack(spacing: 2.5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8.5, weight: .bold))
                                Text("Top")
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.shopPurple)
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 3.5)
                            .background(Color.shopPurpleLight.opacity(0.96))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(9)

                    // Bottom Overlays: Multi-Store Count Pill (Left) + Wishlist Heart (Right)
                    VStack {
                        Spacer()
                        HStack(alignment: .bottom) {
                            if let stores = product.multi_store_count, stores > 1 {
                                Text("\(stores) negozi")
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3.5)
                                    .background(Color.shopDark.opacity(0.76))
                                    .clipShape(Capsule())
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
                                        .frame(width: 31, height: 31)
                                        .shadow(color: Color.black.opacity(0.10), radius: 5, x: 0, y: 2)

                                    Image(systemName: wishlist.isFavorite(matchedProduct.canonical_name) ? "heart.fill" : "heart")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(wishlist.isFavorite(matchedProduct.canonical_name) ? .shopRed : .shopDark)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(9)
                    }
                    .frame(height: 176)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 176)

                // 2. Eyebrow Row: Brand (+ Store in Cross-Store mode)
                HStack(spacing: 4) {
                    Text(cleanBrandLabel)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.shopTextMuted)
                        .tracking(0.4)
                        .lineLimit(1)

                    if showStorePill, let sName = product.store_name, !sName.isEmpty {
                        Text("· \(sName)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.shopPurple)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 2)

                // 3. Clean 2-Line Product Title
                Text(product.titleWithoutLeadingBrand)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.shopDark)
                    .lineLimit(2)
                    .lineSpacing(1.2)
                    .frame(height: 34, alignment: .topLeading)

                // 4. Price Row
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(format: "%.2f €", product.current_price).replacingOccurrences(of: ".", with: ","))
                        .font(.system(size: 15.5, weight: .heavy, design: .rounded))
                        .foregroundColor(.shopDark)

                    if let orig = product.original_price, orig > product.current_price {
                        Text(String(format: "%.2f €", orig).replacingOccurrences(of: ".", with: ","))
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundColor(.shopTextMuted)
                            .strikethrough()
                            .lineLimit(1)
                    }
                }

                // 5. High-Value Decision Row
                HStack(spacing: 6) {
                    if let matchedSize = matchedPreferredSize {
                        HStack(spacing: 2.5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("Tg. \(matchedSize)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.shopPurple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.shopPurpleLight)
                        .clipShape(Capsule())
                    }

                    if product.effectiveFreeShipping {
                        HStack(spacing: 2.5) {
                            Image(systemName: "box.truck.fill")
                                .font(.system(size: 8.5))
                            Text("Gratis")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.shopGreen)
                        .lineLimit(1)
                    } else if matchedPreferredSize == nil, let sc = product.size_count, sc >= 3 {
                        Text("\(sc) taglie disp.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .frame(height: 18)
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

// MARK: - Complete Deals Filter, Sort & Category Bottom Sheet

struct DealsFilterSheetView: View {
    let categories: [DealCategoryFilter]
    let preferredShoeSize: String
    let preferredApparelSize: String
    let favoriteBrands: [String]
    var onApply: (String, DealsFilterOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftCategory: String
    @State private var draftFilters: DealsFilterOptions
    @State private var sizeTab: SizeGroupTab = .shoes

    enum SizeGroupTab: String, CaseIterable {
        case shoes = "Scarpe"
        case apparel = "Abbigliamento"
    }

    private let maxPriceChoices: [(label: String, value: Double?)] = [
        ("Qualsiasi", nil),
        ("≤ 50 €", 50),
        ("≤ 80 €", 80),
        ("≤ 100 €", 100),
        ("≤ 150 €", 150),
        ("≤ 200 €", 200)
    ]

    private let minDiscountChoices: [(label: String, value: Double?)] = [
        ("Qualsiasi", nil),
        ("≥ 20%", 20),
        ("≥ 30%", 30),
        ("≥ 40%", 40),
        ("≥ 50%", 50)
    ]

    private let genderChoices: [(label: String, value: String?)] = [
        ("Tutti", nil),
        ("Uomo", "uomo"),
        ("Donna", "donna"),
        ("Unisex", "unisex")
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
        let isApparelSize = filters.size.map { UserPreferencesManager.apparelSizes.contains($0.uppercased()) } ?? false
        let isApparelCat = ["abbigliamento", "fitness", "nuoto"].contains(selectedCategory)
        self._sizeTab = State(initialValue: (isApparelSize || (filters.size == nil && isApparelCat)) ? .apparel : .shoes)
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        // 1. Ordinamento
                        sortSection

                        // 2. Categoria
                        categorySection

                        // 3. Genere
                        genderSection

                        // 4. Taglia
                        sizeSection

                        // 5. Budget massimo
                        budgetSection

                        // 6. Sconto minimo
                        discountSection

                        // 7. Brand
                        brandSection

                        // 8. Opzioni extra
                        optionsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }

                // Sticky Bottom Apply Bar
                stickyFooter
            }
            .background(Color(red: 248/255, green: 248/255, blue: 250/255))
            .navigationTitle("Filtra offerte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(.shopDark)
                            .frame(width: 32, height: 32)
                            .background(Color(red: 238/255, green: 239/255, blue: 243/255))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sheet Sections

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Ordina per", icon: "arrow.up.arrow.down")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(DealsSortOption.allCases) { option in
                    let isSelected = draftFilters.sort == option
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        draftFilters.sort = option
                    }) {
                        HStack(spacing: 7) {
                            Image(systemName: option.icon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(isSelected ? .shopPurple : .shopTextMuted)
                            Text(option.title)
                                .font(.system(size: 12.5, weight: isSelected ? .bold : .semibold, design: .rounded))
                                .foregroundColor(isSelected ? .shopPurple : .shopDark)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(isSelected ? Color.shopPurpleLight : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: isSelected ? 1.4 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Categoria", icon: "square.grid.2x2.fill")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { cat in
                        let isSelected = draftCategory == cat.id
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            draftCategory = cat.id
                            if cat.id == "uomo" || cat.id == "donna" {
                                draftFilters.gender = nil
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundColor(isSelected ? .white : cat.accentColor)
                                Text(cat.name)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .semibold, design: .rounded))
                                    .foregroundColor(isSelected ? .white : .shopDark)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(isSelected ? Color.shopDark : Color.white)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(isSelected ? Color.clear : Color.shopBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var genderSection: some View {
        let effectiveGender: String? = {
            if draftCategory == "uomo" { return "uomo" }
            if draftCategory == "donna" { return "donna" }
            return draftFilters.gender
        }()

        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Genere", icon: "person.2.fill")

            HStack(spacing: 8) {
                ForEach(genderChoices, id: \.label) { item in
                    let isSelected = effectiveGender == item.value
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if draftCategory == "uomo" || draftCategory == "donna" {
                            draftCategory = "tutti"
                        }
                        draftFilters.gender = item.value
                    }) {
                        Text(item.label)
                            .font(.system(size: 13, weight: isSelected ? .bold : .semibold, design: .rounded))
                            .foregroundColor(isSelected ? .white : .shopDark)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9.5)
                            .background(isSelected ? Color.shopDark : Color.white)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isSelected ? Color.clear : Color.shopBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sizeSection: some View {
        let sizes = sizeTab == .shoes ? UserPreferencesManager.shoeSizes : UserPreferencesManager.apparelSizes
        let userPref = (sizeTab == .shoes ? preferredShoeSize : preferredApparelSize).trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Taglia disponibile", icon: "ruler")
                Spacer()
                HStack(spacing: 2) {
                    ForEach(SizeGroupTab.allCases, id: \.self) { tab in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            sizeTab = tab
                        }) {
                            Text(tab.rawValue)
                                .font(.system(size: 11.5, weight: sizeTab == tab ? .bold : .medium, design: .rounded))
                                .foregroundColor(sizeTab == tab ? .white : .shopTextMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(sizeTab == tab ? Color.shopDark : Color.clear)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2.5)
                .background(Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.shopBorder, lineWidth: 1))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    // "Tutte" pill
                    let isAll = draftFilters.size == nil
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        draftFilters.size = nil
                    }) {
                        Text("Tutte")
                            .font(.system(size: 12.5, weight: isAll ? .bold : .semibold, design: .rounded))
                            .foregroundColor(isAll ? .white : .shopDark)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8.5)
                            .background(isAll ? Color.shopDark : Color.white)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isAll ? Color.clear : Color.shopBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    // User's preferred size pinned first if configured
                    if !userPref.isEmpty {
                        let isPrefSelected = draftFilters.size?.caseInsensitiveCompare(userPref) == .orderedSame
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            draftFilters.size = isPrefSelected ? nil : userPref
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9.5))
                                Text("Mia: \(userPref)")
                                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(isPrefSelected ? .white : .shopPurple)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8.5)
                            .background(isPrefSelected ? Color.shopPurple : Color.shopPurpleLight)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.shopPurple.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(sizes, id: \.self) { sz in
                        let isSelected = draftFilters.size?.caseInsensitiveCompare(sz) == .orderedSame
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            draftFilters.size = isSelected ? nil : sz
                        }) {
                            Text(sz)
                                .font(.system(size: 13, weight: isSelected ? .bold : .semibold, design: .rounded))
                                .foregroundColor(isSelected ? .white : .shopDark)
                                .frame(minWidth: 42)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8.5)
                                .background(isSelected ? Color.shopPurple : Color.white)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(isSelected ? Color.clear : Color.shopBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Budget massimo", icon: "eurosign.circle.fill")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(maxPriceChoices, id: \.label) { item in
                        let isSelected = draftFilters.maxPrice == item.value
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            draftFilters.maxPrice = item.value
                        }) {
                            Text(item.label)
                                .font(.system(size: 13, weight: isSelected ? .bold : .semibold, design: .rounded))
                                .foregroundColor(isSelected ? .white : .shopDark)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(isSelected ? Color.shopDark : Color.white)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(isSelected ? Color.clear : Color.shopBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var discountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Sconto minimo", icon: "percent")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(minDiscountChoices, id: \.label) { item in
                        let isSelected = draftFilters.minDiscount == item.value
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            draftFilters.minDiscount = item.value
                        }) {
                            Text(item.label)
                                .font(.system(size: 13, weight: isSelected ? .bold : .semibold, design: .rounded))
                                .foregroundColor(isSelected ? .white : .shopDark)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(isSelected ? Color.shopRed : Color.white)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(isSelected ? Color.clear : Color.shopBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var brandSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Brand", icon: "tag.fill")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let isAll = draftFilters.brand == nil
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        draftFilters.brand = nil
                    }) {
                        Text("Tutti")
                            .font(.system(size: 13, weight: isAll ? .bold : .semibold, design: .rounded))
                            .foregroundColor(isAll ? .white : .shopDark)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(isAll ? Color.shopDark : Color.white)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isAll ? Color.clear : Color.shopBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    ForEach(availableBrands, id: \.self) { brandName in
                        let isSelected = draftFilters.brand?.caseInsensitiveCompare(brandName) == .orderedSame
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            draftFilters.brand = isSelected ? nil : brandName
                        }) {
                            Text(brandName)
                                .font(.system(size: 13, weight: isSelected ? .bold : .semibold, design: .rounded))
                                .foregroundColor(isSelected ? .white : .shopDark)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(isSelected ? Color.shopPurple : Color.white)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(isSelected ? Color.clear : Color.shopBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var optionsSection: some View {
        VStack(spacing: 10) {
            Toggle(isOn: $draftFilters.freeShippingOnly) {
                HStack(spacing: 10) {
                    Image(systemName: "box.truck.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.shopGreen)
                        .frame(width: 28, height: 28)
                        .background(Color.shopGreenLight)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Solo spedizione gratuita")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.shopDark)
                        Text("Mostra solo articoli con consegna a 0 €")
                            .font(.system(size: 11.5))
                            .foregroundColor(.shopTextMuted)
                    }
                }
            }
            .tint(.shopGreen)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.shopBorder, lineWidth: 1))

            Toggle(isOn: $draftFilters.includeKids) {
                HStack(spacing: 10) {
                    Image(systemName: "figure.2.and.child.holdinghands")
                        .font(.system(size: 14))
                        .foregroundColor(.shopPurple)
                        .frame(width: 28, height: 28)
                        .background(Color.shopPurpleLight)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Includi articoli Bambino / Junior")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.shopDark)
                        Text("Di default mostriamo solo taglie adulto")
                            .font(.system(size: 11.5))
                            .foregroundColor(.shopTextMuted)
                    }
                }
            }
            .tint(.shopPurple)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.shopBorder, lineWidth: 1))
        }
    }

    private var stickyFooter: some View {
        HStack(spacing: 12) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                draftCategory = "tutti"
                draftFilters = DealsFilterOptions()
            }) {
                Text("Ripristina")
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundColor(hasAnyResettableState ? .shopDark : .shopTextMuted)
                    .frame(height: 50)
                    .padding(.horizontal, 20)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.shopBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!hasAnyResettableState)

            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onApply(draftCategory, draftFilters)
                dismiss()
            }) {
                let count = draftFilters.activeFilterCount
                Text(count > 0 ? "Applica filtri (\(count))" : "Applica")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.shopDark)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color.white)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.shopPurple)
            Text(title)
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
        }
    }
}
