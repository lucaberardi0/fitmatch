import Foundation

struct WishlistItem: Identifiable, Codable, Hashable {
    var id: String { canonical_name }
    let canonical_name: String
    let brand: String?
    let image_url: String?
    var initialPrice: Double
    var currentBestPrice: Double
    var highestPrice: Double?
    var bestStore: String?
    var bestStoreUrl: String?
    var offersCount: Int
    var selectedSize: String?
    var targetAlertPrice: Double?
    var isAlertEnabled: Bool
    var dateAdded: Date
    var lastCheckedDate: Date
    var lastPriceDrop: Double?

    var formattedCurrentPrice: String {
        String(format: "€%.2f", currentBestPrice)
    }

    var formattedInitialPrice: String {
        String(format: "€%.2f", initialPrice)
    }

    var formattedTargetPrice: String? {
        guard let target = targetAlertPrice else { return nil }
        return String(format: "€%.2f", target)
    }

    var hasPriceDropped: Bool {
        return currentBestPrice < initialPrice
    }

    var savingsSinceAdded: Double {
        max(0, initialPrice - currentBestPrice)
    }

    var formattedSavingsSinceAdded: String? {
        let diff = savingsSinceAdded
        guard diff > 0.5 else { return nil }
        return String(format: "-€%.2f", diff)
    }
}
