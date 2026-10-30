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
