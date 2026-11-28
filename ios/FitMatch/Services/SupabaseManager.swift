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
            let candidate = token ?? UserDefaults.standard.string(forKey: userDefaultsKeyToken)
            if let candidate = candidate, candidate.split(separator: ".").count == 3 {
                activeToken = candidate
            } else {
                activeToken = anonKey
            }
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
        clearStoredAuthSession()
        self.isAuthenticated = false
        self.isAnonymous = true
        self.currentUserEmail = nil
        self.currentUserId = nil
        self.syncStatusMessage = "Account Anonimo (Ospite)"
    }

    // MARK: - Auth (Supabase Auth / auth.users)

    private let userDefaultsKeyToken = "fitmatch_supabase_token"
    private let userDefaultsKeyRefreshToken = "fitmatch_supabase_refresh_token"
    private let userDefaultsKeyUserId = "fitmatch_supabase_user_id"
    private let userDefaultsKeyEmail = "fitmatch_supabase_email"
    private let userDefaultsKeyIsAnonymous = "fitmatch_supabase_is_anonymous"
    private var isEnsuringSession = false

    private func clearStoredAuthSession() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyToken)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyRefreshToken)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyUserId)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyEmail)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyIsAnonymous)
    }

    /// Returns `currentUserId` whenever it is a valid Supabase Auth UUID (permanent or anonymous user in `auth.users`).
    var validCurrentUserId: String? {
        guard let uid = currentUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
              let parsed = UUID(uuidString: uid) else {
            return nil
        }
        return parsed.uuidString.lowercased()
    }

    private func loadSavedSession() {
        if let token = UserDefaults.standard.string(forKey: userDefaultsKeyToken), !token.isEmpty {
            let email = UserDefaults.standard.string(forKey: userDefaultsKeyEmail)
            // Purge legacy tester or non-JWT fallback sessions so auth state always reflects real Supabase Auth
            if email == "luca.tester.app2026@gmail.com" || email == "utente.apple@icloud.com" || token.split(separator: ".").count != 3 {
                clearStoredAuthSession()
                self.isAuthenticated = false
                self.isAnonymous = true
                self.currentUserId = nil
                self.currentUserEmail = nil
                self.syncStatusMessage = "Account Anonimo (Ospite)"
                return
            }

            let savedUserId = UserDefaults.standard.string(forKey: userDefaultsKeyUserId)
            let savedIsAnon = UserDefaults.standard.bool(forKey: userDefaultsKeyIsAnonymous)
            self.currentUserId = savedUserId
            if savedIsAnon || (email ?? "").isEmpty {
                self.currentUserEmail = nil
                self.isAuthenticated = false
                self.isAnonymous = true
                self.syncStatusMessage = "Account Anonimo (Ospite)"
            } else {
                self.currentUserEmail = email
                self.isAuthenticated = true
                self.isAnonymous = false
                self.syncStatusMessage = "Autenticato: \(email ?? "Utente")"
            }
        } else {
            self.isAuthenticated = false
            self.isAnonymous = true
            self.currentUserId = nil
            self.currentUserEmail = nil
            self.syncStatusMessage = "Account Anonimo (Ospite)"
        }
    }

    func saveSession(token: String, refreshToken: String? = nil, userId: String, email: String?, isAnonymous: Bool = false) {
        let previousAnonToken = self.isAnonymous ? UserDefaults.standard.string(forKey: userDefaultsKeyToken) : nil
        let previousAnonUserId = self.isAnonymous ? self.validCurrentUserId : nil

        UserDefaults.standard.set(token, forKey: userDefaultsKeyToken)
        if let refreshToken, !refreshToken.isEmpty {
            UserDefaults.standard.set(refreshToken, forKey: userDefaultsKeyRefreshToken)
        }
        UserDefaults.standard.set(userId, forKey: userDefaultsKeyUserId)
        UserDefaults.standard.set(email, forKey: userDefaultsKeyEmail)
        UserDefaults.standard.set(isAnonymous, forKey: userDefaultsKeyIsAnonymous)

        self.currentUserId = userId
        self.currentUserEmail = isAnonymous ? nil : email
        self.isAuthenticated = !isAnonymous
        self.isAnonymous = isAnonymous
        self.syncStatusMessage = isAnonymous ? "Account Anonimo (Ospite)" : "Autenticato: \(email ?? "Utente")"

        // Update preferences only for permanent accounts
        if !isAnonymous, let em = email, !em.isEmpty {
            UserPreferencesManager.shared.preferences.userEmail = em
            if UserPreferencesManager.shared.preferences.userName == "Ospite" {
                let namePart = em.components(separatedBy: "@").first ?? "Utente"
                UserPreferencesManager.shared.preferences.userName = namePart.capitalized
            }
        }

        // Migrate/link device data (and any prior anonymous user rows) to this Supabase Auth user
        Task {
            await linkAnonymousDataToAccount(
                newUserId: userId,
                previousAnonymousUserId: previousAnonUserId,
                previousAnonymousToken: previousAnonToken
            )
            NotificationCenter.default.post(name: NSNotification.Name("FitMatchAuthSessionDidChange"), object: nil)
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
                let refresh_token: String?
                let user: AuthUser
            }
            struct AuthUser: Codable {
                let id: String
                let email: String?
            }

            let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
            await MainActor.run {
                self.saveSession(
                    token: decoded.access_token,
                    refreshToken: decoded.refresh_token,
                    userId: decoded.user.id,
                    email: decoded.user.email,
                    isAnonymous: false
                )
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
                let refresh_token: String?
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
                    self.saveSession(
                        token: token,
                        refreshToken: decoded.refresh_token,
                        userId: user.id,
                        email: user.email,
                        isAnonymous: false
                    )
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

    static func extractEmailFromJWT(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String,
              !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return email
    }

    func signInWithApple(idToken: String, email: String?) async throws {
        guard let url = URL(string: "\(authURL)/token?grant_type=id_token") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "provider": "apple",
            "id_token": idToken
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            struct ErrorResponse: Codable {
                let msg: String?
                let message: String?
                let error_description: String?
                let error_code: String?
            }
            let err = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            let rawMsg = err?.msg ?? err?.message ?? err?.error_description ?? "Errore autenticazione Apple (\(http.statusCode))"
            let userMsg: String
            if err?.error_code == "provider_disabled" || rawMsg.lowercased().contains("not enabled") {
                userMsg = "Provider Apple non abilitato su Supabase (Authentication → Providers → Apple)."
            } else {
                userMsg = rawMsg
            }
            throw NSError(domain: "SupabaseAuth", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: userMsg])
        }

        struct AuthResponse: Codable {
            let access_token: String
            let refresh_token: String?
            let user: AuthUser
        }
        struct AuthUser: Codable {
            let id: String
            let email: String?
        }

        let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)
        let resolvedEmail = decoded.user.email ?? email ?? Self.extractEmailFromJWT(idToken)
        await MainActor.run {
            self.saveSession(
                token: decoded.access_token,
                refreshToken: decoded.refresh_token,
                userId: decoded.user.id,
                email: resolvedEmail,
                isAnonymous: false
            )
        }
    }

    func linkAnonymousDataToAccount(
        newUserId: String,
        previousAnonymousUserId: String? = nil,
        previousAnonymousToken: String? = nil
    ) async {
        guard let parsedUuid = UUID(uuidString: newUserId.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }
        let cleanUid = parsedUuid.uuidString.lowercased()
        let devId = encodeQueryValue(self.deviceId)
        let tablesToLink = [
            "wishlists",
            "recent_activity",
            "user_preferences",
            "followed_stores",
            "collections",
            "chat_sessions",
            "device_tokens",
            "notifications",
            "search_feedback",
            "hidden_stores",
            "store_reports"
        ]

        // Atomically claim anonymous wishlist & collection rows via SECURITY DEFINER RPC
        if let claimUrl = URL(string: "\(restURL)/rpc/claim_anonymous_wishlist_data_v1") {
            var claimReq = URLRequest(url: claimUrl)
            claimReq.httpMethod = "POST"
            for (k, v) in makeHeaders() { claimReq.setValue(v, forHTTPHeaderField: k) }
            var claimBody: [String: Any] = ["p_device_id": self.deviceId]
            if let prevId = previousAnonymousUserId?.lowercased(), prevId != cleanUid {
                claimBody["p_previous_user_id"] = prevId
            }
            claimReq.httpBody = try? JSONSerialization.data(withJSONObject: claimBody)
            _ = try? await session.data(for: claimReq)
        }

        // If transitioning from a previous Supabase anonymous user ID to a different permanent user ID,
        // release ownership using the anonymous JWT first so RLS tables allow claiming.
        if let prevId = previousAnonymousUserId?.lowercased(),
           prevId != cleanUid,
           let prevToken = previousAnonymousToken,
           prevToken.split(separator: ".").count == 3 {
            for table in tablesToLink where table != "wishlists" && table != "collections" {
                guard let releaseUrl = URL(string: "\(restURL)/\(table)?device_id=eq.\(devId)&user_id=eq.\(prevId)") else {
                    continue
                }
                var req = URLRequest(url: releaseUrl)
                req.httpMethod = "PATCH"
                for (k, v) in makeHeaders(token: prevToken) { req.setValue(v, forHTTPHeaderField: k) }
                req.httpBody = try? JSONSerialization.data(withJSONObject: ["user_id": NSNull()])
                _ = try? await session.data(for: req)
            }
        }

        for table in tablesToLink where table != "wishlists" && table != "collections" {
            guard let url = URL(string: "\(restURL)/\(table)?device_id=eq.\(devId)&user_id=is.null") else {
                continue
            }
            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            for (k, v) in makeHeaders() { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["user_id": cleanUid])
            _ = try? await session.data(for: req)
        }
    }

    private func isJWTExpiringSoon(_ jwt: String, leewaySeconds: TimeInterval = 120) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return true }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return false
        }
        return Date().timeIntervalSince1970 + leewaySeconds >= exp
    }

    private func refreshSession(refreshToken: String, wasAnonymous: Bool) async -> Bool {
        guard let url = URL(string: "\(authURL)/token?grant_type=refresh_token") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return false
            }
            struct RefreshResponse: Codable {
                let access_token: String
                let refresh_token: String?
                let user: RefreshUser
            }
            struct RefreshUser: Codable {
                let id: String
                let email: String?
                let is_anonymous: Bool?
            }
            let decoded = try JSONDecoder().decode(RefreshResponse.self, from: data)
            let isAnon = decoded.user.is_anonymous ?? wasAnonymous
            saveSession(
                token: decoded.access_token,
                refreshToken: decoded.refresh_token ?? refreshToken,
                userId: decoded.user.id,
                email: decoded.user.email,
                isAnonymous: isAnon
            )
            return true
        } catch {
            print("Supabase refreshSession error: \(error)")
            return false
        }
    }

    @discardableResult
    func signInAnonymously() async -> Bool {
        guard let url = URL(string: "\(authURL)/signup") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return false
            }
            struct AnonResponse: Codable {
                let access_token: String
                let refresh_token: String?
                let user: AnonUser
            }
            struct AnonUser: Codable {
                let id: String
                let is_anonymous: Bool?
            }
            let decoded = try JSONDecoder().decode(AnonResponse.self, from: data)
            saveSession(
                token: decoded.access_token,
                refreshToken: decoded.refresh_token,
                userId: decoded.user.id,
                email: nil,
                isAnonymous: decoded.user.is_anonymous ?? true
            )
            return true
        } catch {
            print("Supabase signInAnonymously error: \(error)")
            return false
        }
    }

    func ensureUserSession() async {
        guard !isEnsuringSession else { return }
        isEnsuringSession = true
        defer { isEnsuringSession = false }

        loadSavedSession()

        if let token = UserDefaults.standard.string(forKey: userDefaultsKeyToken),
           !token.isEmpty,
           validCurrentUserId != nil {
            if isJWTExpiringSoon(token),
               let refresh = UserDefaults.standard.string(forKey: userDefaultsKeyRefreshToken),
               !refresh.isEmpty {
                let refreshed = await refreshSession(refreshToken: refresh, wasAnonymous: self.isAnonymous)
                if !refreshed {
                    handleAuthFailure()
                    await signInAnonymously()
                }
            }
            return
        }

        // No active Supabase Auth user yet: create an anonymous user in auth.users
        await signInAnonymously()
    }

    func signOut() {
        clearStoredAuthSession()

        self.currentUserId = nil
        self.currentUserEmail = nil
        self.isAuthenticated = false
        self.isAnonymous = true
        self.syncStatusMessage = "Account Anonimo (Ospite)"

        // Reset preferences to default guest
        UserPreferencesManager.shared.preferences.userName = "Ospite"
        UserPreferencesManager.shared.preferences.userEmail = ""
        NotificationCenter.default.post(name: NSNotification.Name("FitMatchAuthSessionDidChange"), object: nil)

        Task {
            await signInAnonymously()
        }
    }

    func deleteAccount() async throws -> Bool {
        // Delete user/device cloud records across tables for GDPR & App Store 5.1.1(v) compliance
        let tablesToPurge = [
            "wishlists",
            "collections",
            "followed_stores",
            "recent_activity",
            "user_preferences",
            "device_tokens",
            "notifications",
            "hidden_stores"
        ]
        let encodedDevId = encodeQueryValue(deviceId)
        for table in tablesToPurge {
            var urlStr = "\(restURL)/\(table)?"
            if let uid = validCurrentUserId {
                urlStr += "or=(user_id.eq.\(uid),device_id.eq.\(encodedDevId))"
            } else {
                urlStr += "device_id=eq.\(encodedDevId)"
            }
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            for (k, v) in makeHeaders() {
                req.setValue(v, forHTTPHeaderField: k)
            }
            _ = try? await session.data(for: req)
        }

        // Regenerate anonymous device identifier so no residual association remains
        UserDefaults.standard.removeObject(forKey: "fitmatch_device_unique_id")
        signOut()
        return true
    }

    // MARK: - Wishlists API (Live RPC + Direct PostgREST)

    /// Fetches user's saved items hydrated with live prices, stock, store count, sizes, shipping,
    /// all-time low status, and genuine price delta since saved via `get_wishlist_live_v1`.
    func fetchWishlistLive(shoeSize: String? = nil, apparelSize: String? = nil) async throws -> [WishlistItem] {
        guard validCurrentUserId != nil else {
            return try await fetchWishlist()
        }
        guard let url = URL(string: "\(restURL)/rpc/get_wishlist_live_v1") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }

        var payload: [String: Any] = [:]
        let cleanShoe = shoeSize?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanApp = apparelSize?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        payload["p_shoe_size"] = cleanShoe.isEmpty ? NSNull() : cleanShoe
        payload["p_apparel_size"] = cleanApp.isEmpty ? NSNull() : cleanApp
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return try await fetchWishlist()
        }

        let rows = try JSONDecoder().decode([WishlistLiveRow].self, from: data)
        self.lastSyncDate = Date()
        self.isCloudConnected = true
        return rows.map { $0.toWishlistItem() }
    }

    func fetchWishlist(collection: String? = nil) async throws -> [WishlistItem] {
        var urlStr = "\(restURL)/wishlists?select=*"
        if let uid = validCurrentUserId {
            urlStr += "&user_id=eq.\(uid)"
        } else {
            urlStr += "&device_id=eq.\(encodeQueryValue(deviceId))"
        }
        if let col = collection, !col.isEmpty && col.lowercased() != "tutti" {
            let encodedCol = encodeQueryValue(col)
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
        // Preferred atomic RPC: scopes strictly to auth.uid(), preserves saved_price, stores product_id,
        // target_alert_price, and multi-collection array.
        if validCurrentUserId != nil, let rpcUrl = URL(string: "\(restURL)/rpc/upsert_wishlist_item_v1") {
            var req = URLRequest(url: rpcUrl)
            req.httpMethod = "POST"
            for (k, v) in makeHeaders() {
                req.setValue(v, forHTTPHeaderField: k)
            }

            let rpcBody: [String: Any] = [
                "p_canonical_name": item.canonical_name,
                "p_product_id": item.productId ?? NSNull(),
                "p_brand": item.brand ?? NSNull(),
                "p_category": item.category ?? NSNull(),
                "p_store_id": item.bestStoreId ?? item.resolvedStoreId,
                "p_store_name": item.bestStore ?? NSNull(),
                "p_current_price": item.currentBestPrice,
                "p_saved_price": item.savedPrice,
                "p_original_price": item.highestPrice ?? item.initialPrice,
                "p_discount_pct": item.discountPct ?? NSNull(),
                "p_image_url": item.image_url ?? NSNull(),
                "p_product_url": item.bestStoreUrl ?? NSNull(),
                "p_selected_size": item.selectedSize ?? NSNull(),
                "p_collection_names": item.collectionNames,
                "p_target_alert_price": item.targetAlertPrice ?? NSNull(),
                "p_is_alert_enabled": item.isAlertEnabled,
                "p_device_id": deviceId
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: rpcBody)
            let (_, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if [200, 201, 204].contains(code) {
                self.lastSyncDate = Date()
                return true
            }
        }

        // Fallback direct PostgREST upsert
        let conflictCols = validCurrentUserId != nil ? "user_id,canonical_name" : "canonical_name"
        guard let url = URL(string: "\(restURL)/wishlists?on_conflict=\(conflictCols)") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders(upsert: true) {
            req.setValue(v, forHTTPHeaderField: k)
        }

        var body: [String: Any] = [
            "canonical_name": item.canonical_name,
            "brand": item.brand ?? "",
            "store_id": item.bestStoreId ?? item.resolvedStoreId,
            "store_name": item.bestStore ?? "",
            "current_price": item.currentBestPrice,
            "saved_price": item.savedPrice,
            "original_price": item.highestPrice ?? item.initialPrice,
            "discount_pct": item.discountPct ?? 0.0,
            "image_url": item.image_url ?? "",
            "product_url": item.bestStoreUrl ?? "",
            "collection_name": item.collectionName ?? "Tutti",
            "collection_names": item.collectionNames,
            "is_alert_enabled": item.isAlertEnabled,
            "device_id": deviceId
        ]
        if let pid = item.productId, !pid.isEmpty {
            body["product_id"] = pid
        }
        if let cat = item.category, !cat.isEmpty {
            body["category"] = cat
        }
        if let sz = item.selectedSize, !sz.isEmpty {
            body["selected_size"] = sz
        } else {
            body["selected_size"] = NSNull()
        }
        if let target = item.targetAlertPrice {
            body["target_alert_price"] = target
        } else {
            body["target_alert_price"] = NSNull()
        }
        if let uid = validCurrentUserId {
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
        let encoded = encodeQueryValue(canonicalName)
        var urlStr = "\(restURL)/wishlists?canonical_name=eq.\(encoded)"
        if let uid = validCurrentUserId {
            urlStr += "&user_id=eq.\(uid)"
        } else {
            urlStr += "&device_id=eq.\(encodeQueryValue(deviceId))"
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
        if let uid = validCurrentUserId {
            urlStr += "&user_id=eq.\(uid)"
        } else {
            urlStr += "&device_id=eq.\(encodeQueryValue(deviceId))"
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
        if let uid = validCurrentUserId {
            body["user_id"] = uid
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 201].contains(code)
    }

    func renameCollection(oldName: String, newName: String) async throws -> Bool {
        let cleanOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanOld.isEmpty, !cleanNew.isEmpty,
              cleanOld.lowercased() != "tutti", cleanNew.lowercased() != "tutti" else {
            return false
        }
        if validCurrentUserId != nil, let url = URL(string: "\(restURL)/rpc/rename_wishlist_collection_v1") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            for (k, v) in makeHeaders() { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "p_old_name": cleanOld,
                "p_new_name": cleanNew
            ])
            let (_, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, [200, 201, 204].contains(http.statusCode) {
                return true
            }
        }
        return false
    }

    func deleteCollection(name: String) async throws -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.lowercased() != "tutti" else { return false }

        // 1. Delete collection row(s)
        let encodedName = encodeQueryValue(cleanName)
        var delUrlStr = "\(restURL)/collections?name=ilike.\(encodedName)"
        if let uid = validCurrentUserId {
            delUrlStr += "&user_id=eq.\(uid)"
        } else {
            delUrlStr += "&device_id=eq.\(encodeQueryValue(deviceId))"
        }
        if let url = URL(string: delUrlStr) {
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            for (k, v) in makeHeaders() { req.setValue(v, forHTTPHeaderField: k) }
            _ = try? await session.data(for: req)
        }

        // 2. Atomically remove collection from all user wishlist rows (multi-collection safe)
        if validCurrentUserId != nil, let rpcUrl = URL(string: "\(restURL)/rpc/remove_collection_from_wishlists_v1") {
            var req = URLRequest(url: rpcUrl)
            req.httpMethod = "POST"
            for (k, v) in makeHeaders() { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["p_name": cleanName])
            _ = try? await session.data(for: req)
        }
        return true
    }

    // MARK: - Followed Stores API

    func fetchFollowedStores() async throws -> [FollowedStoreItem] {
        var urlStr = "\(restURL)/followed_stores?select=*"
        if let uid = validCurrentUserId {
            urlStr += "&user_id=eq.\(uid)"
        } else {
            urlStr += "&device_id=eq.\(encodeQueryValue(deviceId))"
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
        let decoded = try JSONDecoder().decode([FollowedStoreItem].self, from: data)
        var seen = Set<String>()
        var unique: [FollowedStoreItem] = []
        for item in decoded {
            let cleanId = item.store_id.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanId.isEmpty, seen.insert(cleanId).inserted else { continue }
            unique.append(
                FollowedStoreItem(
                    store_id: cleanId,
                    store_name: item.store_name,
                    store_logo: item.store_logo,
                    created_at: item.created_at
                )
            )
        }
        return unique
    }

    func followStore(storeId: String, storeName: String, storeLogo: String? = nil) async throws -> Bool {
        let cleanId = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return false }
        guard let url = URL(string: "\(restURL)/followed_stores?on_conflict=device_id,store_id") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders(upsert: true) {
            req.setValue(v, forHTTPHeaderField: k)
        }
        var body: [String: Any] = [
            "store_id": cleanId,
            "store_name": storeName,
            "device_id": deviceId
        ]
        if let uid = validCurrentUserId {
            body["user_id"] = uid
        }
        if let logo = storeLogo, !logo.isEmpty {
            body["store_logo"] = logo
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 409 can happen if the same authenticated user already followed this store on another device (partial unique index)
        return [200, 201, 409].contains(code)
    }

    func unfollowStore(storeId: String) async throws -> Bool {
        let cleanId = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedId = encodeQueryValue(cleanId)
        var urlStr = "\(restURL)/followed_stores?store_id=eq.\(encodedId)"
        if let uid = validCurrentUserId {
            urlStr += "&user_id=eq.\(uid)"
        } else {
            urlStr += "&device_id=eq.\(encodeQueryValue(deviceId))"
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
        if let uid = validCurrentUserId {
            body["user_id"] = uid
        }
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
        if let uid = validCurrentUserId {
            body["user_id"] = uid
        }
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
        if let uid = validCurrentUserId {
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

        return false
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

    private static let postgrestQueryValueAllowed: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-._~")
        return cs
    }()

    private func encodeQueryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: Self.postgrestQueryValueAllowed) ?? value
    }

    private var recentActivityOwnerFilter: String {
        if let uid = validCurrentUserId {
            return "user_id=eq.\(encodeQueryValue(uid))"
        } else {
            return "device_id=eq.\(encodeQueryValue(deviceId))"
        }
    }

    func fetchRecentActivities() async throws -> [RecentActivityItem] {
        let urlStr = "\(restURL)/recent_activity?select=*&\(recentActivityOwnerFilter)&order=created_at.desc&limit=60"

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
            let product_id: String?
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
            let productData: MatchedProduct? = (actType == .product) ? MatchedProduct(
                id_val: (r.product_id?.isEmpty == false) ? r.product_id : r.id.uuidString,
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

    func recordRecentActivity(id: UUID? = nil, type: String, title: String, subtitle: String? = nil, imageUrl: String? = nil, price: Double? = nil, originalPrice: Double? = nil, storeId: String? = nil, storeName: String? = nil, productId: String? = nil) async throws -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }

        // Remove any prior duplicate rows for the same owner + activity_type + title before inserting
        let encodedType = encodeQueryValue(type)
        let encodedTitle = encodeQueryValue(trimmedTitle)
        if let delUrl = URL(string: "\(restURL)/recent_activity?\(recentActivityOwnerFilter)&activity_type=eq.\(encodedType)&title=eq.\(encodedTitle)") {
            var delReq = URLRequest(url: delUrl)
            delReq.httpMethod = "DELETE"
            for (k, v) in makeHeaders() {
                delReq.setValue(v, forHTTPHeaderField: k)
            }
            _ = try? await session.data(for: delReq)
        }

        guard let url = URL(string: "\(restURL)/recent_activity") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        var body: [String: Any] = [
            "activity_type": type,
            "title": trimmedTitle,
            "device_id": deviceId
        ]
        if let rowId = id { body["id"] = rowId.uuidString }
        if let uid = validCurrentUserId {
            body["user_id"] = uid
        }
        if let pid = productId, !pid.isEmpty { body["product_id"] = pid }
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

    func deleteRecentActivity(id: UUID, type: String, title: String) async throws -> Bool {
        let owner = recentActivityOwnerFilter
        var allSucceeded = true

        // 1. Delete exact row by id
        if let idUrl = URL(string: "\(restURL)/recent_activity?id=eq.\(id.uuidString)&\(owner)") {
            var req = URLRequest(url: idUrl)
            req.httpMethod = "DELETE"
            for (k, v) in makeHeaders() {
                req.setValue(v, forHTTPHeaderField: k)
            }
            let (_, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if ![200, 204].contains(code) {
                allSucceeded = false
            }
        }

        // 2. Delete any duplicate rows matching the same activity_type + title
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            let encodedType = encodeQueryValue(type)
            let encodedTitle = encodeQueryValue(trimmedTitle)
            if let titleUrl = URL(string: "\(restURL)/recent_activity?\(owner)&activity_type=eq.\(encodedType)&title=eq.\(encodedTitle)") {
                var req = URLRequest(url: titleUrl)
                req.httpMethod = "DELETE"
                for (k, v) in makeHeaders() {
                    req.setValue(v, forHTTPHeaderField: k)
                }
                let (_, response) = try await session.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if ![200, 204].contains(code) {
                    allSucceeded = false
                }
            }
        }

        return allSucceeded
    }

    func clearRecentActivities() async throws -> Bool {
        let urlStr = "\(restURL)/recent_activity?\(recentActivityOwnerFilter)"
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
            "preferred_sizes": [prefs.preferredShoeSize, prefs.preferredApparelSize].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            "favorite_brands": prefs.favoriteBrands,
            "selected_sports": prefs.selectedSports,
            "notifications_enabled": prefs.isPushNotificationEnabled
        ]
        if let uid = validCurrentUserId {
            body["user_id"] = uid
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return [200, 201].contains(code)
    }

    // MARK: - Direct Store Showcases from Supabase Cloud Database

    func fetchStoreShowcasesDirect() async throws -> [StoreShowcase] {
        // 1. Primary path: upgraded single-roundtrip RPC `get_home_showcases_v2`
        //    (quality-ranked, deduplicated, adult sport only, multi-store + all-time-low signals)
        struct FastShowcaseRowV2: Codable {
            let id: String
            let product_id: String?
            let store_id: String
            let store_name: String
            let raw_title: String
            let product_canonical_name: String?
            let product_brand: String?
            let product_category: String?
            let product_gender: String?
            let current_price: Double
            let original_price: Double?
            let discount_pct: Double?
            let product_url: String
            let image_url: String?
            let gallery_images: [String]?
            let available_sizes: [String]?
            let size_count: Int?
            let multi_store_count: Int?
            let market_min_price: Double?
            let market_max_price: Double?
            let is_best_market_price: Bool?
            let is_all_time_low: Bool?
            let price_drop_eur: Double?
            let has_free_shipping: Bool?
            let shipping_cost: Double?
            let free_shipping_threshold: Double?
            let courier: String?
            let last_checked_at: String?
            let store_rating: Double?
            let store_review_count: Int?
            let store_formatted_review_count: String?
            let store_card_theme: String?
            let store_accent_color: String?
            let store_logo_url: String?
            let store_total_offers: Int?
            let store_avg_discount: Double?
            let home_score: Double?
        }

        if let rpcV2Url = URL(string: "\(restURL)/rpc/get_home_showcases_v2") {
            var rpcReq = URLRequest(url: rpcV2Url)
            rpcReq.httpMethod = "POST"
            rpcReq.httpBody = Data("{\"p_per_store\":12}".utf8)
            for (k, v) in makeHeaders(isPublic: true) { rpcReq.setValue(v, forHTTPHeaderField: k) }
            if let (rpcData, rpcResp) = try? await session.data(for: rpcReq),
               let http = rpcResp as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let rowsV2 = try? JSONDecoder().decode([FastShowcaseRowV2].self, from: rpcData),
               !rowsV2.isEmpty {
                var grouped: [String: (
                    name: String,
                    products: [StoreShowcaseProduct],
                    rating: Double?,
                    reviewCount: Int?,
                    formattedReviews: String?,
                    theme: String?,
                    accent: String?,
                    logo: String?,
                    totalOffers: Int,
                    avgDiscount: Double
                )] = [:]

                for r in rowsV2 {
                    let sId = r.store_id.lowercased()
                    let extractedBrand = ProductBrandHelper.extractBrand(
                        from: r.product_canonical_name ?? r.raw_title,
                        fallback: r.product_brand ?? r.store_name
                    )
                    let isFreeShip: Bool = {
                        if let free = r.has_free_shipping { return free }
                        if let cost = r.shipping_cost { return cost == 0.0 }
                        if let thresh = r.free_shipping_threshold, thresh > 0 { return r.current_price >= thresh }
                        return false
                    }()
                    let resolvedShipCost: Double? = isFreeShip ? 0.0 : r.shipping_cost
                    let shippingLabel: String? = {
                        if isFreeShip { return "Sped. Gratis" }
                        if let cost = resolvedShipCost, cost > 0 { return "+ \(String(format: "%.2f", cost)) €" }
                        return nil
                    }()
                    let crossSavings: Double? = {
                        guard (r.multi_store_count ?? 1) >= 2,
                              let mx = r.market_max_price,
                              mx > r.current_price + 1.0,
                              mx <= r.current_price * 2.35 else { return nil }
                        return mx - r.current_price
                    }()
                    let canonical = (r.product_canonical_name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                        ? r.product_canonical_name!
                        : r.raw_title

                    let p = StoreShowcaseProduct(
                        id: r.id,
                        title: r.raw_title,
                        brand: extractedBrand,
                        image_url: r.image_url,
                        gallery_images: r.gallery_images,
                        available_sizes: r.available_sizes,
                        current_price: r.current_price,
                        original_price: r.original_price,
                        discount_pct: r.discount_pct,
                        product_url: r.product_url,
                        canonical_name: canonical,
                        product_id: r.product_id,
                        shipping_cost: resolvedShipCost,
                        total_price: resolvedShipCost.map { r.current_price + $0 },
                        is_free_shipping: isFreeShip,
                        shipping_label: shippingLabel,
                        free_shipping_threshold: r.free_shipping_threshold,
                        courier: r.courier,
                        store_id: sId,
                        store_name: r.store_name,
                        store_rating: r.store_rating.map { String(format: "%.1f", $0) },
                        store_review_count: r.store_formatted_review_count,
                        store_logo_url: r.store_logo_url,
                        product_category: r.product_category,
                        product_gender: r.product_gender,
                        size_count: r.size_count,
                        multi_store_count: r.multi_store_count,
                        market_min_price: r.market_min_price,
                        market_max_price: r.market_max_price,
                        cross_store_savings: crossSavings,
                        is_best_market_price: r.is_best_market_price,
                        is_all_time_low: r.is_all_time_low,
                        price_drop_eur: r.price_drop_eur,
                        deal_score: r.home_score,
                        last_checked_at: r.last_checked_at
                    )
                    if grouped[sId] == nil {
                        grouped[sId] = (
                            name: r.store_name,
                            products: [],
                            rating: r.store_rating,
                            reviewCount: r.store_review_count,
                            formattedReviews: r.store_formatted_review_count,
                            theme: r.store_card_theme,
                            accent: r.store_accent_color,
                            logo: r.store_logo_url,
                            totalOffers: r.store_total_offers ?? 0,
                            avgDiscount: r.store_avg_discount ?? 0.0
                        )
                    }
                    if (grouped[sId]?.products.count ?? 0) < 12 {
                        grouped[sId]?.products.append(p)
                    }
                }

                let v2Showcases: [StoreShowcase] = grouped.compactMap { (sId, info) in
                    guard !info.products.isEmpty else { return nil }
                    let ratingStr = info.rating.map { String(format: "%.1f", $0) } ?? "4.8"
                    let revStr = info.formattedReviews ?? (info.reviewCount != nil ? "\(info.reviewCount!)" : nil)
                    return StoreShowcase(
                        store_id: sId,
                        store_name: info.name,
                        total_offers: max(info.totalOffers, info.products.count),
                        avg_discount: info.avgDiscount,
                        rating: ratingStr,
                        review_count: revStr,
                        card_theme: info.theme ?? "white",
                        accent_color: info.accent,
                        logo_url: info.logo,
                        products: info.products
                    )
                }

                return v2Showcases.sorted {
                    let s0IsBrand = $0.store_id == "nike" || $0.store_id == "adidas"
                    let s1IsBrand = $1.store_id == "nike" || $1.store_id == "adidas"
                    if s0IsBrand && !s1IsBrand { return true }
                    if !s0IsBrand && s1IsBrand { return false }
                    return $0.total_offers > $1.total_offers
                }
            }
        }

        // 1b. Legacy fallback RPC `get_home_showcases_fast`
        struct FastShowcaseRow: Codable {
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
            let store_rating: Double?
            let store_review_count: Int?
            let store_formatted_review_count: String?
            let store_card_theme: String?
            let store_accent_color: String?
            let store_logo_url: String?
            let store_total_offers: Int?
            let store_avg_discount: Double?
        }

        if let rpcUrl = URL(string: "\(restURL)/rpc/get_home_showcases_fast") {
            var rpcReq = URLRequest(url: rpcUrl)
            rpcReq.httpMethod = "POST"
            rpcReq.httpBody = Data("{}".utf8)
            for (k, v) in makeHeaders(isPublic: true) { rpcReq.setValue(v, forHTTPHeaderField: k) }
            if let (rpcData, rpcResp) = try? await session.data(for: rpcReq),
               let http = rpcResp as? HTTPURLResponse, http.statusCode == 200,
               let fastRows = try? JSONDecoder().decode([FastShowcaseRow].self, from: rpcData),
               !fastRows.isEmpty {
                var grouped: [String: (
                    name: String,
                    products: [StoreShowcaseProduct],
                    rating: Double?,
                    reviewCount: Int?,
                    formattedReviews: String?,
                    theme: String?,
                    accent: String?,
                    logo: String?,
                    totalOffers: Int,
                    avgDiscount: Double
                )] = [:]

                for r in fastRows {
                    let sId = r.store_id.lowercased()
                    let extractedBrand = ProductBrandHelper.extractBrand(from: r.raw_title, fallback: r.store_name)
                    let isFreeShip = (r.shipping_cost != nil && r.shipping_cost == 0.0)
                        || (r.free_shipping_threshold != nil && r.free_shipping_threshold! > 0 && r.current_price >= r.free_shipping_threshold!)
                    let resolvedShip = isFreeShip ? 0.0 : r.shipping_cost
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
                        shipping_cost: resolvedShip,
                        total_price: resolvedShip.map { r.current_price + $0 },
                        is_free_shipping: isFreeShip,
                        shipping_label: isFreeShip ? "Sped. Gratis" : resolvedShip.map { "+ \(String(format: "%.2f", $0)) €" },
                        free_shipping_threshold: r.free_shipping_threshold,
                        courier: r.courier,
                        store_id: sId,
                        store_name: r.store_name
                    )
                    if grouped[sId] == nil {
                        grouped[sId] = (
                            name: r.store_name,
                            products: [],
                            rating: r.store_rating,
                            reviewCount: r.store_review_count,
                            formattedReviews: r.store_formatted_review_count,
                            theme: r.store_card_theme,
                            accent: r.store_accent_color,
                            logo: r.store_logo_url,
                            totalOffers: r.store_total_offers ?? 0,
                            avgDiscount: r.store_avg_discount ?? 25.0
                        )
                    }
                    if (grouped[sId]?.products.count ?? 0) < 12 {
                        grouped[sId]?.products.append(p)
                    }
                }

                let fastShowcases: [StoreShowcase] = grouped.compactMap { (sId, info) in
                    guard !info.products.isEmpty else { return nil }
                    let ratingStr = info.rating.map { String(format: "%.1f", $0) } ?? "4.8"
                    let revStr = info.formattedReviews ?? (info.reviewCount != nil ? "\(info.reviewCount!)" : nil)
                    return StoreShowcase(
                        store_id: sId,
                        store_name: info.name,
                        total_offers: max(info.totalOffers, info.products.count),
                        avg_discount: info.avgDiscount,
                        rating: ratingStr,
                        review_count: revStr,
                        card_theme: info.theme ?? "white",
                        accent_color: info.accent,
                        logo_url: info.logo,
                        products: info.products
                    )
                }

                return fastShowcases.sorted {
                    let s0IsBrand = $0.store_id == "nike" || $0.store_id == "adidas"
                    let s1IsBrand = $1.store_id == "nike" || $1.store_id == "adidas"
                    if s0IsBrand && !s1IsBrand { return true }
                    if !s0IsBrand && s1IsBrand { return false }
                    return $0.total_offers > $1.total_offers
                }
            }
        }

        // 2. Fallback: execute offers, catalog stats, and store metadata in parallel
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

        struct StoreCatalogStats: Codable {
            let store_id: String
            let total_offers: Int
            let avg_discount: Double?
        }

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

        let baseRestURL = restURL
        let publicHeaders = makeHeaders(isPublic: true)
        let urlSession = session

        async let offersTask: [OfferRow] = {
            if let viewUrl = URL(string: "\(baseRestURL)/store_showcase_offers?select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,available_sizes,shipping_cost,free_shipping_threshold,courier&order=rn.asc") {
                var req = URLRequest(url: viewUrl)
                for (k, v) in publicHeaders { req.setValue(v, forHTTPHeaderField: k) }
                if let (data, resp) = try? await urlSession.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let rows = try? JSONDecoder().decode([OfferRow].self, from: data),
                   !rows.isEmpty {
                    return rows
                }
            }
            if let rawUrl = URL(string: "\(baseRestURL)/store_offers?select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,available_sizes,shipping_cost,free_shipping_threshold,courier&limit=2500") {
                var req = URLRequest(url: rawUrl)
                for (k, v) in publicHeaders { req.setValue(v, forHTTPHeaderField: k) }
                if let (data, resp) = try? await urlSession.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let rows = try? JSONDecoder().decode([OfferRow].self, from: data) {
                    return rows
                }
            }
            return []
        }()

        async let statsTask: [String: StoreCatalogStats] = {
            var map: [String: StoreCatalogStats] = [:]
            if let statsUrl = URL(string: "\(baseRestURL)/store_catalog_stats?select=store_id,total_offers,avg_discount") {
                var statsReq = URLRequest(url: statsUrl)
                for (k, v) in publicHeaders { statsReq.setValue(v, forHTTPHeaderField: k) }
                if let (statsData, statsResp) = try? await urlSession.data(for: statsReq),
                   let http = statsResp as? HTTPURLResponse, http.statusCode == 200,
                   let decodedStats = try? JSONDecoder().decode([StoreCatalogStats].self, from: statsData) {
                    for st in decodedStats {
                        map[st.store_id.lowercased()] = st
                    }
                }
            }
            return map
        }()

        async let storesTask: [String: StoreDbRecord] = {
            var map: [String: StoreDbRecord] = [:]
            if let storesUrl = URL(string: "\(baseRestURL)/stores?select=id,name,rating,review_count,formatted_review_count,card_theme,accent_color,logo_url") {
                var storeReq = URLRequest(url: storesUrl)
                for (k, v) in publicHeaders { storeReq.setValue(v, forHTTPHeaderField: k) }
                if let (sData, sResp) = try? await urlSession.data(for: storeReq),
                   let http = sResp as? HTTPURLResponse, http.statusCode == 200,
                   let decodedStores = try? JSONDecoder().decode([StoreDbRecord].self, from: sData) {
                    for st in decodedStores {
                        map[st.id.lowercased()] = st
                    }
                }
            }
            return map
        }()

        let (fetchedOffers, storeStatsMap, storeDbMap) = await (offersTask, statsTask, storesTask)

        var storeMap: [String: (name: String, products: [StoreShowcaseProduct], discounts: [Double], totalCount: Int)] = [:]
        for r in fetchedOffers {
            let extractedBrand = ProductBrandHelper.extractBrand(from: r.raw_title, fallback: r.store_name)
            let isFreeShip = (r.shipping_cost != nil && r.shipping_cost == 0.0)
                || (r.free_shipping_threshold != nil && r.free_shipping_threshold! > 0 && r.current_price >= r.free_shipping_threshold!)
            let resolvedShip = isFreeShip ? 0.0 : r.shipping_cost
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
                shipping_cost: resolvedShip,
                total_price: resolvedShip.map { r.current_price + $0 },
                is_free_shipping: isFreeShip,
                shipping_label: isFreeShip ? "Sped. Gratis" : resolvedShip.map { "+ \(String(format: "%.2f", $0)) €" },
                free_shipping_threshold: r.free_shipping_threshold,
                courier: r.courier,
                store_id: r.store_id.lowercased(),
                store_name: r.store_name
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

    // MARK: - Direct Home Personalized & Comparator Highlights (`get_home_highlights_v2`)

    func fetchHomeHighlightsDirect(
        shoeSize: String?,
        apparelSize: String?,
        sports: [String],
        brands: [String],
        hiddenStores: [String],
        limitPerSection: Int = 10
    ) async throws -> HomeHighlightsBundle {
        struct HighlightRow: Codable {
            let section_key: String
            let id: String
            let product_id: String?
            let store_id: String
            let store_name: String
            let raw_title: String
            let product_canonical_name: String?
            let product_brand: String?
            let product_category: String?
            let product_gender: String?
            let current_price: Double
            let original_price: Double?
            let discount_pct: Double?
            let product_url: String
            let image_url: String?
            let gallery_images: [String]?
            let available_sizes: [String]?
            let size_count: Int?
            let multi_store_count: Int?
            let market_min_price: Double?
            let market_max_price: Double?
            let cross_store_savings: Double?
            let is_best_market_price: Bool?
            let is_all_time_low: Bool?
            let price_drop_eur: Double?
            let has_free_shipping: Bool?
            let shipping_cost: Double?
            let free_shipping_threshold: Double?
            let courier: String?
            let deal_score: Double?
            let last_checked_at: String?
            let section_rank: Int?
        }

        guard let rpcUrl = URL(string: "\(restURL)/rpc/get_home_highlights_v2") else {
            return .empty
        }

        var payload: [String: Any] = [
            "p_limit_per_section": limitPerSection
        ]
        let cleanShoe = shoeSize?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanApparel = apparelSize?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanShoe.isEmpty { payload["p_shoe_size"] = cleanShoe }
        if !cleanApparel.isEmpty { payload["p_apparel_size"] = cleanApparel }
        if !sports.isEmpty { payload["p_sports"] = sports }
        if !brands.isEmpty { payload["p_brands"] = brands }
        if !hiddenStores.isEmpty { payload["p_hidden_stores"] = hiddenStores }

        var req = URLRequest(url: rpcUrl)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let rows = try JSONDecoder().decode([HighlightRow].self, from: data)
        var personalizedKey = (!cleanShoe.isEmpty || !cleanApparel.isEmpty) ? "for_your_size" : "for_you"
        var personalized: [StoreShowcaseProduct] = []
        var compareSave: [StoreShowcaseProduct] = []
        var priceDrops: [StoreShowcaseProduct] = []

        for r in rows {
            let sId = r.store_id.lowercased()
            let canonical = (r.product_canonical_name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? r.product_canonical_name!
                : r.raw_title
            let extractedBrand = ProductBrandHelper.extractBrand(from: canonical, fallback: r.product_brand ?? r.store_name)
            let isFree = r.has_free_shipping
                ?? ((r.shipping_cost != nil && r.shipping_cost == 0.0)
                    || (r.free_shipping_threshold != nil && r.free_shipping_threshold! > 0 && r.current_price >= r.free_shipping_threshold!))
            let resolvedShip = isFree ? 0.0 : r.shipping_cost
            let prod = StoreShowcaseProduct(
                id: r.id,
                title: r.raw_title,
                brand: extractedBrand,
                image_url: r.image_url,
                gallery_images: r.gallery_images,
                available_sizes: r.available_sizes,
                current_price: r.current_price,
                original_price: r.original_price,
                discount_pct: r.discount_pct,
                product_url: r.product_url,
                canonical_name: canonical,
                product_id: r.product_id,
                shipping_cost: resolvedShip,
                total_price: resolvedShip.map { r.current_price + $0 },
                is_free_shipping: isFree,
                shipping_label: isFree ? "Sped. Gratis" : resolvedShip.map { "+ \(String(format: "%.2f", $0)) €" },
                free_shipping_threshold: r.free_shipping_threshold,
                courier: r.courier,
                store_id: sId,
                store_name: r.store_name,
                product_category: r.product_category,
                product_gender: r.product_gender,
                size_count: r.size_count,
                multi_store_count: r.multi_store_count,
                market_min_price: r.market_min_price,
                market_max_price: r.market_max_price,
                cross_store_savings: r.cross_store_savings,
                is_best_market_price: r.is_best_market_price,
                is_all_time_low: r.is_all_time_low,
                price_drop_eur: r.price_drop_eur,
                deal_score: r.deal_score,
                last_checked_at: r.last_checked_at
            )

            switch r.section_key {
            case "for_your_size", "for_you":
                personalizedKey = r.section_key
                personalized.append(prod)
            case "compare_save":
                compareSave.append(prod)
            case "price_drops":
                priceDrops.append(prod)
            default:
                break
            }
        }

        return HomeHighlightsBundle(
            personalizedSectionKey: personalizedKey,
            personalizedDeals: personalized,
            compareSaveDeals: compareSave,
            priceDropDeals: priceDrops
        )
    }

    // MARK: - Direct Following Feed (`get_following_feed_v2`)

    func fetchFollowingFeedDirect(
        storeIds: [String],
        mode: FollowingFeedMode = .all,
        onlyMySize: Bool = false,
        shoeSize: String? = nil,
        apparelSize: String? = nil,
        sports: [String] = [],
        brands: [String] = [],
        perStore: Int = 12,
        highlightsLimit: Int = 12
    ) async throws -> FollowingFeedBundle {
        let cleanStoreIds = storeIds
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleanStoreIds.isEmpty,
              let rpcUrl = URL(string: "\(restURL)/rpc/get_following_feed_v2") else {
            return .empty
        }

        struct FollowingFeedRow: Codable {
            let row_kind: String
            let id: String
            let product_id: String?
            let store_id: String
            let store_name: String
            let raw_title: String?
            let product_canonical_name: String?
            let product_brand: String?
            let product_category: String?
            let product_gender: String?
            let current_price: Double?
            let original_price: Double?
            let discount_pct: Double?
            let product_url: String?
            let image_url: String?
            let gallery_images: [String]?
            let available_sizes: [String]?
            let size_count: Int?
            let multi_store_count: Int?
            let market_min_price: Double?
            let market_max_price: Double?
            let cross_store_savings: Double?
            let is_best_market_price: Bool?
            let is_all_time_low: Bool?
            let price_drop_eur: Double?
            let has_free_shipping: Bool?
            let shipping_cost: Double?
            let free_shipping_threshold: Double?
            let courier: String?
            let deal_score: Double?
            let last_checked_at: String?
            let product_created_at: String?
            let is_new_arrival: Bool?
            let store_rating: Double?
            let store_review_count: Int?
            let store_formatted_review_count: String?
            let store_card_theme: String?
            let store_accent_color: String?
            let store_logo_url: String?
            let store_total_offers: Int?
            let store_avg_discount: Double?
            let store_max_discount: Double?
            let store_discounted_count: Int?
            let store_atl_count: Int?
            let store_new_7d_count: Int?
            let store_matching_count: Int?
            let item_rank: Int?
        }

        var payload: [String: Any] = [
            "p_store_ids": cleanStoreIds,
            "p_mode": mode.rawValue,
            "p_only_my_size": onlyMySize,
            "p_per_store": perStore,
            "p_highlights_limit": highlightsLimit
        ]
        let cleanShoe = shoeSize?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanApparel = apparelSize?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanShoe.isEmpty { payload["p_shoe_size"] = cleanShoe }
        if !cleanApparel.isEmpty { payload["p_apparel_size"] = cleanApparel }
        if !sports.isEmpty { payload["p_sports"] = sports }
        if !brands.isEmpty { payload["p_brands"] = brands }

        var req = URLRequest(url: rpcUrl)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let rows = try JSONDecoder().decode([FollowingFeedRow].self, from: data)

        struct StoreMetaAcc {
            var name: String
            var totalOffers: Int
            var avgDiscount: Double
            var maxDiscount: Double
            var discountedCount: Int
            var atlCount: Int
            var new7dCount: Int
            var matchingCount: Int
            var rating: String?
            var reviewCount: String?
            var logoUrl: String?
            var accentColor: String?
            var freeShippingThreshold: Double?
            var products: [StoreShowcaseProduct]
        }

        var metaByStore: [String: StoreMetaAcc] = [:]
        var highlightsWithRank: [(rank: Int, product: StoreShowcaseProduct)] = []

        func buildProduct(from r: FollowingFeedRow) -> StoreShowcaseProduct? {
            guard let price = r.current_price, price > 0,
                  let rawTitle = r.raw_title, !rawTitle.isEmpty,
                  let prodUrl = r.product_url, !prodUrl.isEmpty else {
                return nil
            }
            let sId = r.store_id.lowercased()
            let canonical = (r.product_canonical_name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? r.product_canonical_name!
                : rawTitle
            let extractedBrand = ProductBrandHelper.extractBrand(from: canonical, fallback: r.product_brand ?? r.store_name)
            let isFree = r.has_free_shipping
                ?? ((r.shipping_cost != nil && r.shipping_cost == 0.0)
                    || (r.free_shipping_threshold != nil && r.free_shipping_threshold! > 0 && price >= r.free_shipping_threshold!))
            let resolvedShip = isFree ? 0.0 : r.shipping_cost
            let crossSavings: Double? = {
                if let cs = r.cross_store_savings, cs > 1.0 { return cs }
                if (r.multi_store_count ?? 1) >= 2,
                   let mx = r.market_max_price,
                   mx > price + 1.0,
                   mx <= price * 2.35 {
                    return mx - price
                }
                return nil
            }()
            return StoreShowcaseProduct(
                id: r.id,
                title: rawTitle,
                brand: extractedBrand,
                image_url: r.image_url,
                gallery_images: r.gallery_images,
                available_sizes: r.available_sizes,
                current_price: price,
                original_price: r.original_price,
                discount_pct: r.discount_pct,
                product_url: prodUrl,
                canonical_name: canonical,
                product_id: r.product_id,
                shipping_cost: resolvedShip,
                total_price: resolvedShip.map { price + $0 },
                is_free_shipping: isFree,
                shipping_label: isFree ? "Sped. Gratis" : resolvedShip.map { "+ \(String(format: "%.2f", $0)) €" },
                free_shipping_threshold: r.free_shipping_threshold,
                courier: r.courier,
                store_id: sId,
                store_name: r.store_name,
                store_rating: r.store_rating.map { String(format: "%.1f", $0) },
                store_review_count: r.store_formatted_review_count,
                store_logo_url: r.store_logo_url,
                product_category: r.product_category,
                product_gender: r.product_gender,
                size_count: r.size_count,
                multi_store_count: r.multi_store_count,
                market_min_price: r.market_min_price,
                market_max_price: r.market_max_price,
                cross_store_savings: crossSavings,
                is_best_market_price: r.is_best_market_price,
                is_all_time_low: r.is_all_time_low,
                price_drop_eur: r.price_drop_eur,
                deal_score: r.deal_score,
                last_checked_at: r.last_checked_at,
                product_created_at: r.product_created_at,
                is_new_arrival: r.is_new_arrival
            )
        }

        func ensureMeta(for r: FollowingFeedRow) {
            let sId = r.store_id.lowercased()
            if metaByStore[sId] == nil {
                let ratingStr = r.store_rating.map { String(format: "%.1f", $0) }
                let revStr = r.store_formatted_review_count ?? r.store_review_count.map { "\($0)" }
                metaByStore[sId] = StoreMetaAcc(
                    name: r.store_name,
                    totalOffers: r.store_total_offers ?? 0,
                    avgDiscount: r.store_avg_discount ?? 0.0,
                    maxDiscount: r.store_max_discount ?? 0.0,
                    discountedCount: r.store_discounted_count ?? 0,
                    atlCount: r.store_atl_count ?? 0,
                    new7dCount: r.store_new_7d_count ?? 0,
                    matchingCount: r.store_matching_count ?? 0,
                    rating: ratingStr,
                    reviewCount: revStr,
                    logoUrl: r.store_logo_url,
                    accentColor: r.store_accent_color,
                    freeShippingThreshold: r.free_shipping_threshold,
                    products: []
                )
            }
        }

        for r in rows {
            let sId = r.store_id.lowercased()
            ensureMeta(for: r)
            switch r.row_kind {
            case "store_meta":
                continue
            case "highlight":
                if let prod = buildProduct(from: r) {
                    highlightsWithRank.append((rank: r.item_rank ?? 999, product: prod))
                }
            case "store_item":
                if let prod = buildProduct(from: r) {
                    metaByStore[sId]?.products.append(prod)
                }
            default:
                break
            }
        }

        let sortedHighlights = highlightsWithRank
            .sorted { $0.rank < $1.rank }
            .map(\.product)

        var orderedSections: [FollowingStoreSection] = []
        var seenStoreIds = Set<String>()
        for sid in cleanStoreIds where seenStoreIds.insert(sid).inserted {
            if let acc = metaByStore[sid] {
                orderedSections.append(
                    FollowingStoreSection(
                        store_id: sid,
                        store_name: acc.name,
                        total_offers: max(acc.totalOffers, acc.products.count),
                        avg_discount: acc.avgDiscount,
                        max_discount: acc.maxDiscount,
                        discounted_count: acc.discountedCount,
                        atl_count: acc.atlCount,
                        new_7d_count: acc.new7dCount,
                        matching_count: max(acc.matchingCount, acc.products.count),
                        rating: acc.rating,
                        review_count: acc.reviewCount,
                        logo_url: acc.logoUrl,
                        accent_color: acc.accentColor,
                        free_shipping_threshold: acc.freeShippingThreshold,
                        products: acc.products
                    )
                )
            }
        }

        return FollowingFeedBundle(highlights: sortedHighlights, stores: orderedSections)
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
        guard let url = URL(string: "\(restURL)/store_offers?store_id=eq.\(encodeQueryValue(cleanId))&in_stock=neq.false&current_price=gt.0&image_url=not.is.null&image_url=neq.&order=discount_pct.desc.nullslast,current_price.desc&limit=\(limit)&select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,available_sizes,shipping_cost,free_shipping_threshold,courier,last_checked_at") else {
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
            let last_checked_at: String?
        }
        let rows = try JSONDecoder().decode([OfferRow].self, from: data)
        let storeShipRule = DynamicCatalogRegistry.shared.shippingRule(for: cleanId)
        return rows.map { r in
            let extractedBrand = ProductBrandHelper.extractBrand(from: r.raw_title, fallback: r.store_name)
            let effThreshold = r.free_shipping_threshold ?? storeShipRule?.threshold
            let isFreeShip: Bool = {
                if let cost = r.shipping_cost, cost == 0.0 { return true }
                if let thresh = effThreshold, thresh > 0, r.current_price >= thresh { return true }
                return false
            }()
            let resolvedShipCost: Double? = isFreeShip ? 0.0 : (r.shipping_cost ?? storeShipRule?.standard)
            let shippingLabel: String? = {
                if isFreeShip { return "Sped. Gratis" }
                if let cost = resolvedShipCost, cost > 0 { return "+ \(String(format: "%.2f", cost)) €" }
                return nil
            }()
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
                shipping_cost: resolvedShipCost,
                total_price: resolvedShipCost.map { r.current_price + $0 },
                is_free_shipping: isFreeShip,
                shipping_label: shippingLabel,
                free_shipping_threshold: effThreshold,
                courier: r.courier,
                store_id: cleanId,
                store_name: r.store_name,
                size_count: r.available_sizes?.count,
                last_checked_at: r.last_checked_at
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

    func findBestLiveOfferDirect(canonicalName: String, productId: String? = nil, requiredSize: String? = nil) async -> LiveOfferResult? {
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

        // 1. Resolve exact cluster product_id first so we NEVER cross-match unrelated accessories via loose ILIKE
        var resolvedProductId = productId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedProductId == nil || resolvedProductId?.isEmpty == true {
            let cleanName = canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanName.isEmpty,
               let prodUrl = URL(string: "\(restURL)/products?canonical_name=ilike.\(encodeQueryValue(cleanName))&select=id&limit=1") {
                var pReq = URLRequest(url: prodUrl)
                for (k, v) in makeHeaders(isPublic: true) { pReq.setValue(v, forHTTPHeaderField: k) }
                struct ProdIdRow: Codable { let id: String }
                if let (pData, pResp) = try? await session.data(for: pReq),
                   let pHttp = pResp as? HTTPURLResponse, pHttp.statusCode == 200,
                   let pRows = try? JSONDecoder().decode([ProdIdRow].self, from: pData),
                   let matchedId = pRows.first?.id, !matchedId.isEmpty {
                    resolvedProductId = matchedId
                }
            }
        }

        let targetURL: URL?
        if let pid = resolvedProductId, !pid.isEmpty {
            targetURL = URL(string: "\(restURL)/store_offers?product_id=eq.\(encodeQueryValue(pid))&in_stock=neq.false&current_price=gt.0&order=current_price.asc&limit=40&select=store_id,store_name,current_price,original_price,discount_pct,product_url,image_url,available_sizes")
        } else {
            // Safe text fallback: preserve numeric model versions (e.g. "19" in "Ride 19") and require >=2 tokens
            let stopWords: Set<String> = ["scarpe", "scarpa", "donna", "uomo", "modello", "edition"]
            let rawWords = canonicalName
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 || ($0.count >= 2 && $0.allSatisfy(\.isNumber)) }
            let filteredWords = rawWords.filter { !stopWords.contains($0.lowercased()) }
            let searchWords = filteredWords.isEmpty ? Array(rawWords.prefix(4)) : Array(filteredWords.prefix(4))
            guard searchWords.count >= 2 else { return nil }
            let pattern = searchWords.joined(separator: "*")
            targetURL = URL(string: "\(restURL)/store_offers?raw_title=ilike.\(encodeQueryValue("*\(pattern)*"))&in_stock=neq.false&current_price=gt.0&order=current_price.asc&limit=20&select=store_id,store_name,current_price,original_price,discount_pct,product_url,image_url,available_sizes")
        }

        guard let url = targetURL else { return nil }
        var req = URLRequest(url: url)
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }

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
                    let c = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                        .replacingOccurrences(of: ",", with: ".")
                    let targetNorm = cleanSize.replacingOccurrences(of: ",", with: ".")
                    return c == targetNorm || c == "eu \(targetNorm)"
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

    // MARK: - Dedicated Deals Showcases v2 (Deal Quality Score, Multi-Filter & Cross-Store)

    private struct RpcDealRowV2: Codable {
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
        let gallery_images: [String]?
        let shipping_cost: Double?
        let free_shipping_threshold: Double?
        let courier: String?
        let store_rating: Double?
        let store_formatted_review_count: String?
        let store_review_count: Int?
        let store_card_theme: String?
        let store_accent_color: String?
        let store_logo_url: String?
        let product_brand: String?
        let product_category: String?
        let product_gender: String?
        let product_canonical_name: String?
        let size_count: Int?
        let multi_store_count: Int?
        let market_min_price: Double?
        let is_best_market_price: Bool?
        let is_all_time_low: Bool?
        let price_drop_eur: Double?
        let deal_score: Double?
        let last_checked_at: String?
        let store_total_category_deals: Int?
    }

    private func buildDealsRpcPayload(
        category: String,
        perStoreOrLimitKey: String,
        perStoreOrLimitValue: Int,
        filters: DealsFilterOptions
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "p_category": category,
            perStoreOrLimitKey: perStoreOrLimitValue,
            "p_free_shipping": filters.freeShippingOnly,
            "p_include_kids": filters.includeKids,
            "p_sort": filters.sort.rawValue
        ]
        if let g = filters.gender, !g.isEmpty { payload["p_gender"] = g }
        if let sz = filters.size, !sz.isEmpty { payload["p_size"] = sz }
        if let mp = filters.maxPrice { payload["p_max_price"] = mp }
        if let md = filters.minDiscount { payload["p_min_discount"] = md }
        if let br = filters.brand, !br.isEmpty { payload["p_brand"] = br }
        return payload
    }

    private func mapRpcDealRow(_ r: RpcDealRowV2) -> StoreShowcaseProduct {
        let extractedBrand: String = {
            if let b = r.product_brand?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
                return b
            }
            return ProductBrandHelper.extractBrand(from: r.raw_title, fallback: r.store_name)
        }()
        let cleanTitle = DealTitleSanitizer.clean(
            r.raw_title,
            brand: extractedBrand,
            canonicalName: r.product_canonical_name
        )
        let cleanCanonical: String = {
            if let c = r.product_canonical_name?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
                return DealTitleSanitizer.clean(c, brand: extractedBrand)
            }
            return cleanTitle
        }()
        let resolvedShip: Double = {
            if let s = r.shipping_cost { return s }
            if let t = r.free_shipping_threshold, t > 0, r.current_price >= t { return 0.0 }
            if let rule = DynamicCatalogRegistry.shared.shippingRule(for: r.store_id) {
                if let t = r.free_shipping_threshold ?? rule.threshold, r.current_price >= t { return 0.0 }
                return rule.standard
            }
            return 0.0
        }()
        let ratingStr = r.store_rating.map { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") }
        let revStr = r.store_formatted_review_count ?? r.store_review_count.map { "\($0)" }
        return StoreShowcaseProduct(
            id: r.id,
            title: cleanTitle,
            brand: extractedBrand,
            image_url: r.image_url,
            gallery_images: r.gallery_images,
            available_sizes: r.available_sizes,
            current_price: r.current_price,
            original_price: r.original_price,
            discount_pct: r.discount_pct,
            product_url: r.product_url,
            canonical_name: cleanCanonical,
            product_id: r.product_id,
            shipping_cost: resolvedShip,
            total_price: r.current_price + resolvedShip,
            is_free_shipping: resolvedShip == 0.0,
            shipping_label: resolvedShip == 0.0 ? "Sped. Gratis" : "+ \(String(format: "%.2f", resolvedShip)) €",
            free_shipping_threshold: r.free_shipping_threshold,
            courier: r.courier,
            store_id: r.store_id.lowercased(),
            store_name: r.store_name,
            store_rating: ratingStr,
            store_review_count: revStr,
            store_logo_url: r.store_logo_url,
            product_category: r.product_category,
            product_gender: r.product_gender,
            size_count: r.size_count ?? r.available_sizes?.count,
            multi_store_count: r.multi_store_count,
            market_min_price: r.market_min_price,
            is_best_market_price: r.is_best_market_price,
            is_all_time_low: r.is_all_time_low,
            price_drop_eur: r.price_drop_eur,
            deal_score: r.deal_score,
            last_checked_at: r.last_checked_at
        )
    }

    func fetchTopDealsCrossStoreDirect(
        category: String? = nil,
        filters: DealsFilterOptions = DealsFilterOptions(),
        limit: Int = 40,
        offset: Int = 0
    ) async throws -> (deals: [StoreShowcaseProduct], totalMatching: Int) {
        let normalizedCategory = (category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "tutti"

        // 1. Primary path: paged v2 RPC (`get_top_deals_cross_store_v2`) supporting true infinite scroll via `p_offset`
        if let v2Url = URL(string: "\(restURL)/rpc/get_top_deals_cross_store_v2") {
            var rpcReq = URLRequest(url: v2Url)
            rpcReq.httpMethod = "POST"
            for (k, v) in makeHeaders(isPublic: true) {
                rpcReq.setValue(v, forHTTPHeaderField: k)
            }
            var payload = buildDealsRpcPayload(
                category: normalizedCategory,
                perStoreOrLimitKey: "p_limit",
                perStoreOrLimitValue: limit,
                filters: filters
            )
            payload["p_offset"] = max(0, offset)
            rpcReq.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            if let (data, resp) = try? await session.data(for: rpcReq),
               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let rows = try? JSONDecoder().decode([RpcDealRowV2].self, from: data) {
                let mapped = rows.map { mapRpcDealRow($0) }
                let total = rows.first?.store_total_category_deals ?? (offset + mapped.count)
                return (mapped, total)
            }
        }

        // 2. Legacy fallback (first page only)
        guard offset == 0, let rpcUrl = URL(string: "\(restURL)/rpc/get_top_deals_cross_store") else {
            return ([], offset)
        }
        var rpcReq = URLRequest(url: rpcUrl)
        rpcReq.httpMethod = "POST"
        for (k, v) in makeHeaders(isPublic: true) {
            rpcReq.setValue(v, forHTTPHeaderField: k)
        }
        let payload = buildDealsRpcPayload(
            category: normalizedCategory,
            perStoreOrLimitKey: "p_limit",
            perStoreOrLimitValue: limit,
            filters: filters
        )
        rpcReq.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await session.data(for: rpcReq)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let rows = try JSONDecoder().decode([RpcDealRowV2].self, from: data)
        let mapped = rows.map { mapRpcDealRow($0) }
        let total = rows.first?.store_total_category_deals ?? mapped.count
        return (mapped, total)
    }

    func fetchDealsShowcasesDirect(
        category: String? = nil,
        filters: DealsFilterOptions = DealsFilterOptions()
    ) async throws -> [StoreShowcase] {
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

        let normalizedCategory = (category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "tutti"

        // 1. Primary path: upgraded PostgreSQL RPC `get_deals_showcases_v2` (Deal Quality Score + multi-filter + gallery + market/history signals)
        if let rpcUrl = URL(string: "\(restURL)/rpc/get_deals_showcases_v2") {
            var rpcReq = URLRequest(url: rpcUrl)
            rpcReq.httpMethod = "POST"
            for (k, v) in makeHeaders(isPublic: true) {
                rpcReq.setValue(v, forHTTPHeaderField: k)
            }
            let payload = buildDealsRpcPayload(
                category: normalizedCategory,
                perStoreOrLimitKey: "p_per_store",
                perStoreOrLimitValue: 12,
                filters: filters
            )
            rpcReq.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            if let (data, resp) = try? await session.data(for: rpcReq),
               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let rpcRows = try? JSONDecoder().decode([RpcDealRowV2].self, from: data) {
                if rpcRows.isEmpty {
                    return []
                }

                var storeOrder: [String] = []
                var grouped: [String: (
                    name: String,
                    products: [StoreShowcaseProduct],
                    discounts: [Double],
                    totalCategoryDeals: Int,
                    rating: Double?,
                    formattedReviews: String?,
                    reviewCount: Int?,
                    theme: String?,
                    accent: String?,
                    logo: String?
                )] = [:]

                for r in rpcRows {
                    let p = mapRpcDealRow(r)
                    let sId = r.store_id.lowercased()
                    if grouped[sId] == nil {
                        storeOrder.append(sId)
                        grouped[sId] = (
                            name: r.store_name,
                            products: [],
                            discounts: [],
                            totalCategoryDeals: r.store_total_category_deals ?? 0,
                            rating: r.store_rating,
                            formattedReviews: r.store_formatted_review_count,
                            reviewCount: r.store_review_count,
                            theme: r.store_card_theme,
                            accent: r.store_accent_color,
                            logo: r.store_logo_url
                        )
                    }
                    grouped[sId]?.products.append(p)
                    if let disc = r.discount_pct, disc > 0 {
                        grouped[sId]?.discounts.append(disc)
                    }
                    if let totalCat = r.store_total_category_deals, totalCat > (grouped[sId]?.totalCategoryDeals ?? 0) {
                        grouped[sId]?.totalCategoryDeals = totalCat
                    }
                }

                // Preserve server-computed store ranking (Deal Quality Score / requested sort)
                return storeOrder.compactMap { sId in
                    guard let info = grouped[sId], !info.products.isEmpty else { return nil }
                    let avgDisc = info.discounts.isEmpty ? 25.0 : (info.discounts.reduce(0, +) / Double(info.discounts.count))
                    let rating = info.rating.map { String(format: "%.1f", $0) } ?? "4.8"
                    let revStr = info.formattedReviews ?? info.reviewCount.map { "\($0)" }
                    return StoreShowcase(
                        store_id: sId,
                        store_name: info.name,
                        total_offers: max(info.totalCategoryDeals, info.products.count),
                        avg_discount: avgDisc,
                        rating: rating,
                        review_count: revStr,
                        card_theme: info.theme ?? "white",
                        accent_color: info.accent,
                        logo_url: info.logo,
                        products: info.products
                    )
                }
            }
        }

        // 1b. Legacy RPC fallback if v2 is temporarily unreachable (default filters only)
        if filters.isDefault, let legacyUrl = URL(string: "\(restURL)/rpc/get_category_deals_showcases") {
            var rpcReq = URLRequest(url: legacyUrl)
            rpcReq.httpMethod = "POST"
            for (k, v) in makeHeaders(isPublic: true) {
                rpcReq.setValue(v, forHTTPHeaderField: k)
            }
            let payload: [String: Any] = ["p_category": normalizedCategory, "p_per_store": 12]
            rpcReq.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            if let (data, resp) = try? await session.data(for: rpcReq),
               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let rpcRows = try? JSONDecoder().decode([RpcDealRowV2].self, from: data) {
                if rpcRows.isEmpty { return [] }
                var storeOrder: [String] = []
                var grouped: [String: (name: String, products: [StoreShowcaseProduct], discounts: [Double], rating: Double?, formattedReviews: String?, reviewCount: Int?, theme: String?, accent: String?, logo: String?)] = [:]
                for r in rpcRows {
                    let p = mapRpcDealRow(r)
                    let sId = r.store_id.lowercased()
                    if grouped[sId] == nil {
                        storeOrder.append(sId)
                        grouped[sId] = (r.store_name, [], [], r.store_rating, r.store_formatted_review_count, r.store_review_count, r.store_card_theme, r.store_accent_color, r.store_logo_url)
                    }
                    grouped[sId]?.products.append(p)
                    if let disc = r.discount_pct, disc > 0 { grouped[sId]?.discounts.append(disc) }
                }
                return storeOrder.compactMap { sId in
                    guard let info = grouped[sId], !info.products.isEmpty else { return nil }
                    let avgDisc = info.discounts.isEmpty ? 25.0 : (info.discounts.reduce(0, +) / Double(info.discounts.count))
                    let rating = info.rating.map { String(format: "%.1f", $0) } ?? "4.8"
                    let revStr = info.formattedReviews ?? info.reviewCount.map { "\($0)" }
                    return StoreShowcase(
                        store_id: sId,
                        store_name: info.name,
                        total_offers: info.products.count,
                        avg_discount: avgDisc,
                        rating: rating,
                        review_count: revStr,
                        card_theme: info.theme ?? "white",
                        accent_color: info.accent,
                        logo_url: info.logo,
                        products: info.products
                    )
                }
            }
        }

        // 2. Fallback REST query if RPC is unavailable
        let isAllCategories = normalizedCategory == "tutti"
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
            guard let url = URL(string: "\(restURL)/store_offers?select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,available_sizes,shipping_cost,free_shipping_threshold,courier&discount_pct=gt.0&in_stock=neq.false&order=discount_pct.desc.nullslast&limit=1000") else {
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
        if normalizedCategory != "tutti" {
            rows = fetchedOffers.filter { CategoryFilterMatcher.matches(title: DealTitleSanitizer.clean($0.raw_title), category: normalizedCategory) }
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

        var storeMap: [String: (name: String, products: [StoreShowcaseProduct], seenKeys: Set<String>, discounts: [Double], maxDisc: Double)] = [:]
        for r in rows {
            let cleanTitle = DealTitleSanitizer.clean(r.raw_title)
            let dedupKey = (r.product_id?.isEmpty == false) ? r.product_id! : cleanTitle.lowercased()
            let sId = r.store_id.lowercased()
            if storeMap[sId] == nil {
                storeMap[sId] = (name: r.store_name, products: [], seenKeys: [], discounts: [], maxDisc: 0.0)
            }
            guard storeMap[sId]?.seenKeys.contains(dedupKey) != true else { continue }
            storeMap[sId]?.seenKeys.insert(dedupKey)

            let extractedBrand = ProductBrandHelper.extractBrand(from: cleanTitle, fallback: r.store_name)
            let p = StoreShowcaseProduct(
                id: r.id,
                title: cleanTitle,
                brand: extractedBrand,
                image_url: r.image_url,
                available_sizes: r.available_sizes,
                current_price: r.current_price,
                original_price: r.original_price,
                discount_pct: r.discount_pct,
                product_url: r.product_url,
                canonical_name: cleanTitle,
                product_id: r.product_id,
                shipping_cost: r.shipping_cost,
                total_price: r.current_price + (r.shipping_cost ?? 0.0),
                is_free_shipping: (r.shipping_cost ?? 0.0) == 0.0,
                shipping_label: (r.shipping_cost ?? 0.0) == 0.0 ? "Sped. Gratis" : "+ \(String(format: "%.2f", r.shipping_cost ?? 0.0)) €",
                free_shipping_threshold: r.free_shipping_threshold,
                courier: r.courier,
                store_id: sId,
                store_name: r.store_name
            )
            if (storeMap[sId]?.products.count ?? 0) < 12 {
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

        return showcases.sorted {
            let max0 = storeMap[$0.store_id]?.maxDisc ?? 0
            let max1 = storeMap[$1.store_id]?.maxDisc ?? 0
            if max0 != max1 {
                return max0 > max1
            }
            return $0.avg_discount > $1.avg_discount
        }
    }

    // MARK: - Multi-Store Offer Hydration for ProductDetailView

    func fetchHydratedProductDirect(productId: String, preferredOfferUrl: String? = nil) async -> MatchedProduct? {
        let trimmed = productId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        struct ProductMetaRow: Codable {
            let id: String
            let canonical_name: String
            let brand: String?
            let category: String?
            let gender: String?
            let image_url: String?
            let gallery_images: [String]?
        }
        struct SiblingOfferRow: Codable {
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
            let gallery_images: [String]?
            let available_sizes: [String]?
            let in_stock: Bool?
            let shipping_cost: Double?
            let free_shipping_threshold: Double?
            let courier: String?
            let last_checked_at: String?
        }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#")
        guard let encPid = trimmed.addingPercentEncoding(withAllowedCharacters: allowed),
              let offersUrl = URL(string: "\(restURL)/store_offers?product_id=eq.\(encPid)&in_stock=neq.false&current_price=gt.0&order=current_price.asc&limit=80&select=id,product_id,store_id,store_name,raw_title,current_price,original_price,discount_pct,product_url,image_url,gallery_images,available_sizes,in_stock,shipping_cost,free_shipping_threshold,courier,last_checked_at"),
              let prodUrl = URL(string: "\(restURL)/products?id=eq.\(encPid)&select=id,canonical_name,brand,category,gender,image_url,gallery_images&limit=1") else {
            return nil
        }

        let headers = makeHeaders(isPublic: true)
        var offersReq = URLRequest(url: offersUrl)
        var prodReq = URLRequest(url: prodUrl)
        for (k, v) in headers {
            offersReq.setValue(v, forHTTPHeaderField: k)
            prodReq.setValue(v, forHTTPHeaderField: k)
        }

        async let offersFetch = session.data(for: offersReq)
        async let prodFetch = session.data(for: prodReq)

        guard let (offersData, offersResp) = try? await offersFetch,
              let offersHttp = offersResp as? HTTPURLResponse, offersHttp.statusCode == 200,
              let siblingRows = try? JSONDecoder().decode([SiblingOfferRow].self, from: offersData),
              !siblingRows.isEmpty else {
            return nil
        }

        var prodMeta: ProductMetaRow? = nil
        if let (prodData, prodResp) = try? await prodFetch,
           let prodHttp = prodResp as? HTTPURLResponse, prodHttp.statusCode == 200,
           let decoded = try? JSONDecoder().decode([ProductMetaRow].self, from: prodData) {
            prodMeta = decoded.first
        }

        var seenOfferIds = Set<String>()
        var mappedOffers: [Offer] = []
        for row in siblingRows {
            let dedupKey = "\(row.store_id.lowercased())_\(row.product_url)"
            guard !seenOfferIds.contains(dedupKey) else { continue }
            seenOfferIds.insert(dedupKey)

            let effBrand = prodMeta?.brand ?? ProductBrandHelper.extractBrand(from: row.raw_title, fallback: row.store_name)
            let cleanTitle = DealTitleSanitizer.clean(row.raw_title, brand: effBrand, canonicalName: prodMeta?.canonical_name)
            let effShip: Double? = {
                if let t = row.free_shipping_threshold, t > 0, row.current_price >= t { return 0.0 }
                if let s = row.shipping_cost { return s }
                if let rule = DynamicCatalogRegistry.shared.shippingRule(for: row.store_id) {
                    if let t = row.free_shipping_threshold ?? rule.threshold, row.current_price >= t { return 0.0 }
                    return rule.standard
                }
                return nil
            }()
            let effDiscount: Double? = {
                if let d = row.discount_pct, d > 0 { return d }
                if let orig = row.original_price, orig > row.current_price {
                    return ((orig - row.current_price) / orig) * 100.0
                }
                return nil
            }()

            mappedOffers.append(Offer(
                store_id: row.store_id,
                store_name: row.store_name,
                product_id: row.product_id ?? trimmed,
                title: cleanTitle,
                brand: effBrand,
                price: row.current_price,
                original_price: row.original_price,
                discount_pct: effDiscount,
                savings: (row.original_price ?? row.current_price) - row.current_price,
                url: row.product_url,
                image_url: row.image_url,
                gallery_images: row.gallery_images,
                available_sizes: row.available_sizes ?? [],
                in_stock: row.in_stock ?? true,
                shipping_cost: effShip,
                total_price: effShip.map { row.current_price + $0 },
                is_free_shipping: effShip.map { $0 <= 0.001 },
                shipping_label: effShip.map { $0 <= 0.001 ? "Sped. Gratis" : String(format: "+ €%.2f sped.", $0) },
                free_shipping_threshold: row.free_shipping_threshold,
                courier: row.courier,
                last_checked_at: row.last_checked_at
            ))
        }

        guard !mappedOffers.isEmpty else { return nil }
        mappedOffers.sort { $0.calculatedTotalPrice < $1.calculatedTotalPrice }

        let minPrice = mappedOffers.map(\.price).min() ?? mappedOffers.first!.price
        let maxPrice = mappedOffers.map(\.price).max() ?? mappedOffers.last!.price
        let distinctStoreCount = Set(mappedOffers.map { $0.store_id.lowercased() }).count
        let crossSavings: Double? = (distinctStoreCount > 1 && maxPrice - minPrice > 1.0) ? (maxPrice - minPrice) : nil

        // Prioritize the tapped/preferred offer's own images first so the product hero never swaps to a mismatched colorway
        let preferredOffer: Offer? = {
            if let prefUrl = preferredOfferUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !prefUrl.isEmpty,
               let matched = mappedOffers.first(where: { $0.url.trimmingCharacters(in: .whitespacesAndNewlines) == prefUrl }) {
                return matched
            }
            return mappedOffers.first
        }()

        var allGallery: [String] = []
        if let pref = preferredOffer {
            for img in pref.allImages where !allGallery.contains(img) {
                allGallery.append(img)
            }
        }
        for off in mappedOffers {
            for img in off.allImages where !allGallery.contains(img) {
                allGallery.append(img)
            }
        }
        if let pImg = prodMeta?.image_url, !pImg.isEmpty, !allGallery.contains(pImg) {
            allGallery.append(pImg)
        }
        for g in prodMeta?.gallery_images ?? [] where !g.isEmpty && !allGallery.contains(g) {
            allGallery.append(g)
        }

        let canonical = DealTitleSanitizer.clean(
            prodMeta?.canonical_name ?? mappedOffers.first!.title,
            brand: prodMeta?.brand
        )
        return MatchedProduct(
            id_val: prodMeta?.id ?? trimmed,
            canonical_name: canonical,
            brand: prodMeta?.brand ?? mappedOffers.first?.effectiveBrand,
            category: prodMeta?.category,
            image_url: preferredOffer?.allImages.first ?? allGallery.first ?? prodMeta?.image_url,
            gallery_images: allGallery.isEmpty ? nil : allGallery,
            gender: prodMeta?.gender,
            offers: mappedOffers,
            best_price: minPrice,
            highest_price: maxPrice,
            cross_store_savings: crossSavings
        )
    }

    /// Fetches category-, gender-, and price-aligned related products directly from Supabase
    /// so "Potrebbe piacerti anche" recommends genuine alternatives rather than unrelated brand items.
    func fetchRelatedProductsDirect(
        excludingProductId: String?,
        excludingCanonicalName: String,
        category: String?,
        brand: String?,
        gender: String?,
        referencePrice: Double?,
        limit: Int = 8
    ) async -> [MatchedProduct] {
        let cleanCat = category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasSpecificCategory = (cleanCat != nil && !cleanCat!.isEmpty && cleanCat != "gear" && cleanCat != "non_sport" && cleanCat != "all")

        var candidates: [MatchedProduct] = []
        if hasSpecificCategory, let cat = cleanCat {
            // 1. Same category + gender (mix of brands for true alternatives)
            let catMatches = await fetchSmartProductsDirect(
                category: cat,
                keywords: [],
                brand: nil,
                gender: gender,
                maxPrice: referencePrice.map { max($0 * 1.85, $0 + 60) },
                limit: 28
            )
            candidates.append(contentsOf: catMatches)

            // 2. Also pull same-brand items inside the SAME category (e.g. sibling running shoes)
            if let b = brand?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
                let sameBrandSameCat = await fetchSmartProductsDirect(
                    category: cat,
                    keywords: [b],
                    brand: b,
                    gender: gender,
                    limit: 12
                )
                for item in sameBrandSameCat where !candidates.contains(where: { $0.id == item.id }) {
                    candidates.append(item)
                }
            }
        } else if let b = brand?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
            candidates = await fetchSmartProductsDirect(
                category: nil,
                keywords: [b],
                brand: b,
                gender: gender,
                limit: 20
            )
        }

        let normExclName = excludingCanonicalName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = candidates.filter { item in
            if let pid = excludingProductId, !pid.isEmpty, item.id_val == pid { return false }
            if item.canonical_name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normExclName { return false }
            guard let img = item.image_url?.trimmingCharacters(in: .whitespacesAndNewlines), !img.isEmpty else { return false }
            return (item.best_price ?? 0) > 0
        }

        // Rank by price proximity + balanced brand diversity (at most 3 from the same brand in the top 8)
        let refP = max(referencePrice ?? 80.0, 15.0)
        let scored = filtered.sorted { lhs, rhs in
            let lp = lhs.best_price ?? refP
            let rp = rhs.best_price ?? refP
            let lDist = abs(lp - refP) / refP
            let rDist = abs(rp - refP) / refP
            let lMulti = lhs.offers.count > 1 ? -0.18 : 0.0
            let rMulti = rhs.offers.count > 1 ? -0.18 : 0.0
            let lDisc = (lhs.bestOffer?.discount_pct ?? 0) >= 15 ? -0.10 : 0.0
            let rDisc = (rhs.bestOffer?.discount_pct ?? 0) >= 15 ? -0.10 : 0.0
            return (lDist + lMulti + lDisc) < (rDist + rMulti + rDisc)
        }

        var selected: [MatchedProduct] = []
        var brandCounts: [String: Int] = [:]
        for item in scored {
            let bKey = item.effectiveBrand.lowercased()
            if !bKey.isEmpty && (brandCounts[bKey] ?? 0) >= 3 && scored.count > limit {
                continue
            }
            selected.append(item)
            if !bKey.isEmpty { brandCounts[bKey, default: 0] += 1 }
            if selected.count >= limit { break }
        }
        return selected
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
        if let uid = validCurrentUserId {
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
        if let uid = validCurrentUserId {
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
        gender: String? = nil,
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
                case "sensor", "heart_rate_monitor":
                    params.append("category=in.(sensor,strap,gear,gps_watch)")
                case "running_shoes", "shoes":
                    params.append("category=in.(running_shoes,shoes,fitness)")
                case "trail_running":
                    params.append("category=in.(trail_running,running_shoes,shoes)")
                case "football_boots":
                    params.append("category=in.(football_boots,shoes)")
                case "top":
                    params.append("category=in.(top,apparel)")
                case "pants":
                    params.append("category=in.(pants,apparel)")
                case "jacket":
                    params.append("category=in.(jacket,apparel,top)")
                case "socks":
                    params.append("category=in.(socks,apparel,gear)")
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
            var andClauses: [String] = []
            let gLow = gender?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if gLow == "uomo" {
                andClauses.append("or(gender.ilike.*Uomo*,gender.eq.Unisex,gender.is.null)")
            } else if gLow == "donna" {
                andClauses.append("or(gender.ilike.*Donna*,gender.eq.Unisex,gender.is.null)")
            }
            if !term.isEmpty {
                let allWords = term.components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count >= 2 || ($0.count == 1 && $0.first?.isNumber == true) }
                let stopwords = Set(["scarpe", "scarpa", "running", "corsa", "per", "da", "di", "in", "con", "il", "la", "le", "i", "gli", "un", "una", "uno", "shoe", "shoes"])
                let specificWords = allWords.filter { !stopwords.contains($0.lowercased()) }
                let words = specificWords.isEmpty ? allWords : specificWords

                for w in words.prefix(4) {
                    if let wEnc = w.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        andClauses.append("or(canonical_name.ilike.*\(wEnc)*,brand.ilike.*\(wEnc)*)")
                    }
                }
            }
            if andClauses.count == 1, let single = andClauses.first {
                if single.hasPrefix("or(") && single.hasSuffix(")") {
                    params.append("or=(\(String(single.dropFirst(3).dropLast(1))))")
                } else {
                    params.append(single)
                }
            } else if andClauses.count > 1 {
                params.append("and=(\(andClauses.joined(separator: ",")))")
            }
            params.append(gLow == "uomo" || gLow == "donna" ? "limit=50" : "limit=25")

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

        let reqGender = gender?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filterByGender = (reqGender == "uomo" || reqGender == "donna")

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
            if filterByGender, let rg = reqGender {
                let pg = (p.gender ?? "unisex").lowercased()
                let isDual = pg.contains("uomo") && pg.contains("donna")
                if pg != "unisex" && !pg.isEmpty && !isDual && !pg.contains(rg) && !rg.contains(pg) {
                    continue
                }
                let offerMeta = rawOffers.prefix(4).map { "\($0.raw_title ?? "") \($0.product_url)" }.joined(separator: " ")
                let probe = "\(p.canonical_name) \(offerMeta)".lowercased()
                let hasF = probe.range(of: #"(?:\b(?:donna|donne|wmns|woman|women|womens|femme|lady|ladies|damen|mujer)\b|/(?:donna|woman|women|womens|wmns|femme)/)"#, options: .regularExpression) != nil
                let hasM = probe.range(of: #"(?:\b(?:uomo|uomini|men|mens|homme|herren|hombre)\b|/(?:uomo|men|mens|homme)/)"#, options: .regularExpression) != nil
                if rg == "uomo" && hasF && !hasM { continue }
                if rg == "donna" && hasM && !hasF { continue }
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
            let isValidImg: (String?) -> Bool = { raw in
                guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return false }
                let low = s.lowercased()
                return !low.contains("no-image") && !low.contains("no_image") && !low.contains("placeholder")
            }
            let primaryImg = formattedOffers.first(where: { isValidImg($0.image_url) })?.image_url
                ?? (isValidImg(p.image_url) ? p.image_url : nil)
                ?? formattedOffers.first?.image_url
                ?? p.image_url

            results.append(MatchedProduct(
                id_val: p.id,
                canonical_name: p.canonical_name,
                brand: p.brand,
                category: p.category,
                image_url: primaryImg,
                gallery_images: primaryImg != nil ? [primaryImg!] : nil,
                gender: p.gender ?? "Unisex",
                offers: formattedOffers,
                best_price: minP,
                highest_price: maxP,
                cross_store_savings: savings
            ))
        }

        if filterByGender, let rg = reqGender {
            results.sort { lhs, rhs in
                let lg = (lhs.gender ?? "unisex").lowercased()
                let rgG = (rhs.gender ?? "unisex").lowercased()
                let lhsExact = lg.contains(rg) && !(lg.contains("uomo") && lg.contains("donna"))
                let rhsExact = rgG.contains(rg) && !(rgG.contains("uomo") && rgG.contains("donna"))
                if lhsExact != rhsExact {
                    return lhsExact && !rhsExact
                }
                return (lhs.best_price ?? 0) < (rhs.best_price ?? 0)
            }
        }

        return Array(results.prefix(limit))
    }

    // MARK: - Direct Persistent AI Chat Sessions & Messages

    func fetchChatSessionsDirect(deviceId: String, userId: String? = nil, limit: Int = 20) async -> [ChatSessionSummary] {
        let did = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = (userId ?? validCurrentUserId)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validUid = (uid != nil && UUID(uuidString: uid!) != nil) ? uid : nil

        var filterClause: String?
        if let u = validUid, let uEnc = u.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           !did.isEmpty, let didEnc = did.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            filterClause = "or=(user_id.eq.\(uEnc),device_id.eq.\(didEnc))"
        } else if let u = validUid, let uEnc = u.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            filterClause = "user_id=eq.\(uEnc)"
        } else if !did.isEmpty, let didEnc = did.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            filterClause = "device_id=eq.\(didEnc)"
        }

        guard let filter = filterClause,
              let url = URL(string: "\(restURL)/chat_sessions?\(filter)&is_archived=eq.false&order=updated_at.desc&limit=\(limit)") else {
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
        response: SmartSearchResponse,
        userImageURL: String? = nil
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
            let user_image_url: String?
            let created_at: String
        }

        let sid = sessionId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !sid.isEmpty, UUID(uuidString: sid) != nil else { return }

        let nowIso = ISO8601DateFormatter().string(from: Date())
        let existing = await fetchChatSessionDetailDirect(sessionId: sid)
        let turnIdx = existing?.messages?.count ?? existing?.turn_count ?? 0
        let effImage = userImageURL ?? response.user_image_url
        let previewUrl = response.spotlight?.product.image_url ?? response.results.first?.image_url ?? effImage ?? existing?.preview_image_url

        let prevCtx = existing?.context_state
        let ctx = ChatSessionContextState(
            subject_query: prevCtx?.subject_query ?? (isFollowUp ? existing?.title : query),
            last_query: query,
            last_keywords: response.intent?.target_keywords ?? prevCtx?.last_keywords,
            entity_tokens: prevCtx?.entity_tokens,
            product_type: prevCtx?.product_type,
            brand: response.intent?.brand ?? prevCtx?.brand,
            excluded_brands: prevCtx?.excluded_brands,
            sub_brand: prevCtx?.sub_brand,
            category: response.intent?.category ?? prevCtx?.category,
            gender: response.intent?.gender ?? prevCtx?.gender,
            max_price: response.intent?.max_price ?? prevCtx?.max_price,
            min_price: response.intent?.min_price ?? prevCtx?.min_price,
            size: response.intent?.size ?? prevCtx?.size,
            color: prevCtx?.color,
            store: prevCtx?.store,
            excluded_stores: prevCtx?.excluded_stores,
            excluded_features: prevCtx?.excluded_features,
            sort_by: prevCtx?.sort_by,
            free_shipping: prevCtx?.free_shipping,
            on_sale: prevCtx?.on_sale,
            min_discount: prevCtx?.min_discount,
            features: response.intent?.features ?? prevCtx?.features
        )

        let resolvedTitle = existing?.title ?? query
        let resolvedSubtitle: String? = {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if isFollowUp, !trimmedQuery.isEmpty,
               trimmedQuery.caseInsensitiveCompare(resolvedTitle) != .orderedSame {
                return trimmedQuery
            }
            let totalProds = response.results.count
            if totalProds > 0 {
                let minPrice = response.results.compactMap { $0.best_price }.filter { $0 > 0 }.min()
                let countLabel = totalProds == 1 ? "1 prodotto" : "\(totalProds) prodotti"
                if let minP = minPrice {
                    let priceStr = String(format: "%.2f €", minP).replacingOccurrences(of: ".", with: ",")
                    return "\(countLabel) · da \(priceStr)"
                }
                return countLabel
            }
            let rawHeader = (response.conversational_header ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let genericHeaders: Set<String> = ["ho cercato prodotti", "ho cercato", "ricerca prodotti", "ricerca"]
            if !rawHeader.isEmpty,
               !genericHeaders.contains(rawHeader.lowercased()),
               rawHeader.caseInsensitiveCompare(resolvedTitle) != .orderedSame {
                return rawHeader
            }
            return nil
        }()

        let sessionPayload = SessionUpsertPayload(
            id: sid,
            device_id: deviceId,
            user_id: validCurrentUserId ?? existing?.user_id,
            chat_type: "smart_search",
            title: resolvedTitle,
            subtitle: resolvedSubtitle,
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
            results: Array(response.results.prefix(35)),
            curated_sections: Array((response.curated_sections ?? []).prefix(5)),
            comparative_cards: Array((response.comparative_cards ?? []).prefix(5)),
            featured_cards: Array((response.featured_cards ?? []).prefix(4)),
            searched_queries: Array((response.searched_queries ?? []).prefix(6)),
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
            user_image_url: effImage,
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

    /// Fetches all active stores directly from Supabase `stores` table (fast baseline independent of Render cold starts).
    func fetchActiveStoresDirect() async -> [ActiveStoreItem] {
        struct RawStoreRow: Codable {
            let id: String
            let name: String
            let base_url: String?
            let rating: Double?
            let review_count: Int?
            let formatted_review_count: String?
            let accent_color: String?
            let card_theme: String?
            let free_shipping_threshold: Double?
            let standard_shipping_cost: Double?
            let courier: String?
            let logo_url: String?
            let refund_policy: String?
            let shipping_policy: String?
            let is_verified: Bool?
        }

        let select = "id,name,base_url,rating,review_count,formatted_review_count,accent_color,card_theme,free_shipping_threshold,standard_shipping_cost,courier,logo_url,refund_policy,shipping_policy,is_verified"
        guard let url = URL(string: "\(restURL)/stores?select=\(select)&order=name.asc") else {
            return []
        }

        var req = URLRequest(url: url)
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let rows = try? JSONDecoder().decode([RawStoreRow].self, from: data) else {
            return []
        }

        let euStores: Set<String> = ["top4running", "deporvillage", "alltricks", "runningwarehouse", "tradeinn"]
        return rows.map { row in
            let sid = row.id.lowercased()
            let baseUrl = row.base_url ?? ""
            let lowerUrl = baseUrl.lowercased()
            let country: String = (euStores.contains(sid) || lowerUrl.contains(".eu") || lowerUrl.contains(".es") || lowerUrl.contains(".de") || lowerUrl.contains(".fr")) ? "EU" : "IT"

            var subParts: [String] = []
            if let courier = row.courier, !courier.isEmpty {
                subParts.append(courier)
            }
            if let thresh = row.free_shipping_threshold {
                let tStr = thresh.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(thresh))" : String(format: "%.2f", thresh)
                subParts.append("Gratis da €\(tStr)")
            } else if let stdCost = row.standard_shipping_cost {
                subParts.append(String(format: "Sped. da €%.2f", stdCost))
            }
            let subtitle = subParts.isEmpty ? nil : subParts.joined(separator: " · ")

            return ActiveStoreItem(
                id: row.id,
                name: row.name,
                base_url: baseUrl,
                rating: row.rating,
                review_count: row.review_count,
                formatted_review_count: row.formatted_review_count,
                accent_color: row.accent_color,
                card_theme: row.card_theme,
                free_shipping_threshold: row.free_shipping_threshold,
                standard_shipping_cost: row.standard_shipping_cost,
                courier: row.courier,
                country: country,
                logo_url: row.logo_url,
                is_new: nil,
                subtitle: subtitle,
                refund_policy: row.refund_policy,
                shipping_policy: row.shipping_policy,
                is_verified: row.is_verified
            )
        }
    }

    // MARK: - Direct Store Details & Paginated Catalog (RPC v2)

    func fetchStoreCatalogPageDirect(
        storeId: String,
        query: String = "",
        category: String = "tutti",
        brand: String? = nil,
        size: String? = nil,
        onlyDiscounted: Bool = false,
        maxPrice: Double? = nil,
        sort: String = "recommended",
        preferredSize: String? = nil,
        limit: Int = 40,
        offset: Int = 0
    ) async throws -> StoreCatalogPageResponse {
        struct RawStoreCatalogRow: Codable {
            let id: String
            let product_id: String?
            let store_id: String
            let store_name: String
            let raw_title: String
            let product_canonical_name: String?
            let product_brand: String?
            let product_category: String?
            let product_gender: String?
            let current_price: Double
            let original_price: Double?
            let discount_pct: Double?
            let product_url: String
            let image_url: String?
            let available_sizes: [String]?
            let size_count: Int?
            let has_free_shipping: Bool?
            let shipping_cost: Double?
            let free_shipping_threshold: Double?
            let courier: String?
            let matches_preferred_size: Bool?
            let last_checked_at: String?
            let total_matching: Int?
        }

        let sid = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(restURL)/rpc/get_store_catalog_v2") else {
            throw URLError(.badURL)
        }

        var payload: [String: Any] = [
            "p_store_id": sid,
            "p_category": category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "p_only_discounted": onlyDiscounted,
            "p_sort": sort,
            "p_limit": limit,
            "p_offset": offset
        ]
        let cleanQ = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanQ.isEmpty { payload["p_query"] = cleanQ }
        if let br = brand?.trimmingCharacters(in: .whitespacesAndNewlines), !br.isEmpty {
            payload["p_brand"] = br
        }
        if let sz = size?.trimmingCharacters(in: .whitespacesAndNewlines), !sz.isEmpty {
            payload["p_size"] = sz
        }
        if let mp = maxPrice, mp > 0 {
            payload["p_max_price"] = mp
        }
        if let pref = preferredSize?.trimmingCharacters(in: .whitespacesAndNewlines), !pref.isEmpty {
            payload["p_preferred_size"] = pref
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let rows = try JSONDecoder().decode([RawStoreCatalogRow].self, from: data)
        let total = rows.first?.total_matching ?? (offset + rows.count)
        let products: [StoreShowcaseProduct] = rows.map { r in
            let shipCost = r.shipping_cost ?? 0.0
            let isFree = r.has_free_shipping ?? (shipCost == 0.0)
            let extractedBrand = ProductBrandHelper.extractBrand(from: r.raw_title, fallback: r.product_brand ?? r.store_name)
            return StoreShowcaseProduct(
                id: r.id,
                title: r.raw_title,
                brand: extractedBrand,
                image_url: r.image_url,
                gallery_images: nil,
                available_sizes: r.available_sizes,
                current_price: r.current_price,
                original_price: r.original_price,
                discount_pct: r.discount_pct,
                product_url: r.product_url,
                canonical_name: r.product_canonical_name ?? r.raw_title,
                product_id: r.product_id,
                shipping_cost: shipCost,
                total_price: r.current_price + shipCost,
                is_free_shipping: isFree,
                shipping_label: isFree ? "Spedizione gratuita" : String(format: "+%.2f € sped.", shipCost),
                free_shipping_threshold: r.free_shipping_threshold,
                courier: r.courier,
                store_id: r.store_id,
                store_name: r.store_name,
                product_category: r.product_category,
                product_gender: r.product_gender,
                size_count: r.size_count,
                last_checked_at: r.last_checked_at
            )
        }
        return StoreCatalogPageResponse(products: products, totalMatching: total)
    }

    func fetchStoreDetailsDirect(
        storeId: String,
        query: String = "",
        sort: String = "recommended",
        preferredSize: String? = nil,
        limit: Int = 40
    ) async throws -> StoreDetailResponse {
        struct RawStoreOverviewRow: Codable {
            let store_id: String
            let store_name: String
            let base_url: String?
            let rating: Double?
            let review_count: Int?
            let formatted_review_count: String?
            let description: String?
            let full_description: String?
            let contact_email: String?
            let contact_phone: String?
            let social_instagram: String?
            let refund_policy: String?
            let shipping_policy: String?
            let privacy_policy_url: String?
            let terms_url: String?
            let city_or_location: String?
            let free_shipping_threshold: Double?
            let standard_shipping_cost: Double?
            let courier: String?
            let distinct_products: Int?
            let discounted_products: Int?
            let avg_discount: Double?
            let min_price: Double?
            let categories: [StoreCategoryFacet]?
            let top_brands: [StoreBrandFacet]?
        }

        let sid = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let publicHeaders = makeHeaders(isPublic: true)
        let urlSession = session
        let baseRest = restURL

        async let overviewTask: RawStoreOverviewRow? = {
            guard let url = URL(string: "\(baseRest)/rpc/get_store_overview_v2") else { return nil }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            for (k, v) in publicHeaders { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["p_store_id": sid])
            guard let (data, resp) = try? await urlSession.data(for: req),
                  let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let rows = try? JSONDecoder().decode([RawStoreOverviewRow].self, from: data) else {
                return nil
            }
            return rows.first
        }()

        async let catalogTask: StoreCatalogPageResponse = fetchStoreCatalogPageDirect(
            storeId: sid,
            query: query,
            sort: sort,
            preferredSize: preferredSize,
            limit: limit,
            offset: 0
        )

        async let reviewsTask: [StoreCustomerReview] = fetchStoreReviews(storeId: sid, limit: 20)

        let catalogPage = try await catalogTask
        let (overview, reviews) = await (overviewTask, reviewsTask)

        if overview == nil && catalogPage.products.isEmpty {
            throw URLError(.resourceUnavailable)
        }

        let storeName = overview?.store_name ?? catalogPage.products.first?.store_name ?? sid.capitalized
        let baseUrl = overview?.base_url ?? ""
        let ratingScore = overview?.rating ?? 0
        let ratingStr = ratingScore > 0 ? String(format: "%.1f", ratingScore) : ""
        let reviewCountStr = overview?.formatted_review_count ?? (overview?.review_count.map { "\($0)" } ?? "")
        let desc = overview?.description ?? "Rivenditore partner per attrezzatura e abbigliamento sportivo."
        let fullDesc = overview?.full_description ?? desc
        let refundPolicy = overview?.refund_policy
        let shippingPolicy: String? = {
            if let sp = overview?.shipping_policy, !sp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return sp
            }
            if let thresh = overview?.free_shipping_threshold, thresh > 0 {
                let std = overview?.standard_shipping_cost ?? 4.90
                return String(format: "Spedizione standard %.2f € · Gratuita da %.0f €", std, thresh)
            }
            if let std = overview?.standard_shipping_cost, std > 0 {
                return String(format: "Spedizione standard %.2f €", std)
            }
            return nil
        }()

        let totalOffers = overview?.distinct_products ?? catalogPage.totalMatching
        let avgDiscount = overview?.avg_discount ?? 0.0
        let minPrice = overview?.min_price ?? catalogPage.products.map(\.current_price).min() ?? 0.0

        let ratingBreakdown: StoreRatingBreakdown? = ratingScore > 0 ? StoreRatingBreakdown(
            score: ratingScore,
            positive_pct: ratingScore >= 4.5 ? "95%" : (ratingScore >= 4.0 ? "88%" : "75%"),
            review_count: reviewCountStr,
            platform: "Valutazione negozio"
        ) : nil

        var badges = ["Rivenditore Partner"]
        if let thresh = overview?.free_shipping_threshold, thresh > 0 {
            badges.append("Gratis da \(Int(thresh)) €")
        }
        if let c = overview?.courier, !c.isEmpty {
            badges.append(c)
        }

        return StoreDetailResponse(
            store_id: sid,
            store_name: storeName,
            base_url: baseUrl,
            rating: ratingStr,
            review_count: reviewCountStr,
            description: desc,
            full_description: fullDesc,
            badges: badges,
            highlights: nil,
            location: overview?.city_or_location,
            shipping_info: shippingPolicy,
            return_policy: refundPolicy,
            rating_breakdown: ratingBreakdown,
            total_offers: totalOffers,
            avg_discount: (avgDiscount * 10).rounded() / 10,
            min_price: minPrice,
            products: catalogPage.products,
            contact_email: overview?.contact_email,
            contact_phone: overview?.contact_phone,
            social_instagram: overview?.social_instagram,
            privacy_policy_url: overview?.privacy_policy_url,
            terms_url: overview?.terms_url,
            refund_policy: refundPolicy,
            shipping_policy: shippingPolicy,
            city_or_location: overview?.city_or_location,
            customer_reviews: reviews.isEmpty ? nil : reviews,
            customer_photos: nil,
            free_shipping_threshold: overview?.free_shipping_threshold,
            standard_shipping_cost: overview?.standard_shipping_cost,
            courier: overview?.courier,
            discounted_products: overview?.discounted_products,
            categories: overview?.categories,
            top_brands: overview?.top_brands,
            total_matching: catalogPage.totalMatching
        )
    }

    // MARK: - Direct Price History

    func fetchPriceHistoryDirect(
        canonicalName: String,
        productId: String? = nil,
        days: Int = 90
    ) async throws -> PriceHistoryResponse {
        struct ProductRow: Codable {
            let id: String
            let canonical_name: String
        }
        struct OfferRow: Codable {
            let id: String
            let store_name: String?
            let current_price: Double?
            let original_price: Double?
        }
        struct HistoryRow: Codable {
            let offer_id: String
            let price: Double
            let recorded_at: String
        }

        let headers = makeHeaders(isPublic: true)
        var resolvedProductId = productId?.trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedCanonical = canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let pid = resolvedProductId, !pid.isEmpty,
           let encPid = pid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "\(restURL)/products?id=eq.\(encPid)&select=id,canonical_name&limit=1") {
            var req = URLRequest(url: url)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            if let (data, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let rows = try? JSONDecoder().decode([ProductRow].self, from: data),
               let first = rows.first {
                resolvedProductId = first.id
                resolvedCanonical = first.canonical_name
            }
        } else if !resolvedCanonical.isEmpty {
            let cleaned = resolvedCanonical.replacingOccurrences(of: "*", with: "")
            if let enc = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "\(restURL)/products?canonical_name=ilike.*\(enc)*&select=id,canonical_name&limit=1") {
                var req = URLRequest(url: url)
                for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
                if let (data, resp) = try? await session.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let rows = try? JSONDecoder().decode([ProductRow].self, from: data),
                   let first = rows.first {
                    resolvedProductId = first.id
                    resolvedCanonical = first.canonical_name
                }
            }
        }

        var offers: [OfferRow] = []
        if let pid = resolvedProductId, !pid.isEmpty,
           let encPid = pid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "\(restURL)/store_offers?product_id=eq.\(encPid)&select=id,store_name,current_price,original_price") {
            var req = URLRequest(url: url)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            if let (data, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let rows = try? JSONDecoder().decode([OfferRow].self, from: data) {
                offers = rows
            }
        }

        if offers.isEmpty && !resolvedCanonical.isEmpty {
            let cleaned = resolvedCanonical.replacingOccurrences(of: "*", with: "")
            if let enc = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "\(restURL)/store_offers?raw_title=ilike.*\(enc)*&select=id,store_name,current_price,original_price&limit=15") {
                var req = URLRequest(url: url)
                for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
                if let (data, resp) = try? await session.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let rows = try? JSONDecoder().decode([OfferRow].self, from: data) {
                    offers = rows
                }
            }
        }

        var offerStoreMap: [String: String] = [:]
        var offerCurrentMap: [String: Double] = [:]
        var offerOrigMap: [String: Double] = [:]
        for o in offers {
            offerStoreMap[o.id] = o.store_name ?? "Store"
            if let p = o.current_price { offerCurrentMap[o.id] = p }
            if let op = o.original_price { offerOrigMap[o.id] = op }
        }

        let now = Date()
        let iso = ISO8601DateFormatter()
        let startIso = iso.string(from: now.addingTimeInterval(TimeInterval(-days * 86400)))
        var rawPoints: [PriceHistoryPoint] = []

        if !offers.isEmpty {
            let ids = offers.prefix(30).map { "\"\($0.id)\"" }.joined(separator: ",")
            if let encIn = ids.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let encStart = startIso.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "\(restURL)/price_history?offer_id=in.(\(encIn))&recorded_at=gte.\(encStart)&order=recorded_at.asc&limit=500") {
                var req = URLRequest(url: url)
                for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
                if let (data, resp) = try? await session.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let rows = try? JSONDecoder().decode([HistoryRow].self, from: data) {
                    for r in rows {
                        rawPoints.append(PriceHistoryPoint(
                            date: r.recorded_at,
                            price: r.price,
                            store_name: offerStoreMap[r.offer_id] ?? "Store",
                            offer_id: r.offer_id
                        ))
                    }
                }
            }
        }

        let nowStr = iso.string(from: now)
        for (oid, curP) in offerCurrentMap {
            rawPoints.append(PriceHistoryPoint(
                date: nowStr,
                price: curP,
                store_name: offerStoreMap[oid] ?? "Store",
                offer_id: oid
            ))
        }

        if rawPoints.count == offerCurrentMap.count, !offerCurrentMap.isEmpty,
           let maxOrig = offerOrigMap.values.max(),
           let minCur = offerCurrentMap.values.min(),
           maxOrig > minCur {
            let past30d = iso.string(from: now.addingTimeInterval(-30 * 86400))
            rawPoints.insert(PriceHistoryPoint(
                date: past30d,
                price: (maxOrig * 100).rounded() / 100,
                store_name: "Listino Ufficiale",
                offer_id: nil
            ), at: 0)
        }

        rawPoints.sort { $0.date < $1.date }

        var filteredPoints: [PriceHistoryPoint] = []
        var seenKeys = Set<String>()
        for pt in rawPoints {
            let dShort = String(pt.date.prefix(10))
            let roundedP = (pt.price * 100).rounded() / 100
            let key = "\(dShort)_\(pt.store_name)_\(roundedP)"
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                filteredPoints.append(pt)
            }
        }

        var allPrices = filteredPoints.map(\.price).filter { $0 > 0 }
        if allPrices.isEmpty && !offerCurrentMap.isEmpty {
            allPrices = Array(offerCurrentMap.values)
        }

        let currentPrice = offerCurrentMap.values.min() ?? allPrices.last ?? 0.0
        let lowestPrice = allPrices.min() ?? currentPrice
        let highestPrice = allPrices.max() ?? currentPrice
        let averagePrice = allPrices.isEmpty ? currentPrice : ((allPrices.reduce(0, +) / Double(allPrices.count)) * 100).rounded() / 100
        let isAllTimeLow = currentPrice > 0 && currentPrice <= (lowestPrice + 0.50)
        let dropPct = (averagePrice > currentPrice && averagePrice > 0)
            ? (((averagePrice - currentPrice) / averagePrice) * 1000).rounded() / 10
            : 0.0
        let dropAmt = (averagePrice > currentPrice)
            ? ((averagePrice - currentPrice) * 100).rounded() / 100
            : 0.0

        return PriceHistoryResponse(
            canonical_name: resolvedCanonical.isEmpty ? (resolvedProductId ?? "") : resolvedCanonical,
            product_id: resolvedProductId,
            current_price: (currentPrice * 100).rounded() / 100,
            lowest_price: (lowestPrice * 100).rounded() / 100,
            highest_price: (highestPrice * 100).rounded() / 100,
            average_price: averagePrice,
            is_all_time_low: isAllTimeLow,
            price_drop_percentage: dropPct,
            price_drop_amount: dropAmt,
            history_points: filteredPoints,
            total_data_points: filteredPoints.count,
            first_recorded_date: filteredPoints.first?.date,
            last_recorded_date: filteredPoints.last?.date
        )
    }

    // MARK: - Direct Chat Turn Feedback

    func updateChatMessageFeedbackDirect(sessionId: String, turnId: String, feedback: Int) async -> Bool {
        let sid = sessionId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tid = turnId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !sid.isEmpty, !tid.isEmpty,
              let sidEnc = sid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let tidEnc = tid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(restURL)/chat_messages?id=eq.\(tidEnc)&session_id=eq.\(sidEnc)"),
              let body = try? JSONSerialization.data(withJSONObject: ["user_feedback": feedback]) else {
            return false
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        guard let (_, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else {
            return false
        }
        return (200...299).contains(http.statusCode)
    }

    // MARK: - Live Catalog Autocomplete Suggestions

    func fetchCatalogSuggestions(prefix: String, limit: Int = 5) async -> [String] {
        let clean = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return [] }

        // 1. Primary: multi-token in-stock Postgres RPC ranked by store count & prefix match
        if let rpcUrl = URL(string: "\(restURL)/rpc/suggest_products_autocomplete_v1") {
            var rpcReq = URLRequest(url: rpcUrl)
            rpcReq.httpMethod = "POST"
            rpcReq.timeoutInterval = 3.5
            for (k, v) in makeHeaders(isPublic: true) { rpcReq.setValue(v, forHTTPHeaderField: k) }
            rpcReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["p_query": clean, "p_limit": limit]
            rpcReq.httpBody = try? JSONSerialization.data(withJSONObject: body)

            struct SuggestionRow: Decodable { let suggestion: String }
            if let (data, resp) = try? await session.data(for: rpcReq),
               let http = resp as? HTTPURLResponse,
               (200...299).contains(http.statusCode),
               let rows = try? JSONDecoder().decode([SuggestionRow].self, from: data) {
                return rows
                    .map { $0.suggestion.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count >= 3 }
            }
        }

        // 2. Graceful fallback if RPC is unreachable
        let safePattern = clean.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "%", with: "")
        guard !safePattern.isEmpty,
              let encoded = "*\(safePattern)*".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(restURL)/products?select=canonical_name&canonical_name=ilike.\(encoded)&category=neq.non_sport&limit=\(max(limit * 3, 12))") else {
            return []
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 4.0
        for (k, v) in makeHeaders(isPublic: true) { req.setValue(v, forHTTPHeaderField: k) }

        struct NameRow: Decodable { let canonical_name: String }
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([NameRow].self, from: data) else {
            return []
        }
        var seen = Set<String>()
        var out: [String] = []
        let lowPrefix = clean.lowercased()
        let sorted = rows.map(\.canonical_name).sorted { a, b in
            let aStarts = a.lowercased().hasPrefix(lowPrefix)
            let bStarts = b.lowercased().hasPrefix(lowPrefix)
            if aStarts != bStarts { return aStarts }
            return a.count < b.count
        }
        for name in sorted {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            if trimmed.count >= 3, !seen.contains(key) {
                seen.insert(key)
                out.append(trimmed)
                if out.count >= limit { break }
            }
        }
        return out
    }
}
