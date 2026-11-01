import Foundation
import SwiftUI
import Combine

@MainActor
class WishlistManager: ObservableObject {
    static let shared = WishlistManager()

    @Published var items: [WishlistItem] = []
    @Published var collections: [WishlistCollection] = []
    @Published var selectedCollection: String = "Tutti"
    @Published var isCheckingPrices: Bool = false
    @Published var isSyncingDatabase: Bool = false
    @Published var lastCheckMessage: String? = nil

    private let saveFileName = "fitmatch_wishlist.json"

    private var fileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(saveFileName)
    }

    init() {
        loadItems()
        Task {
            await syncWithDatabase()
        }
    }

    // MARK: - Database Sync (Supabase Cloud + Local Gateway)

    func syncWithDatabase() async {
        isSyncingDatabase = true
        defer { isSyncingDatabase = false }

        // 1. Try Supabase Cloud Database first
        do {
            async let supaItems = SupabaseManager.shared.fetchWishlist()
            async let supaCols = SupabaseManager.shared.fetchCollections()

            let (items, cols) = try await (supaItems, supaCols)
            if !items.isEmpty {
                var processed = items
                for i in 0..<processed.count {
                    if processed[i].collectionName == nil || processed[i].collectionName == "Tutti" || processed[i].collectionName?.isEmpty == true {
                        processed[i].collectionName = Self.inferCollection(for: processed[i].canonical_name, discountPct: processed[i].discountPct)
                    }
                }
                self.items = processed
                saveItems()
                if !cols.isEmpty {
                    self.collections = cols
                }
                return
            }
        } catch {
            print("Supabase direct sync note: \(error.localizedDescription), trying gateway...")
        }

        // 2. Fall back to local FastAPI backend
        do {
            async let fetchedItems = APIService.shared.getWishlist()
            async let fetchedCols = APIService.shared.getCollections()

            let (dbItems, dbCols) = try await (fetchedItems, fetchedCols)

            if !dbItems.isEmpty {
                var processed = dbItems
                for i in 0..<processed.count {
                    if processed[i].collectionName == nil || processed[i].collectionName == "Tutti" || processed[i].collectionName?.isEmpty == true {
                        processed[i].collectionName = Self.inferCollection(for: processed[i].canonical_name, discountPct: processed[i].discountPct)
                    }
                }
                self.items = processed
                saveItems()
            }
            if !dbCols.isEmpty {
                self.collections = dbCols
            }
        } catch {
            print("Wishlist sync warning: \(error.localizedDescription)")
            // Fall back to local storage
        }
    }

    // MARK: - Persistence

    func loadItems() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var decoded = try decoder.decode([WishlistItem].self, from: data)

            // Auto-categorize items that don't have a specific collection assigned yet
            for i in 0..<decoded.count {
                if decoded[i].collectionName == nil || decoded[i].collectionName == "Tutti" || decoded[i].collectionName?.isEmpty == true {
                    decoded[i].collectionName = Self.inferCollection(for: decoded[i].canonical_name, discountPct: decoded[i].discountPct)
                }
            }

            self.items = decoded
        } catch {
            print("Errore caricamento wishlist locale: \(error)")
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

    static func inferCollection(for canonicalName: String, discountPct: Double? = nil) -> String {
        let lower = canonicalName.lowercased()
        if lower.contains("garmin") || lower.contains("polar") || lower.contains("suunto") || lower.contains("smartwatch") || lower.contains("coros") || lower.contains("forerunner") || lower.contains("fenix") || lower.contains("apple watch") || lower.contains("cardio") {
            return "Smartwatch & GPS"
        } else if lower.contains("trail") || lower.contains("outdoor") || lower.contains("gtx") || lower.contains("gore-tex") || lower.contains("speedcross") || lower.contains("hiking") || lower.contains("trekking") || lower.contains("vibram") {
            return "Trail & Outdoor"
        } else if (discountPct ?? 0) >= 20 {
            return "Offerte Speciali"
        } else {
            return "Scarpe da Corsa"
        }
    }

    func addToWishlist(product: MatchedProduct, selectedSize: String? = nil, targetPrice: Double? = nil, collection: String? = nil) {
        let bestPrice = product.best_price ?? product.bestOffer?.price ?? 0.0
        let bestOffer = product.bestOffer
        let defaultAlert = targetPrice ?? (bestPrice > 0 ? (bestPrice * 0.90).rounded() : nil)

        let highest = product.highest_price
        let discountPct: Double? = {
            if let h = highest, h > bestPrice && h > 0 {
                return ((h - bestPrice) / h) * 100.0
            }
            return nil
        }()

        let assignedCollection: String = {
            if let c = collection, c != "Tutti", !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return c
            }
            return Self.inferCollection(for: product.canonical_name, discountPct: discountPct)
        }()

        let newItem = WishlistItem(
            canonical_name: product.canonical_name,
            brand: product.brand,
            image_url: product.image_url ?? bestOffer?.image_url,
            initialPrice: highest ?? bestPrice,
            currentBestPrice: bestPrice,
            highestPrice: highest,
            discountPct: discountPct,
            bestStore: bestOffer?.store_name,
            bestStoreUrl: bestOffer?.url,
            offersCount: product.offers.count,
            selectedSize: selectedSize ?? "Standard",
            collectionName: assignedCollection,
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

        // Background sync to Supabase Cloud & Local Gateway
        Task {
            _ = try? await SupabaseManager.shared.upsertWishlistItem(item: newItem)
            _ = try? await APIService.shared.addToWishlist(item: newItem)
        }

        // Check and prompt notification permissions if alerts are enabled
        NotificationManager.shared.checkAuthorization()
        if !NotificationManager.shared.isAuthorized {
            NotificationManager.shared.requestAuthorization()
        }
    }

    func removeFromWishlist(_ canonicalName: String) {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()

        items.removeAll { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }
        saveItems()

        // Background sync to Supabase Cloud & Local Gateway
        Task {
            _ = try? await SupabaseManager.shared.deleteWishlistItem(canonicalName: canonicalName)
            _ = try? await APIService.shared.removeFromWishlist(canonicalName: canonicalName)
        }
    }

    static let defaultCollectionNames = [
        "Tutti",
        "Scarpe da Corsa",
        "Smartwatch & GPS",
        "Trail & Outdoor",
        "Offerte Speciali"
    ]

    func getAvailableCollections() -> [WishlistCollection] {
        var names: [String] = WishlistManager.defaultCollectionNames
        for c in collections {
            if !names.contains(where: { $0.caseInsensitiveCompare(c.name) == .orderedSame }) {
                names.append(c.name)
            }
        }
        for item in items {
            if let cName = item.collectionName, !cName.isEmpty {
                if !names.contains(where: { $0.caseInsensitiveCompare(cName) == .orderedSame }) {
                    names.append(cName)
                }
            }
        }
        return names.map { name in
            WishlistCollection(name: name, item_count: getItemCount(for: name))
        }
    }

    func getItemCount(for collectionName: String) -> Int {
        if collectionName.caseInsensitiveCompare("Tutti") == .orderedSame {
            return items.count
        }
        return items.filter { $0.collectionName?.caseInsensitiveCompare(collectionName) == .orderedSame }.count
    }

    func getThumbnails(for collectionName: String, limit: Int = 4) -> [String] {
        let matching = (collectionName.caseInsensitiveCompare("Tutti") == .orderedSame)
            ? items
            : items.filter { $0.collectionName?.caseInsensitiveCompare(collectionName) == .orderedSame }
        return matching.compactMap { $0.image_url }.prefix(limit).map { $0 }
    }

    func moveItem(canonicalName: String, toCollection: String) {
        guard let index = items.firstIndex(where: { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }) else {
            return
        }
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()

        items[index].collectionName = toCollection
        saveItems()

        let updatedItem = items[index]
        Task {
            _ = try? await APIService.shared.updateItemCollection(canonicalName: canonicalName, collectionName: toCollection)
            _ = try? await SupabaseManager.shared.upsertWishlistItem(item: updatedItem)
        }
    }

    func deleteCollection(name: String) {
        guard name.caseInsensitiveCompare("Tutti") != .orderedSame else { return }
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()

        // Reassign any items in this collection to Tutti
        for i in 0..<items.count {
            if items[i].collectionName?.caseInsensitiveCompare(name) == .orderedSame {
                items[i].collectionName = "Tutti"
            }
        }
        saveItems()

        collections.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        if selectedCollection.caseInsensitiveCompare(name) == .orderedSame {
            selectedCollection = "Tutti"
        }

        Task {
            _ = try? await APIService.shared.deleteCollection(name: name)
            _ = try? await SupabaseManager.shared.deleteCollection(name: name)
        }
    }

    func createCollection(name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !collections.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) {
            collections.append(WishlistCollection(name: cleanName, item_count: 0))
        }
        Task {
            _ = try? await SupabaseManager.shared.createCollection(name: cleanName)
            _ = try? await APIService.shared.createCollection(name: cleanName)
            await syncWithDatabase()
        }
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

        let item = items[index]
        Task {
            _ = try? await APIService.shared.addToWishlist(item: item)
        }

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

        // Sync to backend DB
        let item = items[index]
        Task {
            _ = try? await APIService.shared.addToWishlist(item: item)
        }

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
        lastCheckMessage = "Controllo prezzi sui negozi partner..."

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

                        if items[i].isAlertEnabled {
                            let shouldNotify = (items[i].targetAlertPrice == nil) || (newBest <= items[i].targetAlertPrice!)
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
            lastCheckMessage = "Prezzi aggiornati con il database."
        }
    }
}
