import Foundation
import SwiftUI
import Combine

@MainActor
class WishlistManager: ObservableObject {
    static let shared = WishlistManager()

    @Published var items: [WishlistItem] = []
    @Published var isCheckingPrices: Bool = false
    @Published var lastCheckMessage: String? = nil

    private let saveFileName = "fitmatch_wishlist.json"

    private var fileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(saveFileName)
    }

    init() {
        loadItems()
    }

    // MARK: - Persistence

    func loadItems() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            self.items = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([WishlistItem].self, from: data)
            self.items = decoded
        } catch {
            print("Errore caricamento wishlist: \(error)")
            self.items = []
        }
    }

    func saveItems() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: [.atomicWrite, .completeFileProtection])
        } catch {
            print("Errore salvataggio wishlist: \(error)")
        }
    }

    // MARK: - Queries

    func isFavorite(_ canonicalName: String) -> Bool {
        items.contains { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }
    }

    func getItem(_ canonicalName: String) -> WishlistItem? {
        items.first { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }
    }

    // MARK: - Mutations

    func toggleFavorite(product: MatchedProduct, selectedSize: String? = nil, targetPrice: Double? = nil) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        if isFavorite(product.canonical_name) {
            removeFromWishlist(product.canonical_name)
        } else {
            addToWishlist(product: product, selectedSize: selectedSize, targetPrice: targetPrice)
        }
    }

    func addToWishlist(product: MatchedProduct, selectedSize: String? = nil, targetPrice: Double? = nil) {
        let bestPrice = product.best_price ?? product.bestOffer?.price ?? 0.0
        let bestOffer = product.bestOffer

        // Default alert target: 10% below current price if not specified
        let defaultAlert = targetPrice ?? (bestPrice > 0 ? (bestPrice * 0.90).rounded() : nil)

        let newItem = WishlistItem(
            canonical_name: product.canonical_name,
            brand: product.brand,
            image_url: product.image_url ?? bestOffer?.image_url,
            initialPrice: bestPrice,
            currentBestPrice: bestPrice,
            highestPrice: product.highest_price,
            bestStore: bestOffer?.store_name,
            bestStoreUrl: bestOffer?.url,
            offersCount: product.offers.count,
            selectedSize: selectedSize,
            targetAlertPrice: defaultAlert,
            isAlertEnabled: true,
            dateAdded: Date(),
            lastCheckedDate: Date(),
            lastPriceDrop: nil
        )

        // Remove duplicate if exists
        items.removeAll { $0.canonical_name.caseInsensitiveCompare(product.canonical_name) == .orderedSame }
        items.insert(newItem, at: 0)
        saveItems()

        // Check and prompt notification permissions if alerts are enabled
        NotificationManager.shared.checkAuthorization()
        if !NotificationManager.shared.isAuthorized {
            NotificationManager.shared.requestAuthorization()
        }
    }

    func removeFromWishlist(_ canonicalName: String) {
        items.removeAll { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }
        saveItems()
    }

    func updateAlertSettings(
        canonicalName: String,
        isEnabled: Bool,
        targetPrice: Double?,
        selectedSize: String?
    ) {
        guard let index = items.firstIndex(where: { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }) else {
            return
        }

        items[index].isAlertEnabled = isEnabled
        items[index].targetAlertPrice = targetPrice
        items[index].selectedSize = selectedSize
        saveItems()

        if isEnabled && !NotificationManager.shared.isAuthorized {
            NotificationManager.shared.requestAuthorization()
        }
    }

    // MARK: - Price Drop Simulator (for Testing & Demos)

    func simulatePriceDrop(for canonicalName: String, dropAmount: Double = 25.0) {
        guard let index = items.firstIndex(where: { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }) else {
            return
        }

        let oldPrice = items[index].currentBestPrice
        let newPrice = max(19.0, oldPrice - dropAmount)
        let store = items[index].bestStore ?? "Mister Running"

        items[index].currentBestPrice = newPrice
        items[index].lastPriceDrop = dropAmount
        items[index].lastCheckedDate = Date()
        saveItems()

        // Trigger native notification
        NotificationManager.shared.sendPriceDropNotification(
            productTitle: items[index].canonical_name,
            oldPrice: oldPrice,
            newPrice: newPrice,
            storeName: store,
            targetPrice: items[index].targetAlertPrice,
            url: items[index].bestStoreUrl
        )

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // MARK: - Live Check Against API

    func refreshAllPrices(apiService: APIService) async {
        guard !items.isEmpty else { return }
        isCheckingPrices = true
        lastCheckMessage = "Controllo prezzi su 4 negozi partner..."

        var updatedCount = 0
        var dropsFound = 0

        for i in 0..<items.count {
            let item = items[i]
            do {
                let products = try await apiService.search(query: item.canonical_name, size: item.selectedSize)
                if let matched = products.first, let newBest = matched.best_price {
                    let oldPrice = item.currentBestPrice
                    items[i].lastCheckedDate = Date()
                    items[i].offersCount = matched.offers.count

                    if let bestOffer = matched.bestOffer {
                        items[i].bestStore = bestOffer.store_name
                        items[i].bestStoreUrl = bestOffer.url
                    }

                    if newBest < oldPrice {
                        let drop = oldPrice - newBest
                        items[i].currentBestPrice = newBest
                        items[i].lastPriceDrop = drop
                        dropsFound += 1

                        // Check alert condition
                        if items[i].isAlertEnabled {
                            let shouldNotify: Bool
                            if let target = items[i].targetAlertPrice {
                                shouldNotify = newBest <= target
                            } else {
                                shouldNotify = true
                            }

                            if shouldNotify {
                                NotificationManager.shared.sendPriceDropNotification(
                                    productTitle: item.canonical_name,
                                    oldPrice: oldPrice,
                                    newPrice: newBest,
                                    storeName: items[i].bestStore ?? "Store Partner",
                                    targetPrice: items[i].targetAlertPrice,
                                    url: items[i].bestStoreUrl
                                )
                            }
                        }
                    } else {
                        items[i].currentBestPrice = newBest
                    }
                    updatedCount += 1
                }
            } catch {
                print("Errore verifica prezzo per \(item.canonical_name): \(error)")
            }
        }

        saveItems()
        isCheckingPrices = false

        if dropsFound > 0 {
            lastCheckMessage = "Trovati \(dropsFound) cali di prezzo!"
        } else {
            lastCheckMessage = "Prezzi aggiornati: nessun nuovo calo rilevato."
        }
    }
}
