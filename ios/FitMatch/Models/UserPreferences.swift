import Foundation

struct UserPreferences: Codable {
    var userName: String
    var userEmail: String
    var preferredShoeSize: String
    var preferredApparelSize: String
    var selectedSports: [String]
    var favoriteBrands: [String]
    var minDiscountThreshold: Int // e.g. 20 (percent)
    var isPushNotificationEnabled: Bool
    var isHapticFeedbackEnabled: Bool
    var isAutoRefreshEnabled: Bool

    static let `default` = UserPreferences(
        userName: "Ospite",
        userEmail: "",
        preferredShoeSize: "42",
        preferredApparelSize: "M",
        selectedSports: [],
        favoriteBrands: [],
        minDiscountThreshold: 20,
        isPushNotificationEnabled: true,
        isHapticFeedbackEnabled: true,
        isAutoRefreshEnabled: true
    )
}

struct UpdaterStatusResponse: Codable {
    let is_running: Bool
    let last_run: String?
    let scheduler_active: Bool
    let last_stats: UpdaterStats?

    struct UpdaterStats: Codable {
        let offers_checked: Int?
        let prices_updated: Int?
        let price_drops: Int?
        let total_savings: Double?
        let duration_seconds: Double?
        let timestamp: String?
    }
}

struct DynamicCategoryItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String?
    let accent_hex: String?
    let bg_hex: String?
    let db_categories: [String]?
    let keywords: [String]?
    let excluded_keywords: [String]?
}

struct ActiveStoresResponse: Codable {
    let active_stores: [ActiveStoreItem]
    let categories: [DynamicCategoryItem]?
    let known_brands: [String]?
}

struct ActiveStoreItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let base_url: String
    let rating: Double?
    let review_count: Int?
    let formatted_review_count: String?
    let accent_color: String?
    let card_theme: String?
    let free_shipping_threshold: Double?
    let standard_shipping_cost: Double?
    let courier: String?
    let subtitle: String?

    var computedInitials: String {
        let lower = name.lowercased()
        let knownOverrides: [(String, String)] = [
            ("starcow", "STARCOW"), ("peakpulse", "PP"), ("diez", "10"),
            ("drip", "DRIP"), ("outlet", "SO"), ("end", "END."),
            ("arc", "ARC"), ("cisalfa", "CS"), ("maxi", "MS"),
            ("mister", "MR"), ("nencini", "NS"), ("top4", "T4"),
            ("warehouse", "RW"), ("depor", "DV"), ("alltricks", "AT"),
            ("decathlon", "DC"), ("sportler", "SP"), ("sportit", "SI"),
            ("tennis", "TP"), ("basketball", "BS"), ("nonsolosport", "NS"),
            ("intersport", "IS"), ("bshopzone", "BZ"), ("nike", "NK"), ("adidas", "AD")
        ]
        for (token, code) in knownOverrides where lower.contains(token) {
            return code
        }
        let words = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if words.count >= 2 {
            return "\(words[0].prefix(1))\(words[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
