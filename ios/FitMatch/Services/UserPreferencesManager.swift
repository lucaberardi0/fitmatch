import Foundation
import SwiftUI
import Combine

@MainActor
class UserPreferencesManager: ObservableObject {
    static let shared = UserPreferencesManager()

    private let storageKey = "fitmatch_user_preferences_v1"

    @Published var preferences: UserPreferences {
        didSet {
            save()
        }
    }

    @Published var updaterStatus: UpdaterStatusResponse?
    @Published var isRefreshingPrices: Bool = false
    @Published var refreshMessage: String?
    @Published var activeStores: [ActiveStoreItem] = []

    init() {
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
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
        Task {
            _ = try? await SupabaseManager.shared.saveUserPreferences(self.preferences)
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
        var total: Double = 0.0
        for item in wishlistItems {
            if let drop = item.lastPriceDrop {
                total += drop
            }
        }
        return total
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

        for sport in preferences.selectedSports {
            let s = sport.lowercased()
            if s.contains("corsa") || s.contains("running") {
                if combined.contains("running") || combined.contains("corsa") || combined.contains("zoom") || combined.contains("gel") || combined.contains("pegasus") || combined.contains("clifton") {
                    return true
                }
            } else if s.contains("trail") {
                if combined.contains("trail") || combined.contains("outdoor") || combined.contains("gore-tex") || combined.contains("gtx") {
                    return true
                }
            } else if s.contains("fitness") || s.contains("palestra") {
                if combined.contains("training") || combined.contains("fitness") || combined.contains("gym") || combined.contains("crossfit") {
                    return true
                }
            } else if s.contains("padel") || s.contains("tennis") {
                if combined.contains("padel") || combined.contains("tennis") || combined.contains("racchetta") {
                    return true
                }
            } else if s.contains("ciclismo") || s.contains("bici") {
                if combined.contains("cycling") || combined.contains("ciclismo") || combined.contains("bike") || combined.contains("bici") {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Relevance Scoring & Re-Ranking

    func productRelevanceScore(_ product: StoreShowcaseProduct) -> Double {
        var score: Double = 0.0

        // 1. Size availability in user's size (+80 pts)
        if matchesUserShoeSize(availableSizes: product.available_sizes) {
            score += 80.0
        } else if matchesUserApparelSize(availableSizes: product.available_sizes) {
            score += 60.0
        }

        // 2. Favorite brand match (+50 pts)
        if matchesFavoriteBrand(product.brand, title: product.title) {
            score += 50.0
        }

        // 3. Sport match (+35 pts)
        if matchesSelectedSports(title: product.title) {
            score += 35.0
        }

        // 4. Discount weighting (+discount% * 0.6)
        if let disc = product.discount_pct, disc > 0 {
            if disc >= Double(preferences.minDiscountThreshold) {
                score += 20.0
            }
            score += disc * 0.6
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

        // 4. Store product matches
        let productsWithSize = showcase.products.filter { hasUserPreferredSize(availableSizes: $0.available_sizes) }.count
        score += Double(productsWithSize) * 8.0

        let productsWithFavBrand = showcase.products.filter { matchesFavoriteBrand($0.brand, title: $0.title) }.count
        score += Double(productsWithFavBrand) * 10.0

        // 5. Store quality baseline (rating & avg discount)
        let ratingVal = Double(showcase.rating.replacingOccurrences(of: ",", with: ".")) ?? 4.8
        score += ratingVal * 5.0
        score += min(showcase.avg_discount, 50.0) * 0.4

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
        guard let url = URL(string: "\(apiService.baseURL)/api/stores") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(ActiveStoresResponse.self, from: data)
            self.activeStores = decoded.active_stores
        } catch {
            print("Errore caricamento store attivi: \(error)")
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
        refreshMessage = "Sincronizzazione in corso su 9 negozi partner..."

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
