import Foundation
import SwiftUI
import Combine

enum ActivityType: String, Codable {
    case search
    case product
    case store
}

struct RecentActivityItem: Identifiable, Codable, Hashable {
    let id: UUID
    let type: ActivityType
    let title: String
    let subtitle: String?
    let imageUrl: String?
    let systemIcon: String?
    let timestamp: Date
    let productData: MatchedProduct?
    var storeId: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, type, title, subtitle, imageUrl, systemIcon, timestamp, productData, storeId
    }

    init(
        id: UUID = UUID(),
        type: ActivityType,
        title: String,
        subtitle: String? = nil,
        imageUrl: String? = nil,
        systemIcon: String? = nil,
        timestamp: Date = Date(),
        productData: MatchedProduct? = nil,
        storeId: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.imageUrl = imageUrl
        self.systemIcon = systemIcon
        self.timestamp = timestamp
        self.productData = productData
        self.storeId = storeId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.type = try container.decode(ActivityType.self, forKey: .type)
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        self.imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        self.systemIcon = try container.decodeIfPresent(String.self, forKey: .systemIcon)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.productData = try container.decodeIfPresent(MatchedProduct.self, forKey: .productData)
        self.storeId = try container.decodeIfPresent(String.self, forKey: .storeId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(systemIcon, forKey: .systemIcon)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(productData, forKey: .productData)
        try container.encodeIfPresent(storeId, forKey: .storeId)
    }

    var effectiveProduct: MatchedProduct {
        if let prod = productData {
            return prod
        }
        return MatchedProduct(
            id_val: id.uuidString,
            canonical_name: title,
            brand: subtitle,
            image_url: imageUrl,
            gender: nil,
            offers: [],
            best_price: nil,
            highest_price: nil,
            cross_store_savings: nil
        )
    }

    var formattedDate: String {
        let calendar = Calendar.current
        let now = Date()

        let elapsedSeconds = now.timeIntervalSince(timestamp)
        if elapsedSeconds < 60 {
            return "adesso"
        } else if elapsedSeconds < 3600 {
            let minutes = max(1, Int(elapsedSeconds / 60))
            return "\(minutes) min fa"
        } else if elapsedSeconds < 86400 {
            let hours = max(1, Int(elapsedSeconds / 3600))
            return hours == 1 ? "1 ora fa" : "\(hours) ore fa"
        }

        if calendar.isDateInYesterday(timestamp) {
            return "ieri"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        if calendar.component(.year, from: timestamp) == calendar.component(.year, from: now) {
            formatter.dateFormat = "MMM d"
        } else {
            formatter.dateFormat = "MMM d yyyy"
        }
        return formatter.string(from: timestamp).lowercased()
    }
}

@MainActor
class RecentActivityManager: ObservableObject {
    static let shared = RecentActivityManager()

    @Published var activities: [RecentActivityItem] = []

    private let saveFileName = "fitmatch_recent_activity.json"

    private var fileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(saveFileName)
    }

    init() {
        loadActivities()
        // Purge legacy test activities from previous shared simulator/tester session
        if !UserDefaults.standard.bool(forKey: "fitmatch_recent_purged_v3") {
            self.activities.removeAll()
            saveActivities()
            UserDefaults.standard.set(true, forKey: "fitmatch_recent_purged_v3")
        }
        Task {
            await syncFromDatabase()
        }
    }

    func syncFromDatabase() async {
        do {
            let supaItems = try await SupabaseManager.shared.fetchRecentActivities()
            self.activities = supaItems
            saveActivities()
        } catch {
            print("RecentActivityManager sync note: \(error)")
        }
    }

    // MARK: - Filtered Views for Search Redesign

    var recentlyViewedProducts: [MatchedProduct] {
        var seen = Set<String>()
        var unique: [MatchedProduct] = []
        for p in activities.compactMap({ $0.productData }) {
            let key = p.canonical_name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(p)
            }
        }
        return unique
    }

    var continueShoppingItems: [RecentActivityItem] {
        var seen = Set<String>()
        var unique: [RecentActivityItem] = []
        for act in activities {
            let key = act.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(act)
            }
        }
        return unique
    }

    // MARK: - Actions

    func recordSearch(_ query: String) {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        // Deduplicate: remove any previous search for the same query so it rises to the top
        activities.removeAll { $0.type == .search && $0.title.caseInsensitiveCompare(clean) == .orderedSame }

        let icon = clean.lowercased().contains("per") || clean.lowercased().contains("miglior") || clean.lowercased().contains("sotto")
            ? "sparkles"
            : "text.bubble.fill"

        let newItem = RecentActivityItem(
            id: UUID(),
            type: .search,
            title: clean,
            subtitle: nil,
            imageUrl: nil,
            systemIcon: icon,
            timestamp: Date(),
            productData: nil
        )

        activities.insert(newItem, at: 0)

        if activities.count > 30 {
            activities = Array(activities.prefix(30))
        }

        saveActivities()

        // Background Sync to Supabase
        Task {
            _ = try? await SupabaseManager.shared.recordRecentActivity(
                type: "search",
                title: clean
            )
        }
    }

    func recordProductView(_ product: MatchedProduct) {
        // Deduplicate: remove any previous entry for this product
        activities.removeAll { $0.type == .product && $0.title.caseInsensitiveCompare(product.canonical_name) == .orderedSame }

        let newItem = RecentActivityItem(
            id: UUID(),
            type: .product,
            title: product.canonical_name,
            subtitle: product.brand,
            imageUrl: product.image_url,
            systemIcon: nil,
            timestamp: Date(),
            productData: product
        )

        activities.insert(newItem, at: 0)

        if activities.count > 30 {
            activities = Array(activities.prefix(30))
        }

        saveActivities()

        // Background Sync to Supabase
        Task {
            let bestPrice = product.best_price ?? product.bestOffer?.price
            let origPrice = product.highest_price ?? product.bestOffer?.original_price
            let store = product.bestOffer?.store_name
            let sId = product.bestOffer?.store_id
            _ = try? await SupabaseManager.shared.recordRecentActivity(
                type: "product",
                title: product.canonical_name,
                subtitle: product.brand,
                imageUrl: product.image_url,
                price: bestPrice,
                originalPrice: origPrice,
                storeId: sId,
                storeName: store
            )
        }
    }

    func recordStoreView(storeId: String, storeName: String, logoUrl: String? = nil) {
        let clean = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        // Deduplicate: remove any previous entry for this store
        activities.removeAll { $0.type == .store && ($0.storeId == storeId || $0.title.caseInsensitiveCompare(clean) == .orderedSame) }

        let newItem = RecentActivityItem(
            id: UUID(),
            type: .store,
            title: clean,
            subtitle: "Negozio",
            imageUrl: logoUrl,
            systemIcon: "bag.fill",
            timestamp: Date(),
            productData: nil,
            storeId: storeId
        )

        activities.insert(newItem, at: 0)

        if activities.count > 30 {
            activities = Array(activities.prefix(30))
        }

        saveActivities()

        // Background Sync to Supabase
        Task {
            _ = try? await SupabaseManager.shared.recordRecentActivity(
                type: "store",
                title: clean,
                subtitle: "Negozio",
                imageUrl: logoUrl,
                storeId: storeId,
                storeName: clean
            )
        }
    }

    func removeActivity(_ item: RecentActivityItem) {
        activities.removeAll { $0.id == item.id }
        saveActivities()
    }

    func clearAll() {
        activities.removeAll()
        saveActivities()
        Task {
            _ = try? await SupabaseManager.shared.clearRecentActivities()
        }
    }

    // MARK: - Persistence

    private func loadActivities() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([RecentActivityItem].self, from: data)
            self.activities = decoded
        } catch {
            print("Errore caricamento cronologia: \(error)")
        }
    }

    private func saveActivities() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(activities)
            try data.write(to: fileURL, options: [.atomicWrite, .completeFileProtection])
        } catch {
            print("Errore salvataggio cronologia: \(error)")
        }
    }
}
