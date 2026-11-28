import Foundation

struct WishlistResponse: Codable {
    let items: [WishlistItem]
    let count: Int
}

struct CollectionsResponse: Codable {
    let collections: [WishlistCollection]
}

struct WishlistCollection: Identifiable, Codable, Hashable {
    var id: String { name }
    let name: String
    let item_count: Int
}

// MARK: - Live RPC Row Decoder (`get_wishlist_live_v1`)

struct WishlistLiveRow: Codable {
    let wishlist_id: String?
    let product_id: String?
    let canonical_name: String
    let brand: String?
    let category: String?
    let gender: String?
    let collection_name: String?
    let collection_names: [String]?
    let selected_size: String?
    let target_alert_price: Double?
    let is_alert_enabled: Bool?
    let saved_price: Double?
    let snapshot_price: Double?
    let snapshot_original_price: Double?
    let live_best_price: Double?
    let live_original_price: Double?
    let live_discount_pct: Double?
    let live_store_id: String?
    let live_store_name: String?
    let live_product_url: String?
    let live_image_url: String?
    let live_gallery_images: [String]?
    let live_shipping_cost: Double?
    let live_free_shipping_threshold: Double?
    let live_courier: String?
    let live_has_free_shipping: Bool?
    let live_last_checked_at: String?
    let live_offers_count: Int?
    let live_store_count: Int?
    let is_in_stock: Bool?
    let live_available_sizes: [String]?
    let monitored_size: String?
    let is_monitored_size_available: Bool?
    let market_max_price: Double?
    let cross_store_savings: Double?
    let hist_min_price: Double?
    let hist_avg_price: Double?
    let is_all_time_low: Bool?
    let price_change_since_saved: Double?
    let target_reached: Bool?
    let created_at: String?
    let updated_at: String?

    func toWishlistItem() -> WishlistItem {
        let bestPrice = live_best_price ?? snapshot_price ?? 0.0
        let saved = saved_price ?? snapshot_price ?? bestPrice
        let origPrice = live_original_price ?? snapshot_original_price
        let cleanCols = WishlistItem.normalizeCollections(
            names: collection_names,
            fallbackSingle: collection_name
        )
        let parsedCreated = WishlistDateParser.parse(created_at) ?? Date()
        let parsedChecked = WishlistDateParser.parse(live_last_checked_at)
            ?? WishlistDateParser.parse(updated_at)
            ?? Date()
        let changeSinceSaved = price_change_since_saved ?? (saved > 0 && bestPrice > 0 ? bestPrice - saved : 0.0)
        let dropSinceSaved: Double? = changeSinceSaved <= -0.50 ? abs(changeSinceSaved) : nil

        let cleanSelectedSize = WishlistItem.normalizeExplicitSize(selected_size)
        let effDiscount: Double? = {
            if let d = live_discount_pct, d >= 1.0 { return d }
            if let orig = origPrice, orig > bestPrice && orig > 0 {
                return ((orig - bestPrice) / orig) * 100.0
            }
            return nil
        }()

        return WishlistItem(
            productId: product_id,
            canonical_name: canonical_name,
            brand: brand,
            category: category,
            gender: gender,
            image_url: live_image_url,
            galleryImages: live_gallery_images,
            initialPrice: origPrice ?? saved,
            savedPrice: saved,
            currentBestPrice: bestPrice,
            highestPrice: origPrice,
            discountPct: effDiscount,
            bestStoreId: live_store_id,
            bestStore: live_store_name,
            bestStoreUrl: live_product_url,
            offersCount: max(live_offers_count ?? 0, (is_in_stock ?? true) ? 1 : 0),
            storeCount: live_store_count ?? ((is_in_stock ?? true) ? 1 : 0),
            selectedSize: cleanSelectedSize,
            collectionName: cleanCols.first,
            collectionNames: cleanCols,
            targetAlertPrice: target_alert_price,
            isAlertEnabled: is_alert_enabled ?? true,
            dateAdded: parsedCreated,
            lastCheckedDate: parsedChecked,
            lastPriceDrop: dropSinceSaved,
            isInStock: is_in_stock ?? true,
            availableSizes: live_available_sizes ?? [],
            monitoredSize: monitored_size,
            isMonitoredSizeAvailable: is_monitored_size_available,
            shippingCost: live_shipping_cost,
            freeShippingThreshold: live_free_shipping_threshold,
            courier: live_courier,
            hasFreeShipping: live_has_free_shipping,
            lastVerifiedAt: live_last_checked_at,
            marketMaxPrice: market_max_price,
            crossStoreSavings: cross_store_savings,
            histMinPrice: hist_min_price,
            histAvgPrice: hist_avg_price,
            isAllTimeLow: is_all_time_low ?? false,
            priceChangeSinceSaved: changeSinceSaved,
            targetReached: target_reached ?? false
        )
    }
}

enum WishlistDateParser {
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let str = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty else {
            return nil
        }
        if let d = isoFrac.date(from: str) { return d }
        if let d = isoPlain.date(from: str) { return d }
        let normalized = str.replacingOccurrences(of: " ", with: "T")
        if let d = isoFrac.date(from: normalized) { return d }
        if let d = isoPlain.date(from: normalized) { return d }
        return nil
    }
}

// MARK: - Wishlist Item Model

struct WishlistItem: Identifiable, Codable, Hashable {
    var id: String { canonical_name }
    var productId: String?
    let canonical_name: String
    var brand: String?
    var category: String?
    var gender: String?
    var image_url: String?
    var galleryImages: [String]?
    /// Legacy reference price (list/original price or saved price)
    var initialPrice: Double
    /// True best price at the moment the user saved this item
    var savedPrice: Double
    var currentBestPrice: Double
    var highestPrice: Double?
    var discountPct: Double?
    var bestStoreId: String?
    var bestStore: String?
    var bestStoreUrl: String?
    var offersCount: Int
    var storeCount: Int
    var selectedSize: String?
    var collectionNames: [String]
    var collectionName: String? {
        get { collectionNames.first }
        set {
            let cleaned = Self.normalizeCollections(names: nil, fallbackSingle: newValue)
            collectionNames = cleaned
        }
    }
    var targetAlertPrice: Double?
    var isAlertEnabled: Bool
    var dateAdded: Date
    var lastCheckedDate: Date
    var lastPriceDrop: Double?

    // Live comparator & availability metadata (hydrated via `get_wishlist_live_v1`)
    var isInStock: Bool
    var availableSizes: [String]
    var monitoredSize: String?
    var isMonitoredSizeAvailable: Bool?
    var shippingCost: Double?
    var freeShippingThreshold: Double?
    var courier: String?
    var hasFreeShipping: Bool?
    var lastVerifiedAt: String?
    var marketMaxPrice: Double?
    var crossStoreSavings: Double?
    var histMinPrice: Double?
    var histAvgPrice: Double?
    var isAllTimeLow: Bool
    var priceChangeSinceSaved: Double
    var targetReached: Bool

    enum CodingKeys: String, CodingKey {
        case productId, product_id
        case canonical_name
        case brand
        case category
        case gender
        case image_url
        case galleryImages, gallery_images
        case initialPrice, savedPrice, saved_price
        case currentBestPrice, highestPrice, discountPct
        case original_price, current_price, discount_pct
        case bestStoreId, store_id
        case bestStore, bestStoreUrl, store_name, product_url
        case offersCount, storeCount
        case selectedSize, selected_size
        case collectionName, collection_name
        case collectionNames, collection_names
        case targetAlertPrice, target_alert_price
        case isAlertEnabled, is_alert_enabled
        case dateAdded, created_at
        case lastCheckedDate, updated_at
        case lastPriceDrop
        case isInStock, availableSizes, monitoredSize, isMonitoredSizeAvailable
        case shippingCost, freeShippingThreshold, courier, hasFreeShipping, lastVerifiedAt
        case marketMaxPrice, crossStoreSavings, histMinPrice, histAvgPrice
        case isAllTimeLow, priceChangeSinceSaved, targetReached
    }

    static func normalizeExplicitSize(_ raw: String?) -> String? {
        guard let clean = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !clean.isEmpty else {
            return nil
        }
        let low = clean.lowercased()
        let ignored: Set<String> = ["standard", "tutte", "tutte le taglie", "all", "none", "default"]
        return ignored.contains(low) ? nil : clean
    }

    static func normalizeCollections(names: [String]?, fallbackSingle: String?) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let rawList: [String] = {
            if let names, !names.isEmpty { return names }
            if let single = fallbackSingle { return [single] }
            return []
        }()
        for entry in rawList {
            let clean = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.lowercased() != "tutti" else { continue }
            let key = clean.lowercased()
            if seen.insert(key).inserted {
                result.append(clean)
            }
        }
        return result
    }

    init(
        productId: String? = nil,
        canonical_name: String,
        brand: String? = nil,
        category: String? = nil,
        gender: String? = nil,
        image_url: String? = nil,
        galleryImages: [String]? = nil,
        initialPrice: Double,
        savedPrice: Double? = nil,
        currentBestPrice: Double,
        highestPrice: Double? = nil,
        discountPct: Double? = nil,
        bestStoreId: String? = nil,
        bestStore: String? = nil,
        bestStoreUrl: String? = nil,
        offersCount: Int = 1,
        storeCount: Int? = nil,
        selectedSize: String? = nil,
        collectionName: String? = nil,
        collectionNames: [String]? = nil,
        targetAlertPrice: Double? = nil,
        isAlertEnabled: Bool = true,
        dateAdded: Date = Date(),
        lastCheckedDate: Date = Date(),
        lastPriceDrop: Double? = nil,
        isInStock: Bool = true,
        availableSizes: [String] = [],
        monitoredSize: String? = nil,
        isMonitoredSizeAvailable: Bool? = nil,
        shippingCost: Double? = nil,
        freeShippingThreshold: Double? = nil,
        courier: String? = nil,
        hasFreeShipping: Bool? = nil,
        lastVerifiedAt: String? = nil,
        marketMaxPrice: Double? = nil,
        crossStoreSavings: Double? = nil,
        histMinPrice: Double? = nil,
        histAvgPrice: Double? = nil,
        isAllTimeLow: Bool = false,
        priceChangeSinceSaved: Double = 0.0,
        targetReached: Bool = false
    ) {
        self.productId = productId
        self.canonical_name = canonical_name
        self.brand = brand
        self.category = category
        self.gender = gender
        self.image_url = image_url
        self.galleryImages = galleryImages
        self.initialPrice = initialPrice
        self.savedPrice = savedPrice ?? currentBestPrice
        self.currentBestPrice = currentBestPrice
        self.highestPrice = highestPrice
        self.discountPct = discountPct
        self.bestStoreId = bestStoreId
        self.bestStore = bestStore
        self.bestStoreUrl = bestStoreUrl
        self.offersCount = offersCount
        self.storeCount = storeCount ?? max(offersCount > 0 ? 1 : 0, 0)
        self.selectedSize = Self.normalizeExplicitSize(selectedSize)
        self.collectionNames = Self.normalizeCollections(names: collectionNames, fallbackSingle: collectionName)
        self.targetAlertPrice = targetAlertPrice
        self.isAlertEnabled = isAlertEnabled
        self.dateAdded = dateAdded
        self.lastCheckedDate = lastCheckedDate
        self.lastPriceDrop = lastPriceDrop
        self.isInStock = isInStock
        self.availableSizes = availableSizes
        self.monitoredSize = monitoredSize
        self.isMonitoredSizeAvailable = isMonitoredSizeAvailable
        self.shippingCost = shippingCost
        self.freeShippingThreshold = freeShippingThreshold
        self.courier = courier
        self.hasFreeShipping = hasFreeShipping
        self.lastVerifiedAt = lastVerifiedAt
        self.marketMaxPrice = marketMaxPrice
        self.crossStoreSavings = crossStoreSavings
        self.histMinPrice = histMinPrice
        self.histAvgPrice = histAvgPrice
        self.isAllTimeLow = isAllTimeLow
        self.priceChangeSinceSaved = priceChangeSinceSaved
        self.targetReached = targetReached
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.productId = try container.decodeIfPresent(String.self, forKey: .productId)
            ?? container.decodeIfPresent(String.self, forKey: .product_id)
        self.canonical_name = try container.decode(String.self, forKey: .canonical_name)
        self.brand = try container.decodeIfPresent(String.self, forKey: .brand)
        self.category = try container.decodeIfPresent(String.self, forKey: .category)
        self.gender = try container.decodeIfPresent(String.self, forKey: .gender)
        self.image_url = try container.decodeIfPresent(String.self, forKey: .image_url)
        self.galleryImages = try container.decodeIfPresent([String].self, forKey: .galleryImages)
            ?? container.decodeIfPresent([String].self, forKey: .gallery_images)

        let currPrice = try container.decodeIfPresent(Double.self, forKey: .currentBestPrice)
            ?? container.decodeIfPresent(Double.self, forKey: .current_price)
            ?? 0.0
        self.currentBestPrice = currPrice

        let origPrice = try container.decodeIfPresent(Double.self, forKey: .initialPrice)
            ?? container.decodeIfPresent(Double.self, forKey: .original_price)
            ?? currPrice
        self.initialPrice = origPrice

        self.savedPrice = try container.decodeIfPresent(Double.self, forKey: .savedPrice)
            ?? container.decodeIfPresent(Double.self, forKey: .saved_price)
            ?? currPrice

        self.highestPrice = try container.decodeIfPresent(Double.self, forKey: .highestPrice)
            ?? container.decodeIfPresent(Double.self, forKey: .original_price)

        var disc = try container.decodeIfPresent(Double.self, forKey: .discountPct)
            ?? container.decodeIfPresent(Double.self, forKey: .discount_pct)
        if (disc == nil || (disc ?? 0) <= 0), let h = self.highestPrice, h > currPrice && h > 0 {
            disc = ((h - currPrice) / h) * 100.0
        } else if (disc == nil || (disc ?? 0) <= 0), origPrice > currPrice && origPrice > 0 {
            disc = ((origPrice - currPrice) / origPrice) * 100.0
        }
        self.discountPct = (disc ?? 0) > 0 ? disc : nil

        self.bestStoreId = try container.decodeIfPresent(String.self, forKey: .bestStoreId)
            ?? container.decodeIfPresent(String.self, forKey: .store_id)
        self.bestStore = try container.decodeIfPresent(String.self, forKey: .bestStore)
            ?? container.decodeIfPresent(String.self, forKey: .store_name)
        self.bestStoreUrl = try container.decodeIfPresent(String.self, forKey: .bestStoreUrl)
            ?? container.decodeIfPresent(String.self, forKey: .product_url)

        let decodedOffers = try container.decodeIfPresent(Int.self, forKey: .offersCount) ?? 1
        self.offersCount = decodedOffers
        self.storeCount = try container.decodeIfPresent(Int.self, forKey: .storeCount) ?? max(decodedOffers > 0 ? 1 : 0, 0)

        let rawSize = try container.decodeIfPresent(String.self, forKey: .selectedSize)
            ?? container.decodeIfPresent(String.self, forKey: .selected_size)
        self.selectedSize = Self.normalizeExplicitSize(rawSize)

        let rawColArray = try container.decodeIfPresent([String].self, forKey: .collectionNames)
            ?? container.decodeIfPresent([String].self, forKey: .collection_names)
        let rawColSingle = try container.decodeIfPresent(String.self, forKey: .collectionName)
            ?? container.decodeIfPresent(String.self, forKey: .collection_name)
        self.collectionNames = Self.normalizeCollections(names: rawColArray, fallbackSingle: rawColSingle)

        self.targetAlertPrice = try container.decodeIfPresent(Double.self, forKey: .targetAlertPrice)
            ?? container.decodeIfPresent(Double.self, forKey: .target_alert_price)
        self.isAlertEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAlertEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .is_alert_enabled)
            ?? true

        if let d = try? container.decodeIfPresent(Date.self, forKey: .dateAdded) {
            self.dateAdded = d
        } else if let raw = try? container.decodeIfPresent(String.self, forKey: .created_at),
                  let parsed = WishlistDateParser.parse(raw) {
            self.dateAdded = parsed
        } else {
            self.dateAdded = Date()
        }

        if let d = try? container.decodeIfPresent(Date.self, forKey: .lastCheckedDate) {
            self.lastCheckedDate = d
        } else if let raw = try? container.decodeIfPresent(String.self, forKey: .updated_at),
                  let parsed = WishlistDateParser.parse(raw) {
            self.lastCheckedDate = parsed
        } else {
            self.lastCheckedDate = Date()
        }

        self.lastPriceDrop = try container.decodeIfPresent(Double.self, forKey: .lastPriceDrop)
        self.isInStock = try container.decodeIfPresent(Bool.self, forKey: .isInStock) ?? true
        self.availableSizes = try container.decodeIfPresent([String].self, forKey: .availableSizes) ?? []
        self.monitoredSize = try container.decodeIfPresent(String.self, forKey: .monitoredSize)
        self.isMonitoredSizeAvailable = try container.decodeIfPresent(Bool.self, forKey: .isMonitoredSizeAvailable)
        self.shippingCost = try container.decodeIfPresent(Double.self, forKey: .shippingCost)
        self.freeShippingThreshold = try container.decodeIfPresent(Double.self, forKey: .freeShippingThreshold)
        self.courier = try container.decodeIfPresent(String.self, forKey: .courier)
        self.hasFreeShipping = try container.decodeIfPresent(Bool.self, forKey: .hasFreeShipping)
        self.lastVerifiedAt = try container.decodeIfPresent(String.self, forKey: .lastVerifiedAt)
        self.marketMaxPrice = try container.decodeIfPresent(Double.self, forKey: .marketMaxPrice)
        self.crossStoreSavings = try container.decodeIfPresent(Double.self, forKey: .crossStoreSavings)
        self.histMinPrice = try container.decodeIfPresent(Double.self, forKey: .histMinPrice)
        self.histAvgPrice = try container.decodeIfPresent(Double.self, forKey: .histAvgPrice)
        self.isAllTimeLow = try container.decodeIfPresent(Bool.self, forKey: .isAllTimeLow) ?? false
        self.priceChangeSinceSaved = try container.decodeIfPresent(Double.self, forKey: .priceChangeSinceSaved)
            ?? (self.savedPrice > 0 && currPrice > 0 ? currPrice - self.savedPrice : 0.0)
        self.targetReached = try container.decodeIfPresent(Bool.self, forKey: .targetReached) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(productId, forKey: .productId)
        try container.encode(canonical_name, forKey: .canonical_name)
        try container.encodeIfPresent(brand, forKey: .brand)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(image_url, forKey: .image_url)
        try container.encodeIfPresent(galleryImages, forKey: .galleryImages)
        try container.encode(initialPrice, forKey: .initialPrice)
        try container.encode(savedPrice, forKey: .savedPrice)
        try container.encode(currentBestPrice, forKey: .currentBestPrice)
        try container.encodeIfPresent(highestPrice, forKey: .highestPrice)
        try container.encodeIfPresent(discountPct, forKey: .discountPct)
        try container.encodeIfPresent(bestStoreId, forKey: .bestStoreId)
        try container.encodeIfPresent(bestStore, forKey: .bestStore)
        try container.encodeIfPresent(bestStoreUrl, forKey: .bestStoreUrl)
        try container.encode(offersCount, forKey: .offersCount)
        try container.encode(storeCount, forKey: .storeCount)
        try container.encodeIfPresent(selectedSize, forKey: .selectedSize)
        try container.encodeIfPresent(collectionName, forKey: .collectionName)
        try container.encode(collectionNames, forKey: .collectionNames)
        try container.encodeIfPresent(targetAlertPrice, forKey: .targetAlertPrice)
        try container.encode(isAlertEnabled, forKey: .isAlertEnabled)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encode(lastCheckedDate, forKey: .lastCheckedDate)
        try container.encodeIfPresent(lastPriceDrop, forKey: .lastPriceDrop)
        try container.encode(isInStock, forKey: .isInStock)
        try container.encode(availableSizes, forKey: .availableSizes)
        try container.encodeIfPresent(monitoredSize, forKey: .monitoredSize)
        try container.encodeIfPresent(isMonitoredSizeAvailable, forKey: .isMonitoredSizeAvailable)
        try container.encodeIfPresent(shippingCost, forKey: .shippingCost)
        try container.encodeIfPresent(freeShippingThreshold, forKey: .freeShippingThreshold)
        try container.encodeIfPresent(courier, forKey: .courier)
        try container.encodeIfPresent(hasFreeShipping, forKey: .hasFreeShipping)
        try container.encodeIfPresent(lastVerifiedAt, forKey: .lastVerifiedAt)
        try container.encodeIfPresent(marketMaxPrice, forKey: .marketMaxPrice)
        try container.encodeIfPresent(crossStoreSavings, forKey: .crossStoreSavings)
        try container.encodeIfPresent(histMinPrice, forKey: .histMinPrice)
        try container.encodeIfPresent(histAvgPrice, forKey: .histAvgPrice)
        try container.encode(isAllTimeLow, forKey: .isAllTimeLow)
        try container.encode(priceChangeSinceSaved, forKey: .priceChangeSinceSaved)
        try container.encode(targetReached, forKey: .targetReached)
    }

    // MARK: - Helpers & Formatting

    static func formatEuro(_ value: Double) -> String {
        String(format: "%.2f €", value).replacingOccurrences(of: ".", with: ",")
    }

    var effectiveBrand: String {
        let extracted = ProductBrandHelper.extractBrand(from: canonical_name, fallback: brand)
        if !extracted.isEmpty { return extracted }
        return brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var resolvedStoreId: String {
        if let sid = bestStoreId?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty {
            return sid.lowercased()
        }
        if let name = bestStore, let matched = DynamicCatalogRegistry.shared.storeItem(for: name) {
            return matched.id.lowercased()
        }
        return bestStore?.lowercased().replacingOccurrences(of: " ", with: "") ?? "store"
    }

    var effectiveStoreCount: Int {
        if storeCount > 0 { return storeCount }
        return isInStock ? 1 : 0
    }

    func belongsToCollection(_ name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        if clean.lowercased() == "tutti" { return true }
        return collectionNames.contains { $0.caseInsensitiveCompare(clean) == .orderedSame }
    }

    var formattedCurrentPrice: String {
        Self.formatEuro(currentBestPrice)
    }

    var formattedInitialPrice: String? {
        guard let orig = originalPriceForDisplay, orig > currentBestPrice + 0.5 else {
            return nil
        }
        return Self.formatEuro(orig)
    }

    var originalPriceForDisplay: Double? {
        if let h = highestPrice, h > currentBestPrice + 0.5 {
            return h
        }
        if initialPrice > currentBestPrice + 0.5 && abs(initialPrice - savedPrice) > 0.5 {
            return initialPrice
        }
        if let disc = discountPct, disc >= 5.0 && disc < 90.0 {
            return currentBestPrice / (1.0 - (disc / 100.0))
        }
        return nil
    }

    var effectiveDiscountPct: Double? {
        if let d = discountPct, d >= 5.0 {
            return d
        }
        if let orig = originalPriceForDisplay, orig > currentBestPrice && orig > 0 {
            let pct = ((orig - currentBestPrice) / orig) * 100.0
            if pct >= 5.0 { return pct }
        }
        return nil
    }

    var discountBadgeText: String? {
        guard let pct = effectiveDiscountPct else { return nil }
        return "-\(Int(pct.rounded()))%"
    }

    /// True ONLY when the live price dropped since the user actually saved the product.
    var hasDroppedSinceSaved: Bool {
        priceChangeSinceSaved <= -0.99
    }

    var droppedAmountSinceSaved: Double {
        priceChangeSinceSaved <= -0.99 ? abs(priceChangeSinceSaved) : 0.0
    }

    var hasIncreasedSinceSaved: Bool {
        priceChangeSinceSaved >= 1.0
    }

    var formattedPriceDropSinceSaved: String? {
        guard droppedAmountSinceSaved >= 1.0 else { return nil }
        if droppedAmountSinceSaved.truncatingRemainder(dividingBy: 1) < 0.05 {
            return "-\(Int(droppedAmountSinceSaved.rounded())) €"
        }
        return String(format: "-%.2f €", droppedAmountSinceSaved).replacingOccurrences(of: ".", with: ",")
    }

    var isTargetReachedEffective: Bool {
        if targetReached { return true }
        guard isAlertEnabled, let target = targetAlertPrice, target > 0, currentBestPrice > 0 else {
            return false
        }
        return currentBestPrice <= target + 0.01
    }

    var hasPriceDropped: Bool {
        hasDroppedSinceSaved
    }

    var savingsSinceAdded: Double {
        droppedAmountSinceSaved
    }

    var formattedSavingsSinceAdded: String? {
        formattedPriceDropSinceSaved
    }

    /// Indicates footwear vs apparel vs gear for size suggestions & alert presets.
    var isApparelCategory: Bool {
        let low = (category ?? "").lowercased()
        if ["top", "pants", "jacket", "apparel", "swim", "fitness"].contains(low) { return true }
        let titleLow = canonical_name.lowercased()
        let apparelWords = ["maglia", "t-shirt", "canotta", "pantalon", "shorts", "leggings", "tights", "giacca", "felpa", "gilet", "intimo"]
        return apparelWords.contains { titleLow.contains($0) }
    }

    var isFootwearCategory: Bool {
        let low = (category ?? "").lowercased()
        if ["shoes", "running_shoes", "trail_running", "football_boots", "basketball_shoes"].contains(low) { return true }
        if isApparelCategory || isGearCategory { return false }
        let titleLow = canonical_name.lowercased()
        let shoeWords = ["scarpa", "scarpe", "pegasus", "nimbus", "novablast", "clifton", "bondi", "vaporfly", "alphafly", "ride ", "triumph", "ghost", "glycerin", "adizero", "boston", "ultraboost", "speedgoat", "peregrine", "kayano", "cumulus", "mach "]
        return shoeWords.contains { titleLow.contains($0) }
    }

    var isGearCategory: Bool {
        let low = (category ?? "").lowercased()
        if ["gps_watch", "smartwatch", "electronics", "accessories", "nutrition", "cycling", "racket", "ski"].contains(low) {
            return true
        }
        let titleLow = canonical_name.lowercased()
        let gearWords = ["garmin", "forerunner", "fenix", "coros", "polar", "suunto", "orologio", "smartwatch", "occhiali", "oakley", "zaino", "borraccia", "fascia", "rullo", "gps"]
        return gearWords.contains { titleLow.contains($0) }
    }

    func toMatchedProduct() -> MatchedProduct {
        let realStoreId = resolvedStoreId
        let cleanPid = productId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validPid = (cleanPid?.isEmpty == false) ? cleanPid : nil
        let offerSizes: [String]? = {
            if !availableSizes.isEmpty { return availableSizes }
            if let s = selectedSize, !s.isEmpty { return [s] }
            return nil
        }()
        let offer = Offer(
            store_id: realStoreId,
            store_name: bestStore ?? DynamicCatalogRegistry.shared.storeItem(for: realStoreId)?.name ?? "Negozio partner",
            product_id: validPid,
            title: canonical_name,
            brand: effectiveBrand.isEmpty ? brand : effectiveBrand,
            price: currentBestPrice,
            original_price: originalPriceForDisplay,
            discount_pct: effectiveDiscountPct,
            savings: (crossStoreSavings ?? 0) > 1.0 ? crossStoreSavings : nil,
            url: bestStoreUrl ?? "",
            image_url: image_url,
            gallery_images: galleryImages,
            available_sizes: offerSizes,
            in_stock: isInStock,
            shipping_cost: shippingCost,
            total_price: shippingCost.map { currentBestPrice + $0 },
            is_free_shipping: hasFreeShipping,
            shipping_label: hasFreeShipping == true ? "Spedizione gratuita" : nil,
            free_shipping_threshold: freeShippingThreshold,
            courier: courier,
            last_checked_at: lastVerifiedAt
        )
        return MatchedProduct(
            id_val: validPid ?? canonical_name,
            canonical_name: canonical_name,
            brand: effectiveBrand.isEmpty ? brand : effectiveBrand,
            category: category,
            image_url: image_url,
            gallery_images: galleryImages,
            gender: gender,
            offers: [offer],
            best_price: currentBestPrice,
            highest_price: marketMaxPrice ?? originalPriceForDisplay,
            cross_store_savings: (crossStoreSavings ?? 0) > 1.0 ? crossStoreSavings : nil
        )
    }
}
