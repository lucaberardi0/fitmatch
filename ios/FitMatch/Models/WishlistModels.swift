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

struct WishlistItem: Identifiable, Codable, Hashable {
    var id: String { canonical_name }
    let canonical_name: String
    let brand: String?
    let image_url: String?
    var initialPrice: Double
    var currentBestPrice: Double
    var highestPrice: Double?
    var discountPct: Double?
    var bestStore: String?
    var bestStoreUrl: String?
    var offersCount: Int
    var selectedSize: String?
    var collectionName: String?
    var targetAlertPrice: Double?
    var isAlertEnabled: Bool
    var dateAdded: Date
    var lastCheckedDate: Date
    var lastPriceDrop: Double?

    enum CodingKeys: String, CodingKey {
        case canonical_name
        case brand
        case image_url
        case initialPrice, currentBestPrice, highestPrice, discountPct
        case original_price, current_price, discount_pct
        case bestStore, bestStoreUrl, store_name, product_url
        case offersCount
        case selectedSize, selected_size
        case collectionName, collection_name
        case targetAlertPrice, isAlertEnabled
        case dateAdded, lastCheckedDate, lastPriceDrop
    }

    init(
        canonical_name: String,
        brand: String? = nil,
        image_url: String? = nil,
        initialPrice: Double,
        currentBestPrice: Double,
        highestPrice: Double? = nil,
        discountPct: Double? = nil,
        bestStore: String? = nil,
        bestStoreUrl: String? = nil,
        offersCount: Int = 1,
        selectedSize: String? = nil,
        collectionName: String? = "Tutti",
        targetAlertPrice: Double? = nil,
        isAlertEnabled: Bool = true,
        dateAdded: Date = Date(),
        lastCheckedDate: Date = Date(),
        lastPriceDrop: Double? = nil
    ) {
        self.canonical_name = canonical_name
        self.brand = brand
        self.image_url = image_url
        self.initialPrice = initialPrice
        self.currentBestPrice = currentBestPrice
        self.highestPrice = highestPrice
        self.discountPct = discountPct
        self.bestStore = bestStore
        self.bestStoreUrl = bestStoreUrl
        self.offersCount = offersCount
        self.selectedSize = selectedSize
        self.collectionName = collectionName
        self.targetAlertPrice = targetAlertPrice
        self.isAlertEnabled = isAlertEnabled
        self.dateAdded = dateAdded
        self.lastCheckedDate = lastCheckedDate
        self.lastPriceDrop = lastPriceDrop
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.canonical_name = try container.decode(String.self, forKey: .canonical_name)
        self.brand = try container.decodeIfPresent(String.self, forKey: .brand)
        self.image_url = try container.decodeIfPresent(String.self, forKey: .image_url)

        let currPrice = try container.decodeIfPresent(Double.self, forKey: .currentBestPrice)
            ?? container.decodeIfPresent(Double.self, forKey: .current_price)
            ?? 0.0
        self.currentBestPrice = currPrice

        let origPrice = try container.decodeIfPresent(Double.self, forKey: .initialPrice)
            ?? container.decodeIfPresent(Double.self, forKey: .original_price)
            ?? currPrice
        self.initialPrice = origPrice

        self.highestPrice = try container.decodeIfPresent(Double.self, forKey: .highestPrice)
            ?? container.decodeIfPresent(Double.self, forKey: .original_price)

        var disc = try container.decodeIfPresent(Double.self, forKey: .discountPct)
            ?? container.decodeIfPresent(Double.self, forKey: .discount_pct)
        if disc == nil && origPrice > currPrice && origPrice > 0 {
            disc = ((origPrice - currPrice) / origPrice) * 100.0
        }
        self.discountPct = disc

        self.bestStore = try container.decodeIfPresent(String.self, forKey: .bestStore)
            ?? container.decodeIfPresent(String.self, forKey: .store_name)
        self.bestStoreUrl = try container.decodeIfPresent(String.self, forKey: .bestStoreUrl)
            ?? container.decodeIfPresent(String.self, forKey: .product_url)

        self.offersCount = try container.decodeIfPresent(Int.self, forKey: .offersCount) ?? 1
        self.selectedSize = try container.decodeIfPresent(String.self, forKey: .selectedSize)
            ?? container.decodeIfPresent(String.self, forKey: .selected_size)
        self.collectionName = try container.decodeIfPresent(String.self, forKey: .collectionName)
            ?? container.decodeIfPresent(String.self, forKey: .collection_name)
            ?? "Tutti"

        self.targetAlertPrice = try container.decodeIfPresent(Double.self, forKey: .targetAlertPrice)
        self.isAlertEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAlertEnabled) ?? true

        self.dateAdded = try container.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
        self.lastCheckedDate = try container.decodeIfPresent(Date.self, forKey: .lastCheckedDate) ?? Date()
        self.lastPriceDrop = try container.decodeIfPresent(Double.self, forKey: .lastPriceDrop)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(canonical_name, forKey: .canonical_name)
        try container.encodeIfPresent(brand, forKey: .brand)
        try container.encodeIfPresent(image_url, forKey: .image_url)
        try container.encode(initialPrice, forKey: .initialPrice)
        try container.encode(currentBestPrice, forKey: .currentBestPrice)
        try container.encodeIfPresent(highestPrice, forKey: .highestPrice)
        try container.encodeIfPresent(discountPct, forKey: .discountPct)
        try container.encodeIfPresent(bestStore, forKey: .bestStore)
        try container.encodeIfPresent(bestStoreUrl, forKey: .bestStoreUrl)
        try container.encode(offersCount, forKey: .offersCount)
        try container.encodeIfPresent(selectedSize, forKey: .selectedSize)
        try container.encodeIfPresent(collectionName, forKey: .collectionName)
        try container.encodeIfPresent(targetAlertPrice, forKey: .targetAlertPrice)
        try container.encode(isAlertEnabled, forKey: .isAlertEnabled)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encode(lastCheckedDate, forKey: .lastCheckedDate)
        try container.encodeIfPresent(lastPriceDrop, forKey: .lastPriceDrop)
    }

    var formattedCurrentPrice: String {
        String(format: "%.2f €", currentBestPrice).replacingOccurrences(of: ".", with: ",")
    }

    var formattedInitialPrice: String? {
        guard let orig = highestPrice ?? (initialPrice > currentBestPrice ? initialPrice : nil), orig > currentBestPrice else {
            return nil
        }
        return String(format: "%.2f €", orig).replacingOccurrences(of: ".", with: ",")
    }

    var discountBadgeText: String? {
        if let d = discountPct, d >= 5.0 {
            return "\(Int(d.rounded()))% di sconto"
        } else if initialPrice > currentBestPrice && initialPrice > 0 {
            let pct = ((initialPrice - currentBestPrice) / initialPrice) * 100.0
            if pct >= 5.0 {
                return "\(Int(pct.rounded()))% di sconto"
            }
        }
        return nil
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
        return String(format: "-%.2f €", diff).replacingOccurrences(of: ".", with: ",")
    }

    func toMatchedProduct() -> MatchedProduct {
        let offer = Offer(
            store_id: bestStore?.lowercased() ?? "store",
            store_name: bestStore ?? "Negozio",
            product_id: nil,
            title: canonical_name,
            brand: brand,
            price: currentBestPrice,
            original_price: highestPrice ?? initialPrice,
            discount_pct: discountPct,
            savings: savingsSinceAdded,
            url: bestStoreUrl ?? "",
            image_url: image_url,
            gallery_images: nil,
            available_sizes: selectedSize != nil ? [selectedSize!] : nil,
            in_stock: true,
            shipping_cost: 0.0,
            total_price: currentBestPrice,
            is_free_shipping: true,
            shipping_label: "Spedizione gratuita",
            free_shipping_threshold: nil,
            courier: nil
        )
        return MatchedProduct(
            id_val: id,
            canonical_name: canonical_name,
            brand: brand,
            image_url: image_url,
            gallery_images: nil,
            gender: nil,
            offers: [offer],
            best_price: currentBestPrice,
            highest_price: highestPrice ?? initialPrice,
            cross_store_savings: savingsSinceAdded
        )
    }
}
