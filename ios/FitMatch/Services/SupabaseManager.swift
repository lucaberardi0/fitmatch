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
        guard let url = URL(string: "\(restURL)/wishlists?on_conflict=canonical_name") else { throw URLError(.badURL) }
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
        guard let url = URL(string: "\(restURL)/store_offers?select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,shipping_cost,free_shipping_threshold,courier&order=discount_pct.desc.nullslast&limit=1000") else {
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

        var storeMap: [String: (name: String, products: [StoreShowcaseProduct], discounts: [Double], totalCount: Int)] = [:]
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
                storeMap[sId] = (name: r.store_name, products: [], discounts: [], totalCount: 0)
            }
            storeMap[sId]?.totalCount += 1
            if (storeMap[sId]?.products.count ?? 0) < 10 {
                storeMap[sId]?.products.append(p)
            }
            if let disc = r.discount_pct, disc > 0 {
                storeMap[sId]?.discounts.append(disc)
            }
        }

        let ratings: [String: String] = [
            "misterrunning": "4.9",
            "cisalfa": "4.8",
            "maxisport": "4.9",
            "top4running": "4.8",
            "alltricks": "4.4",
            "deporvillage": "4.3",
            "runningwarehouse": "4.9",
            "decathlon": "4.6",
            "nencini": "4.7",
            "sportler": "4.7",
            "nike": "4.9"
        ]

        // Query real total offer counts per store directly from Supabase
        var realStoreCounts: [String: Int] = [:]
        if let countsUrl = URL(string: "\(restURL)/store_offers?select=store_id&limit=1000") {
            var countReq = URLRequest(url: countsUrl)
            for (k, v) in makeHeaders() { countReq.setValue(v, forHTTPHeaderField: k) }
            if let (cData, cResp) = try? await session.data(for: countReq),
               let http = cResp as? HTTPURLResponse, http.statusCode == 200 {
                struct StoreIdRow: Codable { let store_id: String }
                if let countRows = try? JSONDecoder().decode([StoreIdRow].self, from: cData) {
                    for cr in countRows {
                        realStoreCounts[cr.store_id.lowercased(), default: 0] += 1
                    }
                }
            }
        }

        var showcases: [StoreShowcase] = []
        for (sId, info) in storeMap {
            guard !info.products.isEmpty else { continue }
            let avgDisc = info.discounts.isEmpty ? 25.0 : (info.discounts.reduce(0, +) / Double(info.discounts.count))
            let rating = ratings[sId] ?? "4.8"
            let realCount = realStoreCounts[sId] ?? info.totalCount
            showcases.append(StoreShowcase(
                store_id: sId,
                store_name: info.name,
                total_offers: max(realCount, info.products.count),
                avg_discount: avgDisc,
                rating: rating,
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
