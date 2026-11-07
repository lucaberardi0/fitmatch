import Foundation
import Combine

public struct CrawlLogItem: Identifiable, Codable, Equatable {
    public let id: Int
    public let storeId: String
    public let category: String
    public let itemsFound: Int
    public let durationSeconds: Double
    public let crawledAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case category
        case itemsFound = "items_found"
        case durationSeconds = "duration_seconds"
        case crawledAt = "crawled_at"
    }
}

@MainActor
public class AdminNetworkService: ObservableObject {
    public static let shared = AdminNetworkService()

    // Production Cloud Supabase instance
    public let supabaseBaseURL = "https://goopfdvnqhdmsoutkldp.supabase.co/rest/v1"
    public let supabaseApiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdvb3BmZHZucWhkbXNvdXRrbGRwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM1MzA3MzIsImV4cCI6MjEwOTEwNjczMn0.iXpBGsAORT0-1oFtQh-PAmgfwkGRVTyekalZoS2_Zyo"

    // Backend URL (Render Cloud default, editable in Settings)
    @Published public var backendURL: String = "https://fitmatch-backend-klhv.onrender.com"
    @Published public var isBackendOnline: Bool = false
    @Published public var isSupabaseOnline: Bool = false

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)

        #if targetEnvironment(simulator)
        self.backendURL = "http://127.0.0.1:8000"
        #endif
    }

    private func makeSupabaseHeaders() -> [String: String] {
        return [
            "apikey": supabaseApiKey,
            "Authorization": "Bearer \(supabaseApiKey)",
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
    }

    // MARK: - Supabase Direct Queries (Works anywhere on iPhone without local server)

    public func fetchSyncSessions(limit: Int = 40, sessionType: String? = nil) async -> [SyncSessionItem] {
        var endpoint = "\(supabaseBaseURL)/sync_sessions?select=*&order=started_at.desc&limit=\(limit)"
        if let type = sessionType, !type.isEmpty {
            endpoint += "&session_type=eq.\(type)"
        }
        guard let url = URL(string: endpoint) else { return [] }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in makeSupabaseHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }

        do {
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let items = try JSONDecoder().decode([SyncSessionItem].self, from: data)
            self.isSupabaseOnline = true
            return items
        } catch {
            print("[AdminNetwork] Error fetching sessions: \(error)")
            return []
        }
    }

    public func fetchStoreHealthMetrics() async -> [StoreHealthMetric] {
        guard let url = URL(string: "\(supabaseBaseURL)/store_health_metrics?select=*&order=total_offers.desc") else { return [] }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in makeSupabaseHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }

        do {
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let items = try JSONDecoder().decode([StoreHealthMetric].self, from: data)
            self.isSupabaseOnline = true
            return items
        } catch {
            print("[AdminNetwork] Error fetching store health: \(error)")
            return []
        }
    }

    public func fetchSessionCrawlLogs(sessionId: String) async -> [CrawlLogItem] {
        guard let url = URL(string: "\(supabaseBaseURL)/crawl_logs?session_id=eq.\(sessionId)&select=*&order=crawled_at.asc") else { return [] }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in makeSupabaseHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }

        do {
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            return (try? JSONDecoder().decode([CrawlLogItem].self, from: data)) ?? []
        } catch {
            return []
        }
    }

    public func fetchSearchFeedbacks(limit: Int = 100) async -> [SearchFeedbackItem] {
        guard let url = URL(string: "\(supabaseBaseURL)/search_feedback?select=*&order=created_at.desc&limit=\(limit)") else { return [] }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in makeSupabaseHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }

        do {
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let items = try JSONDecoder().decode([SearchFeedbackItem].self, from: data)
            self.isSupabaseOnline = true
            return items
        } catch {
            print("[AdminNetwork] Error fetching search feedback: \(error)")
            return []
        }
    }

    public func deleteSearchFeedback(id: String) async -> Bool {
        guard let url = URL(string: "\(supabaseBaseURL)/search_feedback?id=eq.\(id)") else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        for (k, v) in makeSupabaseHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }

        do {
            let (_, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return status >= 200 && status < 300
        } catch {
            print("[AdminNetwork] Error deleting search feedback: \(error)")
            return false
        }
    }

    public func deleteSyncSession(id: String) async -> Bool {
        // Try deleting from backend first
        if let bUrl = URL(string: "\(backendURL)/api/scheduler/sessions/\(id)") {
            var req = URLRequest(url: bUrl)
            req.httpMethod = "DELETE"
            if let (_, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode >= 200 && http.statusCode < 300 {
                return true
            }
        }

        // Direct Supabase fallback
        guard let url = URL(string: "\(supabaseBaseURL)/sync_sessions?id=eq.\(id)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        for (k, v) in makeSupabaseHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        do {
            let (_, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return status >= 200 && status < 300
        } catch {
            print("[AdminNetwork] Error deleting sync session: \(error)")
            return false
        }
    }

    public func clearFailedSessions() async -> Bool {
        // Try clearing via backend first
        if let bUrl = URL(string: "\(backendURL)/api/scheduler/sessions?status=failed") {
            var req = URLRequest(url: bUrl)
            req.httpMethod = "DELETE"
            if let (_, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode >= 200 && http.statusCode < 300 {
                return true
            }
        }

        // Direct Supabase fallback
        guard let url = URL(string: "\(supabaseBaseURL)/sync_sessions?status=eq.failed") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        for (k, v) in makeSupabaseHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        do {
            let (_, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return status >= 200 && status < 300
        } catch {
            print("[AdminNetwork] Error clearing failed sync sessions: \(error)")
            return false
        }
    }

    // MARK: - FastAPI Backend Triggers

    public func checkBackendHealth() async -> Bool {
        guard let url = URL(string: "\(backendURL)/health") else { return false }
        do {
            let (_, resp) = try await session.data(from: url)
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            self.isBackendOnline = ok
            return ok
        } catch {
            self.isBackendOnline = false
            return false
        }
    }

    public func triggerDiscovery(limitPerStore: Int = 200) async throws -> Bool {
        guard let url = URL(string: "\(backendURL)/api/scheduler/run-discovery?limit_per_store=\(limitPerStore)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (_, resp) = try await session.data(for: req)
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    public func triggerPriceRefresh(limit: Int = 50) async throws -> Bool {
        guard let url = URL(string: "\(backendURL)/api/scheduler/run-refresh?limit=\(limit)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (_, resp) = try await session.data(for: req)
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    public func triggerSizeEnrichment(limitPerStore: Int = 50) async throws -> Bool {
        guard let url = URL(string: "\(backendURL)/api/scheduler/run-enrichment?limit_per_store=\(limitPerStore)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (_, resp) = try await session.data(for: req)
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    public func triggerRecluster() async throws -> Bool {
        guard let url = URL(string: "\(backendURL)/api/catalog/recluster") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (_, resp) = try await session.data(for: req)
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    public func crawlStore(storeId: String, limit: Int = 150) async throws -> Bool {
        let encoded = storeId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? storeId
        guard let url = URL(string: "\(backendURL)/api/crawl?store=\(encoded)&limit_per_store=\(limit)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (_, resp) = try await session.data(for: req)
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Affiliate Monetization Analytics

    public func fetchAffiliateStats() async -> [String: Any]? {
        guard let url = URL(string: "\(backendURL)/api/admin/affiliate/stats") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        } catch {
            return nil
        }
        return nil
    }
}
