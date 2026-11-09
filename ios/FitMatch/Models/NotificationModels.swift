import Foundation
import SwiftUI

enum NotificationType: String, Codable, CaseIterable {
    case priceDrop = "price_drop"
    case storeDrop = "store_drop"
    case promo = "promo"

    var title: String {
        switch self {
        case .priceDrop: return "Calo Prezzo"
        case .storeDrop: return "Nuovo Drop"
        case .promo: return "Offerta Speciale"
        }
    }

    var iconName: String {
        switch self {
        case .priceDrop: return "flame.fill"
        case .storeDrop: return "sparkles"
        case .promo: return "tag.fill"
        }
    }

    var badgeColor: Color {
        switch self {
        case .priceDrop: return Color(red: 228/255, green: 42/255, blue: 38/255)
        case .storeDrop: return Color(red: 99/255, green: 59/255, blue: 238/255)
        case .promo: return Color(red: 245/255, green: 158/255, blue: 11/255)
        }
    }
}

struct AppNotification: Identifiable, Codable, Hashable {
    let id: String
    let type: NotificationType
    let title: String
    let subtitle: String?
    let body: String
    let timestamp: Date
    var isRead: Bool

    // Rich Product / Store Metadata
    var productCanonicalName: String?
    var storeId: String?
    var storeName: String?
    var imageUrl: String?
    var oldPrice: Double?
    var newPrice: Double?
    var discountPct: Double?
    var actionUrl: String?

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    var savingsAmount: Double? {
        guard let old = oldPrice, let current = newPrice, old > current else { return nil }
        return old - current
    }

    init(
        id: String = UUID().uuidString,
        type: NotificationType,
        title: String,
        subtitle: String? = nil,
        body: String,
        timestamp: Date = Date(),
        isRead: Bool = false,
        productCanonicalName: String? = nil,
        storeId: String? = nil,
        storeName: String? = nil,
        imageUrl: String? = nil,
        oldPrice: Double? = nil,
        newPrice: Double? = nil,
        discountPct: Double? = nil,
        actionUrl: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.timestamp = timestamp
        self.isRead = isRead
        self.productCanonicalName = productCanonicalName
        self.storeId = storeId
        self.storeName = storeName
        self.imageUrl = imageUrl
        self.oldPrice = oldPrice
        self.newPrice = newPrice
        self.discountPct = discountPct
        self.actionUrl = actionUrl
    }

    func toMatchedProduct() -> MatchedProduct? {
        guard let name = productCanonicalName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let price = newPrice ?? oldPrice ?? 0.0
        let orig = oldPrice ?? price
        let savings = (orig > price) ? (orig - price) : nil
        let disc = discountPct ?? ((orig > price && orig > 0) ? ((orig - price) / orig * 100.0) : nil)

        let sId = (storeId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? storeId! : "store"
        let sName = (storeName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? storeName! : "Negozio Partner"

        let brandCandidate = name.split(separator: " ").first.map(String.init) ?? "Scarpe"

        let offer = Offer(
            store_id: sId,
            store_name: sName,
            product_id: nil,
            title: name,
            brand: brandCandidate,
            price: price,
            original_price: orig,
            discount_pct: disc,
            savings: savings,
            url: actionUrl ?? "",
            image_url: imageUrl,
            gallery_images: imageUrl != nil ? [imageUrl!] : nil,
            available_sizes: nil,
            in_stock: true,
            shipping_cost: 0.0,
            total_price: price,
            is_free_shipping: true,
            shipping_label: "Spedizione partner",
            free_shipping_threshold: nil,
            courier: nil
        )

        return MatchedProduct(
            id_val: id,
            canonical_name: name,
            brand: brandCandidate,
            image_url: imageUrl,
            gallery_images: imageUrl != nil ? [imageUrl!] : nil,
            gender: nil,
            offers: [offer],
            best_price: price,
            highest_price: orig,
            cross_store_savings: savings
        )
    }
}

struct StoreDeepLink: Identifiable, Hashable {
    let id: String
    let name: String
}
