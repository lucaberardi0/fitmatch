import Foundation

struct UserPreferences: Codable, Equatable {
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

    var hasShoeSize: Bool {
        !preferredShoeSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasApparelSize: Bool {
        !preferredApparelSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAnySize: Bool {
        hasShoeSize || hasApparelSize
    }

    var formattedSizeSummary: String {
        switch (hasShoeSize, hasApparelSize) {
        case (true, true):
            return "EU\u{00A0}\(preferredShoeSize) · \(preferredApparelSize)"
        case (true, false):
            return "EU\u{00A0}\(preferredShoeSize)"
        case (false, true):
            return preferredApparelSize
        case (false, false):
            return "Non impostate"
        }
    }

    var configuredPreferencesSummary: String {
        var parts: [String] = []
        if hasAnySize {
            parts.append(formattedSizeSummary)
        }
        if !selectedSports.isEmpty {
            parts.append(selectedSports.count == 1 ? selectedSports[0] : "\(selectedSports.count) sport")
        }
        if !favoriteBrands.isEmpty {
            parts.append(favoriteBrands.count == 1 ? favoriteBrands[0] : "\(favoriteBrands.count) brand")
        }
        return parts.isEmpty ? "Personalizza" : parts.prefix(2).joined(separator: " · ")
    }

    static let `default` = UserPreferences(
        userName: "Ospite",
        userEmail: "",
        preferredShoeSize: "",
        preferredApparelSize: "",
        selectedSports: [],
        favoriteBrands: [],
        minDiscountThreshold: 20,
        isPushNotificationEnabled: true,
        isHapticFeedbackEnabled: true,
        isAutoRefreshEnabled: true
    )
}

struct RemoteUserPreferencesRow: Codable {
    let user_name: String?
    let preferred_shoe_size: String?
    let preferred_apparel_size: String?
    let selected_sports: [String]?
    let favorite_brands: [String]?
    let min_discount_threshold: Int?
    let notifications_enabled: Bool?
    let haptic_feedback_enabled: Bool?
    let auto_refresh_enabled: Bool?
    let updated_at: String?
}

struct AccountMonitorStats: Codable {
    let latest_catalog_check_at: String?
    let active_store_count: Int
    let monitored_wishlist_count: Int
    let target_alerts_count: Int
    let recent_drops_7d: Int
    let unread_notifications_count: Int
    let chat_sessions_count: Int
    let hidden_stores_count: Int

    var latestCatalogCheckDate: Date? {
        SupabaseManager.parseISO8601Date(latest_catalog_check_at)
    }

    var formattedLastCheckRelative: String {
        guard let date = latestCatalogCheckDate else {
            return "Controllo automatico attivo"
        }
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 120 {
            return "Aggiornato adesso"
        } else if elapsed < 3600 {
            let mins = max(1, Int(elapsed / 60))
            return "\(mins) min fa"
        } else if elapsed < 86400 {
            let hours = max(1, Int(elapsed / 3600))
            return hours == 1 ? "1 ora fa" : "\(hours) ore fa"
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.dateFormat = "d MMM, HH:mm"
        return df.string(from: date)
    }
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
    let country: String?
    let logo_url: String?
    let is_new: Bool?
    let subtitle: String?
    let refund_policy: String?
    let shipping_policy: String?
    let is_verified: Bool?

    init(
        id: String,
        name: String,
        base_url: String,
        rating: Double? = nil,
        review_count: Int? = nil,
        formatted_review_count: String? = nil,
        accent_color: String? = nil,
        card_theme: String? = nil,
        free_shipping_threshold: Double? = nil,
        standard_shipping_cost: Double? = nil,
        courier: String? = nil,
        country: String? = nil,
        logo_url: String? = nil,
        is_new: Bool? = nil,
        subtitle: String? = nil,
        refund_policy: String? = nil,
        shipping_policy: String? = nil,
        is_verified: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.base_url = base_url
        self.rating = rating
        self.review_count = review_count
        self.formatted_review_count = formatted_review_count
        self.accent_color = accent_color
        self.card_theme = card_theme
        self.free_shipping_threshold = free_shipping_threshold
        self.standard_shipping_cost = standard_shipping_cost
        self.courier = courier
        self.country = country
        self.logo_url = logo_url
        self.is_new = is_new
        self.subtitle = subtitle
        self.refund_policy = refund_policy
        self.shipping_policy = shipping_policy
        self.is_verified = is_verified
    }

    var computedInitials: String {
        let lower = name.lowercased()
        let knownOverrides: [(String, String)] = [
            ("cisalfa", "CS"), ("maxi", "MS"), ("mister", "MR"),
            ("nencini", "NS"), ("top4", "T4"), ("warehouse", "RW"),
            ("depor", "DV"), ("alltricks", "AT"), ("decathlon", "DC"),
            ("sportler", "SP"), ("sportit", "SI"), ("df sport", "DF"),
            ("sportspecialist", "DF"), ("tradeinn", "TI"), ("tennis", "TP"),
            ("basketball", "BS"), ("nonsolosport", "NS"), ("intersport", "IS"),
            ("bshopzone", "BZ"), ("nike", "NK"), ("adidas", "AD")
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
