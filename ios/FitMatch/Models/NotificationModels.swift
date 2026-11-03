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
}
