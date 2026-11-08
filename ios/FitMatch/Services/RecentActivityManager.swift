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
        if let d = try? container.decode(Date.self, forKey: .timestamp) {
            self.timestamp = d
        } else if let s = try? container.decode(String.self, forKey: .timestamp),
                  let d = SupabaseManager.parseISO8601Date(s) {
            self.timestamp = d
        } else if let ts = try? container.decode(Double.self, forKey: .timestamp) {
            self.timestamp = Date(timeIntervalSince1970: ts)
        } else {
            self.timestamp = Date()
        }
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
        if elapsedSeconds <= 60 {
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

        let days = calendar.dateComponents([.day], from: timestamp, to: now).day ?? 0
        if days < 7 {
            return "\(max(2, days)) giorni fa"
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
        // Purge legacy test activities and conversational follow-ups from previous sessions
        if !UserDefaults.standard.bool(forKey: "fitmatch_recent_purged_v5") {
            self.activities = self.activities.filter {
                $0.type != .search || RecentActivityManager.isValidShoppingQuery($0.title)
            }
            saveActivities()
            UserDefaults.standard.set(true, forKey: "fitmatch_recent_purged_v5")
        }

        // Heal any local cache corrupted by previous versions where all items got identical timestamps
        if !UserDefaults.standard.bool(forKey: "fitmatch_recent_timestamps_fixed_v2") {
            let timestamps = self.activities.map { $0.timestamp.timeIntervalSince1970 }
            if let first = timestamps.first, timestamps.count > 1 {
                let allIdentical = timestamps.allSatisfy { abs($0 - first) < 5.0 }
                if allIdentical {
                    self.activities = []
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            UserDefaults.standard.set(true, forKey: "fitmatch_recent_timestamps_fixed_v2")
        }

        Task {
            await syncFromDatabase()
        }
    }

    func syncFromDatabase() async {
        do {
            let supaItems = try await SupabaseManager.shared.fetchRecentActivities()
            // Deduplicate remote items preserving the newest timestamp
            var seenKeys = Set<String>()
            var deduplicated: [RecentActivityItem] = []
            for item in supaItems {
                guard item.type != .search || RecentActivityManager.isValidShoppingQuery(item.title) else {
                    continue
                }
                let key = "\(item.type.rawValue):\(item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                if !seenKeys.contains(key) {
                    seenKeys.insert(key)
                    deduplicated.append(item)
                }
            }

            // Keep any recent local activities that haven't synced to remote yet
            for local in self.activities {
                let key = "\(local.type.rawValue):\(local.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                if !seenKeys.contains(key) {
                    seenKeys.insert(key)
                    deduplicated.append(local)
                }
            }

            deduplicated.sort { $0.timestamp > $1.timestamp }
            if deduplicated.count > 30 {
                deduplicated = Array(deduplicated.prefix(30))
            }
            self.activities = deduplicated
            saveActivities()
        } catch {
            print("RecentActivityManager sync note: \(error)")
        }
    }

    // MARK: - Validation for Shopping Intents

    /// Determines whether a search string represents a genuine product or shopping category,
    /// explicitly excluding conversational follow-up questions, chat prompts, attribute filters,
    /// and off-topic queries from ever appearing in "Continua ad acquistare".
    static func isValidShoppingQuery(_ query: String) -> Bool {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return false }
        guard clean.count <= 60 else { return false }

        // Reject if it contains a question mark (conversational question / follow-up prompt)
        if clean.contains("?") || clean.contains("¿") {
            return false
        }

        let lower = clean.lowercased()

        // 1. Conversational interrogative / follow-up prefixes
        let conversationalPrefixes = [
            "e per ", "e se ", "e con ", "e invece ", "ma ", "oppure ",
            "quali ", "quale ", "cosa ", "come ", "perché ", "perchè ", "quanto ", "quanti ", "quante ",
            "chi ", "dove ", "quando ",
            "ci sono ", "c'è ", "c’è ", "ce ne sono ",
            "mostrami ", "fammi vedere ", "trovami ", "consigliami ", "consiglia ",
            "dimmi ", "parlami di ", "aiutami a ", "spiegami ",
            "confronta ", "compara ", "differenza tra ",
            "vorrei ", "voglio ", "cerco un ", "cerco una ", "sto cercando ",
            "what ", "which ", "how ", "why ", "where ", "can you ", "show me ", "tell me ", "compare ", "recommend "
        ]
        for prefix in conversationalPrefixes {
            if lower.hasPrefix(prefix) {
                return false
            }
        }

        // 2. Isolated refinements / filters (not shopping products by themselves)
        let isolatedRefinements = [
            "prezzo più basso", "prezzo piu basso", "più economico", "piu economico",
            "meno caro", "in sconto", "in offerta", "in saldo", "scontati", "scontate",
            "da uomo", "da donna", "per uomo", "per donna", "unisex",
            "da bambino", "da bambina", "per bambini", "per bambina", "ragazzo", "ragazza",
            "spedizione gratuita", "miglior prezzo", "migliore offerta"
        ]
        if isolatedRefinements.contains(lower) {
            return false
        }

        // Standalone size or price filters
        if lower.hasPrefix("taglia ") || lower.hasPrefix("tg ") || lower.hasPrefix("numero ") {
            return false
        }
        if lower.hasPrefix("sotto i ") || lower.hasPrefix("sotto ") || lower.hasPrefix("meno di ") || lower.hasPrefix("fino a ") || lower.hasPrefix("max ") {
            return false
        }

        // 3. Smalltalk / Greetings
        let smalltalk = [
            "ciao", "salve", "buongiorno", "buonasera", "buonanotte",
            "come stai", "chi sei", "grazie", "grazie mille", "ok", "va bene", "perfetto"
        ]
        if smalltalk.contains(lower) {
            return false
        }

        // 4. Off-topic domain guardrails (food recipes, weather forecasts, injections)
        let offTopicKeywords = [
            "pasta", "carbonara", "pizza", "amatriciana", "cacio e pepe", "spaghetti",
            "ricetta", "cucina", "ristorante", "cena", "pranzo", "colazione",
            "che tempo", "meteo", "previsioni del tempo", "gradi oggi",
            "system prompt", "ignore previous", "dan mode", "jailbreak", "<script", "eval("
        ]
        for keyword in offTopicKeywords {
            if lower.contains(keyword) {
                return false
            }
        }

        return true
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
            // Must be a viewed product, a store, or a genuine shopping search query
            if act.type == .search && !RecentActivityManager.isValidShoppingQuery(act.title) {
                continue
            }
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
        // Guard against conversational follow-up questions, off-topic tests, or isolated filters
        guard RecentActivityManager.isValidShoppingQuery(clean) else { return }

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
            // Sanitize loaded activities so conversational/follow-up queries never persist
            self.activities = decoded.filter {
                $0.type != .search || RecentActivityManager.isValidShoppingQuery($0.title)
            }
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
