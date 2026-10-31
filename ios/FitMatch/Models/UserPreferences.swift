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
        userName: "Luca",
        userEmail: "luca.runner@fitmatch.it",
        preferredShoeSize: "43",
        preferredApparelSize: "M",
        selectedSports: ["Running Corsa", "Trail Running", "Ciclismo & GPS"],
        favoriteBrands: ["Nike", "Asics", "Garmin", "Salomon", "Hoka", "Brooks"],
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

struct ActiveStoresResponse: Codable {
    let active_stores: [ActiveStoreItem]
}

struct ActiveStoreItem: Codable, Identifiable {
    let id: String
    let name: String
    let base_url: String
}
