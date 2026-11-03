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
    private let collectionsFileName = "fitmatch_user_collections.json"

    private var fileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(saveFileName)
    }

    private var collectionsFileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(collectionsFileName)
    }

    init() {
        loadItems()
        loadCollections()
        Task {
            await syncWithDatabase()
        }
    }

    // MARK: - Legacy Category Detection (Ensure NO pre-created categories exist)

    static func isOldDefaultCategory(_ name: String?) -> Bool {
        guard let n = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !n.isEmpty else {
            return true
        }
        let oldDefaults: Set<String> = [
            "tutti",
            "scarpe da corsa",
            "smartwatch & gps",
            "trail & outdoor",
            "offerte speciali",
            "sneakers",
            "running",
            "abbigliamento"
        ]
        return oldDefaults.contains(n)
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
                    if Self.isOldDefaultCategory(processed[i].collectionName) {
                        processed[i].collectionName = nil
                    }
                }
                self.items = processed
                saveItems()
            }
            if !cols.isEmpty {
                let validCols = cols.filter { !Self.isOldDefaultCategory($0.name) }
                self.collections = validCols
                saveCollections()
            }
            if !items.isEmpty {
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
                    if Self.isOldDefaultCategory(processed[i].collectionName) {
                        processed[i].collectionName = nil
                    }
                }
                self.items = processed
                saveItems()
            }
            if !dbCols.isEmpty {
                let validCols = dbCols.filter { !Self.isOldDefaultCategory($0.name) }
                self.collections = validCols
                saveCollections()
            }
        } catch {
            print("Wishlist sync warning: \(error.localizedDescription)")
            // Fall back to local storage
        }
    }

    // MARK: - Persistence

    func loadCollections() {
        guard FileManager.default.fileExists(atPath: collectionsFileURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: collectionsFileURL)
            let decoded = try JSONDecoder().decode([WishlistCollection].self, from: data)
            self.collections = decoded.filter { !Self.isOldDefaultCategory($0.name) }
        } catch {
            print("Errore caricamento collezioni locali: \(error)")
        }
    }

    func saveCollections() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(collections)
            try data.write(to: collectionsFileURL, options: [.atomicWrite, .completeFileProtection])
        } catch {
            print("Errore salvataggio collezioni: \(error)")
        }
    }

    func loadItems() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var decoded = try decoder.decode([WishlistItem].self, from: data)

            // Clean up any old mock categories from previous sessions
            for i in 0..<decoded.count {
                if Self.isOldDefaultCategory(decoded[i].collectionName) {
                    decoded[i].collectionName = nil
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

        let assignedCollection: String? = {
            if let c = collection, !Self.isOldDefaultCategory(c) {
                return c.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
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

    func getAvailableCollections() -> [WishlistCollection] {
        return collections
            .filter { !Self.isOldDefaultCategory($0.name) }
            .map { WishlistCollection(name: $0.name, item_count: getItemCount(for: $0.name)) }
    }

    func getItemCount(for collectionName: String) -> Int {
        if collectionName.caseInsensitiveCompare("Tutti") == .orderedSame {
            return items.count
        }
        return items.filter { $0.collectionName?.caseInsensitiveCompare(collectionName) == .orderedSame }.count
    }

    func getThumbnails(for collectionName: String, limit: Int = 1) -> [String] {
        let matching = (collectionName.caseInsensitiveCompare("Tutti") == .orderedSame)
            ? items
            : items.filter { $0.collectionName?.caseInsensitiveCompare(collectionName) == .orderedSame }
        return matching.compactMap { $0.image_url }.filter { !$0.isEmpty }.prefix(limit).map { $0 }
    }

    func moveItem(canonicalName: String, toCollection: String?) {
        guard let index = items.firstIndex(where: { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }) else {
            return
        }
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()

        let target = (toCollection == nil || toCollection?.caseInsensitiveCompare("Tutti") == .orderedSame) ? nil : toCollection
        items[index].collectionName = target
        saveItems()

        let updatedItem = items[index]
        Task {
            _ = try? await APIService.shared.updateItemCollection(canonicalName: canonicalName, collectionName: target ?? "Tutti")
            _ = try? await SupabaseManager.shared.upsertWishlistItem(item: updatedItem)
        }
    }

    func deleteCollection(name: String) {
        guard !Self.isOldDefaultCategory(name) else { return }
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()

        // Reassign any items in this collection to nil
        for i in 0..<items.count {
            if items[i].collectionName?.caseInsensitiveCompare(name) == .orderedSame {
                items[i].collectionName = nil
            }
        }
        saveItems()

        collections.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        saveCollections()

        if selectedCollection.caseInsensitiveCompare(name) == .orderedSame {
            selectedCollection = "Tutti"
        }

        Task {
            _ = try? await APIService.shared.deleteCollection(name: name)
            _ = try? await SupabaseManager.shared.deleteCollection(name: name)
        }
    }

    func createCollection(name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !Self.isOldDefaultCategory(cleanName) else { return }
        if !collections.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) {
            collections.append(WishlistCollection(name: cleanName, item_count: 0))
            saveCollections()
        }
        Task {
            _ = try? await SupabaseManager.shared.createCollection(name: cleanName)
            _ = try? await APIService.shared.createCollection(name: cleanName)
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
