import Foundation

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
        self.in_stock = in_stock
        self.shipping_cost = shipping_cost
        self.total_price = total_price
        self.is_free_shipping = is_free_shipping
        self.shipping_label = shipping_label
        self.free_shipping_threshold = free_shipping_threshold
        self.courier = courier
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

    var displayTitle: String {
        if let g = gender, !g.isEmpty && g.lowercased() != "unisex" && !canonical_name.lowercased().contains(g.lowercased()) {
            return "\(canonical_name) (\(g))"
        }
        return canonical_name
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
        let offer = Offer(
            store_id: storeId,
            store_name: storeName,
            product_id: product_id,
            title: title,
            brand: brand,
            price: current_price,
            original_price: original_price,
            discount_pct: discount_pct,
            savings: (original_price ?? current_price) - current_price,
            url: product_url,
            image_url: image_url,
            gallery_images: gallery_images,
            available_sizes: [],
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
            brand: brand,
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
        self.products = products
    }

    var formattedRatingWithReviews: String {
        let r = rating.replacingOccurrences(of: ".", with: ",")
        if let rev = review_count, !rev.isEmpty {
            return "\(r) ★ (\(rev))"
        }
        return "\(r) ★"
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
    let products: [StoreShowcaseProduct]
}

// MARK: - Smart Search (Shopify Shop Style)
struct SmartSearchChip: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let param_key: String
    let value: String
}

struct SmartSearchIntent: Codable, Hashable {
    let raw_query: String
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
}

struct SmartSearchResponse: Codable {
    let intent: SmartSearchIntent
    let chips: [SmartSearchChip]
    let total_found: Int
    let results: [MatchedProduct]
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


