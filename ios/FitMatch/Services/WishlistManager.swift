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
    @Published var lastLiveSyncDate: Date? = nil
    @Published var lastCheckMessage: String? = nil

    private let saveFileName = "fitmatch_wishlist.json"
    private let collectionsFileName = "fitmatch_user_collections.json"
    private var authObserver: NSObjectProtocol?
    private var mutationGeneration: Int = 0
    private var isSyncing: Bool = false
    private var needsAnotherSync: Bool = false

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

        // One-time purge of legacy seed/default items from old test installs
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

        if !UserDefaults.standard.bool(forKey: "fitmatch_default_collections_purged_v1") {
            let defaultCollectionNames: Set<String> = [
                "scarpe da corsa",
                "smartwatch & gps",
                "trail & outdoor",
                "offerte speciali",
                "sneakers",
                "running",
                "abbigliamento"
            ]
            let usedCollectionNames = Set(items.flatMap { $0.collectionNames.map { $0.lowercased() } })
            self.collections.removeAll { col in
                let lower = col.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return defaultCollectionNames.contains(lower) && !usedCollectionNames.contains(lower)
            }
            saveCollections()
            UserDefaults.standard.set(true, forKey: "fitmatch_default_collections_purged_v1")
        }

        authObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("FitMatchAuthSessionDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.syncWithDatabase(force: true)
            }
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

    // MARK: - Live Database Sync (Supabase Cloud + Live Catalog Hydration)

    func syncWithDatabase(force: Bool = false) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-testSalvatiPopulated") {
            return
        }
        #endif
        if isSyncing {
            if force {
                needsAnotherSync = true
            }
            return
        }
        isSyncing = true
        isSyncingDatabase = true
        defer {
            isSyncing = false
            isSyncingDatabase = false
            if needsAnotherSync {
                needsAnotherSync = false
                Task { [weak self] in
                    await self?.syncWithDatabase()
                }
            }
        }

        await SupabaseManager.shared.ensureUserSession()

        let prefs = UserPreferencesManager.shared.preferences
        let startGen = mutationGeneration
        do {
            async let supaItems = SupabaseManager.shared.fetchWishlistLive(
                shoeSize: prefs.preferredShoeSize,
                apparelSize: prefs.preferredApparelSize
            )
            async let supaCols = SupabaseManager.shared.fetchCollections()

            let (fetchedItems, cols) = try await (supaItems, supaCols)
            guard startGen == mutationGeneration else {
                needsAnotherSync = true
                return
            }

            // Preserve clean order (newest saved first) and sanitize reserved collection names
            var processed = fetchedItems
            for i in 0..<processed.count {
                processed[i].collectionNames = WishlistItem.normalizeCollections(
                    names: processed[i].collectionNames,
                    fallbackSingle: nil
                )
            }
            self.items = processed
            self.lastLiveSyncDate = Date()
            saveItems()

            var remoteMap: [String: WishlistCollection] = [:]
            for c in cols {
                let name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !Self.isReservedCollectionName(name) {
                    remoteMap[name.lowercased()] = WishlistCollection(name: name, item_count: 0)
                }
            }
            self.collections = Array(remoteMap.values).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            saveCollections()
        } catch {
            // Keep local user-scoped cache when offline
            print("Supabase live wishlist sync note: \(error.localizedDescription)")
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
                if seen.insert(clean.lowercased()).inserted {
                    unique.append(WishlistCollection(name: clean, item_count: col.item_count))
                }
            }
            self.collections = unique
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
                if seen.insert(clean.lowercased()).inserted {
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
                decoded[i].collectionNames = WishlistItem.normalizeCollections(
                    names: decoded[i].collectionNames,
                    fallbackSingle: nil
                )
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

    // MARK: - Queries & Live Summary Stats

    func isFavorite(_ canonicalName: String) -> Bool {
        items.contains { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }
    }

    func getItem(_ canonicalName: String) -> WishlistItem? {
        items.first { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }
    }

    var priceDropsCount: Int {
        items.filter { $0.hasDroppedSinceSaved || $0.isTargetReachedEffective }.count
    }

    var targetReachedCount: Int {
        items.filter { $0.isTargetReachedEffective }.count
    }

    var totalDroppedSavingsEur: Double {
        items.reduce(0.0) { $0 + $1.droppedAmountSinceSaved }
    }

    // MARK: - Mutations

    func resetLocalOnly() {
        mutationGeneration += 1
        items.removeAll()
        collections.removeAll()
        selectedCollection = "Tutti"
        lastLiveSyncDate = nil
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: collectionsFileURL)
    }

    func toggleFavorite(product: MatchedProduct, selectedSize: String? = nil, targetPrice: Double? = nil) {
        ShopHaptics.impact(.medium)

        if isFavorite(product.canonical_name) {
            removeFromWishlist(product.canonical_name)
        } else {
            addToWishlist(product: product, selectedSize: selectedSize, targetPrice: targetPrice)
        }
    }

    func addToWishlist(
        product: MatchedProduct,
        selectedSize: String? = nil,
        targetPrice: Double? = nil,
        isAlertEnabled: Bool = true,
        collection: String? = nil
    ) {
        let bestOffer = product.bestOffer ?? product.offers.first
        let bestPrice = product.best_price ?? bestOffer?.price ?? 0.0
        let existingItem = getItem(product.canonical_name)

        // Resolve real catalog product_id (never store canonical_name as a fake product_id)
        let candidatePid = bestOffer?.product_id ?? product.offers.first(where: { ($0.product_id ?? "").isEmpty == false })?.product_id ?? product.id_val
        let resolvedPid: String? = {
            guard let pid = candidatePid?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !pid.isEmpty,
                  pid.caseInsensitiveCompare(product.canonical_name) != .orderedSame else {
                return existingItem?.productId
            }
            return pid
        }()

        let highest = bestOffer?.original_price ?? product.highest_price
        let discountPct: Double? = {
            if let d = bestOffer?.discount_pct, d >= 1.0 { return d }
            if let h = highest, h > bestPrice && h > 0 {
                return ((h - bestPrice) / h) * 100.0
            }
            return nil
        }()

        var mergedCols = existingItem?.collectionNames ?? []
        if let c = collection?.trimmingCharacters(in: .whitespacesAndNewlines),
           !Self.isReservedCollectionName(c),
           !mergedCols.contains(where: { $0.caseInsensitiveCompare(c) == .orderedSame }) {
            mergedCols.append(c)
        }

        let distinctStores = max(1, Set(product.offers.map { $0.store_id.lowercased() }).count)
        let cleanSize = WishlistItem.normalizeExplicitSize(selectedSize) ?? existingItem?.selectedSize
        let savedPriceRef = existingItem?.savedPrice ?? bestPrice
        let resolvedTarget = targetPrice ?? existingItem?.targetAlertPrice
        let allSizes = product.allAvailableSizes.isEmpty ? (existingItem?.availableSizes ?? []) : product.allAvailableSizes

        let newItem = WishlistItem(
            productId: resolvedPid,
            canonical_name: product.canonical_name,
            brand: product.brand ?? bestOffer?.brand ?? existingItem?.brand,
            category: product.category ?? existingItem?.category,
            gender: product.gender ?? existingItem?.gender,
            image_url: product.image_url ?? bestOffer?.image_url ?? existingItem?.image_url,
            galleryImages: product.gallery_images ?? bestOffer?.gallery_images ?? existingItem?.galleryImages,
            initialPrice: highest ?? savedPriceRef,
            savedPrice: savedPriceRef,
            currentBestPrice: bestPrice,
            highestPrice: highest,
            discountPct: discountPct,
            bestStoreId: bestOffer?.store_id ?? existingItem?.bestStoreId,
            bestStore: bestOffer?.store_name ?? existingItem?.bestStore,
            bestStoreUrl: bestOffer?.url ?? existingItem?.bestStoreUrl,
            offersCount: max(product.offers.count, existingItem?.offersCount ?? 1),
            storeCount: max(distinctStores, existingItem?.storeCount ?? 1),
            selectedSize: cleanSize,
            collectionName: mergedCols.first,
            collectionNames: mergedCols,
            targetAlertPrice: resolvedTarget,
            isAlertEnabled: isAlertEnabled,
            dateAdded: existingItem?.dateAdded ?? Date(),
            lastCheckedDate: Date(),
            lastPriceDrop: existingItem?.lastPriceDrop,
            isInStock: bestOffer?.in_stock ?? true,
            availableSizes: allSizes,
            monitoredSize: cleanSize ?? existingItem?.monitoredSize,
            isMonitoredSizeAvailable: existingItem?.isMonitoredSizeAvailable,
            shippingCost: bestOffer?.shipping_cost ?? existingItem?.shippingCost,
            freeShippingThreshold: bestOffer?.free_shipping_threshold ?? existingItem?.freeShippingThreshold,
            courier: bestOffer?.courier ?? existingItem?.courier,
            hasFreeShipping: bestOffer?.is_free_shipping ?? existingItem?.hasFreeShipping,
            lastVerifiedAt: bestOffer?.last_checked_at ?? existingItem?.lastVerifiedAt,
            marketMaxPrice: product.highest_price ?? existingItem?.marketMaxPrice,
            crossStoreSavings: product.cross_store_savings ?? existingItem?.crossStoreSavings,
            histMinPrice: existingItem?.histMinPrice,
            histAvgPrice: existingItem?.histAvgPrice,
            isAllTimeLow: existingItem?.isAllTimeLow ?? false,
            priceChangeSinceSaved: savedPriceRef > 0 && bestPrice > 0 ? bestPrice - savedPriceRef : 0.0,
            targetReached: isAlertEnabled && (resolvedTarget ?? 0) > 0 && bestPrice > 0 && bestPrice <= (resolvedTarget ?? 0)
        )

        mutationGeneration += 1
        items.removeAll { $0.canonical_name.caseInsensitiveCompare(product.canonical_name) == .orderedSame }
        items.insert(newItem, at: 0)
        saveItems()

        Task {
            await SupabaseManager.shared.ensureUserSession()
            _ = try? await SupabaseManager.shared.upsertWishlistItem(item: newItem)
            // Hydrate live multi-store stats right after saving so badges appear immediately
            await self.syncWithDatabase()
        }

        if isAlertEnabled {
            NotificationManager.shared.checkAuthorization()
            if !NotificationManager.shared.isAuthorized {
                NotificationManager.shared.requestAuthorization()
            }
        }
    }

    /// Restores a previously removed item (used by Undo toast in WishlistView).
    func restoreItem(_ item: WishlistItem, at index: Int? = nil) {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()

        mutationGeneration += 1
        items.removeAll { $0.canonical_name.caseInsensitiveCompare(item.canonical_name) == .orderedSame }
        let safeIdx = min(max(index ?? 0, 0), items.count)
        items.insert(item, at: safeIdx)
        saveItems()

        Task {
            await SupabaseManager.shared.ensureUserSession()
            _ = try? await SupabaseManager.shared.upsertWishlistItem(item: item)
        }
    }

    @discardableResult
    func removeFromWishlist(_ canonicalName: String) -> (item: WishlistItem, index: Int)? {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()

        guard let idx = items.firstIndex(where: { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }) else {
            return nil
        }
        let removed = items[idx]
        mutationGeneration += 1
        items.remove(at: idx)
        saveItems()

        Task {
            await SupabaseManager.shared.ensureUserSession()
            _ = try? await SupabaseManager.shared.deleteWishlistItem(canonicalName: canonicalName)
        }
        return (removed, idx)
    }

    // MARK: - Collections Queries & Mutations (Multi-Collection Aware)

    func getAvailableCollections() -> [WishlistCollection] {
        var seen = Set<String>()
        var result: [WishlistCollection] = []

        for col in collections {
            let name = col.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !Self.isReservedCollectionName(name) else { continue }
            if seen.insert(name.lowercased()).inserted {
                result.append(WishlistCollection(name: name, item_count: getItemCount(for: name)))
            }
        }

        for item in items {
            for colName in item.collectionNames {
                let clean = colName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !Self.isReservedCollectionName(clean) else { continue }
                if seen.insert(clean.lowercased()).inserted {
                    result.append(WishlistCollection(name: clean, item_count: getItemCount(for: clean)))
                }
            }
        }

        return result
    }

    func getItemCount(for collectionName: String) -> Int {
        let clean = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased() == "tutti" {
            return items.count
        }
        return items.filter { $0.belongsToCollection(clean) }.count
    }

    func getThumbnails(for collectionName: String, limit: Int = 4) -> [String] {
        let clean = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = (clean.lowercased() == "tutti")
            ? items
            : items.filter { $0.belongsToCollection(clean) }
        return matching.compactMap { $0.image_url }.filter { !$0.isEmpty }.prefix(limit).map { $0 }
    }

    /// Toggles membership of an item in a single collection without removing its other collections.
    func toggleCollection(_ collectionName: String, for canonicalName: String) {
        let cleanCol = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.isReservedCollectionName(cleanCol),
              let index = items.firstIndex(where: { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }) else {
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        mutationGeneration += 1

        var cols = items[index].collectionNames
        if let existingIdx = cols.firstIndex(where: { $0.caseInsensitiveCompare(cleanCol) == .orderedSame }) {
            cols.remove(at: existingIdx)
        } else {
            cols.append(cleanCol)
            ensureCollectionExistsLocallyAndRemotely(cleanCol)
        }
        items[index].collectionNames = cols
        saveItems()

        let updatedItem = items[index]
        Task {
            await SupabaseManager.shared.ensureUserSession()
            _ = try? await SupabaseManager.shared.upsertWishlistItem(item: updatedItem)
        }
    }

    /// Replaces the full list of collections assigned to an item.
    func setCollections(_ collectionNames: [String], for canonicalName: String) {
        guard let index = items.firstIndex(where: { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }) else {
            return
        }
        let cleaned = WishlistItem.normalizeCollections(names: collectionNames, fallbackSingle: nil)
        mutationGeneration += 1
        items[index].collectionNames = cleaned
        saveItems()

        for col in cleaned {
            ensureCollectionExistsLocallyAndRemotely(col)
        }

        let updatedItem = items[index]
        Task {
            await SupabaseManager.shared.ensureUserSession()
            _ = try? await SupabaseManager.shared.upsertWishlistItem(item: updatedItem)
        }
    }

    /// Removes an item from one specific collection (keeping any other collections it belongs to).
    func removeItem(_ canonicalName: String, fromCollection collectionName: String) {
        let cleanCol = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.isReservedCollectionName(cleanCol),
              let index = items.firstIndex(where: { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }) else {
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        mutationGeneration += 1
        items[index].collectionNames.removeAll { $0.caseInsensitiveCompare(cleanCol) == .orderedSame }
        saveItems()

        let updatedItem = items[index]
        Task {
            await SupabaseManager.shared.ensureUserSession()
            _ = try? await SupabaseManager.shared.upsertWishlistItem(item: updatedItem)
        }
    }

    /// Backwards-compatible helper: assigns collection (or clears all collections if `nil`).
    func moveItem(canonicalName: String, toCollection: String?) {
        guard let index = items.firstIndex(where: { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }) else {
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        mutationGeneration += 1
        if let col = toCollection?.trimmingCharacters(in: .whitespacesAndNewlines),
           !Self.isReservedCollectionName(col) {
            if !items[index].belongsToCollection(col) {
                items[index].collectionNames.append(col)
            }
            ensureCollectionExistsLocallyAndRemotely(col)
        } else {
            items[index].collectionNames = []
        }
        saveItems()

        let updatedItem = items[index]
        Task {
            await SupabaseManager.shared.ensureUserSession()
            _ = try? await SupabaseManager.shared.upsertWishlistItem(item: updatedItem)
        }
    }

    /// Multi-collection safe batch update for AddToCollectionSheet:
    /// adds `collectionName` to selected items without stripping their other collections,
    /// and removes ONLY `collectionName` from deselected items.
    func setItemsForCollection(collectionName: String, selectedCanonicalNames: Set<String>) {
        let cleanCol = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.isReservedCollectionName(cleanCol) else { return }

        ensureCollectionExistsLocallyAndRemotely(cleanCol)

        var changedItems: [WishlistItem] = []

        for i in 0..<items.count {
            let wasInCollection = items[i].belongsToCollection(cleanCol)
            let isSelected = selectedCanonicalNames.contains(items[i].canonical_name)

            if isSelected && !wasInCollection {
                items[i].collectionNames.append(cleanCol)
                changedItems.append(items[i])
            } else if !isSelected && wasInCollection {
                items[i].collectionNames.removeAll { $0.caseInsensitiveCompare(cleanCol) == .orderedSame }
                changedItems.append(items[i])
            }
        }

        guard !changedItems.isEmpty else { return }
        mutationGeneration += 1
        saveItems()

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            await SupabaseManager.shared.ensureUserSession()
            for item in changedItems {
                _ = try? await SupabaseManager.shared.upsertWishlistItem(item: item)
            }
        }
    }

    func renameCollection(oldName: String, newName: String) {
        let cleanOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.isReservedCollectionName(cleanOld), !Self.isReservedCollectionName(cleanNew) else { return }
        guard cleanOld.caseInsensitiveCompare(cleanNew) != .orderedSame else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        mutationGeneration += 1

        var affectedCount = 0
        for i in 0..<items.count {
            if items[i].belongsToCollection(cleanOld) {
                var mapped = items[i].collectionNames.map { col in
                    col.caseInsensitiveCompare(cleanOld) == .orderedSame ? cleanNew : col
                }
                mapped = WishlistItem.normalizeCollections(names: mapped, fallbackSingle: nil)
                items[i].collectionNames = mapped
                affectedCount += 1
            }
        }
        saveItems()

        collections.removeAll { $0.name.caseInsensitiveCompare(cleanOld) == .orderedSame }
        if !collections.contains(where: { $0.name.caseInsensitiveCompare(cleanNew) == .orderedSame }) {
            collections.append(WishlistCollection(name: cleanNew, item_count: affectedCount))
            collections.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        saveCollections()

        if selectedCollection.caseInsensitiveCompare(cleanOld) == .orderedSame {
            selectedCollection = cleanNew
        }

        Task {
            await SupabaseManager.shared.ensureUserSession()
            _ = try? await SupabaseManager.shared.renameCollection(oldName: cleanOld, newName: cleanNew)
        }
    }

    /// Deletes a collection and returns the canonical names of items that belonged to it (for Undo support).
    @discardableResult
    func deleteCollection(name: String) -> [String] {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.isReservedCollectionName(cleanName) else { return [] }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        mutationGeneration += 1

        var affected: [String] = []
        for i in 0..<items.count {
            if items[i].belongsToCollection(cleanName) {
                affected.append(items[i].canonical_name)
                items[i].collectionNames.removeAll { $0.caseInsensitiveCompare(cleanName) == .orderedSame }
            }
        }
        saveItems()

        collections.removeAll { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }
        saveCollections()

        if selectedCollection.caseInsensitiveCompare(cleanName) == .orderedSame {
            selectedCollection = "Tutti"
        }

        Task {
            await SupabaseManager.shared.ensureUserSession()
            _ = try? await SupabaseManager.shared.deleteCollection(name: cleanName)
        }
        return affected
    }

    func restoreCollection(name: String, itemCanonicalNames: [String]) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.isReservedCollectionName(cleanName) else { return }

        createCollection(name: cleanName)
        let targetSet = Set(itemCanonicalNames)
        if !targetSet.isEmpty {
            setItemsForCollection(collectionName: cleanName, selectedCanonicalNames: targetSet)
        }
    }

    func createCollection(name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !Self.isReservedCollectionName(cleanName) else { return }
        ensureCollectionExistsLocallyAndRemotely(cleanName)
    }

    private func ensureCollectionExistsLocallyAndRemotely(_ cleanName: String) {
        guard !collections.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) else {
            return
        }
        mutationGeneration += 1
        collections.append(WishlistCollection(name: cleanName, item_count: 0))
        collections.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveCollections()

        Task {
            await SupabaseManager.shared.ensureUserSession()
            _ = try? await SupabaseManager.shared.createCollection(name: cleanName)
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

        let cleanSize = WishlistItem.normalizeExplicitSize(selectedSize)
        mutationGeneration += 1
        items[index].isAlertEnabled = isEnabled
        items[index].targetAlertPrice = targetPrice
        items[index].selectedSize = cleanSize
        if let sz = cleanSize {
            items[index].monitoredSize = sz
        }
        items[index].targetReached = isEnabled
            && (targetPrice ?? 0) > 0
            && items[index].currentBestPrice > 0
            && items[index].currentBestPrice <= (targetPrice ?? 0) + 0.01
        saveItems()

        let item = items[index]
        Task {
            await SupabaseManager.shared.ensureUserSession()
            _ = try? await SupabaseManager.shared.upsertWishlistItem(item: item)
            await self.syncWithDatabase()
        }

        if isEnabled && !NotificationManager.shared.isAuthorized {
            NotificationManager.shared.requestAuthorization()
        }
    }

    // MARK: - Live Price Refresh (delegates to fast single-RPC live sync)

    func refreshAllPrices(apiService: APIService) async {
        guard !items.isEmpty else { return }
        isCheckingPrices = true
        lastCheckMessage = "Aggiornamento prezzi live..."
        await syncWithDatabase(force: true)
        isCheckingPrices = false
        let drops = priceDropsCount
        lastCheckMessage = drops > 0
            ? "Trovati \(drops) cali di prezzo!"
            : "Prezzi aggiornati in tempo reale."
    }

    #if DEBUG
    func simulatePriceDrop(for canonicalName: String, dropAmount: Double = 25.0) {
        guard let index = items.firstIndex(where: { $0.canonical_name.caseInsensitiveCompare(canonicalName) == .orderedSame }) else {
            return
        }

        let oldPrice = items[index].currentBestPrice
        let newPrice = max(19.0, oldPrice - dropAmount)
        let store = items[index].bestStore ?? "Mister Running"

        mutationGeneration += 1
        items[index].currentBestPrice = newPrice
        items[index].lastPriceDrop = dropAmount
        items[index].priceChangeSinceSaved = newPrice - items[index].savedPrice
        items[index].lastCheckedDate = Date()
        saveItems()

        let item = items[index]
        Task {
            await SupabaseManager.shared.ensureUserSession()
            _ = try? await SupabaseManager.shared.upsertWishlistItem(item: item)
        }

        NotificationManager.shared.sendPriceDropNotification(
            productTitle: items[index].canonical_name,
            oldPrice: oldPrice,
            newPrice: newPrice,
            storeName: store,
            targetPrice: items[index].targetAlertPrice,
            url: items[index].bestStoreUrl
        )
    }
    #endif
}
