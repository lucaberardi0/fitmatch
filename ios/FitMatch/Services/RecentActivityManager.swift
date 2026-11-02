import Foundation
import SwiftUI
import Combine

enum ActivityType: String, Codable {
    case search
    case product
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

    var formattedDate: String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(timestamp) {
            return "oggi"
        } else if calendar.isDateInYesterday(timestamp) {
            return "ieri"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        if calendar.component(.year, from: timestamp) == calendar.component(.year, from: now) {
            formatter.dateFormat = "d MMM"
        } else {
            formatter.dateFormat = "d MMM yyyy"
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
        Task {
            await syncFromDatabase()
        }
    }

    func syncFromDatabase() async {
        do {
            let supaItems = try await SupabaseManager.shared.fetchRecentActivities()
            if !supaItems.isEmpty {
                self.activities = supaItems
                saveActivities()
            }
        } catch {
            print("RecentActivityManager sync note: \(error)")
        }
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

    func removeActivity(_ item: RecentActivityItem) {
        activities.removeAll { $0.id == item.id }
        saveActivities()
    }

    func clearAll() {
        activities.removeAll()
        saveActivities()
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
