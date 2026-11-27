import SwiftUI

struct FollowingView: View {
    var onGoShopping: (() -> Void)? = nil

    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var prefsManager = UserPreferencesManager.shared
    @StateObject private var api = APIService.shared

    @State private var feedBundle: FollowingFeedBundle
    @State private var fallbackShowcases: [StoreShowcase]
    @State private var selectedStoreId: String? = nil
    @State private var selectedMode: FollowingFeedMode = .all
    @State private var onlyMySize: Bool = false

    @State private var isLoading: Bool
    @State private var isSwitchingFilter: Bool = false
    @State private var loadError: String? = nil
    @State private var activeFeedTask: Task<Void, Never>? = nil

    // Sheets, navigation & feedback
    @State private var showingManageStoresSheet: Bool = false
    @State private var navigatingStore: StoreNavTarget? = nil
    @State private var toastMessage: String? = nil
    @State private var undoUnfollowedStore: FollowedStoreItem? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil

    struct StoreNavTarget: Identifiable, Hashable {
        let id: String
        let name: String
    }

    struct PartnerStoreItem: Identifiable, Hashable {
        let id: String
        let name: String
        let subtitle: String
        let logoURL: String?
        let totalOffers: Int
    }

    private let twoColumnGrid = [
        GridItem(.flexible(), spacing: ShopLayout.gridColumnSpacing),
        GridItem(.flexible(), spacing: ShopLayout.gridColumnSpacing)
    ]

    private static let italianCountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "it_IT")
        f.usesGroupingSeparator = true
        f.groupingSeparator = "."
        return f
    }()

    init(onGoShopping: (() -> Void)? = nil) {
        self.onGoShopping = onGoShopping

        let followed = FollowedStoresManager.shared.followedStores
        let prefs = UserPreferencesManager.shared.preferences
        let storeIds = followed.map { $0.store_id.lowercased() }
        let cachedHome = APIService.shared.cachedHomeShowcases() ?? []
        self._fallbackShowcases = State(initialValue: cachedHome)

        let cacheKey = APIService.shared.followingFeedCacheKey(
            storeIds: storeIds,
            mode: .all,
            onlyMySize: false,
            shoeSize: prefs.preferredShoeSize,
            apparelSize: prefs.preferredApparelSize,
            sports: prefs.selectedSports,
            brands: prefs.favoriteBrands
        )

        if let cachedFeed = APIService.shared.cachedFollowingFeed(for: cacheKey), !cachedFeed.isEmpty {
            self._feedBundle = State(initialValue: cachedFeed)
            self._isLoading = State(initialValue: false)
        } else if !followed.isEmpty && !cachedHome.isEmpty {
            let instant = Self.buildOptimisticBundle(
                from: cachedHome,
                followedStores: followed,
                prefsManager: UserPreferencesManager.shared
            )
            self._feedBundle = State(initialValue: instant)
            self._isLoading = State(initialValue: instant.isEmpty)
        } else {
            self._feedBundle = State(initialValue: .empty)
            self._isLoading = State(initialValue: !followed.isEmpty)
        }
    }

    // MARK: - Computed Helpers

    private var followedStoreIds: [String] {
        followedManager.followedStores.map { $0.store_id.lowercased() }
    }

    private var feedSignature: String {
        let p = prefsManager.preferences
        let ids = followedStoreIds.joined(separator: ",")
        let sports = p.selectedSports.sorted().joined(separator: ",")
        let brands = p.favoriteBrands.sorted().joined(separator: ",")
        return "\(ids)|\(selectedMode.rawValue)|\(onlyMySize ? 1 : 0)|\(p.preferredShoeSize)|\(p.preferredApparelSize)|\(sports)|\(brands)"
    }

    private var hasPreferredSize: Bool {
        prefsManager.preferences.hasAnySize
    }

    private var preferredSizeChipLabel: String {
        let shoe = prefsManager.preferences.preferredShoeSize.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = prefsManager.preferences.preferredApparelSize.trimmingCharacters(in: .whitespacesAndNewlines)
        if !shoe.isEmpty && !app.isEmpty {
            return "Taglia \(shoe) · \(app)"
        } else if !shoe.isEmpty {
            return "Taglia \(shoe)"
        } else if !app.isEmpty {
            return "Taglia \(app)"
        }
        return "La mia taglia"
    }

    private var hasActiveFilters: Bool {
        selectedMode != .all || onlyMySize || selectedStoreId != nil
    }

    private func formattedCount(_ value: Int) -> String {
        Self.italianCountFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func compactPartnerSubtitle(for sc: StoreShowcase, freeThreshold: Double? = nil) -> String {
        let countStr = "\(formattedCount(sc.total_offers)) articoli"
        let maxDisc = Int((sc.products.compactMap(\.discount_pct).max() ?? sc.avg_discount).rounded())
        let sid = sc.store_id.lowercased()
        let isOfficial = (sid == "nike" || sid == "adidas" || sid == "decathlon")

        if maxDisc >= 10 {
            return "\(countStr) · Fino \(IntelligentPromoGenerator.upToPercent(maxDisc))"
        }
        if isOfficial {
            return "\(countStr) · Store ufficiale"
        }
        if let thresh = freeThreshold ?? DynamicCatalogRegistry.shared.shippingRule(for: sid)?.threshold, thresh > 0 {
            return "\(countStr) · Sped. gratis da \(Int(thresh.rounded())) €"
        }
        return "\(countStr) · Partner verificato"
    }

    private var partnerStores: [PartnerStoreItem] {
        var showcaseById: [String: StoreShowcase] = [:]
        for sc in fallbackShowcases {
            showcaseById[sc.store_id.lowercased()] = sc
        }

        if !prefsManager.activeStores.isEmpty {
            let mapped: [(item: PartnerStoreItem, score: Double)] = prefsManager.activeStores.map { store in
                let sid = store.id.lowercased()
                let sc = showcaseById[sid]
                let count = sc?.total_offers ?? 0
                let subtitle: String
                let relevance: Double
                if let sc {
                    subtitle = compactPartnerSubtitle(for: sc, freeThreshold: store.free_shipping_threshold)
                    relevance = prefsManager.storeRelevanceScore(
                        showcase: sc,
                        isFollowed: false,
                        recentStoreIds: [],
                        wishlistStoreNames: []
                    )
                } else if let info = store.subtitle, !info.isEmpty {
                    subtitle = info
                    relevance = Double(count) * 0.001
                } else if let thresh = store.free_shipping_threshold, thresh > 0 {
                    subtitle = "Spedizione gratis da \(Int(thresh.rounded())) €"
                    relevance = Double(count) * 0.001
                } else {
                    subtitle = "Rivenditore partner verificato"
                    relevance = Double(count) * 0.001
                }
                let item = PartnerStoreItem(
                    id: sid,
                    name: store.name,
                    subtitle: subtitle,
                    logoURL: store.logo_url ?? sc?.logo_url,
                    totalOffers: count
                )
                return (item: item, score: relevance)
            }
            return mapped.sorted { a, b in
                if abs(a.score - b.score) > 0.1 { return a.score > b.score }
                if a.item.totalOffers != b.item.totalOffers { return a.item.totalOffers > b.item.totalOffers }
                return a.item.name.localizedCaseInsensitiveCompare(b.item.name) == .orderedAscending
            }.map(\.item)
        }

        if !fallbackShowcases.isEmpty {
            return fallbackShowcases.map { sc in
                PartnerStoreItem(
                    id: sc.store_id.lowercased(),
                    name: sc.store_name,
                    subtitle: compactPartnerSubtitle(for: sc),
                    logoURL: sc.logo_url,
                    totalOffers: sc.total_offers
                )
            }
        }

        // Fallback before initial catalog registry hydration
        let defaults: [(id: String, name: String, highlight: String)] = [
            ("misterrunning", "Mister Running", "Specialista scarpe da corsa e trail"),
            ("nike", "Nike", "Store ufficiale Nike"),
            ("cisalfa", "Cisalfa Sport", "Multisport, sneaker e abbigliamento"),
            ("maxisport", "Maxi Sport", "Running, outdoor e sportswear"),
            ("alltricks", "Alltricks", "Running, trail, ciclismo e GPS"),
            ("top4running", "Top4Running", "Scarpe racing e pista"),
            ("decathlon", "Decathlon", "Corsa, trail, fitness e outdoor"),
            ("deporvillage", "Deporvillage", "Ciclismo, outdoor e smartwatch GPS"),
            ("df_sportspecialist", "DF Sport Specialist", "Outdoor, montagna e running"),
            ("nencini", "Nencini Sport", "Articoli sportivi multimarca"),
            ("tradeinn", "Tradeinn", "Catalogo multisport internazionale"),
            ("adidas", "Adidas", "Store ufficiale Adidas"),
            ("runningwarehouse", "Running Warehouse Europe", "Scarpe da gara e allenamento")
        ]
        return defaults.map {
            PartnerStoreItem(
                id: $0.id,
                name: $0.name,
                subtitle: $0.highlight,
                logoURL: DynamicCatalogRegistry.shared.storeItem(for: $0.id)?.logo_url,
                totalOffers: 0
            )
        }
    }

    private var unfollowedPartnerStores: [PartnerStoreItem] {
        partnerStores.filter { !followedManager.isFollowing(storeId: $0.id) }
    }

    private var orderedStoreSections: [FollowingStoreSection] {
        var byId: [String: FollowingStoreSection] = [:]
        for sec in feedBundle.stores {
            byId[sec.store_id.lowercased()] = sec
        }

        return followedManager.followedStores.map { followed in
            let sid = followed.store_id.lowercased()
            if let existing = byId[sid] {
                return existing
            }
            let sc = fallbackShowcases.first { $0.store_id.lowercased() == sid }
            let reg = DynamicCatalogRegistry.shared.storeItem(for: sid)
            return FollowingStoreSection(
                store_id: sid,
                store_name: followed.store_name,
                total_offers: sc?.total_offers ?? 0,
                avg_discount: sc?.avg_discount ?? 0,
                max_discount: sc?.products.compactMap(\.discount_pct).max() ?? 0,
                discounted_count: sc?.products.filter { ($0.discount_pct ?? 0) >= 10 }.count ?? 0,
                atl_count: sc?.products.filter(\.isVerifiedAllTimeLow).count ?? 0,
                new_7d_count: 0,
                matching_count: sc?.products.count ?? 0,
                rating: sc?.rating,
                review_count: sc?.review_count,
                logo_url: followed.store_logo ?? sc?.logo_url ?? reg?.logo_url,
                accent_color: sc?.accent_color ?? reg?.accent_color,
                free_shipping_threshold: reg?.free_shipping_threshold,
                products: sc?.products ?? []
            )
        }
    }

    private var selectedStoreSection: FollowingStoreSection? {
        guard let sid = selectedStoreId?.lowercased() else { return nil }
        return orderedStoreSections.first { $0.store_id.lowercased() == sid }
    }

    private var highlightsHeaderTitle: String {
        if onlyMySize {
            switch selectedMode {
            case .drops: return "Ribassi nella tua taglia"
            case .newArrivals: return "Nuovi arrivi nella tua taglia"
            case .deals: return "Sconti nella tua taglia"
            case .all: return "Nella tua taglia dai tuoi negozi"
            }
        }
        switch selectedMode {
        case .all: return "Ribassi e novità dai tuoi negozi"
        case .drops: return "Migliori ribassi dai tuoi negozi"
        case .newArrivals: return "Ultimi arrivi dai tuoi negozi"
        case .deals: return "Migliori sconti dai tuoi negozi"
        }
    }

    private func resolvedLogoURL(for storeId: String, storedLogo: String? = nil) -> String? {
        let sid = storeId.lowercased()
        if let secLogo = feedBundle.section(for: sid)?.logo_url, !secLogo.isEmpty {
            return secLogo
        }
        if let stored = storedLogo, !stored.isEmpty {
            return stored
        }
        if let regLogo = DynamicCatalogRegistry.shared.storeItem(for: sid)?.logo_url, !regLogo.isEmpty {
            return regLogo
        }
        return fallbackShowcases.first(where: { $0.store_id.lowercased() == sid })?.logo_url
    }

    private func shortAvatarLabel(for storeName: String) -> String {
        let trimmed = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let mappings: [(String, String)] = [
            ("Running Warehouse", "Run. Wareh."),
            ("DF Sport Specialist", "DF Sport"),
            ("Intersport Italia", "Intersport"),
            ("Cisalfa Sport", "Cisalfa"),
            ("Mister Running", "Mister Run"),
            ("Nencini Sport", "Nencini"),
            ("Basketball Store", "Basketball")
        ]
        for (match, short) in mappings {
            if trimmed.localizedCaseInsensitiveContains(match) {
                return short
            }
        }
        return trimmed
    }

    private func truthfulSubtitle(for section: FollowingStoreSection) -> String {
        let totalStr = section.total_offers > 0 ? "\(formattedCount(section.total_offers)) articoli" : nil
        let maxDiscInt = Int(section.max_discount.rounded())
        let discPhrase = maxDiscInt >= 10 ? "Fino \(IntelligentPromoGenerator.upToPercent(maxDiscInt))" : nil

        switch selectedMode {
        case .drops:
            if section.atl_count > 0 {
                let minLabel = section.atl_count == 1 ? "1 minimo storico" : "\(formattedCount(section.atl_count)) minimi storici"
                if let discPhrase { return "\(minLabel) · \(discPhrase)" }
                return minLabel
            }
            if let totalStr, let discPhrase { return "\(totalStr) · \(discPhrase)" }
            return totalStr ?? "Offerte monitorate"

        case .newArrivals:
            if section.new_7d_count > 0 {
                if let totalStr {
                    return "Aggiornato di recente · \(totalStr)"
                }
                return "Nuovi arrivi questa settimana"
            }
            return totalStr ?? "Catalogo aggiornato"

        case .deals:
            if section.discounted_count > 0 {
                let dStr = "\(formattedCount(section.discounted_count)) in sconto"
                if let discPhrase { return "\(dStr) · \(discPhrase)" }
                return dStr
            }
            return totalStr ?? "Catalogo verificato"

        case .all:
            if onlyMySize && section.matching_count > 0 {
                let matchLabel = section.matching_count == 1 ? "1 nella tua taglia" : "\(formattedCount(section.matching_count)) nella tua taglia"
                if let discPhrase { return "\(matchLabel) · \(discPhrase)" }
                return matchLabel
            }
            if let totalStr {
                if section.atl_count >= 3, let discPhrase {
                    return "\(totalStr) · \(discPhrase) · \(formattedCount(section.atl_count)) minimi"
                }
                if let discPhrase {
                    return "\(totalStr) · \(discPhrase)"
                }
                if let thresh = section.free_shipping_threshold, thresh > 0 {
                    return "\(totalStr) · Sped. gratis da \(Int(thresh.rounded())) €"
                }
                return totalStr
            }
            if let discPhrase { return discPhrase }
            return "Rivenditore partner verificato"
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: ShopLayout.sectionSpacing) {
                        if isLoading && feedBundle.isEmpty && !followedManager.followedStores.isEmpty {
                            ShopFollowingSkeletonView()
                                .transition(.opacity)
                        } else if followedManager.followedStores.isEmpty {
                            // MARK: - Empty State + Recommended Stores
                            emptyFollowedBanner
                                .padding(.horizontal, ShopLayout.screenPadding)
                                .padding(.top, 2)

                            suggestedStoresSection(
                                title: "Negozi consigliati",
                                items: partnerStores,
                                showsViewAll: false
                            )
                        } else {
                            // MARK: - 1. Followed Stores Interactive Avatars Strip
                            followedStoresStrip
                                .padding(.top, 2)

                            // MARK: - 2. Mode & Preferred Size Filter Chips
                            filterChipsBar

                            // MARK: - 3. Error / Content
                            if let err = loadError, feedBundle.isEmpty {
                                errorStateView(message: err)
                                    .padding(.horizontal, ShopLayout.screenPadding)
                            } else if let focusedStore = selectedStoreSection {
                                // Focused single-store 2-column grid
                                focusedStoreContent(section: focusedStore)
                                    .opacity(isSwitchingFilter ? 0.55 : 1.0)
                                    .animation(.easeOut(duration: 0.18), value: isSwitchingFilter)
                            } else {
                                // Cross-store highlights + per-store carousels
                                VStack(alignment: .leading, spacing: 24) {
                                    if !feedBundle.highlights.isEmpty {
                                        followingHighlightsSection
                                    }

                                    followedStoresCarousels

                                    if !unfollowedPartnerStores.isEmpty && followedManager.followedStores.count <= 6 {
                                        suggestedStoresSection(
                                            title: "Scopri altri negozi",
                                            items: Array(unfollowedPartnerStores.prefix(4)),
                                            showsViewAll: unfollowedPartnerStores.count > 4
                                        )
                                        .padding(.top, 4)
                                    }
                                }
                                .opacity(isSwitchingFilter ? 0.55 : 1.0)
                                .animation(.easeOut(duration: 0.18), value: isSwitchingFilter)
                            }
                        }

                        Spacer(minLength: ShopLayout.bottomDockClearance)
                    }
                    .id("following_top")
                }
                .refreshable {
                    await refreshAll(forceRefresh: true)
                }
                .onReceive(TabCoordinator.shared.$scrollToTopEvent) { event in
                    guard let event, event.tab == 0 else { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        scrollProxy.scrollTo("following_top", anchor: .top)
                    }
                }
            }

            // MARK: - Floating Undo Toast
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

                    if let storeToRestore = undoUnfollowedStore {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            followedManager.followStore(
                                storeId: storeToRestore.store_id,
                                storeName: storeToRestore.store_name,
                                storeLogo: storeToRestore.store_logo
                            )
                            dismissToast()
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
        .navigationDestination(item: $navigatingStore) { target in
            StoreDetailView(storeId: target.id, initialStoreName: target.name)
        }
        .sheet(isPresented: $showingManageStoresSheet) {
            ManageFollowedStoresSheet(
                partnerStores: partnerStores,
                onOpenStore: { target in
                    showingManageStoresSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        navigatingStore = target
                    }
                }
            )
        }
        .task {
            if fallbackShowcases.isEmpty {
                if let cached = api.cachedHomeShowcases() {
                    fallbackShowcases = cached
                } else if let fetched = try? await api.getStoreShowcases() {
                    fallbackShowcases = fetched
                }
            }
            if prefsManager.activeStores.isEmpty {
                await prefsManager.fetchActiveStores(apiService: api)
            }
            await refreshAll(forceRefresh: false)
        }
        .onChange(of: feedSignature) { _ in
            if let selected = selectedStoreId, !followedManager.isFollowing(storeId: selected) {
                selectedStoreId = nil
            }
            scheduleFeedReload(forceRefresh: false, showSwitchingOpacity: !feedBundle.isEmpty)
        }
        .onDisappear {
            activeFeedTask?.cancel()
            toastDismissTask?.cancel()
        }
    }

    // MARK: - 1. Followed Stores Interactive Avatars Strip

    private var followedStoresStrip: some View {
        let canFilterSingleStore = followedManager.followedStores.count >= 2

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                // "Tutti" pill when following 2+ stores
                if canFilterSingleStore {
                    let isAllSelected = selectedStoreId == nil
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(ShopMotion.pillSlide) {
                            selectedStoreId = nil
                        }
                    }) {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(isAllSelected ? Color.shopDark : Color.white)
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        Circle()
                                            .stroke(isAllSelected ? Color.shopDark : Color.shopBorder, lineWidth: isAllSelected ? 2 : 1)
                                    )
                                    .shadow(color: Color.black.opacity(isAllSelected ? 0.10 : 0.03), radius: 5, x: 0, y: 2)

                                Image(systemName: "square.grid.2x2.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(isAllSelected ? .white : .shopDark)
                            }

                            Text("Tutti")
                                .font(.system(size: 11, weight: isAllSelected ? .bold : .medium, design: .rounded))
                                .foregroundColor(isAllSelected ? .shopDark : .shopTextMuted)
                                .lineLimit(1)
                                .frame(width: 60)
                        }
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.94, pressedOpacity: 0.9))
                }

                // Followed stores avatars with subtle drop indicator & short label
                ForEach(followedManager.followedStores) { store in
                    let sid = store.store_id.lowercased()
                    let isSelected = selectedStoreId?.lowercased() == sid
                    let section = feedBundle.section(for: sid)
                    let hasPriceDrops = (section?.atl_count ?? 0) > 0
                    let logoUrl = resolvedLogoURL(for: sid, storedLogo: store.store_logo)

                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if canFilterSingleStore {
                            withAnimation(ShopMotion.pillSlide) {
                                selectedStoreId = isSelected ? nil : sid
                            }
                        } else {
                            navigatingStore = StoreNavTarget(id: sid, name: store.store_name)
                        }
                    }) {
                        VStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                ShopStoreLogo(
                                    storeName: store.store_name,
                                    showVerified: false,
                                    showLabel: false,
                                    size: 54,
                                    logoURL: logoUrl
                                )
                                .padding(2)
                                .background(
                                    Circle()
                                        .stroke(
                                            isSelected ? Color.shopDark : Color.clear,
                                            lineWidth: 2
                                        )
                                )

                                if hasPriceDrops {
                                    Circle()
                                        .fill(Color.shopGreen)
                                        .frame(width: 11, height: 11)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.shopSurface, lineWidth: 2)
                                        )
                                        .offset(x: -1, y: 1)
                                }
                            }

                            Text(shortAvatarLabel(for: store.store_name))
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundColor(isSelected ? .shopDark : .shopTextMuted)
                                .lineLimit(1)
                                .frame(width: 64)
                        }
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.94, pressedOpacity: 0.9))
                }

                // Add / Manage Stores Button -> opens dedicated searchable sheet
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingManageStoresSheet = true
                }) {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.75))
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Circle()
                                        .stroke(Color(red: 205/255, green: 207/255, blue: 214/255), style: StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
                                )

                            Image(systemName: unfollowedPartnerStores.isEmpty ? "slider.horizontal.3" : "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.shopDark)
                        }

                        Text(unfollowedPartnerStores.isEmpty ? "Gestisci" : "Aggiungi")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.shopTextMuted)
                            .lineLimit(1)
                            .frame(width: 60)
                    }
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.94, pressedOpacity: 0.9))
            }
            .padding(.horizontal, ShopLayout.screenPadding)
        }
    }

    // MARK: - 2. Mode & Preferred Size Filter Chips

    private var filterChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FollowingFeedMode.allCases) { mode in
                    let active = selectedMode == mode
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(ShopMotion.pillSlide) {
                            selectedMode = mode
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(mode.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(active ? .white : .shopDark)
                        .padding(.horizontal, 12.5)
                        .frame(height: 33)
                        .background(active ? Color.shopDark : Color.white)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(active ? Color.clear : Color.shopBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.96, pressedOpacity: 0.92))
                }

                if hasPreferredSize {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(ShopMotion.pillSlide) {
                            onlyMySize.toggle()
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "ruler")
                                .font(.system(size: 11, weight: .semibold))
                            Text(preferredSizeChipLabel)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(onlyMySize ? .white : .shopDark)
                        .padding(.horizontal, 12.5)
                        .frame(height: 33)
                        .background(onlyMySize ? Color.shopPurple : Color.white)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(onlyMySize ? Color.clear : Color.shopBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.96, pressedOpacity: 0.92))
                }

                if hasActiveFilters {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(ShopMotion.pillSlide) {
                            selectedMode = .all
                            onlyMySize = false
                            selectedStoreId = nil
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Azzera")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.shopTextMuted)
                        .padding(.horizontal, 10)
                        .frame(height: 33)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ShopLayout.screenPadding)
        }
    }

    // MARK: - 3. Cross-Followed-Stores Highlights Section

    private var followingHighlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(highlightsHeaderTitle)
                    .font(.system(size: 17.5, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, ShopLayout.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(feedBundle.highlights) { prod in
                        let sId = prod.store_id ?? ""
                        let sName = prod.store_name ?? "Partner Store"
                        let matched = prod.toMatchedProduct(storeId: sId, storeName: sName)
                        FollowingProductCard(
                            product: prod,
                            matchedProduct: matched,
                            mode: selectedMode,
                            showStoreEyebrow: true,
                            cardWidth: 160
                        )
                        .shopCarouselTransition()
                    }
                }
                .padding(.horizontal, ShopLayout.screenPadding)
            }
        }
    }

    // MARK: - 4. Single-Store Focused View (When an Avatar is Selected)

    private func focusedStoreContent(section: FollowingStoreSection) -> some View {
        let sid = section.store_id.lowercased()
        let logoUrl = resolvedLogoURL(for: sid, storedLogo: section.logo_url)

        return VStack(alignment: .leading, spacing: 16) {
            // Compact store hero card with quick CTA to full catalog
            HStack(spacing: 12) {
                ShopStoreLogo(
                    storeName: section.store_name,
                    showVerified: false,
                    showLabel: false,
                    size: 46,
                    logoURL: logoUrl
                )

                VStack(alignment: .leading, spacing: 2.5) {
                    Text(section.store_name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)
                        .lineLimit(1)

                    Text(truthfulSubtitle(for: section))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.shopTextMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    navigatingStore = StoreNavTarget(id: sid, name: section.store_name)
                }) {
                    HStack(spacing: 4) {
                        Text("Negozio")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7.5)
                    .background(Color.shopDark)
                    .clipShape(Capsule())
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.96, pressedOpacity: 0.9))

                storeActionsMenu(section: section)
            }
            .shopCard(padding: 14, cornerRadius: ShopLayout.cardRadius, shadowOpacity: 0.025, shadowRadius: 8, shadowY: 2)
            .padding(.horizontal, ShopLayout.screenPadding)

            if section.products.isEmpty {
                FitMatchEmptyStateView(
                    icon: onlyMySize ? "ruler" : "line.3.horizontal.decrease.circle",
                    title: "Nessun articolo con questi filtri",
                    subtitle: "Non ci sono articoli in \(section.store_name) per «\(selectedMode.title)\(onlyMySize ? " · \(preferredSizeChipLabel)" : "")».",
                    primaryTitle: "Rimuovi filtri",
                    primaryIcon: "arrow.counterclockwise",
                    onPrimaryTap: {
                        withAnimation(ShopMotion.pillSlide) {
                            selectedMode = .all
                            onlyMySize = false
                        }
                    },
                    secondaryTitle: "Apri catalogo completo di \(section.store_name)",
                    secondaryIcon: "arrow.right",
                    onSecondaryTap: {
                        navigatingStore = StoreNavTarget(id: sid, name: section.store_name)
                    }
                )
                .padding(.horizontal, ShopLayout.screenPadding)
            } else {
                LazyVGrid(columns: twoColumnGrid, spacing: ShopLayout.gridRowSpacing) {
                    ForEach(section.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: sid, storeName: section.store_name)
                        FollowingProductCard(
                            product: prod,
                            matchedProduct: matched,
                            mode: selectedMode,
                            showStoreEyebrow: false,
                            cardWidth: nil
                        )
                    }
                }
                .padding(.horizontal, ShopLayout.screenPadding)

                // Footer button to explore full store catalog
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    navigatingStore = StoreNavTarget(id: sid, name: section.store_name)
                }) {
                    HStack(spacing: 6) {
                        Text("Esplora tutti i \(formattedCount(section.total_offers)) articoli di \(section.store_name)")
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .foregroundColor(.shopDark)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.shopBorder, lineWidth: 1))
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.98, pressedOpacity: 0.92))
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - 5. Per-Store Products Carousels Feed

    private var followedStoresCarousels: some View {
        VStack(spacing: 26) {
            ForEach(orderedStoreSections) { section in
                let sid = section.store_id.lowercased()
                let logoUrl = resolvedLogoURL(for: sid, storedLogo: section.logo_url)

                VStack(alignment: .leading, spacing: 12) {
                    // Store Section Header
                    HStack(spacing: 11) {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            navigatingStore = StoreNavTarget(id: sid, name: section.store_name)
                        }) {
                            HStack(spacing: 11) {
                                ShopStoreLogo(
                                    storeName: section.store_name,
                                    showVerified: false,
                                    showLabel: false,
                                    size: 42,
                                    logoURL: logoUrl
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(section.store_name)
                                        .font(.system(size: 16.5, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopDark)
                                        .lineLimit(1)

                                    Text(truthfulSubtitle(for: section))
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.shopTextMuted)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 4)

                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            navigatingStore = StoreNavTarget(id: sid, name: section.store_name)
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.shopTextMuted)
                                .frame(width: 30, height: 30)
                                .background(Color.white)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.shopBorder, lineWidth: 1))
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.94, pressedOpacity: 0.9))

                        storeActionsMenu(section: section)
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)

                    // Products Carousel or Clickable Inline Empty Row
                    if section.products.isEmpty && isLoading {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(0..<3, id: \.self) { _ in
                                    ShopSkeletonBlock(cornerRadius: ShopLayout.mediumRadius, width: 160, height: 156)
                                }
                            }
                            .padding(.horizontal, ShopLayout.screenPadding)
                        }
                    } else if section.products.isEmpty {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            navigatingStore = StoreNavTarget(id: sid, name: section.store_name)
                        }) {
                            FitMatchInlineEmptyRow(
                                icon: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "bag",
                                title: hasActiveFilters ? "Nessun articolo con questi filtri" : "Apri la vetrina completa",
                                subtitle: hasActiveFilters
                                    ? "Esplora tutto il catalogo di \(section.store_name)"
                                    : "Visualizza tutte le offerte di \(section.store_name)",
                                showsChevron: true,
                                isOnSurfaceCanvas: true
                            )
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.985, pressedOpacity: 0.94))
                        .padding(.horizontal, ShopLayout.screenPadding)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(section.products) { prod in
                                    let matched = prod.toMatchedProduct(storeId: sid, storeName: section.store_name)
                                    FollowingProductCard(
                                        product: prod,
                                        matchedProduct: matched,
                                        mode: selectedMode,
                                        showStoreEyebrow: false,
                                        cardWidth: 160
                                    )
                                    .shopCarouselTransition()
                                }
                            }
                            .padding(.horizontal, ShopLayout.screenPadding)
                        }
                    }
                }
            }
        }
    }

    private func storeActionsMenu(section: FollowingStoreSection) -> some View {
        let sid = section.store_id.lowercased()
        return Menu {
            Button(action: {
                navigatingStore = StoreNavTarget(id: sid, name: section.store_name)
            }) {
                Label("Visualizza negozio", systemImage: "storefront")
            }

            if followedManager.followedStores.count >= 2 {
                Button(action: {
                    withAnimation(ShopMotion.pillSlide) {
                        selectedStoreId = (selectedStoreId?.lowercased() == sid) ? nil : sid
                    }
                }) {
                    Label(
                        selectedStoreId?.lowercased() == sid ? "Mostra tutti i negozi" : "Filtra solo \(section.store_name)",
                        systemImage: selectedStoreId?.lowercased() == sid ? "square.grid.2x2" : "line.3.horizontal.decrease"
                    )
                }
            }

            Divider()

            Button(role: .destructive, action: {
                handleUnfollowWithUndo(storeId: sid, fallbackName: section.store_name, fallbackLogo: section.logo_url)
            }) {
                Label("Non seguire più", systemImage: "person.badge.minus")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.shopTextMuted)
                .frame(width: 30, height: 30)
                .background(Color.white)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.shopBorder, lineWidth: 1))
        }
    }

    // MARK: - 6. Empty State, Error State & Recommended Stores

    private var emptyFollowedBanner: some View {
        FitMatchEmptyStateView(
            icon: "storefront",
            title: "Nessun negozio seguito",
            subtitle: "Segui i tuoi store sportivi preferiti per monitorare qui ribassi, minimi storici e nuovi arrivi.",
            primaryTitle: "Esplora negozi",
            onPrimaryTap: {
                onGoShopping?()
            }
        )
    }

    private func errorStateView(message: String) -> some View {
        FitMatchEmptyStateView(
            icon: "wifi.exclamationmark",
            accentColor: .shopRed,
            title: "Impossibile aggiornare i negozi",
            subtitle: message,
            primaryTitle: "Riprova",
            primaryIcon: "arrow.clockwise",
            onPrimaryTap: {
                Task {
                    await refreshAll(forceRefresh: true)
                }
            }
        )
    }

    private func suggestedStoresSection(title: String, items: [PartnerStoreItem], showsViewAll: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 17.5, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)

                Spacer()

                if showsViewAll {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingManageStoresSheet = true
                    }) {
                        Text("Vedi tutti (\(partnerStores.count))")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.shopPurple)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ShopLayout.screenPadding)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, partner in
                    let isFollowed = followedManager.isFollowing(storeId: partner.id)

                    HStack(spacing: 12) {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            navigatingStore = StoreNavTarget(id: partner.id, name: partner.name)
                        }) {
                            HStack(spacing: 12) {
                                ShopStoreLogo(
                                    storeName: partner.name,
                                    showVerified: false,
                                    showLabel: false,
                                    size: 42,
                                    logoURL: partner.logoURL
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(partner.name)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopDark)
                                        .lineLimit(1)

                                    Text(partner.subtitle)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(.shopTextMuted)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            if isFollowed {
                                handleUnfollowWithUndo(storeId: partner.id, fallbackName: partner.name, fallbackLogo: partner.logoURL)
                            } else {
                                followedManager.followStore(
                                    storeId: partner.id,
                                    storeName: partner.name,
                                    storeLogo: partner.logoURL
                                )
                            }
                        }) {
                            Text(isFollowed ? "Segui già" : "Segui")
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundColor(isFollowed ? .shopDark : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(isFollowed ? Color.shopSurfaceElevated : Color.shopDark)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.95, pressedOpacity: 0.9))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    if idx < items.count - 1 {
                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: ShopLayout.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ShopLayout.cardRadius, style: .continuous)
                    .stroke(Color.shopBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.025), radius: 8, x: 0, y: 2)
            .padding(.horizontal, ShopLayout.screenPadding)
        }
    }

    // MARK: - Actions & Data Loading

    private func handleUnfollowWithUndo(storeId: String, fallbackName: String, fallbackLogo: String?) {
        let removed = followedManager.unfollowStore(storeId: storeId)
            ?? FollowedStoreItem(store_id: storeId, store_name: fallbackName, store_logo: fallbackLogo, created_at: nil)

        if selectedStoreId?.lowercased() == storeId.lowercased() {
            selectedStoreId = nil
        }

        toastDismissTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            undoUnfollowedStore = removed
            toastMessage = "Non segui più \(removed.store_name)"
        }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismissToast()
            }
        }
    }

    private func dismissToast() {
        toastDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.22)) {
            toastMessage = nil
            undoUnfollowedStore = nil
        }
    }

    private func scheduleFeedReload(forceRefresh: Bool, showSwitchingOpacity: Bool) {
        activeFeedTask?.cancel()
        if showSwitchingOpacity {
            isSwitchingFilter = true
        }
        activeFeedTask = Task {
            await loadFeed(forceRefresh: forceRefresh)
        }
    }

    private func refreshAll(forceRefresh: Bool) async {
        await followedManager.fetchFollowedStores()
        if forceRefresh {
            if let freshShowcases = try? await api.getStoreShowcases(forceRefresh: true) {
                await MainActor.run {
                    self.fallbackShowcases = freshShowcases
                }
            }
        }
        await loadFeed(forceRefresh: forceRefresh)
    }

    private func loadFeed(forceRefresh: Bool) async {
        let storeIds = followedStoreIds
        if storeIds.isEmpty {
            await MainActor.run {
                self.feedBundle = .empty
                self.isLoading = false
                self.isSwitchingFilter = false
                self.loadError = nil
            }
            return
        }

        let prefs = prefsManager.preferences
        let targetMode = selectedMode
        let targetOnlyMySize = onlyMySize
        let key = api.followingFeedCacheKey(
            storeIds: storeIds,
            mode: targetMode,
            onlyMySize: targetOnlyMySize,
            shoeSize: prefs.preferredShoeSize,
            apparelSize: prefs.preferredApparelSize,
            sports: prefs.selectedSports,
            brands: prefs.favoriteBrands
        )

        if !forceRefresh, let cached = api.cachedFollowingFeed(for: key), !cached.isEmpty {
            await MainActor.run {
                self.feedBundle = cached
                self.isLoading = false
                self.isSwitchingFilter = false
                self.loadError = nil
            }
            if api.isFollowingFeedCacheFresh(for: key) {
                return
            }
        } else if feedBundle.isEmpty {
            await MainActor.run {
                self.isLoading = true
                self.loadError = nil
            }
        }

        do {
            let bundle = try await api.getFollowingFeed(
                storeIds: storeIds,
                mode: targetMode,
                onlyMySize: targetOnlyMySize,
                shoeSize: prefs.preferredShoeSize,
                apparelSize: prefs.preferredApparelSize,
                sports: prefs.selectedSports,
                brands: prefs.favoriteBrands,
                perStore: 12,
                highlightsLimit: 12,
                forceRefresh: forceRefresh
            )
            if Task.isCancelled { return }

            let prefetchUrls = (bundle.highlights.prefix(8) + bundle.stores.flatMap { $0.products.prefix(4) })
                .compactMap { URL(string: $0.image_url ?? "") }
            ImageCacheManager.shared.prefetch(urls: prefetchUrls)

            await MainActor.run {
                guard self.selectedMode == targetMode && self.onlyMySize == targetOnlyMySize else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    self.feedBundle = bundle
                    self.isLoading = false
                    self.isSwitchingFilter = false
                    self.loadError = nil
                }
            }
        } catch is CancellationError {
            return
        } catch {
            print("FollowingView loadFeed error: \(error)")
            // Graceful fallback to home showcases if available
            if let showcases = try? await api.getStoreShowcases(forceRefresh: forceRefresh), !showcases.isEmpty {
                let fallback = Self.buildOptimisticBundle(
                    from: showcases,
                    followedStores: followedManager.followedStores,
                    prefsManager: prefsManager
                )
                await MainActor.run {
                    self.fallbackShowcases = showcases
                    if self.feedBundle.isEmpty {
                        self.feedBundle = fallback
                    }
                    self.isLoading = false
                    self.isSwitchingFilter = false
                    self.loadError = fallback.isEmpty ? "Verifica la connessione di rete e riprova." : nil
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                    self.isSwitchingFilter = false
                    if self.feedBundle.isEmpty {
                        self.loadError = "Verifica la connessione di rete e riprova a sincronizzare i negozi."
                    }
                }
            }
        }
    }

    private static func buildOptimisticBundle(
        from showcases: [StoreShowcase],
        followedStores: [FollowedStoreItem],
        prefsManager: UserPreferencesManager
    ) -> FollowingFeedBundle {
        var byId: [String: StoreShowcase] = [:]
        for sc in showcases {
            byId[sc.store_id.lowercased()] = sc
        }

        var sections: [FollowingStoreSection] = []
        var allCandidates: [StoreShowcaseProduct] = []

        for followed in followedStores {
            let sid = followed.store_id.lowercased()
            guard let sc = byId[sid] else { continue }
            let rankedProducts = sc.products.sorted {
                prefsManager.productRelevanceScore($0) > prefsManager.productRelevanceScore($1)
            }
            allCandidates.append(contentsOf: rankedProducts.prefix(4))
            sections.append(
                FollowingStoreSection(
                    store_id: sid,
                    store_name: sc.store_name,
                    total_offers: sc.total_offers,
                    avg_discount: sc.avg_discount,
                    max_discount: rankedProducts.compactMap(\.discount_pct).max() ?? sc.avg_discount,
                    discounted_count: rankedProducts.filter { ($0.discount_pct ?? 0) >= 10 }.count,
                    atl_count: rankedProducts.filter(\.isVerifiedAllTimeLow).count,
                    new_7d_count: 0,
                    matching_count: rankedProducts.count,
                    rating: sc.rating,
                    review_count: sc.review_count,
                    logo_url: sc.logo_url ?? followed.store_logo,
                    accent_color: sc.accent_color,
                    free_shipping_threshold: DynamicCatalogRegistry.shared.shippingRule(for: sid)?.threshold,
                    products: rankedProducts
                )
            )
        }

        let highlights = allCandidates
            .sorted { prefsManager.productRelevanceScore($0) > prefsManager.productRelevanceScore($1) }
            .prefix(10)

        return FollowingFeedBundle(highlights: Array(highlights), stores: sections)
    }
}

// MARK: - Unified v2 Product Card (Cohesive with HomeView, DealsView & StoreDetailView)

struct FollowingProductCard: View {
    let product: StoreShowcaseProduct
    let matchedProduct: MatchedProduct
    var mode: FollowingFeedMode = .all
    var showStoreEyebrow: Bool = false
    var cardWidth: CGFloat? = 160

    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var prefsManager = UserPreferencesManager.shared

    private var imageHeight: CGFloat {
        cardWidth == nil ? 168 : 152
    }

    private var matchedSizeLabel: String? {
        prefsManager.matchedPreferredSizeBadge(for: product)
    }

    private var eyebrowText: String? {
        guard showStoreEyebrow else { return nil }
        let b = product.effectiveBrand.trimmingCharacters(in: .whitespacesAndNewlines)
        let brandPart = b.isEmpty ? nil : b.uppercased()
        let storePart = product.store_name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let brandPart, let storePart, !storePart.isEmpty {
            if brandPart.caseInsensitiveCompare(storePart) == .orderedSame {
                return storePart.uppercased()
            }
            return "\(brandPart) · \(storePart)"
        }
        return storePart ?? brandPart
    }

    private var formattedCurrentPrice: String {
        String(format: "%.2f €", product.current_price).replacingOccurrences(of: ".", with: ",")
    }

    private var formattedOriginalPrice: String? {
        guard let orig = product.original_price, orig > product.current_price + 0.5 else { return nil }
        return String(format: "%.0f €", orig.rounded())
    }

    var body: some View {
        NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            VStack(alignment: .leading, spacing: 5.5) {
                // Centered Crisp Product Image Box with Standardized Overlays
                ZStack {
                    RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                        .fill(Color.white)

                    if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 440) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .padding(10)
                                    .transition(.opacity)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: ShopLayout.mediumRadius)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "tag")
                            .font(.system(size: 24))
                            .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                    }
                }
                .frame(maxWidth: cardWidth ?? .infinity)
                .frame(width: cardWidth, height: imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                        .stroke(Color.shopBorder, lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    // Top badges row: Discount / New + All-Time Low
                    HStack(alignment: .top, spacing: 4) {
                        if mode == .newArrivals && product.isVerifiedNewArrival {
                            Text("Nuovo")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.shopPurple)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.shopPurpleLight)
                                .clipShape(Capsule())
                        } else if let disc = product.discountBadge {
                            Text(disc)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.shopRed)
                                .clipShape(Capsule())
                        } else if product.isVerifiedNewArrival {
                            Text("Nuovo")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.shopPurple)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.shopPurpleLight)
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
                }
                .overlay(alignment: .bottom) {
                    // Bottom row: Size match or Multi-store pill + Standardized White Heart
                    HStack(alignment: .bottom) {
                        if let sz = matchedSizeLabel {
                            Text("✓ \(sz)")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopPurple)
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.95))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.shopPurple.opacity(0.25), lineWidth: 0.7))
                        } else if let stores = product.multi_store_count, stores >= 2 {
                            Text("\(stores) negozi")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.shopDark)
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.94))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.shopBorder, lineWidth: 0.7))
                        }

                        Spacer(minLength: 4)

                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                wishlist.toggleFavorite(product: matchedProduct)
                            }
                        }) {
                            let isFav = wishlist.isFavorite(matchedProduct.canonical_name)
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.94))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(Color.shopBorder.opacity(0.85), lineWidth: 0.7))

                                Image(systemName: isFav ? "heart.fill" : "heart")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(isFav ? .shopRed : .shopDark)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                }

                // Optional Store/Brand Eyebrow (used in cross-store highlights)
                if let eyebrow = eyebrowText {
                    Text(eyebrow)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.shopTextMuted)
                        .lineLimit(1)
                        .padding(.top, 1)
                }

                // Clean Title
                Text(product.cleanDisplayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.shopDark)
                    .lineLimit(cardWidth == nil ? 2 : 1)
                    .truncationMode(.tail)
                    .frame(height: cardWidth == nil ? 33 : nil, alignment: .topLeading)

                // Price + Strikethrough Original Price
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(formattedCurrentPrice)
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    if let origStr = formattedOriginalPrice {
                        Text(origStr)
                            .font(.system(size: 11, weight: .regular))
                            .strikethrough()
                            .foregroundColor(.shopTextMuted)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: cardWidth ?? .infinity, alignment: .leading)
            .frame(width: cardWidth, alignment: .leading)
        }
        .buttonStyle(ShopCardPressStyle())
    }
}

// MARK: - Manage / Add Followed Stores Sheet

private struct ManageFollowedStoresSheet: View {
    let partnerStores: [FollowingView.PartnerStoreItem]
    let onOpenStore: (FollowingView.StoreNavTarget) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @State private var searchText: String = ""
    @State private var scopeFilter: SheetStoreScope = .all

    enum SheetStoreScope: String, CaseIterable, Identifiable {
        case all = "Tutti"
        case following = "Seguiti"
        case discover = "Da scoprire"
        var id: String { rawValue }
    }

    private var filteredStores: [FollowingView.PartnerStoreItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return partnerStores.filter { item in
            let isFollowed = followedManager.isFollowing(storeId: item.id)
            switch scopeFilter {
            case .all: break
            case .following: if !isFollowed { return false }
            case .discover: if isFollowed { return false }
            }
            if query.isEmpty { return true }
            return item.name.lowercased().contains(query) || item.subtitle.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar + Scope Segmented Control
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.shopTextMuted)

                        TextField("Cerca tra \(partnerStores.count) negozi partner...", text: $searchText)
                            .font(.system(size: 14.5))
                            .foregroundColor(.shopDark)
                            .autocorrectionDisabled()

                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(.shopTextMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.shopBorder, lineWidth: 1)
                    )

                    Picker("Filtro", selection: $scopeFilter) {
                        ForEach(SheetStoreScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.vertical, 12)
                .background(Color.shopSurface)

                ScrollView(showsIndicators: false) {
                    if filteredStores.isEmpty {
                        FitMatchEmptyStateView(
                            icon: "storefront",
                            title: scopeFilter == .discover ? "Segui già tutti i negozi" : "Nessun negozio trovato",
                            subtitle: scopeFilter == .discover
                                ? "Ottimo! Stai monitorando l’intero network di negozi FitMatch."
                                : "Prova con un altro nome o rimuovi il filtro.",
                            showsCardBackground: true
                        )
                        .padding(.horizontal, ShopLayout.screenPadding)
                        .padding(.top, 20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredStores.enumerated()), id: \.element.id) { idx, store in
                                let isFollowed = followedManager.isFollowing(storeId: store.id)

                                HStack(spacing: 12) {
                                    Button(action: {
                                        onOpenStore(FollowingView.StoreNavTarget(id: store.id, name: store.name))
                                    }) {
                                        HStack(spacing: 12) {
                                            ShopStoreLogo(
                                                storeName: store.name,
                                                showVerified: false,
                                                showLabel: false,
                                                size: 42,
                                                logoURL: store.logoURL
                                            )

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(store.name)
                                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                                    .foregroundColor(.shopDark)
                                                    .lineLimit(1)

                                                Text(store.subtitle)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.shopTextMuted)
                                                    .lineLimit(1)
                                            }

                                            Spacer(minLength: 4)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Button(action: {
                                        followedManager.toggleFollow(
                                            storeId: store.id,
                                            storeName: store.name,
                                            storeLogo: store.logoURL
                                        )
                                    }) {
                                        Text(isFollowed ? "Segui già" : "Segui")
                                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                            .foregroundColor(isFollowed ? .shopDark : .white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(isFollowed ? Color.shopSurfaceElevated : Color.shopDark)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(ShopCardPressStyle(scale: 0.95, pressedOpacity: 0.9))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)

                                if idx < filteredStores.count - 1 {
                                    Divider()
                                        .padding(.leading, 68)
                                }
                            }
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: ShopLayout.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: ShopLayout.cardRadius, style: .continuous)
                                .stroke(Color.shopBorder, lineWidth: 1)
                        )
                        .padding(.horizontal, ShopLayout.screenPadding)
                        .padding(.bottom, 24)
                    }
                }
                .background(Color.shopSurface)
            }
            .navigationTitle("Negozi (\(followedManager.followedStores.count) seguiti)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fine") {
                        dismiss()
                    }
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
