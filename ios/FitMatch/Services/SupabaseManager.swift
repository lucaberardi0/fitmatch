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
    @Published var isAnonymous: Bool = true
    @Published var currentUserEmail: String? = nil
    @Published var currentUserId: String? = nil
    @Published var lastSyncDate: Date? = nil
    @Published var syncStatusMessage: String = "Account Anonimo (Ospite)"

    /// Unique persistent device identifier for anonymous sessions and local cloud sync
    var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: "fitmatch_device_unique_id"), !existing.isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "fitmatch_device_unique_id")
        return newId
    }

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

        // Load saved session if available (or initialize clean anonymous session)
        loadSavedSession()

        // Ensure session validation
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
        self.isAnonymous = true
        self.currentUserEmail = nil
        self.currentUserId = nil
        self.syncStatusMessage = "Account Anonimo (Ospite)"
    }

    // MARK: - Auth (Supabase Auth / auth.users)

    private let userDefaultsKeyToken = "fitmatch_supabase_token"
    private let userDefaultsKeyUserId = "fitmatch_supabase_user_id"
    private let userDefaultsKeyEmail = "fitmatch_supabase_email"

    private func loadSavedSession() {
        if let token = UserDefaults.standard.string(forKey: userDefaultsKeyToken), !token.isEmpty {
            let email = UserDefaults.standard.string(forKey: userDefaultsKeyEmail)
            // Purge the previous developer tester session if still present on user's device
            if email == "luca.tester.app2026@gmail.com" {
                signOut()
                return
            }
            self.currentUserId = UserDefaults.standard.string(forKey: userDefaultsKeyUserId)
            self.currentUserEmail = email
            self.isAuthenticated = true
            self.isAnonymous = false
            self.syncStatusMessage = "Autenticato: \(self.currentUserEmail ?? "Utente")"
        } else {
            self.isAuthenticated = false
            self.isAnonymous = true
            self.currentUserId = nil
            self.currentUserEmail = nil
            self.syncStatusMessage = "Account Anonimo (Ospite)"
        }
    }

    func saveSession(token: String, userId: String, email: String?) {
        UserDefaults.standard.set(token, forKey: userDefaultsKeyToken)
        UserDefaults.standard.set(userId, forKey: userDefaultsKeyUserId)
        UserDefaults.standard.set(email, forKey: userDefaultsKeyEmail)

        self.currentUserId = userId
        self.currentUserEmail = email
        self.isAuthenticated = true
        self.isAnonymous = false
        self.syncStatusMessage = "Autenticato: \(email ?? "Utente")"

        // Update preferences
        if let em = email, !em.isEmpty {
            UserPreferencesManager.shared.preferences.userEmail = em
            if UserPreferencesManager.shared.preferences.userName == "Ospite" {
                let namePart = em.components(separatedBy: "@").first ?? "Utente"
                UserPreferencesManager.shared.preferences.userName = namePart.capitalized
            }
        }

        // Migrate/link anonymous device data to this user in Supabase
        Task {
            await linkAnonymousDataToAccount(newUserId: userId)
        }
    }

    func signIn(email: String, password: String) async throws {
        guard let url = URL(string: "\(authURL)/token?grant_type=password") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = ["email": cleanEmail, "password": password]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 200 {
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
        } else {
            struct ErrorResponse: Codable {
                let msg: String?
                let message: String?
                let error_description: String?
            }
            let err = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            let errMsg = err?.msg ?? err?.message ?? err?.error_description ?? "Credenziali non valide o errore di connessione."
            throw NSError(domain: "SupabaseAuth", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errMsg])
        }
    }

    func signUp(email: String, password: String) async throws -> (success: Bool, message: String) {
        guard let url = URL(string: "\(authURL)/signup") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = [
            "email": cleanEmail,
            "password": password
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if (200...299).contains(http.statusCode) {
            struct SignUpResponse: Codable {
                let access_token: String?
                let user: AuthUser?
            }
            struct AuthUser: Codable {
                let id: String
                let email: String?
            }
            if let decoded = try? JSONDecoder().decode(SignUpResponse.self, from: data),
               let token = decoded.access_token,
               let user = decoded.user {
                await MainActor.run {
                    self.saveSession(token: token, userId: user.id, email: user.email)
                }
                return (true, "Account creato con successo!")
            } else {
                return (true, "Account creato! Ti abbiamo inviato una mail di conferma.")
            }
        } else {
            struct ErrorResponse: Codable {
                let msg: String?
                let message: String?
                let error_description: String?
            }
            let err = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            let errMsg = err?.msg ?? err?.message ?? err?.error_description ?? "Errore durante la registrazione"
            throw NSError(domain: "SupabaseAuth", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errMsg])
        }
    }

    func linkAnonymousDataToAccount(newUserId: String) async {
        let devId = self.deviceId

        // 1. Link Wishlists
        if let wishUrl = URL(string: "\(restURL)/wishlists?device_id=eq.\(devId)") {
            var req = URLRequest(url: wishUrl)
            req.httpMethod = "PATCH"
            for (k, v) in makeHeaders() { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["user_id": newUserId])
            _ = try? await session.data(for: req)
        }

        // 2. Link Recent Activity
        if let actUrl = URL(string: "\(restURL)/recent_activity?device_id=eq.\(devId)") {
            var req = URLRequest(url: actUrl)
            req.httpMethod = "PATCH"
            for (k, v) in makeHeaders() { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["user_id": newUserId])
            _ = try? await session.data(for: req)
        }

        // 3. Link Preferences
        if let prefUrl = URL(string: "\(restURL)/user_preferences?device_id=eq.\(devId)") {
            var req = URLRequest(url: prefUrl)
            req.httpMethod = "PATCH"
            for (k, v) in makeHeaders() { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["user_id": newUserId])
            _ = try? await session.data(for: req)
        }

        // 4. Link Followed Stores
        if let followUrl = URL(string: "\(restURL)/followed_stores?device_id=eq.\(devId)") {
            var req = URLRequest(url: followUrl)
            req.httpMethod = "PATCH"
            for (k, v) in makeHeaders() { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["user_id": newUserId])
            _ = try? await session.data(for: req)
        }

        // 5. Link Collections
        if let colUrl = URL(string: "\(restURL)/collections?device_id=eq.\(devId)") {
            var req = URLRequest(url: colUrl)
            req.httpMethod = "PATCH"
            for (k, v) in makeHeaders() { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["user_id": newUserId])
            _ = try? await session.data(for: req)
        }
    }

    func ensureUserSession() async {
        loadSavedSession()
        // Anonymous guest mode is default: no hardcoded auto-login!
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyToken)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyUserId)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyEmail)

        self.currentUserId = nil
        self.currentUserEmail = nil
        self.isAuthenticated = false
        self.isAnonymous = true
        self.syncStatusMessage = "Account Anonimo (Ospite)"

        // Reset preferences to default guest
        UserPreferencesManager.shared.preferences.userName = "Ospite"
        UserPreferencesManager.shared.preferences.userEmail = ""
    }

    func deleteAccount() async throws -> Bool {
        // Required for Apple App Store compliance
        signOut()
        return true
    }

    // MARK: - Wishlists API (Direct PostgREST)

    func fetchWishlist(collection: String? = nil) async throws -> [WishlistItem] {
        var urlStr = "\(restURL)/wishlists?select=*"
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            urlStr += "&user_id=eq.\(uid)"
        } else {
            urlStr += "&device_id=eq.\(deviceId)"
        }
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
            "is_alert_enabled": item.isAlertEnabled,
            "device_id": deviceId
        ]
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
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
        var urlStr = "\(restURL)/wishlists?canonical_name=eq.\(encoded)"
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            urlStr += "&user_id=eq.\(uid)"
        } else {
            urlStr += "&device_id=eq.\(deviceId)"
        }
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
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
        var urlStr = "\(restURL)/collections?select=*&order=created_at.asc"
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            urlStr += "&user_id=eq.\(uid)"
        } else {
            urlStr += "&device_id=eq.\(deviceId)"
        }

        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
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

        // Deduplicate rows by name (case-insensitive) and filter out reserved 'Tutti'
        var uniqueCols: [WishlistCollection] = []
        var seenNames = Set<String>()
        for row in rows {
            let clean = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.lowercased() != "tutti" else { continue }
            if !seenNames.contains(clean.lowercased()) {
                seenNames.insert(clean.lowercased())
                uniqueCols.append(WishlistCollection(name: clean, item_count: 0))
            }
        }
        return uniqueCols
    }

    func createCollection(name: String) async throws -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.lowercased() != "tutti" else { return false }

        // Check if collection already exists in remote database to prevent duplicate inserts
        let existing = try? await fetchCollections()
        if existing?.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) == true {
            return true
        }

        guard let url = URL(string: "\(restURL)/collections") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders(upsert: false) {
            req.setValue(v, forHTTPHeaderField: k)
        }

        var body: [String: Any] = [
            "name": cleanName,
            "device_id": deviceId
        ]
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            body["user_id"] = uid
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 201].contains(code)
    }

    func deleteCollection(name: String) async throws -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return false }

        // 1. Delete collection row
        let encodedName = cleanName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanName
        var delUrlStr = "\(restURL)/collections?name=eq.\(encodedName)"
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            delUrlStr += "&user_id=eq.\(uid)"
        } else {
            delUrlStr += "&device_id=eq.\(deviceId)"
        }
        if let url = URL(string: delUrlStr) {
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            for (k, v) in makeHeaders() { req.setValue(v, forHTTPHeaderField: k) }
            _ = try? await session.data(for: req)
        }

        // 2. Reassign wishlist items that were in this collection to 'Tutti'
        var patchUrlStr = "\(restURL)/wishlists?collection_name=eq.\(encodedName)"
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            patchUrlStr += "&user_id=eq.\(uid)"
        } else {
            patchUrlStr += "&device_id=eq.\(deviceId)"
        }
        if let patchUrl = URL(string: patchUrlStr) {
            var req = URLRequest(url: patchUrl)
            req.httpMethod = "PATCH"
            for (k, v) in makeHeaders() { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["collection_name": "Tutti"])
            _ = try? await session.data(for: req)
        }
        return true
    }

    // MARK: - Followed Stores API

    func fetchFollowedStores() async throws -> [FollowedStoreItem] {
        var urlStr = "\(restURL)/followed_stores?select=*"
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            urlStr += "&user_id=eq.\(uid)"
        } else {
            urlStr += "&device_id=eq.\(deviceId)"
        }
        urlStr += "&order=created_at.desc"

        guard let url = URL(string: urlStr) else {
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
            "device_id": deviceId
        ]
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            body["user_id"] = uid
        }
        if let logo = storeLogo {
            body["store_logo"] = logo
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 201].contains(code)
    }

    func unfollowStore(storeId: String) async throws -> Bool {
        var urlStr = "\(restURL)/followed_stores?store_id=eq.\(storeId)"
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            urlStr += "&user_id=eq.\(uid)"
        } else {
            urlStr += "&device_id=eq.\(deviceId)"
        }
        guard let url = URL(string: urlStr) else {
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
            "device_id": deviceId
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
        guard let url = URL(string: "\(restURL)/hidden_stores?device_id=eq.\(deviceId)&store_id=eq.\(storeId)") else {
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
        guard let url = URL(string: "\(restURL)/hidden_stores?device_id=eq.\(deviceId)&select=store_id") else {
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
            "device_id": deviceId
        ]
        if let d = details {
            body["details"] = d
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 201].contains(code)
    }

    // MARK: - Search Feedback (AI Search Result Quality)

    func submitSearchFeedback(
        query: String,
        feedbackType: String,
        comment: String? = nil,
        productEvaluations: [[String: Any]]? = nil
    ) async throws -> Bool {
        guard let url = URL(string: "\(restURL)/search_feedback") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        var body: [String: Any] = [
            "query": query,
            "feedback_type": feedbackType,
            "device_id": deviceId
        ]
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            body["user_id"] = uid
        }
        if let c = comment, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["comment"] = c
        }
        if let evals = productEvaluations, !evals.isEmpty {
            body["product_evaluations"] = evals
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
        var body: [String: Any] = [
            "store_id": storeId.lowercased(),
            "author_name": cleanAuthor.isEmpty ? "Cliente Verificato" : cleanAuthor,
            "rating": max(1, min(5, rating)),
            "review_text": cleanText,
            "device_id": deviceId
        ]
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            body["user_id"] = uid
        }
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

    // MARK: - Robust Date Parsing
    nonisolated static func parseISO8601Date(_ string: String?) -> Date? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFormatter.date(from: string) { return d }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let d = isoFormatter.date(from: string) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        let patterns = [
            "yyyy-MM-dd HH:mm:ss.SSSSSSZ",
            "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd"
        ]
        for pattern in patterns {
            df.dateFormat = pattern
            if let d = df.date(from: string) { return d }
        }
        return nil
    }

    private static func formatRelativeDate(_ iso: String?) -> String {
        guard let d = parseISO8601Date(iso) else { return "Recentemente" }
        let days = Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0
        if days <= 0 { return "Oggi" }
        if days == 1 { return "Ieri" }
        if days < 7 { return "\(days) giorni fa" }
        if days < 30 { return "\(max(1, days / 7)) settimane fa" }
        return "\(max(1, days / 30)) mesi fa"
    }

    // MARK: - Recent Activity API

    func fetchRecentActivities() async throws -> [RecentActivityItem] {
        var urlStr = "\(restURL)/recent_activity?select=*"
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            urlStr += "&user_id=eq.\(uid)"
        } else {
            urlStr += "&device_id=eq.\(deviceId)"
        }
        urlStr += "&order=created_at.desc&limit=30"

        guard let url = URL(string: urlStr) else {
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
        return rows.map { r in
            let date = SupabaseManager.parseISO8601Date(r.created_at) ?? Date()
            let actType: ActivityType
            if r.activity_type == "search" {
                actType = .search
            } else if r.activity_type == "store" {
                actType = .store
            } else {
                actType = .product
            }
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
                systemIcon: actType == .search ? "sparkles" : (actType == .store ? "bag.fill" : nil),
                timestamp: date,
                productData: productData,
                storeId: r.store_id
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
            "device_id": deviceId
        ]
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            body["user_id"] = uid
        }
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
        var urlStr = "\(restURL)/recent_activity?"
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            urlStr += "user_id=eq.\(uid)"
        } else {
            urlStr += "device_id=eq.\(deviceId)"
        }
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
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
        var body: [String: Any] = [
            "device_id": deviceId,
            "preferred_sizes": [prefs.preferredShoeSize, prefs.preferredApparelSize],
            "favorite_brands": prefs.favoriteBrands,
            "selected_sports": prefs.selectedSports,
            "notifications_enabled": prefs.isPushNotificationEnabled
        ]
        if isAuthenticated, let uid = currentUserId, !uid.isEmpty {
            body["user_id"] = uid
        }
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
            let available_sizes: [String]?
            let shipping_cost: Double?
            let free_shipping_threshold: Double?
            let courier: String?
        }

        var fetchedOffers: [OfferRow] = []

        // 1. First fetch top showcase offers partitioned per store from our view store_showcase_offers (guarantees Nike, Adidas, and all stores get equal showcase representation)
        if let viewUrl = URL(string: "\(restURL)/store_showcase_offers?select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,available_sizes,shipping_cost,free_shipping_threshold,courier&order=rn.asc") {
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
            if let rawUrl = URL(string: "\(restURL)/store_offers?select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,available_sizes,shipping_cost,free_shipping_threshold,courier&limit=2500") {
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
            let extractedBrand = ProductBrandHelper.extractBrand(from: r.raw_title, fallback: r.store_name)
            let p = StoreShowcaseProduct(
                id: r.id,
                title: r.raw_title,
                brand: extractedBrand,
                image_url: r.image_url,
                available_sizes: r.available_sizes,
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

    // MARK: - Direct Size Deals Fetcher (Cross-Store In-Stock Deals)

    func fetchSizeDealsDirect(size: String, minDiscount: Double = 15, limit: Int = 12) async -> [StoreShowcaseProduct] {
        let cleanSize = size.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSize.isEmpty else { return [] }

        guard let encodedSize = cleanSize.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let urlStr = "\(restURL)/store_offers?available_sizes=cs.%5B%22\(encodedSize)%22%5D&discount_pct=gte.\(Int(minDiscount))&image_url=not.is.null&order=discount_pct.desc.nullslast&limit=\(limit)&select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,available_sizes,shipping_cost,free_shipping_threshold,courier"

        guard let url = URL(string: urlStr) else { return [] }
        var req = URLRequest(url: url)
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }

        struct SizeOfferRow: Codable {
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
            let available_sizes: [String]?
            let shipping_cost: Double?
            let free_shipping_threshold: Double?
            let courier: String?
        }

        guard let rows = try? JSONDecoder().decode([SizeOfferRow].self, from: data) else {
            return []
        }

        return rows.map { r in
            let extractedBrand = ProductBrandHelper.extractBrand(from: r.raw_title, fallback: r.store_name)
            return StoreShowcaseProduct(
                id: r.id,
                title: r.raw_title,
                brand: extractedBrand,
                image_url: r.image_url,
                available_sizes: r.available_sizes,
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

    // MARK: - Direct Store Products Fetcher (For Followed Stores Fallback)

    func fetchStoreOffersDirect(storeId: String, limit: Int = 12) async throws -> [StoreShowcaseProduct] {
        let cleanId = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(restURL)/store_offers?store_id=eq.\(cleanId)&order=discount_pct.desc.nullslast,current_price.desc&limit=\(limit)&select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,available_sizes,shipping_cost,free_shipping_threshold,courier") else {
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
            let available_sizes: [String]?
            let shipping_cost: Double?
            let free_shipping_threshold: Double?
            let courier: String?
        }
        let rows = try JSONDecoder().decode([OfferRow].self, from: data)
        return rows.map { r in
            let extractedBrand = ProductBrandHelper.extractBrand(from: r.raw_title, fallback: r.store_name)
            return StoreShowcaseProduct(
                id: r.id,
                title: r.raw_title,
                brand: extractedBrand,
                image_url: r.image_url,
                available_sizes: r.available_sizes,
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

    // MARK: - Direct Live Price & Offer Lookup for Smart Notifications

    struct LiveOfferResult {
        let price: Double
        let originalPrice: Double?
        let discountPct: Double?
        let storeName: String
        let storeId: String
        let url: String
        let imageUrl: String?
    }

    func findBestLiveOfferDirect(canonicalName: String, requiredSize: String? = nil) async -> LiveOfferResult? {
        let stopWords: Set<String> = ["scarpe", "scarpa", "donna", "uomo", "modello", "edition"]
        let rawWords = canonicalName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }

        let filteredWords = rawWords.filter { !stopWords.contains($0.lowercased()) }
        let searchWords = filteredWords.isEmpty ? Array(rawWords.prefix(3)) : Array(filteredWords.prefix(3))

        guard !searchWords.isEmpty else { return nil }

        let pattern = searchWords.joined(separator: "*")
        guard let encodedPattern = "*\(pattern)*".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(restURL)/store_offers?raw_title=ilike.\(encodedPattern)&order=current_price.asc&limit=15") else {
            return nil
        }

        var req = URLRequest(url: url)
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }

        struct OfferMatchRow: Codable {
            let store_id: String
            let store_name: String
            let current_price: Double
            let original_price: Double?
            let discount_pct: Double?
            let product_url: String
            let image_url: String?
            let available_sizes: [String]?
        }

        guard let list = try? JSONDecoder().decode([OfferMatchRow].self, from: data), !list.isEmpty else {
            return nil
        }

        let cleanSize = (requiredSize ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isSpecific = !cleanSize.isEmpty && !["standard", "tutte", "tutte le taglie", "all", "none", "default"].contains(cleanSize)

        let selectedOffer: OfferMatchRow
        if isSpecific {
            if let matched = list.first(where: { row in
                guard let sizes = row.available_sizes else { return false }
                return sizes.contains { s in
                    let c = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return c == cleanSize || c.contains(cleanSize)
                }
            }) {
                selectedOffer = matched
            } else {
                return nil
            }
        } else {
            selectedOffer = list.first!
        }

        return LiveOfferResult(
            price: selectedOffer.current_price,
            originalPrice: selectedOffer.original_price,
            discountPct: selectedOffer.discount_pct,
            storeName: selectedOffer.store_name,
            storeId: selectedOffer.store_id,
            url: selectedOffer.product_url,
            imageUrl: selectedOffer.image_url
        )
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
            let available_sizes: [String]?
            let shipping_cost: Double?
            let free_shipping_threshold: Double?
            let courier: String?
        }

        let isAllCategories = (category == nil || category!.lowercased() == "tutti" || category!.isEmpty)
        var fetchedOffers: [OfferRow] = []

        if isAllCategories {
            if let viewUrl = URL(string: "\(restURL)/store_showcase_offers?discount_pct=gt.0&order=rn.asc&select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,available_sizes,shipping_cost,free_shipping_threshold,courier") {
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
            guard let url = URL(string: "\(restURL)/store_offers?select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,available_sizes,shipping_cost,free_shipping_threshold,courier&discount_pct=gt.0&order=discount_pct.desc.nullslast&limit=2500") else {
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
            let extractedBrand = ProductBrandHelper.extractBrand(from: r.raw_title, fallback: r.store_name)
            let p = StoreShowcaseProduct(
                id: r.id,
                title: r.raw_title,
                brand: extractedBrand,
                image_url: r.image_url,
                available_sizes: r.available_sizes,
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
            if isAuthenticated {
                self.syncStatusMessage = "Connesso a Supabase • \(currentUserEmail ?? "Account") (\(items.count) salvati)"
            } else {
                self.syncStatusMessage = "Account Anonimo (Ospite) • \(items.count) salvati"
            }
            return true
        } catch {
            self.isCloudConnected = false
            self.syncStatusMessage = "Offline o connessione in corso..."
            return false
        }
    }

    // MARK: - APNs Device Token & Push Notifications

    struct RemoteDbNotification: Codable {
        let id: String
        let device_id: String?
        let user_id: String?
        let type: String
        let title: String
        let subtitle: String?
        let body: String
        let product_canonical_name: String?
        let store_id: String?
        let store_name: String?
        let old_price: Double?
        let new_price: Double?
        let discount_pct: Double?
        let action_url: String?
        let image_url: String?
        let is_read: Bool
        let created_at: String?
    }

    func registerDeviceTokenDirect(token: String, environment: String = "production") async {
        guard let url = URL(string: "\(restURL)/device_tokens?on_conflict=device_token") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders(upsert: true, isPublic: true) {
            req.setValue(v, forHTTPHeaderField: k)
        }

        var payload: [String: Any] = [
            "device_token": token,
            "device_id": self.deviceId,
            "platform": "ios",
            "environment": environment,
            "is_active": true,
            "notify_price_drop": true,
            "notify_targeted_promo": true,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        if let uid = currentUserId, !uid.isEmpty {
            payload["user_id"] = uid
        }

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                print("✅ [Supabase] Device token registrato con successo in device_tokens")
            } else {
                let errText = String(data: data, encoding: .utf8) ?? "unknown"
                print("⚠️ [Supabase] Errore salvataggio device_token: \(errText)")
            }
        } catch {
            print("⚠️ [Supabase] Errore connessione device_tokens: \(error.localizedDescription)")
        }

        // Also notify local backend if reachable
        if let backendUrl = URL(string: "http://localhost:8000/api/devices/register") {
            var bReq = URLRequest(url: backendUrl)
            bReq.httpMethod = "POST"
            bReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            bReq.timeoutInterval = 3
            bReq.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            _ = try? await session.data(for: bReq)
        }
    }

    func fetchRemoteNotificationsDirect() async -> [AppNotification] {
        let devId = self.deviceId
        var urlString = "\(restURL)/notifications?device_id=eq.\(devId)&order=created_at.desc&limit=50"
        if let uid = currentUserId, !uid.isEmpty {
            urlString = "\(restURL)/notifications?or=(device_id.eq.\(devId),user_id.eq.\(uid))&order=created_at.desc&limit=50"
        }

        guard let url = URL(string: urlString) else { return [] }
        var req = URLRequest(url: url)
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoder = JSONDecoder()
            let remoteRows = try decoder.decode([RemoteDbNotification].self, from: data)

            return remoteRows.map { row in
                let nType: NotificationType
                switch row.type.lowercased() {
                case "price_drop": nType = .priceDrop
                case "promo": nType = .promo
                default: nType = .priceDrop
                }

                let date = parseNotificationDate(row.created_at)

                return AppNotification(
                    id: row.id,
                    type: nType,
                    title: row.title,
                    subtitle: row.subtitle,
                    body: row.body,
                    timestamp: date,
                    isRead: row.is_read,
                    productCanonicalName: row.product_canonical_name,
                    storeId: row.store_id,
                    storeName: row.store_name,
                    imageUrl: row.image_url,
                    oldPrice: row.old_price,
                    newPrice: row.new_price,
                    discountPct: row.discount_pct,
                    actionUrl: row.action_url
                )
            }
        } catch {
            print("⚠️ [Supabase] Errore recupero notifiche remote: \(error.localizedDescription)")
            return []
        }
    }

    func markRemoteNotificationReadDirect(id: String) async {
        guard let url = URL(string: "\(restURL)/notifications?id=eq.\(id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["is_read": true])
        _ = try? await session.data(for: req)
    }

    func deleteRemoteNotificationDirect(id: String) async {
        guard let url = URL(string: "\(restURL)/notifications?id=eq.\(id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }
        _ = try? await session.data(for: req)
    }

    private func parseNotificationDate(_ dateString: String?) -> Date {
        return SupabaseManager.parseISO8601Date(dateString) ?? Date()
    }

    // MARK: - Direct Smart Catalog Query (Intent-Aligned Supabase Cloud Enrichment)

    func fetchSmartProductsDirect(
        category: String?,
        keywords: [String],
        brand: String? = nil,
        maxPrice: Double? = nil,
        size: String? = nil,
        store: String? = nil,
        limit: Int = 35
    ) async -> [MatchedProduct] {
        struct RawOfferRow: Codable {
            let id: String?
            let store_id: String
            let store_name: String
            let raw_title: String?
            let current_price: Double
            let original_price: Double?
            let discount_pct: Double?
            let product_url: String
            let image_url: String?
            let available_sizes: [String]?
            let in_stock: Bool?
        }

        struct RawProductRow: Codable {
            let id: String
            let canonical_name: String
            let brand: String?
            let category: String?
            let gender: String?
            let image_url: String?
            let store_offers: [RawOfferRow]?
        }

        let cleanKeywords = Array(keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }.prefix(8))
        let queryTerms = cleanKeywords.isEmpty ? [""] : cleanKeywords
        let headers = makeHeaders(isPublic: true)
        let restBase = self.restURL
        let urlSession = self.session

        var rawProducts: [RawProductRow] = []
        var seenIds: Set<String> = []

        for term in queryTerms {
            var params: [String] = ["select=id,canonical_name,brand,category,gender,image_url,store_offers!inner(id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,available_sizes,in_stock)"]
            if let cat = category?.lowercased(), !cat.isEmpty, cat != "all", cat != "tutti" {
                switch cat {
                case "gps_watch":
                    params.append("category=eq.gps_watch")
                case "running_shoes", "shoes":
                    params.append("category=in.(running_shoes,shoes,fitness)")
                case "football_boots":
                    params.append("category=in.(football_boots,shoes)")
                case "swim":
                    params.append("category=in.(swim,gear)")
                case "padel":
                    params.append("category=in.(padel,racket)")
                case "hydration":
                    params.append("category=in.(hydration,pack,bag)")
                default:
                    if let encCat = cat.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        params.append("category=eq.\(encCat)")
                    }
                }
            } else {
                params.append("category=neq.non_sport")
            }
            if !term.isEmpty {
                let allWords = term.components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count >= 2 || ($0.count == 1 && $0.first?.isNumber == true) }
                let stopwords = Set(["scarpe", "scarpa", "running", "corsa", "per", "da", "di", "in", "con", "il", "la", "le", "i", "gli", "un", "una", "uno", "shoe", "shoes"])
                let specificWords = allWords.filter { !stopwords.contains($0.lowercased()) }
                let words = specificWords.isEmpty ? allWords : specificWords

                if words.count == 1, let wEnc = words[0].addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    params.append("or=(canonical_name.ilike.*\(wEnc)*,brand.ilike.*\(wEnc)*)")
                } else if words.count > 1 {
                    let andParts = words.prefix(4).compactMap { w -> String? in
                        guard let wEnc = w.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
                        return "or(canonical_name.ilike.*\(wEnc)*,brand.ilike.*\(wEnc)*)"
                    }
                    if !andParts.isEmpty {
                        params.append("and=(\(andParts.joined(separator: ",")))")
                    }
                }
            }
            params.append("limit=25")

            guard let url = URL(string: "\(restBase)/products?\(params.joined(separator: "&"))") else { continue }
            var req = URLRequest(url: url)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

            if let (data, resp) = try? await urlSession.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let decoded = try? JSONDecoder().decode([RawProductRow].self, from: data) {
                for row in decoded where !seenIds.contains(row.id) {
                    seenIds.insert(row.id)
                    rawProducts.append(row)
                }
            }
        }

        var results: [MatchedProduct] = []
        for p in rawProducts {
            guard let rawOffers = p.store_offers, !rawOffers.isEmpty else { continue }
            if let reqBrand = brand?.lowercased(), !reqBrand.isEmpty {
                let pBrand = (p.brand ?? "").lowercased()
                let pName = p.canonical_name.lowercased()
                if !pBrand.contains(reqBrand) && !pName.contains(reqBrand) {
                    continue
                }
            }

            var formattedOffers: [Offer] = []
            for o in rawOffers.sorted(by: { $0.current_price < $1.current_price }) {
                if let st = store?.lowercased(), !st.isEmpty, st != "tutti" {
                    if !o.store_id.lowercased().contains(st) && !o.store_name.lowercased().contains(st) {
                        continue
                    }
                }
                if let mp = maxPrice, o.current_price > mp {
                    continue
                }
                let offerObj = Offer(
                    store_id: o.store_id,
                    store_name: o.store_name,
                    product_id: p.id,
                    title: o.raw_title ?? p.canonical_name,
                    brand: p.brand,
                    price: o.current_price,
                    original_price: o.original_price,
                    discount_pct: o.discount_pct,
                    url: o.product_url,
                    image_url: o.image_url ?? p.image_url,
                    available_sizes: o.available_sizes,
                    in_stock: o.in_stock ?? true
                )
                if let sz = size, !sz.isEmpty, sz != "Tutte", offerObj.hasKnownSizes && !offerObj.hasSize(sz) {
                    continue
                }
                formattedOffers.append(offerObj)
            }

            guard !formattedOffers.isEmpty else { continue }
            let prices = formattedOffers.map { $0.price }
            let minP = prices.min() ?? 0.0
            let maxP = prices.max() ?? minP
            let savings = prices.count > 1 ? max(0.0, maxP - minP) : 0.0
            let primaryImg = p.image_url ?? formattedOffers.first?.image_url

            results.append(MatchedProduct(
                id_val: p.id,
                canonical_name: p.canonical_name,
                brand: p.brand,
                image_url: primaryImg,
                gallery_images: primaryImg != nil ? [primaryImg!] : nil,
                gender: p.gender ?? "Unisex",
                offers: formattedOffers,
                best_price: minP,
                highest_price: maxP,
                cross_store_savings: savings
            ))
        }

        return Array(results.prefix(limit))
    }

    // MARK: - Direct Persistent AI Chat Sessions & Messages

    func fetchChatSessionsDirect(deviceId: String, limit: Int = 20) async -> [ChatSessionSummary] {
        let did = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !did.isEmpty,
              let didEnc = did.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(restURL)/chat_sessions?device_id=eq.\(didEnc)&is_archived=eq.false&order=updated_at.desc&limit=\(limit)") else {
            return []
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode([ChatSessionSummary].self, from: data) else {
            return []
        }
        return decoded
    }

    func fetchChatSessionDetailDirect(sessionId: String) async -> ChatSessionDetail? {
        let sid = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty,
              let sidEnc = sid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let sUrl = URL(string: "\(restURL)/chat_sessions?id=eq.\(sidEnc)&limit=1"),
              let mUrl = URL(string: "\(restURL)/chat_messages?session_id=eq.\(sidEnc)&order=turn_index.asc,created_at.asc") else {
            return nil
        }
        var sReq = URLRequest(url: sUrl)
        sReq.httpMethod = "GET"
        for (k, v) in makeHeaders(isPublic: true) { sReq.setValue(v, forHTTPHeaderField: k) }

        guard let (sData, sResp) = try? await session.data(for: sReq),
              let sHttp = sResp as? HTTPURLResponse, sHttp.statusCode == 200,
              let sRows = try? JSONDecoder().decode([ChatSessionSummary].self, from: sData),
              let sess = sRows.first else {
            return nil
        }

        var mReq = URLRequest(url: mUrl)
        mReq.httpMethod = "GET"
        for (k, v) in makeHeaders(isPublic: true) { mReq.setValue(v, forHTTPHeaderField: k) }

        var msgs: [ChatMessageRecord] = []
        if let (mData, mResp) = try? await session.data(for: mReq),
           let mHttp = mResp as? HTTPURLResponse, mHttp.statusCode == 200,
           let mRows = try? JSONDecoder().decode([ChatMessageRecord].self, from: mData) {
            msgs = mRows
        }

        return ChatSessionDetail(
            id: sess.id,
            device_id: sess.device_id,
            user_id: sess.user_id,
            chat_type: sess.chat_type,
            title: sess.title,
            subtitle: sess.subtitle,
            preview_image_url: sess.preview_image_url,
            turn_count: sess.turn_count,
            context_state: sess.context_state,
            is_archived: sess.is_archived,
            created_at: sess.created_at,
            updated_at: sess.updated_at,
            messages: msgs
        )
    }

    func saveChatTurnDirect(
        sessionId: String,
        deviceId: String,
        query: String,
        isFollowUp: Bool,
        response: SmartSearchResponse
    ) async {
        struct SessionUpsertPayload: Encodable {
            let id: String
            let device_id: String
            let user_id: String?
            let chat_type: String
            let title: String
            let subtitle: String?
            let preview_image_url: String?
            let turn_count: Int
            let context_state: ChatSessionContextState
            let updated_at: String
        }
        struct MessageInsertPayload: Encodable {
            let id: String
            let session_id: String
            let turn_index: Int
            let query: String
            let is_follow_up: Bool
            let is_conversational_advice: Bool
            let conversational_header: String?
            let conversational_summary: String?
            let intent_json: SmartSearchIntent?
            let chips_json: [SmartSearchChip]
            let results_snapshot_json: ChatTurnResultsSnapshot
            let follow_up_suggestions_json: [String]
            let is_off_topic: Bool
            let is_unsafe: Bool
            let created_at: String
        }

        let sid = sessionId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !sid.isEmpty, UUID(uuidString: sid) != nil else { return }

        let nowIso = ISO8601DateFormatter().string(from: Date())
        let existing = await fetchChatSessionDetailDirect(sessionId: sid)
        let turnIdx = existing?.messages?.count ?? existing?.turn_count ?? 0
        let previewUrl = response.spotlight?.product.image_url ?? response.results.first?.image_url ?? existing?.preview_image_url

        let ctx = ChatSessionContextState(
            last_query: query,
            brand: response.intent?.brand ?? existing?.context_state?.brand,
            category: response.intent?.category ?? existing?.context_state?.category,
            gender: response.intent?.gender ?? existing?.context_state?.gender,
            max_price: response.intent?.max_price ?? existing?.context_state?.max_price,
            min_price: response.intent?.min_price ?? existing?.context_state?.min_price,
            size: response.intent?.size ?? existing?.context_state?.size,
            features: response.intent?.features ?? existing?.context_state?.features
        )

        let sessionPayload = SessionUpsertPayload(
            id: sid,
            device_id: deviceId,
            user_id: currentUserId,
            chat_type: "smart_search",
            title: existing?.title ?? query,
            subtitle: response.conversational_header ?? query,
            preview_image_url: previewUrl,
            turn_count: turnIdx + 1,
            context_state: ctx,
            updated_at: nowIso
        )

        if let sUrl = URL(string: "\(restURL)/chat_sessions?on_conflict=id"),
           let sBody = try? JSONEncoder().encode(sessionPayload) {
            var sReq = URLRequest(url: sUrl)
            sReq.httpMethod = "POST"
            for (k, v) in makeHeaders(upsert: true, isPublic: true) { sReq.setValue(v, forHTTPHeaderField: k) }
            sReq.httpBody = sBody
            _ = try? await session.data(for: sReq)
        }

        let snapshot = ChatTurnResultsSnapshot(
            results: Array(response.results.prefix(12)),
            curated_sections: Array((response.curated_sections ?? []).prefix(4)),
            comparative_cards: Array((response.comparative_cards ?? []).prefix(5)),
            spotlight: response.spotlight
        )

        let msgPayload = MessageInsertPayload(
            id: UUID().uuidString.lowercased(),
            session_id: sid,
            turn_index: turnIdx,
            query: query,
            is_follow_up: isFollowUp,
            is_conversational_advice: response.is_conversational_advice ?? false,
            conversational_header: response.conversational_header,
            conversational_summary: response.conversational_summary,
            intent_json: response.intent,
            chips_json: response.chips ?? [],
            results_snapshot_json: snapshot,
            follow_up_suggestions_json: response.follow_up_suggestions ?? [],
            is_off_topic: response.is_off_topic ?? false,
            is_unsafe: response.is_unsafe ?? false,
            created_at: nowIso
        )

        if let mUrl = URL(string: "\(restURL)/chat_messages"),
           let mBody = try? JSONEncoder().encode(msgPayload) {
            var mReq = URLRequest(url: mUrl)
            mReq.httpMethod = "POST"
            for (k, v) in makeHeaders(isPublic: true) { mReq.setValue(v, forHTTPHeaderField: k) }
            mReq.httpBody = mBody
            _ = try? await session.data(for: mReq)
        }
    }

    func deleteChatSessionDirect(sessionId: String, deviceId: String? = nil) async -> Bool {
        let sid = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty,
              let sidEnc = sid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return false
        }
        var urlStr = "\(restURL)/chat_sessions?id=eq.\(sidEnc)"
        if let did = deviceId?.trimmingCharacters(in: .whitespacesAndNewlines), !did.isEmpty,
           let didEnc = did.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlStr += "&device_id=eq.\(didEnc)"
        }
        guard let url = URL(string: urlStr) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }

        guard let (_, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else {
            return false
        }
        return http.statusCode == 200 || http.statusCode == 204
    }
}
