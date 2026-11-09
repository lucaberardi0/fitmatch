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

        // One-time purge of legacy seed items from previous test installs
        if !UserDefaults.standard.bool(forKey: "fitmatch_wishlist_seed_purged_v3") {
            let seedNames: Set<String> = [
                "Nike Air Zoom Pegasus 40",
                "Garmin Forerunner 265",
                "Mizuno Printed Running Tights"
            ]
            self.items.removeAll { seedNames.contains($0.canonical_name) }
            saveItems()
            UserDefaults.standard.set(true, forKey: "fitmatch_wishlist_seed_purged_v3")
        }

        Task {
            await syncWithDatabase()
        }
    }

    // MARK: - Collection Name Helpers

    static func isReservedCollectionName(_ name: String?) -> Bool {
        guard let n = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !n.isEmpty else {
            return true
        }
        return n == "tutti"
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
            var processed = items
            for i in 0..<processed.count {
                if Self.isReservedCollectionName(processed[i].collectionName) {
                    processed[i].collectionName = nil
                }
            }
            if !processed.isEmpty || self.items.isEmpty {
                self.items = processed
                saveItems()
            }

            // Deduplicate remote collections and merge with local
            var mergedMap: [String: WishlistCollection] = [:]
            for c in cols {
                let name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !Self.isReservedCollectionName(name) {
                    mergedMap[name.lowercased()] = WishlistCollection(name: name, item_count: 0)
                }
            }
            for c in self.collections {
                let name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !Self.isReservedCollectionName(name) && mergedMap[name.lowercased()] == nil {
                    mergedMap[name.lowercased()] = WishlistCollection(name: name, item_count: 0)
                }
            }
            self.collections = Array(mergedMap.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            saveCollections()
            return
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
                    if Self.isReservedCollectionName(processed[i].collectionName) {
                        processed[i].collectionName = nil
                    }
                }
                self.items = processed
                saveItems()
            }
            if !dbCols.isEmpty {
                var seen = Set<String>()
                var uniqueCols: [WishlistCollection] = []
                for c in dbCols {
                    let name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !Self.isReservedCollectionName(name) && !seen.contains(name.lowercased()) {
                        seen.insert(name.lowercased())
                        uniqueCols.append(WishlistCollection(name: name, item_count: 0))
                    }
                }
                self.collections = uniqueCols
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
            var seen = Set<String>()
            var unique: [WishlistCollection] = []
            for col in decoded {
                let clean = col.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty, clean.lowercased() != "tutti" else { continue }
                if !seen.contains(clean.lowercased()) {
                    seen.insert(clean.lowercased())
                    unique.append(WishlistCollection(name: clean, item_count: col.item_count))
                }
            }
            self.collections = unique
            saveCollections()
        } catch {
            print("Errore caricamento collezioni locali: \(error)")
        }
    }

    func saveCollections() {
        do {
            var seen = Set<String>()
            var unique: [WishlistCollection] = []
            for col in collections {
                let clean = col.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty, clean.lowercased() != "tutti" else { continue }
                if !seen.contains(clean.lowercased()) {
                    seen.insert(clean.lowercased())
                    unique.append(WishlistCollection(name: clean, item_count: col.item_count))
                }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(unique)
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

            for i in 0..<decoded.count {
                if Self.isReservedCollectionName(decoded[i].collectionName) {
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

        let existingItem = getItem(product.canonical_name)
        let assignedCollection: String? = {
            if let c = collection?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty && c.lowercased() != "tutti" {
                return c
            }
            return existingItem?.collectionName
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
            selectedSize: selectedSize ?? existingItem?.selectedSize ?? "Standard",
            collectionName: assignedCollection,
            targetAlertPrice: defaultAlert,
            isAlertEnabled: true,
            dateAdded: existingItem?.dateAdded ?? Date(),
            lastCheckedDate: Date(),
            lastPriceDrop: existingItem?.lastPriceDrop
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
        var seen = Set<String>()
        var result: [WishlistCollection] = []

        // 1. Collections from collections list
        for col in collections {
            let name = col.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !Self.isReservedCollectionName(name) else { continue }
            if !seen.contains(name.lowercased()) {
                seen.insert(name.lowercased())
                result.append(WishlistCollection(name: name, item_count: getItemCount(for: name)))
            }
        }

        // 2. Also ensure any collection assigned to existing items is visible
        for item in items {
            if let colName = item.collectionName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !Self.isReservedCollectionName(colName),
               !seen.contains(colName.lowercased()) {
                seen.insert(colName.lowercased())
                result.append(WishlistCollection(name: colName, item_count: getItemCount(for: colName)))
            }
        }

        return result
    }

    func getItemCount(for collectionName: String) -> Int {
        let clean = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased() == "tutti" {
            return items.count
        }
        return items.filter {
            guard let c = $0.collectionName?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return c.caseInsensitiveCompare(clean) == .orderedSame
        }.count
    }

    func getThumbnails(for collectionName: String, limit: Int = 1) -> [String] {
        let clean = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = (clean.lowercased() == "tutti")
            ? items
            : items.filter {
                guard let c = $0.collectionName?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
                return c.caseInsensitiveCompare(clean) == .orderedSame
            }
        return matching.compactMap { $0.image_url }.filter { !$0.isEmpty }.prefix(limit).map { $0 }
    }

    func moveItem(canonicalName: String, toCollection: String?) {
        guard let index = items.firstIndex(where: { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }) else {
            return
        }
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()

        let target: String? = {
            guard let col = toCollection?.trimmingCharacters(in: .whitespacesAndNewlines), !col.isEmpty, col.lowercased() != "tutti" else {
                return nil
            }
            return col
        }()

        items[index].collectionName = target
        saveItems()

        // If moved to a new collection, ensure the collection exists in collections list
        if let newCol = target, !collections.contains(where: { $0.name.caseInsensitiveCompare(newCol) == .orderedSame }) {
            collections.append(WishlistCollection(name: newCol, item_count: 1))
            saveCollections()
            Task {
                _ = try? await SupabaseManager.shared.createCollection(name: newCol)
                _ = try? await APIService.shared.createCollection(name: newCol)
            }
        }

        let updatedItem = items[index]
        Task {
            _ = try? await SupabaseManager.shared.upsertWishlistItem(item: updatedItem)
            _ = try? await APIService.shared.updateItemCollection(canonicalName: canonicalName, collectionName: target ?? "Tutti")
        }
    }

    /// Efficient batch update for AddToCollectionSheet
    func setItemsForCollection(collectionName: String, selectedCanonicalNames: Set<String>) {
        let cleanCol = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.isReservedCollectionName(cleanCol) else { return }

        // Ensure collection exists in collections list
        if !collections.contains(where: { $0.name.caseInsensitiveCompare(cleanCol) == .orderedSame }) {
            collections.append(WishlistCollection(name: cleanCol, item_count: 0))
            saveCollections()
            Task {
                _ = try? await SupabaseManager.shared.createCollection(name: cleanCol)
                _ = try? await APIService.shared.createCollection(name: cleanCol)
            }
        }

        var changedItems: [WishlistItem] = []

        for i in 0..<items.count {
            let item = items[i]
            let wasInCollection = item.collectionName?.caseInsensitiveCompare(cleanCol) == .orderedSame
            let isSelected = selectedCanonicalNames.contains(item.canonical_name)

            if isSelected && !wasInCollection {
                items[i].collectionName = cleanCol
                changedItems.append(items[i])
            } else if !isSelected && wasInCollection {
                items[i].collectionName = nil
                changedItems.append(items[i])
            }
        }

        guard !changedItems.isEmpty else { return }
        saveItems()

        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()

        // Sync changed items concurrently
        Task {
            for item in changedItems {
                _ = try? await SupabaseManager.shared.upsertWishlistItem(item: item)
                _ = try? await APIService.shared.updateItemCollection(canonicalName: item.canonical_name, collectionName: item.collectionName ?? "Tutti")
            }
        }
    }

    func renameCollection(oldName: String, newName: String) {
        let cleanOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.isReservedCollectionName(cleanOld), !Self.isReservedCollectionName(cleanNew) else { return }
        guard cleanOld.caseInsensitiveCompare(cleanNew) != .orderedSame else { return }

        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()

        // 1. Update items in memory
        var changedItems: [WishlistItem] = []
        for i in 0..<items.count {
            if items[i].collectionName?.caseInsensitiveCompare(cleanOld) == .orderedSame {
                items[i].collectionName = cleanNew
                changedItems.append(items[i])
            }
        }
        saveItems()

        // 2. Update collections array
        collections.removeAll { $0.name.caseInsensitiveCompare(cleanOld) == .orderedSame }
        if !collections.contains(where: { $0.name.caseInsensitiveCompare(cleanNew) == .orderedSame }) {
            collections.append(WishlistCollection(name: cleanNew, item_count: changedItems.count))
        }
        saveCollections()

        if selectedCollection.caseInsensitiveCompare(cleanOld) == .orderedSame {
            selectedCollection = cleanNew
        }

        // 3. Sync to Supabase & Backend
        Task {
            _ = try? await SupabaseManager.shared.createCollection(name: cleanNew)
            for item in changedItems {
                _ = try? await SupabaseManager.shared.upsertWishlistItem(item: item)
            }
            _ = try? await SupabaseManager.shared.deleteCollection(name: cleanOld)
            _ = try? await APIService.shared.deleteCollection(name: cleanOld)
            _ = try? await APIService.shared.createCollection(name: cleanNew)
        }
    }

    func deleteCollection(name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.isReservedCollectionName(cleanName) else { return }
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()

        // Reassign any items in this collection to nil
        for i in 0..<items.count {
            if items[i].collectionName?.caseInsensitiveCompare(cleanName) == .orderedSame {
                items[i].collectionName = nil
            }
        }
        saveItems()

        collections.removeAll { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }
        saveCollections()

        if selectedCollection.caseInsensitiveCompare(cleanName) == .orderedSame {
            selectedCollection = "Tutti"
        }

        Task {
            _ = try? await SupabaseManager.shared.deleteCollection(name: cleanName)
            _ = try? await APIService.shared.deleteCollection(name: cleanName)
        }
    }

    func createCollection(name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !Self.isReservedCollectionName(cleanName) else { return }
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
                            NotificationManager.shared.sendPriceDropNotification(
                                productTitle: item.canonical_name,
                                oldPrice: oldPrice,
                                newPrice: newBest,
                                storeName: items[i].bestStore ?? "Store Partner",
                                targetPrice: items[i].targetAlertPrice,
                                url: items[i].bestStoreUrl
                            )
                        }

                        let updated = items[i]
                        Task {
                            _ = try? await SupabaseManager.shared.upsertWishlistItem(item: updated)
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
