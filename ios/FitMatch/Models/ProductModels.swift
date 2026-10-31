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
    let available_sizes: [String]?
    let in_stock: Bool?

    // Verified real shipping fields
    let shipping_cost: Double?
    let total_price: Double?
    let is_free_shipping: Bool?
    let shipping_label: String?
    let free_shipping_threshold: Double?
    let courier: String?

    var calculatedShippingCost: Double {
        if let cost = shipping_cost { return cost }
        let s = store_id.lowercased()
        let threshold = (s.contains("cisalfa") || s.contains("maxi")) ? 99.0 :
                        s.contains("nencini") ? 100.0 :
                        s.contains("depor") ? 80.0 :
                        s.contains("top4") ? 75.0 :
                        s.contains("alltricks") ? 69.0 :
                        s.contains("warehouse") ? 59.0 : 49.0
        let standard = s.contains("cisalfa") ? 9.90 :
                       s.contains("maxi") ? 7.90 :
                       s.contains("warehouse") ? 10.00 :
                       s.contains("nencini") ? 5.90 :
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
}

struct MatchedProduct: Identifiable, Codable, Hashable {
    var id: String { canonical_name }
    let canonical_name: String
    let brand: String?
    let image_url: String?
    let offers: [Offer]
    let best_price: Double?
    let highest_price: Double?
    let cross_store_savings: Double?

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
            canonical_name: canonical_name,
            brand: brand,
            image_url: image_url,
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
    let products: [StoreShowcaseProduct]
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

