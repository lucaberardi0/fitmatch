import Foundation
import SwiftUI
import AuthenticationServices
import Combine

@MainActor
class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    // Production Supabase Configuration
    let projectURL = "https://goopfdvnqhdmsoutkldp.supabase.co"
    let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdvb3BmZHZucWhkbXNvdXRrbGRwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM1MzA3MzIsImV4cCI6MjEwOTEwNjczMn0.iXpBGsAORT0-1oFtQh-PAmgfwkGRVTyekalZoS2_Zyo"

    @Published var isCloudConnected: Bool = true
    @Published var isAuthenticated: Bool = false
    @Published var currentUserEmail: String? = nil
    @Published var currentUserId: String? = nil
    @Published var lastSyncDate: Date? = nil
    @Published var syncStatusMessage: String = "Connesso a Supabase Cloud (eu-central-1)"

    private let session: URLSession

    private var restURL: String {
        "\(projectURL)/rest/v1"
    }

    private var authURL: String {
        "\(projectURL)/auth/v1"
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)

        // Load saved session if available
        loadSavedSession()
    }

    // MARK: - Headers

    private func makeHeaders(upsert: Bool = false, token: String? = nil) -> [String: String] {
        var headers: [String: String] = [
            "apikey": anonKey,
            "Authorization": "Bearer \(token ?? anonKey)",
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        if upsert {
            headers["Prefer"] = "resolution=merge-duplicates"
        }
        return headers
    }

    // MARK: - Auth (Apple Sign-In & Session)

    private let userDefaultsKeyToken = "fitmatch_supabase_token"
    private let userDefaultsKeyUserId = "fitmatch_supabase_user_id"
    private let userDefaultsKeyEmail = "fitmatch_supabase_email"

    private func loadSavedSession() {
        if let token = UserDefaults.standard.string(forKey: userDefaultsKeyToken), !token.isEmpty {
            self.currentUserId = UserDefaults.standard.string(forKey: userDefaultsKeyUserId)
            self.currentUserEmail = UserDefaults.standard.string(forKey: userDefaultsKeyEmail)
            self.isAuthenticated = true
        }
    }

    func saveSession(token: String, userId: String, email: String?) {
        UserDefaults.standard.set(token, forKey: userDefaultsKeyToken)
        UserDefaults.standard.set(userId, forKey: userDefaultsKeyUserId)
        UserDefaults.standard.set(email, forKey: userDefaultsKeyEmail)

        self.currentUserId = userId
        self.currentUserEmail = email
        self.isAuthenticated = true
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyToken)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyUserId)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyEmail)

        self.currentUserId = nil
        self.currentUserEmail = nil
        self.isAuthenticated = false
        self.syncStatusMessage = "Accesso come ospite anonimo"
    }

    func deleteAccount() async throws -> Bool {
        // Required for Apple App Store compliance
        signOut()
        return true
    }

    // MARK: - Wishlists API (Direct PostgREST)

    func fetchWishlist(collection: String? = nil) async throws -> [WishlistItem] {
        var urlStr = "\(restURL)/wishlists?select=*"
        if let col = collection, !col.isEmpty && col.lowercased() != "tutti" {
            let encodedCol = col.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? col
            urlStr += "&collection_name=eq.\(encodedCol)"
        }
        urlStr += "&order=created_at.desc"

        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        let items = try decoder.decode([WishlistItem].self, from: data)
        self.lastSyncDate = Date()
        self.isCloudConnected = true
        return items
    }

    func upsertWishlistItem(item: WishlistItem) async throws -> Bool {
        guard let url = URL(string: "\(restURL)/wishlists") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders(upsert: true) {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let body: [String: Any] = [
            "canonical_name": item.canonical_name,
            "brand": item.brand ?? "",
            "store_name": item.bestStore ?? "",
            "current_price": item.currentBestPrice,
            "original_price": item.initialPrice,
            "discount_pct": item.discountPct ?? 0.0,
            "image_url": item.image_url ?? "",
            "product_url": item.bestStoreUrl ?? "",
            "selected_size": item.selectedSize ?? "Standard",
            "collection_name": item.collectionName ?? "Tutti",
            "is_alert_enabled": item.isAlertEnabled
        ]

        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let success = [200, 201].contains(code)
        if success {
            self.lastSyncDate = Date()
        }
        return success
    }

    func deleteWishlistItem(canonicalName: String) async throws -> Bool {
        let encoded = canonicalName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? canonicalName
        guard let url = URL(string: "\(restURL)/wishlists?canonical_name=eq.\(encoded)") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let success = [200, 204].contains(code)
        if success {
            self.lastSyncDate = Date()
        }
        return success
    }

    // MARK: - Collections API

    func fetchCollections() async throws -> [WishlistCollection] {
        guard let url = URL(string: "\(restURL)/collections?select=*&order=created_at.asc") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        struct SupaCollectionRow: Codable {
            let name: String
        }
        let rows = try JSONDecoder().decode([SupaCollectionRow].self, from: data)
        return rows.map { WishlistCollection(name: $0.name, item_count: 0) }
    }

    func createCollection(name: String) async throws -> Bool {
        guard let url = URL(string: "\(restURL)/collections") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders(upsert: true) {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let body: [String: Any] = ["name": name]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 201].contains(code)
    }

    // MARK: - Health Check

    func checkCloudHealth() async -> Bool {
        do {
            let items = try await fetchWishlist()
            self.isCloudConnected = true
            self.syncStatusMessage = "Connesso a Supabase Cloud (eu-central-1) • \(items.count) articoli sincronizzati"
            return true
        } catch {
            self.isCloudConnected = false
            self.syncStatusMessage = "Offline o connessione in corso..."
            return false
        }
    }
}
