import Foundation

// MARK: - Sync Session Model

public struct SyncSessionItem: Identifiable, Codable, Equatable {
    public let id: String
    public let sessionType: String
    public let triggerSource: String?
    public let status: String
    public let startedAt: String?
    public let completedAt: String?
    public let durationSeconds: Double?
    public let totalItemsProcessed: Int?
    public let totalItemsUpdated: Int?
    public let totalPriceDrops: Int?
    public let errorMessage: String?
    public let storeStats: [String: AnyCodableValue]?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionType = "session_type"
        case triggerSource = "trigger_source"
        case status
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationSeconds = "duration_seconds"
        case totalItemsProcessed = "total_items_processed"
        case totalItemsUpdated = "total_items_updated"
        case totalPriceDrops = "total_price_drops"
        case errorMessage = "error_message"
        case storeStats = "store_stats"
    }

    public var isCompleted: Bool { status.lowercased() == "completed" }
    public var isRunning: Bool { status.lowercased() == "running" }
    public var isFailed: Bool { status.lowercased() == "failed" }

    public var displayTitle: String {
        switch sessionType.lowercased() {
        case "discovery": return "Scoperta Catalogo"
        case "price_refresh": return "Monitor Prezzi"
        case "size_enrichment": return "Arricchimento Taglie"
        case "manual_crawl": return "Crawl Manuale"
        case "embedding_sync": return "Embedding Vettoriali"
        default: return sessionType.capitalized
        }
    }

    public var iconName: String {
        switch sessionType.lowercased() {
        case "discovery": return "sparkles"
        case "price_refresh": return "tag.fill"
        case "size_enrichment": return "ruler"
        case "manual_crawl": return "arrow.triangle.2.circlepath"
        case "embedding_sync": return "brain.head.profile"
        default: return "gearshape.2.fill"
        }
    }

    public var displayDuration: String {
        guard let dur = durationSeconds else { return "—" }
        if dur < 60 {
            return String(format: "%.1fs", dur)
        }
        let mins = Int(dur) / 60
        let secs = Int(dur) % 60
        return "\(mins)m \(secs)s"
    }

    public var displayStartedAt: String {
        guard let started = startedAt else { return "—" }
        if started.count >= 16 {
            let sub = started.prefix(16).replacingOccurrences(of: "T", with: " ")
            return String(sub)
        }
        return started
    }
}

// MARK: - Store Health Metric

public struct StoreHealthMetric: Identifiable, Codable, Equatable {
    public var id: String { storeId }
    public let storeId: String
    public let totalOffers: Int
    public let withSizes: Int
    public let sizeCoveragePct: Double?
    public let avgPrice: Double?
    public let avgDiscount: Double?
    public let lastCheckedAt: String?

    enum CodingKeys: String, CodingKey {
        case storeId = "store_id"
        case totalOffers = "total_offers"
        case withSizes = "with_sizes"
        case sizeCoveragePct = "size_coverage_pct"
        case avgPrice = "avg_price"
        case avgDiscount = "avg_discount"
        case lastCheckedAt = "last_checked_at"
    }

    public var coveragePercentage: Double {
        if let pct = sizeCoveragePct { return pct }
        guard totalOffers > 0 else { return 0.0 }
        return Double(withSizes) / Double(totalOffers) * 100.0
    }

    public var displayName: String {
        switch storeId.lowercased() {
        case "cisalfa": return "Cisalfa Sport"
        case "maxisport": return "Maxi Sport"
        case "misterrunning": return "Mister Running"
        case "decathlon": return "Decathlon"
        case "nike": return "Nike Official"
        case "tradeinn": return "Tradeinn"
        case "df_sportspecialist", "df_sport": return "DF Sport Specialist"
        case "alltricks": return "Alltricks"
        case "deporvillage": return "Deporvillage"
        case "top4running": return "Top4Running"
        case "runningwarehouse": return "Running Warehouse"
        case "nencini": return "Nencini Sport"
        case "adidas": return "Adidas"
        case "sportler": return "Sportler"
        default: return storeId.capitalized
        }
    }
}

// MARK: - AnyCodableValue Helper

public enum AnyCodableValue: Codable, Equatable {
    case int(Int)
    case double(Double)
    case string(String)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let val = try? container.decode(Int.self) {
            self = .int(val)
        } else if let val = try? container.decode(Double.self) {
            self = .double(val)
        } else if let val = try? container.decode(Bool.self) {
            self = .bool(val)
        } else if let val = try? container.decode(String.self) {
            self = .string(val)
        } else {
            self = .string("—")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        }
    }

    public var stringValue: String {
        switch self {
        case .int(let v): return "\(v)"
        case .double(let v): return String(format: "%.1f", v)
        case .string(let v): return v
        case .bool(let v): return v ? "Sì" : "No"
        }
    }
}

// MARK: - Search Feedback Models

public struct ProductEvaluationItem: Codable, Equatable, Identifiable {
    public var id: String { productId ?? UUID().uuidString }
    public let productId: String?
    public let productName: String?
    public let thumb: String?

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case productName = "product_name"
        case thumb
    }

    public var isThumbUp: Bool {
        thumb?.lowercased() == "up"
    }
}

public struct SearchFeedbackItem: Identifiable, Codable, Equatable {
    public let id: String
    public let deviceId: String?
    public let userId: String?
    public let query: String
    public let feedbackType: String
    public let comment: String?
    public let productEvaluations: [ProductEvaluationItem]?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case userId = "user_id"
        case query
        case feedbackType = "feedback_type"
        case comment
        case productEvaluations = "product_evaluations"
        case createdAt = "created_at"
    }

    public var isPositive: Bool {
        feedbackType.lowercased() == "positive"
    }

    public var hasComment: Bool {
        guard let comment = comment else { return false }
        return !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var displayCreatedAt: String {
        guard let created = createdAt else { return "—" }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var parsedDate = isoFormatter.date(from: created)
        if parsedDate == nil {
            let standardIso = ISO8601DateFormatter()
            standardIso.formatOptions = [.withInternetDateTime]
            parsedDate = standardIso.date(from: created)
        }
        if let date = parsedDate {
            let outFormatter = DateFormatter()
            outFormatter.locale = Locale(identifier: "it_IT")
            outFormatter.dateFormat = "d MMM, HH:mm"
            return outFormatter.string(from: date)
        }
        if created.count >= 16 {
            return created.prefix(16).replacingOccurrences(of: "T", with: " ")
        }
        return created
    }
}

// MARK: - Embedding Coverage & Job Models

public struct EmbeddingCategoryCoverage: Identifiable, Codable, Equatable {
    public var id: String { category }
    public let category: String
    public let activeCount: Int
    public let embeddedCount: Int
    public let missingCount: Int
    public let coveragePct: Double?

    enum CodingKeys: String, CodingKey {
        case category
        case activeCount = "active_count"
        case embeddedCount = "embedded_count"
        case missingCount = "missing_count"
        case coveragePct = "coverage_pct"
    }

    public var effectiveCoveragePct: Double {
        if let pct = coveragePct { return pct }
        guard activeCount > 0 else { return 100.0 }
        return Double(embeddedCount) / Double(activeCount) * 100.0
    }

    public var displayName: String {
        switch category.lowercased() {
        case "running_shoes": return "Scarpe Running"
        case "trail_running": return "Trail Running"
        case "football_boots": return "Scarpini Calcio"
        case "swim": return "Nuoto & Piscina"
        case "gps_watch": return "Smartwatch GPS"
        case "cycling": return "Ciclismo"
        case "padel": return "Padel & Tennis"
        case "fitness": return "Fitness & Palestra"
        case "shoes": return "Scarpe Generiche"
        case "top": return "Maglie & Top"
        case "pants": return "Pantaloni & Shorts"
        case "jacket": return "Giacche"
        case "socks": return "Calze"
        case "gear": return "Accessori & Gear"
        case "outdoor": return "Outdoor & Trekking"
        case "hydration": return "Idratazione"
        case "pack": return "Zaini & Marsupi"
        case "eyewear": return "Occhiali Sportivi"
        case "nutrition": return "Nutrizione"
        case "mount": return "Supporti & Attacchi"
        case "strap": return "Cinturini"
        case "case": return "Custodie"
        case "sensor": return "Sensori"
        default: return category.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

public struct EmbeddingJobStatus: Codable, Equatable {
    public let isRunning: Bool
    public let category: String?
    public let batchSize: Int
    public let limit: Int?
    public let processedCount: Int
    public let startedAt: String?
    public let lastFinishedAt: String?
    public let lastStatus: String?
    public let lastError: String?
    public let stopRequested: Bool?

    enum CodingKeys: String, CodingKey {
        case isRunning = "is_running"
        case category
        case batchSize = "batch_size"
        case limit
        case processedCount = "processed_count"
        case startedAt = "started_at"
        case lastFinishedAt = "last_finished_at"
        case lastStatus = "last_status"
        case lastError = "last_error"
        case stopRequested = "stop_requested"
    }

    public static let idle = EmbeddingJobStatus(
        isRunning: false,
        category: nil,
        batchSize: 25,
        limit: nil,
        processedCount: 0,
        startedAt: nil,
        lastFinishedAt: nil,
        lastStatus: "idle",
        lastError: nil,
        stopRequested: false
    )
}

public struct EmbeddingCoverageSummary: Codable, Equatable {
    public let totalActive: Int
    public let totalEmbedded: Int
    public let totalMissing: Int
    public let coveragePct: Double
    public let byCategory: [EmbeddingCategoryCoverage]

    enum CodingKeys: String, CodingKey {
        case totalActive = "total_active"
        case totalEmbedded = "total_embedded"
        case totalMissing = "total_missing"
        case coveragePct = "coverage_pct"
        case byCategory = "by_category"
    }
}

public struct EmbeddingAdminStatusResponse: Codable, Equatable {
    public let job: EmbeddingJobStatus
    public let coverage: EmbeddingCoverageSummary
}
