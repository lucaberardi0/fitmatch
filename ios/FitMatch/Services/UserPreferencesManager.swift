import Foundation
import SwiftUI
import Combine

@MainActor
enum ShopHaptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard UserPreferencesManager.shared.preferences.isHapticFeedbackEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard UserPreferencesManager.shared.preferences.isHapticFeedbackEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    static func selection() {
        guard UserPreferencesManager.shared.preferences.isHapticFeedbackEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

@MainActor
class UserPreferencesManager: ObservableObject {
    static let shared = UserPreferencesManager()

    private let storageKey = "fitmatch_user_preferences_v1"
    private let onboardingCompletedKey = "fitmatch_has_completed_onboarding_v1"
    private var authObserver: NSObjectProtocol?
    private var isApplyingRemoteUpdate: Bool = false
    private var cloudSaveTask: Task<Void, Never>? = nil

    static let shoeSizes: [String] = [
        "35", "35.5", "36", "36.5", "37", "37.5", "38", "38.5", "39", "39.5",
        "40", "40.5", "41", "41.5", "42", "42.5", "43", "43.5", "44", "44.5",
        "45", "45.5", "46", "46.5", "47", "48"
    ]
    static let apparelSizes: [String] = ["XS", "S", "M", "L", "XL", "XXL"]

    private static let fallbackSports: [(String, String)] = [
        ("Running Corsa", "figure.run"),
        ("Trail Running", "mountain.2.fill"),
        ("Ciclismo & GPS", "bicycle"),
        ("Fitness & Palestra", "dumbbell.fill"),
        ("Outdoor & Trekking", "tent.fill"),
        ("Padel & Tennis", "tennis.racket"),
        ("Calcio & Calcetto", "soccerball"),
        ("Basket", "basketball.fill"),
        ("Sci & Neve", "snowflake"),
        ("Nuoto", "figure.pool.swim"),
        ("Nutrizione", "bolt.heart.fill")
    ]

    private static let fallbackBrands: [String] = [
        "Nike", "Asics", "Garmin", "Salomon", "Hoka", "Brooks", "New Balance", "Under Armour", "Polar", "Oakley"
    ]

    private static let fallbackOnboardingStores: [(id: String, name: String, subtitle: String)] = [
        ("misterrunning", "Mister Running", "Running, trail e scarpe da gara"),
        ("cisalfa", "Cisalfa Sport", "Multisport, sneaker e abbigliamento"),
        ("decathlon", "Decathlon", "Catalogo completo per ogni disciplina"),
        ("maxisport", "Maxi Sport", "Running, outdoor e lifestyle"),
        ("top4running", "Top4Running", "Scarpe tecniche e performance"),
        ("deporvillage", "Deporvillage", "Ciclismo, outdoor e GPS"),
        ("alltricks", "Alltricks", "Bici, trail e sport endurance"),
        ("nike", "Nike", "Store ufficiale Nike"),
        ("runningwarehouse", "Running Warehouse Europe", "Specialista corsa su strada e trail"),
        ("nencini", "Nencini Sport", "Abbigliamento e attrezzatura sportiva")
    ]

    @Published var preferences: UserPreferences {
        didSet {
            guard preferences != oldValue else { return }
            persistLocally()
            if !isApplyingRemoteUpdate {
                scheduleCloudSave()
            }
        }
    }

    @Published var hasCompletedOnboarding: Bool
    @Published var updaterStatus: UpdaterStatusResponse?
    @Published var accountMonitorStats: AccountMonitorStats?
    @Published var isRefreshingPrices: Bool = false
    @Published var refreshMessage: String?
    @Published var activeStores: [ActiveStoreItem] = []
    @Published var dynamicCategories: [DynamicCategoryItem] = []
    @Published var dynamicBrands: [String] = []

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingCompletedKey)
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            // Reset to default anonymous preferences if the old hardcoded developer values were stored
            if decoded.userEmail == "luca.runner@fitmatch.it" || (decoded.userName == "Luca" && decoded.userEmail.isEmpty) {
                self.preferences = .default
            } else {
                self.preferences = decoded
            }
        } else {
            self.preferences = .default
        }
        self.activeStores = DynamicCatalogRegistry.shared.cachedStores
        self.dynamicCategories = DynamicCatalogRegistry.shared.cachedCategories
        self.dynamicBrands = DynamicCatalogRegistry.shared.allBrands

        authObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("FitMatchAuthSessionDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.syncFromDatabase(force: true)
                await self.fetchAccountMonitorStats()
            }
        }

        Task {
            await syncFromDatabase()
        }
    }

    deinit {
        if let authObserver {
            NotificationCenter.default.removeObserver(authObserver)
        }
    }

    var availableSports: [(String, String)] {
        let nonSportIds: Set<String> = ["tutti", "donna", "uomo", "abbigliamento", "smartwatch", "accessori"]
        var seenIds: Set<String> = ["running", "outdoor", "cycling", "fitness", "padel", "calcio", "tennis", "basket", "sci", "nuoto", "nutrizione"]
        var merged = Self.fallbackSports
        for cat in dynamicCategories {
            let cid = cat.id.lowercased()
            if nonSportIds.contains(cid) || seenIds.contains(cid) { continue }
            seenIds.insert(cid)
            merged.append((cat.name, cat.icon?.isEmpty == false ? cat.icon! : "sportscourt.fill"))
        }
        return merged
    }

    var availableBrands: [String] {
        guard !dynamicBrands.isEmpty else { return Self.fallbackBrands }
        var seen = Set(Self.fallbackBrands.map { $0.lowercased() })
        var merged = Self.fallbackBrands
        for brand in dynamicBrands {
            let low = brand.lowercased()
            if !seen.contains(low) {
                seen.insert(low)
                merged.append(brand)
            }
        }
        return merged
    }

    var suggestedOnboardingStores: [(id: String, name: String, subtitle: String)] {
        guard !activeStores.isEmpty else { return Self.fallbackOnboardingStores }
        return activeStores.map { store in
            let sub = (store.subtitle?.isEmpty == false) ? store.subtitle! : store.base_url
            return (id: store.id, name: store.name, subtitle: sub)
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: onboardingCompletedKey)
        hasCompletedOnboarding = true
        save()
    }

    func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: onboardingCompletedKey)
        hasCompletedOnboarding = false
    }

    private func persistLocally() {
        if let encoded = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func scheduleCloudSave() {
        cloudSaveTask?.cancel()
        let snapshot = preferences
        cloudSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, self != nil else { return }
            _ = try? await SupabaseManager.shared.saveUserPreferences(snapshot)
        }
    }

    func save() {
        persistLocally()
        scheduleCloudSave()
    }

    /// Updates local preferences without triggering a remote write (used on sign-out, deletion, or remote hydration).
    func applyWithoutCloudUpload(_ mutate: (inout UserPreferences) -> Void) {
        cloudSaveTask?.cancel()
        isApplyingRemoteUpdate = true
        mutate(&preferences)
        isApplyingRemoteUpdate = false
        persistLocally()
    }

    func resetLocalOnly() {
        applyWithoutCloudUpload { prefs in
            prefs = .default
        }
        accountMonitorStats = nil
    }

    /// Pulls the authenticated (permanent or anonymous) user's preferences from Supabase.
    func syncFromDatabase(force: Bool = false) async {
        await SupabaseManager.shared.ensureUserSession()
        guard let remote = await SupabaseManager.shared.fetchUserPreferences() else {
            // If this is a permanent account with no remote row yet but local prefs exist, upload once
            if force, SupabaseManager.shared.isAuthenticated {
                _ = try? await SupabaseManager.shared.saveUserPreferences(preferences)
            }
            return
        }

        let remoteName = remote.user_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedEmail = SupabaseManager.shared.currentUserEmail ?? ""

        applyWithoutCloudUpload { local in
            if !remoteName.isEmpty && remoteName.lowercased() != "ospite" {
                local.userName = remoteName
            } else if SupabaseManager.shared.isAuthenticated && local.userName == "Ospite", !resolvedEmail.isEmpty {
                local.userName = (resolvedEmail.components(separatedBy: "@").first ?? "Atleta").capitalized
            } else if !SupabaseManager.shared.isAuthenticated {
                local.userName = remoteName.isEmpty ? "Ospite" : remoteName
            }
            local.userEmail = resolvedEmail
            local.preferredShoeSize = remote.preferred_shoe_size ?? ""
            local.preferredApparelSize = remote.preferred_apparel_size ?? ""
            local.selectedSports = remote.selected_sports ?? []
            local.favoriteBrands = remote.favorite_brands ?? []
            if let disc = remote.min_discount_threshold {
                local.minDiscountThreshold = max(5, min(60, disc))
            }
            if let push = remote.notifications_enabled {
                local.isPushNotificationEnabled = push
            }
            if let haptic = remote.haptic_feedback_enabled {
                local.isHapticFeedbackEnabled = haptic
            }
            if let autoRefresh = remote.auto_refresh_enabled {
                local.isAutoRefreshEnabled = autoRefresh
            }
        }
    }

    func fetchAccountMonitorStats() async {
        await SupabaseManager.shared.ensureUserSession()
        if let stats = await SupabaseManager.shared.fetchAccountMonitorStats() {
            self.accountMonitorStats = stats
        }
    }

    func toggleSport(_ sport: String) {
        if let idx = preferences.selectedSports.firstIndex(of: sport) {
            preferences.selectedSports.remove(at: idx)
        } else {
            preferences.selectedSports.append(sport)
        }
    }

    func toggleBrand(_ brand: String) {
        if let idx = preferences.favoriteBrands.firstIndex(of: brand) {
            preferences.favoriteBrands.remove(at: idx)
        } else {
            preferences.favoriteBrands.append(brand)
        }
    }

    func calculateTotalWishlistSavings(wishlistItems: [WishlistItem]) -> Double {
        wishlistItems.reduce(0.0) { $0 + $1.droppedAmountSinceSaved }
    }

    // MARK: - Personalization & Matching Engine

    func isSizeAvailable(_ targetSize: String, in availableSizes: [String]?) -> Bool {
        guard let sizes = availableSizes, !sizes.isEmpty else { return false }
        let cleanTarget = targetSize.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".").lowercased()
        if cleanTarget.isEmpty { return false }

        let targetDouble = Double(cleanTarget)

        for s in sizes {
            let clean = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".").lowercased()
            if clean == cleanTarget { return true }
            // Handle variations like "42.0", "42 eu", "eu 42", "42 (uk 8)"
            let stripped = clean.replacingOccurrences(of: "eu", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped == cleanTarget { return true }
            if clean.hasPrefix(cleanTarget + " ") || clean.hasSuffix(" " + cleanTarget) {
                return true
            }
            // Proximity tolerance for decimal fractional sizes (e.g. 42.5 matches 42.7 or 42.66 within 0.35)
            if let tD = targetDouble, let sD = Double(stripped), abs(tD - sD) < 0.35 {
                return true
            }
        }
        return false
    }

    func matchesUserShoeSize(availableSizes: [String]?) -> Bool {
        return isSizeAvailable(preferences.preferredShoeSize, in: availableSizes)
    }

    func matchesUserApparelSize(availableSizes: [String]?) -> Bool {
        return isSizeAvailable(preferences.preferredApparelSize, in: availableSizes)
    }

    func hasUserPreferredSize(availableSizes: [String]?) -> Bool {
        guard let sizes = availableSizes, !sizes.isEmpty else { return false }
        return matchesUserShoeSize(availableSizes: sizes) || matchesUserApparelSize(availableSizes: sizes)
    }

    /// Returns a clean user-facing size label ("EU 42" or "M") if the product is in stock in either preferred size.
    func matchedPreferredSizeBadge(for product: StoreShowcaseProduct) -> String? {
        guard let sizes = product.available_sizes, !sizes.isEmpty else { return nil }
        let cat = (product.product_category ?? "").lowercased()
        let isApparelCat = ["top", "pants", "jacket", "apparel", "swim"].contains(cat)

        if isApparelCat {
            if matchesUserApparelSize(availableSizes: sizes) {
                return "Tg. \(preferences.preferredApparelSize)"
            }
            return nil
        }

        if matchesUserShoeSize(availableSizes: sizes) {
            return "EU \(preferences.preferredShoeSize)"
        }
        if matchesUserApparelSize(availableSizes: sizes) {
            return "Tg. \(preferences.preferredApparelSize)"
        }
        return nil
    }

    func matchesFavoriteBrand(_ brand: String?, title: String? = nil) -> Bool {
        guard !preferences.favoriteBrands.isEmpty else { return false }
        let targetBrand = (brand ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let targetTitle = (title ?? "").lowercased()

        for fav in preferences.favoriteBrands {
            let f = fav.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !f.isEmpty && (targetBrand.contains(f) || f.contains(targetBrand) || targetTitle.contains(f)) {
                return true
            }
        }
        return false
    }

    func matchesSelectedSports(title: String, category: String? = nil) -> Bool {
        guard !preferences.selectedSports.isEmpty else { return false }
        let combined = "\(title) \(category ?? "")".lowercased()

        let dynamicCats = DynamicCatalogRegistry.shared.cachedCategories

        for sport in preferences.selectedSports {
            let s = sport.lowercased()
            if s.contains("corsa") || s.contains("running") {
                if combined.contains("running") || combined.contains("corsa") || combined.contains("zoom") || combined.contains("gel") || combined.contains("pegasus") || combined.contains("clifton") {
                    return true
                }
            } else if s.contains("trail") || s.contains("outdoor") || s.contains("trekking") {
                if combined.contains("trail") || combined.contains("outdoor") || combined.contains("gore-tex") || combined.contains("gtx") || combined.contains("trekking") {
                    return true
                }
            } else if s.contains("fitness") || s.contains("palestra") || s.contains("gym") {
                if combined.contains("training") || combined.contains("fitness") || combined.contains("gym") || combined.contains("crossfit") {
                    return true
                }
            } else if s.contains("padel") || s.contains("tennis") {
                if combined.contains("padel") || combined.contains("tennis") || combined.contains("racchetta") {
                    return true
                }
            } else if s.contains("ciclismo") || s.contains("bici") || s.contains("cycling") {
                if combined.contains("cycling") || combined.contains("ciclismo") || combined.contains("bike") || combined.contains("bici") {
                    return true
                }
            } else if s.contains("calcio") || s.contains("calcetto") {
                if CategoryFilterMatcher.matches(title: title, category: "calcio", dbCategory: category) {
                    return true
                }
            } else if s.contains("basket") {
                if CategoryFilterMatcher.matches(title: title, category: "basket", dbCategory: category) {
                    return true
                }
            } else if s.contains("sci") || s.contains("neve") {
                if CategoryFilterMatcher.matches(title: title, category: "sci", dbCategory: category) {
                    return true
                }
            } else if s.contains("nuoto") {
                if CategoryFilterMatcher.matches(title: title, category: "nuoto", dbCategory: category) {
                    return true
                }
            } else if s.contains("nutrizione") {
                if CategoryFilterMatcher.matches(title: title, category: "nutrizione", dbCategory: category) {
                    return true
                }
            }

            // Dynamic match for any backend-added sport/category
            if let dyn = dynamicCats.first(where: {
                let dName = $0.name.lowercased()
                let dId = $0.id.lowercased()
                return dName == s || dId == s || s.contains(dId) || dName.contains(s)
            }) {
                if CategoryFilterMatcher.matches(title: title, category: dyn.id, dbCategory: category) {
                    return true
                }
            } else if combined.contains(s) {
                return true
            }
        }
        return false
    }

    // MARK: - Relevance Scoring & Re-Ranking

    func productRelevanceScore(_ product: StoreShowcaseProduct) -> Double {
        var score: Double = (product.deal_score ?? 0.0) * 0.25

        // 1. Size availability in user's preferred shoe or apparel size (+80 / +65 pts)
        if matchesUserShoeSize(availableSizes: product.available_sizes) {
            score += 80.0
        } else if matchesUserApparelSize(availableSizes: product.available_sizes) {
            score += 65.0
        }

        // 2. Favorite brand match (+50 pts)
        if matchesFavoriteBrand(product.brand, title: product.canonical_name) {
            score += 50.0
        }

        // 3. Sport match (+35 pts)
        if matchesSelectedSports(title: product.canonical_name, category: product.product_category) {
            score += 35.0
        }

        // 4. Verified comparator signals (All-Time Low, Best Market Price, Multi-store)
        if product.isVerifiedAllTimeLow {
            score += 18.0
        }
        if product.isVerifiedBestMarketPrice {
            score += 14.0
        }
        if let stores = product.multi_store_count, stores >= 2 {
            score += min(Double(stores) * 3.0, 15.0)
        }

        // 5. Discount weighting (capped at 55% so clearance junk doesn't beat real flagship deals)
        if let disc = product.discount_pct, disc > 0 {
            if disc >= Double(preferences.minDiscountThreshold) {
                score += 16.0
            }
            score += min(disc, 55.0) * 0.45
        }

        return score
    }

    func storeRelevanceScore(
        showcase: StoreShowcase,
        isFollowed: Bool,
        recentStoreIds: Set<String>,
        wishlistStoreNames: Set<String>
    ) -> Double {
        var score: Double = 0.0
        let sid = showcase.store_id.lowercased()
        let sname = showcase.store_name.lowercased()

        // 1. User explicitly follows the store (Top tier: +180 pts)
        if isFollowed {
            score += 180.0
        }

        // 2. Flagship store of user's favorite brand (Nike, Adidas) (+70 pts)
        if sid == "nike" && preferences.favoriteBrands.contains(where: { $0.caseInsensitiveCompare("Nike") == .orderedSame }) {
            score += 70.0
        }
        if sid == "adidas" && preferences.favoriteBrands.contains(where: { $0.caseInsensitiveCompare("Adidas") == .orderedSame }) {
            score += 70.0
        }

        // 3. Recent activity & Wishlist engagement (+35 pts)
        if recentStoreIds.contains(sid) || recentStoreIds.contains(sname) {
            score += 35.0
        }
        if wishlistStoreNames.contains(sid) || wishlistStoreNames.contains(sname) {
            score += 30.0
        }

        // 4. Store product relevance & comparator quality
        let productsWithSize = showcase.products.filter { hasUserPreferredSize(availableSizes: $0.available_sizes) }.count
        score += Double(productsWithSize) * 8.0

        let productsWithFavBrand = showcase.products.filter { matchesFavoriteBrand($0.brand, title: $0.canonical_name) }.count
        score += Double(productsWithFavBrand) * 10.0

        let bestMarketCount = showcase.products.filter { $0.isVerifiedBestMarketPrice }.count
        score += Double(bestMarketCount) * 4.5

        let atlCount = showcase.products.filter { $0.isVerifiedAllTimeLow }.count
        score += Double(atlCount) * 3.5

        // 5. Store quality baseline (avoid unfairly penalizing official brands with skewed Trustpilot scores)
        let isOfficialFlagship = (sid == "nike" || sid == "adidas" || sid == "decathlon")
        let rawRating = Double(showcase.rating.replacingOccurrences(of: ",", with: ".")) ?? 4.5
        let effectiveRating = isOfficialFlagship ? max(rawRating, 4.4) : max(rawRating, 3.5)
        score += effectiveRating * 4.0
        score += min(showcase.avg_discount, 45.0) * 0.35

        // Deprioritize tiny catalogs (<100 offers) gently below major multi-category partners
        if showcase.total_offers < 100 {
            score -= 25.0
        }

        return score
    }

    func personalizeShowcases(
        _ showcases: [StoreShowcase],
        followedStoreIds: Set<String>,
        recentStoreIds: Set<String>,
        wishlistStoreNames: Set<String>
    ) -> [StoreShowcase] {
        // 1. First re-order products inside each store based on product relevance score
        let reorderedShowcases = showcases.map { sc -> StoreShowcase in
            let sortedProducts = sc.products.sorted {
                let s0 = productRelevanceScore($0)
                let s1 = productRelevanceScore($1)
                if s0 != s1 { return s0 > s1 }
                return ($0.discount_pct ?? 0) > ($1.discount_pct ?? 0)
            }
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
                products: sortedProducts
            )
        }

        // 2. Rank stores by storeRelevanceScore
        return reorderedShowcases.sorted { sc0, sc1 in
            let isF0 = followedStoreIds.contains(sc0.store_id.lowercased())
            let isF1 = followedStoreIds.contains(sc1.store_id.lowercased())
            let score0 = storeRelevanceScore(showcase: sc0, isFollowed: isF0, recentStoreIds: recentStoreIds, wishlistStoreNames: wishlistStoreNames)
            let score1 = storeRelevanceScore(showcase: sc1, isFollowed: isF1, recentStoreIds: recentStoreIds, wishlistStoreNames: wishlistStoreNames)
            if abs(score0 - score1) > 0.1 {
                return score0 > score1
            }
            return sc0.total_offers > sc1.total_offers
        }
    }

    func fetchActiveStores(apiService: APIService) async {
        // 1. Hydrate stores directly from Supabase so logos, ratings, and shipping rules are always fresh
        let directStores = await SupabaseManager.shared.fetchActiveStoresDirect()
        if !directStores.isEmpty {
            DynamicCatalogRegistry.shared.updateStores(directStores)
            self.activeStores = directStores
            return
        }

        // 2. Fallback to API only if Supabase direct query returned empty
        guard let url = URL(string: "\(apiService.baseURL)/api/stores") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(ActiveStoresResponse.self, from: data)
            DynamicCatalogRegistry.shared.update(from: decoded)
            self.activeStores = decoded.active_stores
            if let cats = decoded.categories, !cats.isEmpty {
                self.dynamicCategories = cats
            }
            if let brands = decoded.known_brands, !brands.isEmpty {
                self.dynamicBrands = brands
            }
        } catch {
            if directStores.isEmpty {
                print("Errore caricamento store attivi: \(error)")
            }
        }
    }

    func checkUpdaterStatus(apiService: APIService) async {
        guard let url = URL(string: "\(apiService.baseURL)/api/updater/status") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(UpdaterStatusResponse.self, from: data)
            self.updaterStatus = decoded
        } catch {
            print("Errore caricamento stato updater: \(error)")
        }
    }

    func triggerPriceRefresh(apiService: APIService) async {
        guard let url = URL(string: "\(apiService.baseURL)/api/updater/run?limit=15") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        isRefreshingPrices = true
        let storeCount = activeStores.count
        let scopeLabel = storeCount > 0 ? "\(storeCount) negozi partner" : "tutti i negozi partner"
        refreshMessage = "Sincronizzazione in corso su \(scopeLabel)..."

        let haptic = UINotificationFeedbackGenerator()

        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            haptic.notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await checkUpdaterStatus(apiService: apiService)
            self.isRefreshingPrices = false
            self.refreshMessage = "Sincronizzazione avviata in background!"
        } catch {
            haptic.notificationOccurred(.error)
            self.isRefreshingPrices = false
            self.refreshMessage = "Errore durante la connessione."
        }
    }
}
