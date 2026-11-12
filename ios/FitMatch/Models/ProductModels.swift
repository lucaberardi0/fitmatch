import Foundation

// MARK: - Brand Detection & Cleaning Helper

struct ProductBrandHelper {
    static let knownBrands = [
        "Nike", "Adidas", "Asics", "Hoka", "Brooks", "Saucony", "Puma", "Mizuno",
        "New Balance", "Salomon", "On", "Garmin", "Polar", "Suunto", "Coros",
        "Under Armour", "La Sportiva", "Altra", "Compressport", "Oakley", "The North Face"
    ]

    static let knownStores: Set<String> = [
        "mister running", "misterrunning", "alltricks", "top4running", "maxi sport",
        "maxisport", "cisalfa", "cisalfa sport", "running warehouse", "runningwarehouse",
        "deporvillage", "sportler", "nencini", "nencini sport", "df sport specialist",
        "tradeinn", "decathlon"
    ]

    static func extractBrand(from text: String, fallback: String? = nil) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 1. Check title/text against known brands
        for b in knownBrands {
            let bLow = b.lowercased()
            if lower.hasPrefix(bLow + " ") || lower == bLow || lower.contains(" " + bLow + " ") || lower.contains(bLow + "-") {
                return b
            }
        }

        // 2. If fallback is a valid brand and not a store name, use it
        if let fb = fallback?.trimmingCharacters(in: .whitespacesAndNewlines), !fb.isEmpty {
            let fbLow = fb.lowercased()
            if !knownStores.contains(fbLow) {
                for b in knownBrands {
                    if fbLow.contains(b.lowercased()) { return b }
                }
                return fb
            }
        }

        // 3. Fallback: check first word if not a generic Italian product word or store
        let words = trimmed.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        if let first = words.first, first.count >= 3 {
            let ignore = ["scarpe", "scarpa", "t-shirt", "maglia", "pantaloncini", "shorts", "giacca", "calze", "orologio"]
            if !ignore.contains(first.lowercased()) && !knownStores.contains(first.lowercased()) {
                return first
            }
        }

        return fallback ?? ""
    }
}

enum SizeMatchStatus: Int, Comparable {
    case available = 2
    case unknown = 1
    case unavailable = 0

    static func < (lhs: SizeMatchStatus, rhs: SizeMatchStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct Offer: Identifiable, Codable, Hashable {
    var id: String { "\(store_id)_\(url)" }
    let store_id: String
    let store_name: String
    let product_id: String?
    let title: String
    let brand: String?
    let price: Double
    let original_price: Double?
    let discount_pct: Double?
    let savings: Double?
    let url: String
    let image_url: String?
    let gallery_images: [String]?
    let available_sizes: [String]?
    let variant_name: String?
    let in_stock: Bool?

    // Verified real shipping fields
    let shipping_cost: Double?
    let total_price: Double?
    let is_free_shipping: Bool?
    let shipping_label: String?
    let free_shipping_threshold: Double?
    let courier: String?

    init(
        store_id: String,
        store_name: String,
        product_id: String? = nil,
        title: String,
        brand: String? = nil,
        price: Double,
        original_price: Double? = nil,
        discount_pct: Double? = nil,
        savings: Double? = nil,
        url: String,
        image_url: String? = nil,
        gallery_images: [String]? = nil,
        available_sizes: [String]? = nil,
        variant_name: String? = nil,
        in_stock: Bool? = nil,
        shipping_cost: Double? = nil,
        total_price: Double? = nil,
        is_free_shipping: Bool? = nil,
        shipping_label: String? = nil,
        free_shipping_threshold: Double? = nil,
        courier: String? = nil
    ) {
        self.store_id = store_id
        self.store_name = store_name
        self.product_id = product_id
        self.title = title
        self.brand = brand
        self.price = price
        self.original_price = original_price
        self.discount_pct = discount_pct
        self.savings = savings
        self.url = url
        self.image_url = image_url
        self.gallery_images = gallery_images
        self.available_sizes = available_sizes
        self.variant_name = variant_name
        self.in_stock = in_stock
        self.shipping_cost = shipping_cost
        self.total_price = total_price
        self.is_free_shipping = is_free_shipping
        self.shipping_label = shipping_label
        self.free_shipping_threshold = free_shipping_threshold
        self.courier = courier
    }

    var displayVariant: String? {
        if let v = variant_name, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v
        }
        let parts = title.components(separatedBy: " - ")
        if parts.count > 1 {
            let col = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if col.count >= 3 { return col }
        }
        return nil
    }

    var effectiveBrand: String {
        ProductBrandHelper.extractBrand(from: title, fallback: brand)
    }

    var hasKnownSizes: Bool {
        !(available_sizes ?? []).isEmpty
    }

    func normalizedSizes() -> [String] {
        guard let sizes = available_sizes, !sizes.isEmpty else { return [] }
        return sizes.compactMap { s in
            var clean = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            clean = clean.replacingOccurrences(of: "EU ", with: "")
            clean = clean.replacingOccurrences(of: " EU", with: "")
            clean = clean.replacingOccurrences(of: ".1/2", with: ".5")
            clean = clean.replacingOccurrences(of: " 1/2", with: ".5")
            clean = clean.replacingOccurrences(of: " 2/3", with: ".5")
            clean = clean.replacingOccurrences(of: " 1/3", with: ".5")
            clean = clean.replacingOccurrences(of: ".2/3", with: ".5")
            clean = clean.replacingOccurrences(of: ".1/3", with: ".5")
            // Convert decimal third-sizes from store catalogs (e.g. 42.7 -> 42.5, 43.3 -> 43.5)
            if clean.hasSuffix(".7") || clean.hasSuffix(".67") || clean.hasSuffix(".66") {
                if let val = Double(clean) {
                    clean = String(format: "%.1f", floor(val) + 0.5)
                }
            } else if clean.hasSuffix(".3") || clean.hasSuffix(".33") {
                if let val = Double(clean) {
                    clean = String(format: "%.1f", floor(val) + 0.5)
                }
            }
            if let dashIdx = clean.range(of: "- ")?.upperBound {
                clean = String(clean[dashIdx...]).trimmingCharacters(in: .whitespaces)
            }
            if let parenIdx = clean.firstIndex(of: "(") {
                clean = String(clean[..<parenIdx]).trimmingCharacters(in: .whitespaces)
            }
            clean = clean.trimmingCharacters(in: .whitespaces)
            return clean.isEmpty ? nil : clean
        }
    }

    func hasSize(_ targetSize: String?) -> Bool {
        guard let target = targetSize, !target.isEmpty else { return true }
        guard let sizes = available_sizes, !sizes.isEmpty else { return false }
        let normTarget = target.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let normSizes = normalizedSizes()

        if normSizes.contains(normTarget) { return true }

        // Decimal shoe size proximity tolerance (e.g. 42.5 matches 42.7 or 42.66 within 0.35)
        if let dTarget = Double(normTarget) {
            for s in normSizes {
                if let dSize = Double(s), abs(dTarget - dSize) < 0.35 {
                    return true
                }
            }
            for raw in sizes {
                let cleanRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
                if let dRaw = Double(cleanRaw), abs(dTarget - dRaw) < 0.35 {
                    return true
                }
            }
        }

        let euToUs: [String: String] = [
            "36": "4.5", "36.5": "5", "37": "5", "37.5": "5.5", "38": "6", "38.5": "6",
            "39": "6.5", "39.5": "7", "40": "7", "40.5": "7.5", "41": "8", "41.5": "8.5", "42": "8.5",
            "42.5": "9", "43": "9.5", "43.5": "10", "44": "10", "44.5": "10.5", "45": "11",
            "45.5": "11.5", "46": "12", "46.5": "12.5", "47": "12.5", "47.5": "13", "48": "13.5",
            "48.5": "14", "49": "14.5"
        ]
        let usToEu = Dictionary(euToUs.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        if let us = euToUs[normTarget], normSizes.contains(us) { return true }
        if let eu = usToEu[normTarget], normSizes.contains(eu) { return true }

        return false
    }

    func sizeMatchStatus(_ targetSize: String?) -> SizeMatchStatus {
        guard let target = targetSize, !target.isEmpty else { return .available }
        guard hasKnownSizes else { return .unknown }
        return hasSize(target) ? .available : .unavailable
    }

    var calculatedShippingCost: Double {
        if let cost = shipping_cost { return cost }
        let s = store_id.lowercased()
        let threshold = (s.contains("cisalfa") || s.contains("maxi") || s.contains("nike")) ? 99.0 :
                        s.contains("nencini") ? 100.0 :
                        s.contains("depor") ? 80.0 :
                        s.contains("top4") ? 75.0 :
                        s.contains("alltricks") ? 69.0 :
                        s.contains("warehouse") ? 59.0 : 49.0
        let standard = s.contains("cisalfa") ? 9.90 :
                       s.contains("maxi") ? 7.90 :
                       s.contains("warehouse") ? 10.00 :
                       s.contains("nencini") ? 5.90 :
                       s.contains("nike") ? 5.00 :
                       s.contains("sportler") ? 5.00 :
                       (s.contains("alltricks") || s.contains("depor")) ? 4.99 : 4.90
        return price >= threshold ? 0.0 : standard
    }

    var calculatedTotalPrice: Double {
        total_price ?? (price + calculatedShippingCost)
    }

    var isFreeShipping: Bool {
        is_free_shipping ?? (calculatedShippingCost == 0.0)
    }

    var formattedShipping: String {
        if isFreeShipping {
            return "Sped. Gratis"
        }
        return String(format: "+ €%.2f sped.", calculatedShippingCost)
    }

    var formattedTotalPrice: String {
        String(format: "€%.2f", calculatedTotalPrice)
    }

    var formattedPrice: String {
        String(format: "€%.2f", price)
    }

    var formattedOriginalPrice: String? {
        guard let original_price = original_price, original_price > price else { return nil }
        return String(format: "€%.2f", original_price)
    }

    var discountBadge: String? {
        guard let discount_pct = discount_pct, discount_pct > 0 else { return nil }
        return String(format: "-%.0f%%", discount_pct)
    }

    var allImages: [String] {
        var imgs: [String] = []
        if let primary = image_url, !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            imgs.append(primary)
        }
        if let g = gallery_images {
            for img in g where !img.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !imgs.contains(img) { imgs.append(img) }
            }
        }
        return imgs
    }
}

struct MatchedProduct: Identifiable, Codable, Hashable {
    let id_val: String?
    let canonical_name: String
    let brand: String?
    let image_url: String?
    let gallery_images: [String]?
    let gender: String?
    let offers: [Offer]
    let best_price: Double?
    let highest_price: Double?
    let cross_store_savings: Double?

    init(
        id_val: String? = nil,
        canonical_name: String,
        brand: String? = nil,
        image_url: String? = nil,
        gallery_images: [String]? = nil,
        gender: String? = nil,
        offers: [Offer] = [],
        best_price: Double? = nil,
        highest_price: Double? = nil,
        cross_store_savings: Double? = nil
    ) {
        self.id_val = id_val
        self.canonical_name = canonical_name
        self.brand = brand
        self.image_url = image_url
        self.gallery_images = gallery_images
        self.gender = gender
        self.offers = offers
        self.best_price = best_price
        self.highest_price = highest_price
        self.cross_store_savings = cross_store_savings
    }

    enum CodingKeys: String, CodingKey {
        case id_val = "id"
        case canonical_name
        case brand
        case image_url
        case gallery_images
        case gender
        case offers
        case best_price
        case highest_price
        case cross_store_savings
    }

    var allImages: [String] {
        var imgs: [String] = []
        if let primary = image_url, !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            imgs.append(primary)
        }
        if let g = gallery_images {
            for img in g where !img.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !imgs.contains(img) { imgs.append(img) }
            }
        }
        for o in offers {
            for oImg in o.allImages {
                if !imgs.contains(oImg) { imgs.append(oImg) }
            }
        }
        return imgs
    }

    var id: String {
        if let iv = id_val, !iv.isEmpty {
            return iv
        }
        let g = gender ?? "unisex"
        let p = best_price != nil ? String(format: "%.2f", best_price!) : "0"
        return "\(canonical_name)_\(g)_\(p)"
    }

    var effectiveBrand: String {
        ProductBrandHelper.extractBrand(from: canonical_name, fallback: brand)
    }

    var displayTitle: String {
        let base = cleanTitle
        if let g = gender, !g.isEmpty && g.lowercased() != "unisex" && !base.lowercased().contains(g.lowercased()) {
            return "\(base) (\(g))"
        }
        return base
    }

    var cleanTitle: String {
        var base = canonical_name
        let b = effectiveBrand
        if !b.isEmpty {
            let pattern = "(?i)^(" + NSRegularExpression.escapedPattern(for: b) + "\\s+)+"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(location: 0, length: base.utf16.count)
                base = regex.stringByReplacingMatches(in: base, options: [], range: range, withTemplate: "\(b) ")
            }
        }
        return base.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isComparable: Bool {
        let text = (canonical_name + " " + (gender ?? "") + " " + offers.map { $0.title }.joined(separator: " ")).lowercased()
        let nonShoeKeywords = [
            "fascia", "porta ipod", "porta cellulare", "strap", "cintura", "marsupio",
            "calze", "socks", "maglia", "t-shirt", "pantaloncini", "shorts", "giacca",
            "cappellino", "guanti", "borraccia", "gel", "barretta", "integratore"
        ]
        for neg in nonShoeKeywords {
            if text.contains(neg) { return false }
        }
        let shoeKeywords = [
            "scarpa", "scarpe", "shoe", "shoes", "running", "trail", "sneaker",
            "zoom fly", "pegasus", "vomero", "invincible", "alphafly", "vaporfly",
            "ghost", "glycerin", "clifton", "bondi", "nimbus", "cumulus", "kayano",
            "novablast", "endorphin", "ride", "triumph", "adizero", "boston",
            "ultraboost", "supernova", "prodigio", "speedcross", "cloudmonster",
            "cloudsurfer", "forerunner", "fenix", "venu", "epix", "instinct",
            "coros", "polar", "suunto"
        ]
        for kw in shoeKeywords {
            if text.contains(kw) { return true }
        }
        return false
    }

    var allAvailableSizes: [String] {
        var set = Set<String>()
        for offer in offers {
            for s in offer.normalizedSizes() {
                if !s.isEmpty { set.insert(s) }
            }
        }
        if set.isEmpty {
            return []
        }
        return set.sorted { s1, s2 in
            if let d1 = Double(s1), let d2 = Double(s2) {
                return d1 < d2
            }
            return s1 < s2
        }
    }

    func bestOffer(for size: String?) -> Offer? {
        guard let sz = size, !sz.isEmpty else { return bestOffer }
        let matching = offers.filter { $0.hasSize(sz) }
        return matching.min(by: { $0.price < $1.price }) ?? bestOffer
    }

    var bestOffer: Offer? {
        offers.min(by: { $0.price < $1.price })
    }

    var formattedBestPrice: String {
        if let best_price = best_price {
            return String(format: "€%.2f", best_price)
        }
        return "N/D"
    }

    var formattedSavings: String? {
        guard let savings = cross_store_savings, savings > 1.0 else { return nil }
        return String(format: "Risparmi fino a €%.2f", savings)
    }
}

// MARK: - Price History & Market Trends

struct PriceHistoryPoint: Identifiable, Codable, Hashable {
    var id: String { "\(date)_\(store_name)_\(price)" }
    let date: String
    let price: Double
    let store_name: String
    let offer_id: String?

    var formattedPrice: String {
        String(format: "€%.2f", price)
    }

    var parsedDate: Date {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFormatter.date(from: date) { return d }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let d = isoFormatter.date(from: date) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: date) ?? Date()
    }

    var shortDateLabel: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.dateFormat = "d MMM"
        return df.string(from: parsedDate)
    }

    var formattedDateFull: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.dateFormat = "d MMMM"
        return df.string(from: parsedDate).capitalized
    }
}

struct PriceHistoryResponse: Codable {
    let canonical_name: String
    let product_id: String?
    let current_price: Double
    let lowest_price: Double
    let highest_price: Double
    let average_price: Double
    let is_all_time_low: Bool
    let price_drop_percentage: Double?
    let price_drop_amount: Double?
    let history_points: [PriceHistoryPoint]
    let total_data_points: Int
    let first_recorded_date: String?
    let last_recorded_date: String?

    var formattedCurrentPrice: String {
        String(format: "€%.2f", current_price)
    }

    var formattedLowestPrice: String {
        String(format: "€%.2f", lowest_price)
    }

    var formattedHighestPrice: String {
        String(format: "€%.2f", highest_price)
    }

    var formattedAveragePrice: String {
        String(format: "€%.2f", average_price)
    }

    var formattedSavingsVsAverage: String? {
        guard let diff = price_drop_amount, diff > 1.0 else { return nil }
        return String(format: "€%.2f sotto la media", diff)
    }
}

struct SearchResponse: Codable {
    let query: String
    let execution_time_seconds: Double
    let stores_queried: [String]
    let total_offers_found: Int
    let matched_products: [MatchedProduct]
}

struct AIRecommendation: Identifiable, Codable, Hashable {
    var id: String { product_name }
    let product_name: String
    let brand: String?
    let best_price: Double?
    let best_store: String?
    let original_price: Double?
    let discount_pct: Double?
    let link: String?
    let image_url: String?
    let cross_store_savings: Double?
    let all_offers: [AIOfferOption]
}

struct AIOfferOption: Identifiable, Codable, Hashable {
    var id: String { "\(store)_\(price)" }
    let store: String
    let price: Double
    let url: String
}

struct AIAdviceResponse: Codable {
    let category_name: String
    let category_description: String
    let biomechanical_reasoning: String
    let recommendations: [AIRecommendation]
}

struct TopSaving: Identifiable, Codable {
    var id: String { canonical_name }
    let canonical_name: String
    let brand: String?
    let min_price: Double
    let max_price: Double
    let savings: Double
    let store_count: Int
}

struct CatalogStatsResponse: Codable {
    let total_products: Int
    let total_offers: Int
    let multi_store_products: Int
    let brands_count: Int
    let top_savings: [TopSaving]
}

// MARK: - Shopify Shop-Style Store Showcase Models

struct StoreShowcaseProduct: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let brand: String?
    let image_url: String?
    let gallery_images: [String]?
    let available_sizes: [String]?
    let current_price: Double
    let original_price: Double?
    let discount_pct: Double?
    let product_url: String
    let canonical_name: String
    let product_id: String?
    let shipping_cost: Double?
    let total_price: Double?
    let is_free_shipping: Bool?
    let shipping_label: String?
    let free_shipping_threshold: Double?
    let courier: String?

    init(
        id: String,
        title: String,
        brand: String? = nil,
        image_url: String? = nil,
        gallery_images: [String]? = nil,
        available_sizes: [String]? = nil,
        current_price: Double,
        original_price: Double? = nil,
        discount_pct: Double? = nil,
        product_url: String,
        canonical_name: String,
        product_id: String? = nil,
        shipping_cost: Double? = nil,
        total_price: Double? = nil,
        is_free_shipping: Bool? = nil,
        shipping_label: String? = nil,
        free_shipping_threshold: Double? = nil,
        courier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.brand = brand
        self.image_url = image_url
        self.gallery_images = gallery_images
        self.available_sizes = available_sizes
        self.current_price = current_price
        self.original_price = original_price
        self.discount_pct = discount_pct
        self.product_url = product_url
        self.canonical_name = canonical_name
        self.product_id = product_id
        self.shipping_cost = shipping_cost
        self.total_price = total_price
        self.is_free_shipping = is_free_shipping
        self.shipping_label = shipping_label
        self.free_shipping_threshold = free_shipping_threshold
        self.courier = courier
    }

    var effectiveBrand: String {
        ProductBrandHelper.extractBrand(from: title, fallback: brand)
    }

    var formattedPrice: String {
        String(format: "€%.2f", current_price)
    }

    var formattedOriginalPrice: String? {
        guard let original_price = original_price, original_price > current_price else { return nil }
        return String(format: "€%.2f", original_price)
    }

    var discountBadge: String? {
        guard let discount_pct = discount_pct, discount_pct > 0 else { return nil }
        return String(format: "-%.0f%%", discount_pct)
    }

    var allImages: [String] {
        var imgs: [String] = []
        if let primary = image_url, !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            imgs.append(primary)
        }
        if let g = gallery_images {
            for img in g where !img.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !imgs.contains(img) { imgs.append(img) }
            }
        }
        return imgs
    }

    func toMatchedProduct(storeId: String, storeName: String) -> MatchedProduct {
        let effBrand = ProductBrandHelper.extractBrand(from: title, fallback: brand)
        let offer = Offer(
            store_id: storeId,
            store_name: storeName,
            product_id: product_id,
            title: title,
            brand: effBrand,
            price: current_price,
            original_price: original_price,
            discount_pct: discount_pct,
            savings: (original_price ?? current_price) - current_price,
            url: product_url,
            image_url: image_url,
            gallery_images: gallery_images,
            available_sizes: available_sizes ?? [],
            in_stock: true,
            shipping_cost: shipping_cost,
            total_price: total_price,
            is_free_shipping: is_free_shipping,
            shipping_label: shipping_label,
            free_shipping_threshold: free_shipping_threshold,
            courier: courier
        )
        return MatchedProduct(
            id_val: "\(storeId)_\(product_id ?? UUID().uuidString)",
            canonical_name: canonical_name,
            brand: effBrand,
            image_url: image_url,
            gallery_images: gallery_images,
            gender: nil,
            offers: [offer],
            best_price: current_price,
            highest_price: original_price ?? current_price,
            cross_store_savings: nil
        )
    }
}

struct StoreShowcase: Identifiable, Codable, Hashable {
    var id: String { store_id }
    let store_id: String
    let store_name: String
    let total_offers: Int
    let avg_discount: Double
    let rating: String
    let review_count: String?
    let card_theme: String?
    let accent_color: String?
    let logo_url: String?
    let promo_text: String?
    let products: [StoreShowcaseProduct]

    init(
        store_id: String,
        store_name: String,
        total_offers: Int,
        avg_discount: Double,
        rating: String,
        review_count: String? = nil,
        card_theme: String? = nil,
        accent_color: String? = nil,
        logo_url: String? = nil,
        promo_text: String? = nil,
        products: [StoreShowcaseProduct]
    ) {
        self.store_id = store_id
        self.store_name = store_name
        self.total_offers = total_offers
        self.avg_discount = avg_discount
        self.rating = rating
        self.review_count = review_count
        self.card_theme = card_theme
        self.accent_color = accent_color
        self.logo_url = logo_url
        self.promo_text = promo_text
        self.products = products
    }

    var formattedRatingWithReviews: String {
        let r = rating.replacingOccurrences(of: ".", with: ",")
        if let rev = review_count, !rev.isEmpty {
            return "\(r) ★ (\(rev))"
        }
        return "\(r) ★"
    }

    /// Dynamically computes an authentic, intelligent promo headline based on actual products, discounts, and category.
    func dynamicPromoSubtitle(category: String? = nil) -> String {
        return IntelligentPromoGenerator.generate(for: self, category: category)
    }
}

struct StoreShowcaseResponse: Codable {
    let showcases: [StoreShowcase]
}

struct StoreRatingBreakdown: Codable {
    let score: Double
    let positive_pct: String
    let review_count: String
    let platform: String
}

struct StoreCustomerReview: Identifiable, Codable, Hashable {
    var id: String
    let author: String
    let rating: Double
    let text: String
    let date: String

    init(id: String = UUID().uuidString, author: String, rating: Double, text: String, date: String) {
        self.id = id
        self.author = author
        self.rating = rating
        self.text = text
        self.date = date
    }

    enum CodingKeys: String, CodingKey {
        case id, author, rating, text, date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.author = (try? container.decode(String.self, forKey: .author)) ?? "Cliente Verificato"
        self.rating = (try? container.decode(Double.self, forKey: .rating)) ?? 5.0
        self.text = (try? container.decode(String.self, forKey: .text)) ?? ""
        self.date = (try? container.decode(String.self, forKey: .date)) ?? "Recentemente"
    }
}

struct StoreDetailResponse: Codable {
    let store_id: String
    let store_name: String
    let base_url: String
    let rating: String
    let review_count: String
    let description: String
    let full_description: String?
    let badges: [String]
    let highlights: [String]?
    let location: String?
    let shipping_info: String?
    let return_policy: String?
    let rating_breakdown: StoreRatingBreakdown?
    let total_offers: Int
    let avg_discount: Double
    let min_price: Double
    var products: [StoreShowcaseProduct]
    let contact_email: String?
    let contact_phone: String?
    let social_instagram: String?
    let privacy_policy_url: String?
    let terms_url: String?
    let refund_policy: String?
    let shipping_policy: String?
    let city_or_location: String?
    let customer_reviews: [StoreCustomerReview]?
    let customer_photos: [String]?
}

// MARK: - Smart Search (Shopify Shop Style)
struct SmartSearchChip: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let param_key: String
    let value: String
}

struct CuratedProductSection: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let products: [MatchedProduct]
}

struct SpotlightRecommendation: Codable, Hashable {
    let product: MatchedProduct
    let badge_text: String?
    let highlights: [String]
}

struct ComparativeSpecCard: Identifiable, Codable, Hashable {
    var id: String {
        "\(product.id)_\(model_name)"
    }
    let product: MatchedProduct
    let model_name: String
    let ideal_for: String
    let strengths: String
    let section_title: String?
}

struct SmartSearchIntent: Codable, Hashable {
    let raw_query: String
    let search_mode: String?
    let is_deep_dive: Bool?
    let target_keywords: [String]?
    let brand: String?
    let category: String?
    let gender: String?
    let max_price: Double?
    let min_price: Double?
    let size: String?
    let features: [String]?
    let explanation: String?
    let source: String?
    let is_off_topic: Bool?
    let is_unsafe: Bool?
    let is_conversational_advice: Bool?
}

struct SmartSearchResponse: Codable {
    let search_mode: String?
    let is_deep_dive: Bool?
    let is_conversational_advice: Bool?
    let conversational_header: String?
    let conversational_summary: String?
    let curated_sections: [CuratedProductSection]?
    let comparative_cards: [ComparativeSpecCard]?
    let spotlight: SpotlightRecommendation?
    let follow_up_suggestions: [String]?
    let intent: SmartSearchIntent?
    let chips: [SmartSearchChip]?
    let total_found: Int
    let results: [MatchedProduct]
    let is_off_topic: Bool?
    let is_unsafe: Bool?
}

// MARK: - Conversational Search Turn Model
struct SearchConversationTurn: Identifiable, Codable, Hashable {
    let id: String
    let query: String
    let isFollowUp: Bool
    var isConversationalAdvice: Bool
    var conversationalHeader: String
    var conversationalSummary: String
    var smartIntent: SmartSearchIntent?
    var activeChips: [SmartSearchChip]
    var searchResults: [MatchedProduct]
    var curatedSections: [CuratedProductSection]
    var comparativeCards: [ComparativeSpecCard]
    var spotlight: SpotlightRecommendation?
    var followUpSuggestions: [String]
    var userFeedback: Int?
    var showAiExplanation: Bool
    var error: String?
    var isOffTopic: Bool
    var isUnsafe: Bool
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        query: String,
        isFollowUp: Bool,
        isConversationalAdvice: Bool = false,
        conversationalHeader: String,
        conversationalSummary: String,
        smartIntent: SmartSearchIntent? = nil,
        activeChips: [SmartSearchChip] = [],
        searchResults: [MatchedProduct] = [],
        curatedSections: [CuratedProductSection] = [],
        comparativeCards: [ComparativeSpecCard] = [],
        spotlight: SpotlightRecommendation? = nil,
        followUpSuggestions: [String] = [],
        userFeedback: Int? = nil,
        showAiExplanation: Bool = false,
        error: String? = nil,
        isOffTopic: Bool = false,
        isUnsafe: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.query = query
        self.isFollowUp = isFollowUp
        self.isConversationalAdvice = isConversationalAdvice
        self.conversationalHeader = conversationalHeader
        self.conversationalSummary = conversationalSummary
        self.smartIntent = smartIntent
        self.activeChips = activeChips
        self.searchResults = searchResults
        self.curatedSections = curatedSections
        self.comparativeCards = comparativeCards
        self.spotlight = spotlight
        self.followUpSuggestions = followUpSuggestions
        self.userFeedback = userFeedback
        self.showAiExplanation = showAiExplanation
        self.error = error
        self.isOffTopic = isOffTopic
        self.isUnsafe = isUnsafe
        self.timestamp = timestamp
    }

    var productsForFeedback: [MatchedProduct] {
        var prods: [MatchedProduct] = []
        for sec in curatedSections {
            for p in sec.products {
                if !prods.contains(where: { $0.id == p.id }) {
                    prods.append(p)
                }
            }
        }
        for res in searchResults {
            if !prods.contains(where: { $0.id == res.id }) {
                prods.append(res)
            }
        }
        if let spot = spotlight, !prods.contains(where: { $0.id == spot.product.id }) {
            prods.insert(spot.product, at: 0)
        }
        return Array(prods.prefix(8))
    }
}

// MARK: - AI Model Comparison Models

struct ModelSpecs: Codable, Hashable {
    let name: String
    let brand: String?
    let drop_mm: Int?
    let weight_g: Int?
    let cushioning: String?
    let midsole: String?
    let plate: String?
    let ideal_use: String?
    let target_runner: String?
    let pros: [String]
    let cons: [String]
}

struct StoreOfferBrief: Codable, Hashable {
    let store_name: String
    let price: Double
    let original_price: Double?
    let url: String
    let is_free_shipping: Bool
    let total_price: Double

    var formattedPrice: String {
        String(format: "€%.2f", price)
    }
}

struct ModelMarketData: Codable, Hashable {
    let model_name: String
    let brand: String?
    let best_price: Double?
    let highest_price: Double?
    let best_store: String?
    let image_url: String?
    let total_offers: Int
    let cross_store_savings: Double?
    let top_offers: [StoreOfferBrief]

    var formattedBestPrice: String {
        guard let p = best_price else { return "N/D" }
        return String(format: "€%.2f", p)
    }
}

struct ModelComparisonResponse: Codable, Hashable {
    let model_a_specs: ModelSpecs
    let model_b_specs: ModelSpecs
    let model_a_market: ModelMarketData
    let model_b_market: ModelMarketData
    let key_differences: [String]
    let verdict_summary: String
    let winner_for_value: String
    let winner_for_performance: String
    let price_delta: Double?
    let source: String?
}

// MARK: - Dedicated Category Filter Matcher for Deals & Search

struct CategoryFilterMatcher {
    static func matches(title: String, category: String) -> Bool {
        let t = title.lowercased()
        let cat = category.lowercased()
        if cat == "tutti" || cat.isEmpty { return true }

        if cat == "smartwatch" {
            let exc = ["fleece", "buff", "bolt polar", "polartec", "pile", "fascia", "calzini", "short", "maglia", "canott", "watching", "polaroid", "guanti", "pantalon", "protezione", "vetro", "pellicola", "custodia", "cover", "cinturino", "strap", "supporto", "sostegno", "manubrio", "attacco", "adattatore", "cavo", "sensore"]
            if exc.contains(where: { t.contains($0) }) { return false }
            let incStrong = ["smartwatch", "apple watch", "garmin", "suunto", "coros", "forerunner", "fenix", "epix", "cardiofrequenzimetro", "instinct", "vivoactive", "venu", "enduro"]
            if incStrong.contains(where: { t.contains($0) }) { return true }
            if t.contains("polar") && ["grit", "vantage", "pacer", "ignite", "unite", "orologio", "gps", "cardio"].contains(where: { t.contains($0) }) {
                return true
            }
            return false
        }

        if cat == "running" {
            let exc = ["smartwatch", "apple watch", "garmin", "polar grit", "polar vantage", "polar pacer", "polar ignite", "fleece", "pile"]
            if exc.contains(where: { t.contains($0) }) { return false }
            let inc = ["running", "scarpe running", "corsa", "maratona", "asics", "hoka", "brooks", "saucony", "mizuno", "pegasus", "vaporfly", "alphafly", "clifton", "ghost", "cumulus", "nimbus", "novablast", "adizero", "supernova", "vomero", "invincible", "endorphin", "deviate", "boston", "zoom fly"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "abbigliamento" {
            let exc = ["scarpe", "sneaker", "smartwatch", "apple watch", "garmin", "occhiali", "borraccia"]
            if exc.contains(where: { t.contains($0) }) { return false }
            let inc = ["maglia", "pantalon", "tshirt", "t-shirt", "felpa", "jacket", "giacca", "tight", "short", "top", "tee", "windbreaker", "wind", "pile", "tuta", "leggings", "canotta", "fleece", "reggiseno", "bra", "calze", "calzini"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "donna" {
            let exc = ["uomo", "men", "man", "homme", "bambino", "bambina", "junior", "jr"]
            if exc.contains(where: { t.contains($0) }) { return false }
            let inc = ["donna", "wmn", "women", "femme", "lady", "girl", "reggiseno", "bra"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "outdoor" {
            let exc = ["smartwatch", "apple watch", "t-shirt", "canotta"]
            if exc.contains(where: { t.contains($0) }) { return false }
            let inc = ["trail", "trekking", "outdoor", "montagna", "gore-tex", "gtx", "salomon", "speedcross", "hierro", "cascadia", "peregrine", "terrex", "scarpone", "wildhorse", "mafate", "speedgoat"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "fitness" {
            let exc = ["smartwatch", "apple watch", "occhiali", "scarpe outdoor"]
            if exc.contains(where: { t.contains($0) }) { return false }
            let inc = ["fitness", "training", "gym", "palestra", "pesi", "swoosh", "leggings", "bra", "crossfit", "metcon", "tuta", "manubri"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "accessori" {
            let exc = ["scarpe", "maglia", "pantalone", "felpa", "giacca"]
            if exc.contains(where: { t.contains($0) }) { return false }
            let inc = ["occhiali", "calzini", "guanti", "cappell", "zaino", "borraccia", "sock", "belt", "marsupio", "headband", "visiera", "cinturino", "strap", "cappello", "berretto"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "uomo" {
            let exc = ["donna", "women", "wmn", "femme", "bambino", "bambina", "junior", "jr"]
            if exc.contains(where: { t.contains($0) }) { return false }
            let inc = ["uomo", "men", "man", "homme"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "padel" {
            let exc = ["scarpe running", "smartwatch", "trail", "trekking"]
            if exc.contains(where: { t.contains($0) }) { return false }
            let inc = ["padel", "racchetta", "pala", "bullpadel", "nox", "starvie", "siux", "kuikma", "babolat technical", "head speed", "overgrip", "tubo palline"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "cycling" || cat == "ciclismo" {
            let exc = ["scarpe running", "trail running"]
            if exc.contains(where: { t.contains($0) }) { return false }
            let inc = ["ciclismo", "bici", "ciclocomputer", "rullo", "smart trainer", "kickr", "flux", "tacx", "wahoo", "favero", "assioma", "kask", "poc ventral", "castelli", "sportful", "santini", "salopette", "shimano", "copertone"]
            return inc.contains(where: { t.contains($0) })
        }

        return t.contains(cat)
    }
}



