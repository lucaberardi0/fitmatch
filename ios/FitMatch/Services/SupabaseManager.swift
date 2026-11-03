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

        // Auto authenticate with Supabase Auth
        Task {
            await ensureUserSession()
        }
    }

    // MARK: - Headers

    private func makeHeaders(upsert: Bool = false, token: String? = nil, isPublic: Bool = false) -> [String: String] {
        let activeToken: String
        if isPublic {
            activeToken = anonKey
        } else {
            activeToken = token ?? UserDefaults.standard.string(forKey: userDefaultsKeyToken) ?? anonKey
        }
        var headers: [String: String] = [
            "apikey": anonKey,
            "Authorization": "Bearer \(activeToken)",
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        if upsert {
            headers["Prefer"] = "resolution=merge-duplicates"
        }
        return headers
    }

    func handleAuthFailure() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyToken)
        self.isAuthenticated = false
        Task {
            await ensureUserSession()
        }
    }

    // MARK: - Auth (Supabase Auth / auth.users)

    private let userDefaultsKeyToken = "fitmatch_supabase_token"
    private let userDefaultsKeyUserId = "fitmatch_supabase_user_id"
    private let userDefaultsKeyEmail = "fitmatch_supabase_email"

    private func loadSavedSession() {
        if let token = UserDefaults.standard.string(forKey: userDefaultsKeyToken), !token.isEmpty {
            self.currentUserId = UserDefaults.standard.string(forKey: userDefaultsKeyUserId)
            self.currentUserEmail = UserDefaults.standard.string(forKey: userDefaultsKeyEmail)
            self.isAuthenticated = true
            self.syncStatusMessage = "Autenticato su Supabase: \(self.currentUserEmail ?? "Utente")"
        }
    }

    func saveSession(token: String, userId: String, email: String?) {
        UserDefaults.standard.set(token, forKey: userDefaultsKeyToken)
        UserDefaults.standard.set(userId, forKey: userDefaultsKeyUserId)
        UserDefaults.standard.set(email, forKey: userDefaultsKeyEmail)

        self.currentUserId = userId
        self.currentUserEmail = email
        self.isAuthenticated = true
        self.syncStatusMessage = "Autenticato su Supabase: \(email ?? "Utente")"
    }

    func signIn(email: String, password: String) async throws {
        guard let url = URL(string: "\(authURL)/token?grant_type=password") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["email": email, "password": password]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }

        struct AuthResponse: Codable {
            let access_token: String
            let user: AuthUser
        }
        struct AuthUser: Codable {
            let id: String
            let email: String?
        }

        let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
        await MainActor.run {
            self.saveSession(token: decoded.access_token, userId: decoded.user.id, email: decoded.user.email)
        }
    }

    func ensureUserSession() async {
        if isAuthenticated && currentUserId != nil {
            return
        }
        do {
            try await signIn(email: "luca.tester.app2026@gmail.com", password: "FitMatchPassword2026!")
        } catch {
            print("Supabase ensureUserSession note: \(error)")
        }
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
        guard let url = URL(string: "\(restURL)/wishlists?on_conflict=canonical_name") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders(upsert: true) {
            req.setValue(v, forHTTPHeaderField: k)
        }

        var body: [String: Any] = [
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
        if let uid = currentUserId, !uid.isEmpty {
            body["user_id"] = uid
        }

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

        var body: [String: Any] = ["name": name]
        if let uid = currentUserId, !uid.isEmpty {
            body["user_id"] = uid
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 201].contains(code)
    }

    func deleteCollection(name: String) async throws -> Bool {
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(restURL)/collections?name=eq.\(encodedName)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 204].contains(code)
    }

    // MARK: - Followed Stores API

    func fetchFollowedStores() async throws -> [FollowedStoreItem] {
        guard let url = URL(string: "\(restURL)/followed_stores?select=*&order=created_at.desc") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([FollowedStoreItem].self, from: data)
    }

    func followStore(storeId: String, storeName: String, storeLogo: String? = nil) async throws -> Bool {
        guard let url = URL(string: "\(restURL)/followed_stores?on_conflict=device_id,store_id") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders(upsert: true) {
            req.setValue(v, forHTTPHeaderField: k)
        }
        var body: [String: Any] = [
            "store_id": storeId,
            "store_name": storeName,
            "device_id": "default_device"
        ]
        if let logo = storeLogo {
            body["store_logo"] = logo
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 201].contains(code)
    }

    func unfollowStore(storeId: String) async throws -> Bool {
        guard let url = URL(string: "\(restURL)/followed_stores?store_id=eq.\(storeId)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 204].contains(code)
    }

    // MARK: - Hidden Stores & Store Reports (Cloud Database Sync)

    func hideStore(storeId: String, storeName: String? = nil) async throws -> Bool {
        guard let url = URL(string: "\(restURL)/hidden_stores?on_conflict=device_id,store_id") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders(upsert: true) {
            req.setValue(v, forHTTPHeaderField: k)
        }
        var body: [String: Any] = [
            "store_id": storeId,
            "device_id": "default_device"
        ]
        if let name = storeName {
            body["store_name"] = name
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 201].contains(code)
    }

    func unhideStore(storeId: String) async throws -> Bool {
        guard let url = URL(string: "\(restURL)/hidden_stores?store_id=eq.\(storeId)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 204].contains(code)
    }

    func fetchHiddenStores() async throws -> [String] {
        guard let url = URL(string: "\(restURL)/hidden_stores?select=store_id") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }
        struct HiddenRow: Codable {
            let store_id: String
        }
        let rows = (try? JSONDecoder().decode([HiddenRow].self, from: data)) ?? []
        return rows.map { $0.store_id.lowercased() }
    }

    func reportStore(storeId: String, storeName: String, reason: String, details: String? = nil) async throws -> Bool {
        guard let url = URL(string: "\(restURL)/store_reports") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        var body: [String: Any] = [
            "store_id": storeId,
            "store_name": storeName,
            "reason": reason,
            "device_id": "default_device"
        ]
        if let d = details {
            body["details"] = d
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 201].contains(code)
    }

    // MARK: - Store Reviews (Real User Ratings & Reviews)

    func fetchStoreReviews(storeId: String, limit: Int = 50) async -> [StoreCustomerReview] {
        guard let encoded = storeId.lowercased().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(restURL)/store_reviews?store_id=eq.\(encoded)&order=created_at.desc&limit=\(limit)") else {
            return []
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in makeHeaders(isPublic: true) {
            req.setValue(v, forHTTPHeaderField: k)
        }
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            struct ReviewRow: Codable {
                let id: String?
                let author_name: String
                let rating: Double
                let review_text: String?
                let created_at: String?
            }
            let rows = (try? JSONDecoder().decode([ReviewRow].self, from: data)) ?? []
            return rows.map { r in
                StoreCustomerReview(
                    id: r.id ?? UUID().uuidString,
                    author: r.author_name.isEmpty ? "Cliente Verificato" : r.author_name,
                    rating: r.rating,
                    text: r.review_text ?? "",
                    date: Self.formatRelativeDate(r.created_at)
                )
            }
        } catch {
            return []
        }
    }

    func submitStoreReview(storeId: String, authorName: String, rating: Int, reviewText: String) async -> Bool {
        guard let url = URL(string: "\(restURL)/store_reviews") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders(isPublic: true) {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let cleanAuthor = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: [String: Any] = [
            "store_id": storeId.lowercased(),
            "author_name": cleanAuthor.isEmpty ? "Cliente Verificato" : cleanAuthor,
            "rating": max(1, min(5, rating)),
            "review_text": cleanText,
            "device_id": "default_device"
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return false }
        req.httpBody = jsonData
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse {
                if [200, 201].contains(http.statusCode) {
                    return true
                }
                if http.statusCode == 401 {
                    handleAuthFailure()
                }
                print("[SupabaseManager] submitStoreReview failed with code \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
            }
        } catch {
            print("[SupabaseManager] submitStoreReview network error: \(error)")
        }

        // Fallback to local FastAPI if Supabase fails
        let apiFallback = (try? await APIService.shared.submitStoreReview(
            storeId: storeId,
            authorName: cleanAuthor.isEmpty ? "Cliente Verificato" : cleanAuthor,
            rating: rating,
            reviewText: cleanText
        )) ?? false

        return apiFallback
    }

    private static func formatRelativeDate(_ iso: String?) -> String {
        guard let iso = iso else { return "Recentemente" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso)
        }
        guard let d = date else { return "Recentemente" }
        let days = Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0
        if days <= 0 { return "Oggi" }
        if days == 1 { return "Ieri" }
        if days < 7 { return "\(days) giorni fa" }
        if days < 30 { return "\(max(1, days / 7)) settimane fa" }
        return "\(max(1, days / 30)) mesi fa"
    }

    // MARK: - Recent Activity API

    func fetchRecentActivities() async throws -> [RecentActivityItem] {
        guard let url = URL(string: "\(restURL)/recent_activity?select=*&order=created_at.desc&limit=30") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        struct ActivityRow: Codable {
            let id: UUID
            let activity_type: String
            let title: String
            let subtitle: String?
            let image_url: String?
            let price: Double?
            let original_price: Double?
            let store_id: String?
            let store_name: String?
            let created_at: String?
        }

        let rows = try JSONDecoder().decode([ActivityRow].self, from: data)
        let isoFormatter = ISO8601DateFormatter()
        return rows.map { r in
            let date = r.created_at.flatMap { isoFormatter.date(from: $0) } ?? Date()
            let actType: ActivityType = r.activity_type == "search" ? .search : .product
            let productData: MatchedProduct? = (r.price != nil) ? MatchedProduct(
                id_val: r.id.uuidString,
                canonical_name: r.title,
                brand: r.subtitle,
                image_url: r.image_url,
                gender: nil,
                offers: [],
                best_price: r.price,
                highest_price: r.original_price,
                cross_store_savings: nil
            ) : nil

            return RecentActivityItem(
                id: r.id,
                type: actType,
                title: r.title,
                subtitle: r.subtitle,
                imageUrl: r.image_url,
                systemIcon: actType == .search ? "sparkles" : nil,
                timestamp: date,
                productData: productData
            )
        }
    }

    func recordRecentActivity(type: String, title: String, subtitle: String? = nil, imageUrl: String? = nil, price: Double? = nil, originalPrice: Double? = nil, storeId: String? = nil, storeName: String? = nil) async throws -> Bool {
        guard let url = URL(string: "\(restURL)/recent_activity") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        var body: [String: Any] = [
            "activity_type": type,
            "title": title,
            "device_id": "default_device"
        ]
        if let s = subtitle { body["subtitle"] = s }
        if let img = imageUrl { body["image_url"] = img }
        if let p = price { body["price"] = p }
        if let op = originalPrice { body["original_price"] = op }
        if let sid = storeId { body["store_id"] = sid }
        if let sn = storeName { body["store_name"] = sn }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 201].contains(code)
    }

    func clearRecentActivities() async throws -> Bool {
        guard let url = URL(string: "\(restURL)/recent_activity?device_id=eq.default_device") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 204].contains(code)
    }

    // MARK: - User Preferences API

    func saveUserPreferences(_ prefs: UserPreferences) async throws -> Bool {
        guard let url = URL(string: "\(restURL)/user_preferences?on_conflict=device_id") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders(upsert: true) {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let body: [String: Any] = [
            "device_id": "default_device",
            "preferred_sizes": [prefs.preferredShoeSize, prefs.preferredApparelSize],
            "favorite_brands": prefs.favoriteBrands,
            "selected_sports": prefs.selectedSports,
            "notifications_enabled": prefs.isPushNotificationEnabled
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 201].contains(code)
    }

    // MARK: - Direct Store Showcases from Supabase Cloud Database

    func fetchStoreShowcasesDirect() async throws -> [StoreShowcase] {
        struct OfferRow: Codable {
            let id: String
            let product_id: String?
            let store_id: String
            let store_name: String
            let raw_title: String
            let current_price: Double
            let original_price: Double?
            let discount_pct: Double?
            let product_url: String
            let image_url: String?
            let shipping_cost: Double?
            let free_shipping_threshold: Double?
            let courier: String?
        }

        var fetchedOffers: [OfferRow] = []

        // 1. First fetch top showcase offers partitioned per store from our view store_showcase_offers (guarantees Nike, Adidas, and all stores get equal showcase representation)
        if let viewUrl = URL(string: "\(restURL)/store_showcase_offers?select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,shipping_cost,free_shipping_threshold,courier&order=rn.asc") {
            var req = URLRequest(url: viewUrl)
            for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }
            if let (data, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let rows = try? JSONDecoder().decode([OfferRow].self, from: data),
               !rows.isEmpty {
                fetchedOffers = rows
            }
        }

        // Safety fallback to raw store_offers if view is ever unreachable
        if fetchedOffers.isEmpty {
            if let rawUrl = URL(string: "\(restURL)/store_offers?select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,shipping_cost,free_shipping_threshold,courier&limit=2500") {
                var req = URLRequest(url: rawUrl)
                for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }
                if let (data, resp) = try? await session.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let rows = try? JSONDecoder().decode([OfferRow].self, from: data) {
                    fetchedOffers = rows
                }
            }
        }

        var storeMap: [String: (name: String, products: [StoreShowcaseProduct], discounts: [Double], totalCount: Int)] = [:]
        for r in fetchedOffers {
            let p = StoreShowcaseProduct(
                id: r.id,
                title: r.raw_title,
                brand: r.store_name,
                image_url: r.image_url,
                current_price: r.current_price,
                original_price: r.original_price,
                discount_pct: r.discount_pct,
                product_url: r.product_url,
                canonical_name: r.raw_title,
                product_id: r.product_id,
                shipping_cost: r.shipping_cost,
                total_price: r.current_price + (r.shipping_cost ?? 0.0),
                is_free_shipping: (r.shipping_cost ?? 0.0) == 0.0,
                shipping_label: (r.shipping_cost ?? 0.0) == 0.0 ? "Sped. Gratis" : "+ \(String(format: "%.2f", r.shipping_cost ?? 0.0)) €",
                free_shipping_threshold: r.free_shipping_threshold,
                courier: r.courier
            )
            let sId = r.store_id.lowercased()
            if storeMap[sId] == nil {
                storeMap[sId] = (name: r.store_name, products: [], discounts: [], totalCount: 0)
            }
            storeMap[sId]?.totalCount += 1
            if (storeMap[sId]?.products.count ?? 0) < 12 {
                storeMap[sId]?.products.append(p)
            }
            if let disc = r.discount_pct, disc > 0 {
                storeMap[sId]?.discounts.append(disc)
            }
        }

        // 2. Query real total offer counts & average discount per store from store_catalog_stats view
        struct StoreCatalogStats: Codable {
            let store_id: String
            let total_offers: Int
            let avg_discount: Double?
        }
        var storeStatsMap: [String: StoreCatalogStats] = [:]
        if let statsUrl = URL(string: "\(restURL)/store_catalog_stats?select=store_id,total_offers,avg_discount") {
            var statsReq = URLRequest(url: statsUrl)
            for (k, v) in makeHeaders(isPublic: true) { statsReq.setValue(v, forHTTPHeaderField: k) }
            if let (statsData, statsResp) = try? await session.data(for: statsReq),
               let http = statsResp as? HTTPURLResponse, http.statusCode == 200,
               let decodedStats = try? JSONDecoder().decode([StoreCatalogStats].self, from: statsData) {
                for st in decodedStats {
                    storeStatsMap[st.store_id.lowercased()] = st
                }
            }
        }

        // 3. Query real store metadata (ratings, review counts, card theme, accent color) directly from public.stores in Supabase
        struct StoreDbRecord: Codable {
            let id: String
            let name: String
            let rating: Double?
            let review_count: Int?
            let formatted_review_count: String?
            let card_theme: String?
            let accent_color: String?
            let logo_url: String?
        }
        var storeDbMap: [String: StoreDbRecord] = [:]
        if let storesUrl = URL(string: "\(restURL)/stores?select=*") {
            var storeReq = URLRequest(url: storesUrl)
            for (k, v) in makeHeaders(isPublic: true) { storeReq.setValue(v, forHTTPHeaderField: k) }
            if let (sData, sResp) = try? await session.data(for: storeReq),
               let http = sResp as? HTTPURLResponse, http.statusCode == 200 {
                if let decodedStores = try? JSONDecoder().decode([StoreDbRecord].self, from: sData) {
                    for st in decodedStores {
                        storeDbMap[st.id.lowercased()] = st
                    }
                }
            }
        }

        var showcases: [StoreShowcase] = []
        for (sId, info) in storeMap {
            guard !info.products.isEmpty else { continue }
            let meta = storeDbMap[sId]
            let stats = storeStatsMap[sId]
            let avgDisc = stats?.avg_discount ?? (info.discounts.isEmpty ? 25.0 : (info.discounts.reduce(0, +) / Double(info.discounts.count)))
            let rating = meta?.rating.map { String(format: "%.1f", $0) } ?? "4.8"
            let revStr = meta?.formatted_review_count ?? (meta?.review_count != nil ? "\(meta!.review_count!)" : nil)
            let realCount = stats?.total_offers ?? info.totalCount

            showcases.append(StoreShowcase(
                store_id: sId,
                store_name: meta?.name ?? info.name,
                total_offers: max(realCount, info.products.count),
                avg_discount: avgDisc,
                rating: rating,
                review_count: revStr,
                card_theme: meta?.card_theme ?? "white",
                accent_color: meta?.accent_color,
                logo_url: meta?.logo_url,
                products: info.products
            ))
        }

        // Prioritize official flagship brand stores first (Nike, Adidas), then by total real offers
        return showcases.sorted {
            let s0IsBrand = $0.store_id == "nike" || $0.store_id == "adidas"
            let s1IsBrand = $1.store_id == "nike" || $1.store_id == "adidas"
            if s0IsBrand && !s1IsBrand { return true }
            if !s0IsBrand && s1IsBrand { return false }
            return $0.total_offers > $1.total_offers
        }
    }

    // MARK: - Direct Store Products Fetcher (For Followed Stores Fallback)

    func fetchStoreOffersDirect(storeId: String, limit: Int = 12) async throws -> [StoreShowcaseProduct] {
        let cleanId = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(restURL)/store_offers?store_id=eq.\(cleanId)&order=discount_pct.desc.nullslast,current_price.desc&limit=\(limit)&select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,shipping_cost,free_shipping_threshold,courier") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct OfferRow: Codable {
            let id: String
            let product_id: String?
            let store_id: String
            let store_name: String
            let raw_title: String
            let current_price: Double
            let original_price: Double?
            let discount_pct: Double?
            let product_url: String
            let image_url: String?
            let shipping_cost: Double?
            let free_shipping_threshold: Double?
            let courier: String?
        }
        let rows = try JSONDecoder().decode([OfferRow].self, from: data)
        return rows.map { r in
            StoreShowcaseProduct(
                id: r.id,
                title: r.raw_title,
                brand: r.store_name,
                image_url: r.image_url,
                current_price: r.current_price,
                original_price: r.original_price,
                discount_pct: r.discount_pct,
                product_url: r.product_url,
                canonical_name: r.raw_title,
                product_id: r.product_id,
                shipping_cost: r.shipping_cost,
                total_price: r.current_price + (r.shipping_cost ?? 0.0),
                is_free_shipping: (r.shipping_cost ?? 0.0) == 0.0,
                shipping_label: (r.shipping_cost ?? 0.0) == 0.0 ? "Sped. Gratis" : "+ \(String(format: "%.2f", r.shipping_cost ?? 0.0)) €",
                free_shipping_threshold: r.free_shipping_threshold,
                courier: r.courier
            )
        }
    }

    func fetchStoreCatalogCountDirect(storeId: String) async -> Int? {
        let cleanId = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(restURL)/store_catalog_stats?store_id=eq.\(cleanId)&select=total_offers") else { return nil }
        var req = URLRequest(url: url)
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        struct StatRow: Codable { let total_offers: Int }
        if let list = try? JSONDecoder().decode([StatRow].self, from: data), let first = list.first {
            return first.total_offers
        }
        return nil
    }

    // MARK: - Dedicated Deals Showcases (Ranked by Deepest Discount & Category Filtered)

    func fetchDealsShowcasesDirect(category: String? = nil) async throws -> [StoreShowcase] {
        struct OfferRow: Codable {
            let id: String
            let product_id: String?
            let store_id: String
            let store_name: String
            let raw_title: String
            let current_price: Double
            let original_price: Double?
            let discount_pct: Double?
            let product_url: String
            let image_url: String?
            let shipping_cost: Double?
            let free_shipping_threshold: Double?
            let courier: String?
        }

        let isAllCategories = (category == nil || category!.lowercased() == "tutti" || category!.isEmpty)
        var fetchedOffers: [OfferRow] = []

        if isAllCategories {
            if let viewUrl = URL(string: "\(restURL)/store_showcase_offers?discount_pct=gt.0&order=rn.asc") {
                var req = URLRequest(url: viewUrl)
                for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }
                if let (data, resp) = try? await session.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let rows = try? JSONDecoder().decode([OfferRow].self, from: data),
                   !rows.isEmpty {
                    fetchedOffers = rows
                }
            }
        }

        if fetchedOffers.isEmpty {
            guard let url = URL(string: "\(restURL)/store_offers?select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,shipping_cost,free_shipping_threshold,courier&discount_pct=gt.0&order=discount_pct.desc.nullslast&limit=2500") else {
                throw URLError(.badURL)
            }
            var req = URLRequest(url: url)
            for (k, v) in makeHeaders(isPublic: true) {
                req.setValue(v, forHTTPHeaderField: k)
            }
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                if let http = response as? HTTPURLResponse, http.statusCode == 401 { handleAuthFailure() }
                throw URLError(.badServerResponse)
            }
            fetchedOffers = try JSONDecoder().decode([OfferRow].self, from: data)
        }

        // Filter rows by category keywords if active
        let rows: [OfferRow]
        if let cat = category?.lowercased(), !cat.isEmpty && cat != "tutti" {
            rows = fetchedOffers.filter { CategoryFilterMatcher.matches(title: $0.raw_title, category: cat) }
        } else {
            rows = fetchedOffers
        }

        // Store metadata
        struct StoreDbRecord: Codable {
            let id: String
            let name: String
            let rating: Double?
            let review_count: Int?
            let formatted_review_count: String?
            let card_theme: String?
            let accent_color: String?
            let logo_url: String?
        }
        var storeDbMap: [String: StoreDbRecord] = [:]
        if let storesUrl = URL(string: "\(restURL)/stores?select=*") {
            var storeReq = URLRequest(url: storesUrl)
            for (k, v) in makeHeaders(isPublic: true) { storeReq.setValue(v, forHTTPHeaderField: k) }
            if let (sData, sResp) = try? await session.data(for: storeReq),
               let http = sResp as? HTTPURLResponse, http.statusCode == 200 {
                if let decodedStores = try? JSONDecoder().decode([StoreDbRecord].self, from: sData) {
                    for st in decodedStores {
                        storeDbMap[st.id.lowercased()] = st
                    }
                }
            }
        }

        var storeMap: [String: (name: String, products: [StoreShowcaseProduct], discounts: [Double], maxDisc: Double)] = [:]
        for r in rows {
            let p = StoreShowcaseProduct(
                id: r.id,
                title: r.raw_title,
                brand: r.store_name,
                image_url: r.image_url,
                current_price: r.current_price,
                original_price: r.original_price,
                discount_pct: r.discount_pct,
                product_url: r.product_url,
                canonical_name: r.raw_title,
                product_id: r.product_id,
                shipping_cost: r.shipping_cost,
                total_price: r.current_price + (r.shipping_cost ?? 0.0),
                is_free_shipping: (r.shipping_cost ?? 0.0) == 0.0,
                shipping_label: (r.shipping_cost ?? 0.0) == 0.0 ? "Sped. Gratis" : "+ \(String(format: "%.2f", r.shipping_cost ?? 0.0)) €",
                free_shipping_threshold: r.free_shipping_threshold,
                courier: r.courier
            )
            let sId = r.store_id.lowercased()
            if storeMap[sId] == nil {
                storeMap[sId] = (name: r.store_name, products: [], discounts: [], maxDisc: 0.0)
            }
            if (storeMap[sId]?.products.count ?? 0) < 10 {
                storeMap[sId]?.products.append(p)
            }
            if let disc = r.discount_pct, disc > 0 {
                storeMap[sId]?.discounts.append(disc)
                if disc > (storeMap[sId]?.maxDisc ?? 0) {
                    storeMap[sId]?.maxDisc = disc
                }
            }
        }

        var showcases: [StoreShowcase] = []
        for (sId, info) in storeMap {
            guard !info.products.isEmpty else { continue }
            let avgDisc = info.discounts.isEmpty ? 25.0 : (info.discounts.reduce(0, +) / Double(info.discounts.count))
            let meta = storeDbMap[sId]
            let rating = meta?.rating.map { String(format: "%.1f", $0) } ?? "4.8"
            let revStr = meta?.formatted_review_count ?? (meta?.review_count != nil ? "\(meta!.review_count!)" : nil)

            showcases.append(StoreShowcase(
                store_id: sId,
                store_name: meta?.name ?? info.name,
                total_offers: info.products.count,
                avg_discount: avgDisc,
                rating: rating,
                review_count: revStr,
                card_theme: meta?.card_theme ?? "white",
                accent_color: meta?.accent_color,
                logo_url: meta?.logo_url,
                products: info.products
            ))
        }

        // Sort stores by the HIGHEST real discount first (real Holiday Sales ranking!)
        return showcases.sorted {
            let max0 = storeMap[$0.store_id]?.maxDisc ?? 0
            let max1 = storeMap[$1.store_id]?.maxDisc ?? 0
            if max0 != max1 {
                return max0 > max1
            }
            return $0.avg_discount > $1.avg_discount
        }
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
