import Foundation
import SwiftUI
import Combine

struct FollowedStoreItem: Identifiable, Codable, Hashable {
    var id: String { store_id }
    let store_id: String
    let store_name: String
    let store_logo: String?
    let created_at: String?
}

struct StorePromoPost: Identifiable, Hashable {
    let id: String
    let storeId: String
    let storeName: String
    let title: String
    let badge: String
    let description: String
    let bgGradient: [Color]
    let expiresText: String
}

@MainActor
class FollowedStoresManager: ObservableObject {
    static let shared = FollowedStoresManager()

    @Published var followedStores: [FollowedStoreItem] = []
    @Published var hiddenStoreIds: Set<String> = []
    @Published var isLoading: Bool = false
    @Published var promoPosts: [StorePromoPost] = []

    private let storageKey = "fitmatch_followed_stores_cache"
    private let hiddenStorageKey = "fitmatch_hidden_stores_cache"

    init() {
        loadFromCache()
        loadHiddenStoresFromCache()
        setupPromoPosts()
        Task {
            await fetchFollowedStores()
            await fetchHiddenStores()
        }
    }

    // MARK: - Local Cache

    private func loadHiddenStoresFromCache() {
        if let data = UserDefaults.standard.data(forKey: hiddenStorageKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.hiddenStoreIds = Set(decoded)
        }
    }

    private func saveHiddenStoresToCache() {
        if let encoded = try? JSONEncoder().encode(Array(hiddenStoreIds)) {
            UserDefaults.standard.set(encoded, forKey: hiddenStorageKey)
        }
    }

    private func loadFromCache() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([FollowedStoreItem].self, from: data),
           !decoded.isEmpty {
            self.followedStores = decoded
            // Ensure Nike is included for first-class experience if not present
            if !self.followedStores.contains(where: { $0.store_id == "nike" }) {
                self.followedStores.insert(FollowedStoreItem(store_id: "nike", store_name: "Nike", store_logo: nil, created_at: nil), at: 0)
                saveToCache()
            }
        } else {
            // Initial starter: follow real partner stores from database
            self.followedStores = [
                FollowedStoreItem(store_id: "nike", store_name: "Nike", store_logo: nil, created_at: nil),
                FollowedStoreItem(store_id: "cisalfa", store_name: "Cisalfa Sport", store_logo: nil, created_at: nil),
                FollowedStoreItem(store_id: "misterrunning", store_name: "Mister Running", store_logo: nil, created_at: nil),
                FollowedStoreItem(store_id: "maxisport", store_name: "Maxi Sport", store_logo: nil, created_at: nil)
            ]
            saveToCache()
            Task {
                _ = try? await SupabaseManager.shared.followStore(storeId: "nike", storeName: "Nike")
                _ = try? await SupabaseManager.shared.followStore(storeId: "cisalfa", storeName: "Cisalfa Sport")
                _ = try? await SupabaseManager.shared.followStore(storeId: "misterrunning", storeName: "Mister Running")
                _ = try? await SupabaseManager.shared.followStore(storeId: "maxisport", storeName: "Maxi Sport")
            }
        }
    }

    private func saveToCache() {
        if let encoded = try? JSONEncoder().encode(followedStores) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    // MARK: - Query & Filter

    func isFollowing(storeId: String) -> Bool {
        let cleanId = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return followedStores.contains { $0.store_id.lowercased() == cleanId }
    }

    func isStoreHidden(storeId: String) -> Bool {
        let cleanId = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return hiddenStoreIds.contains(cleanId)
    }

    func hideStore(storeId: String, storeName: String? = nil) {
        let cleanId = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
        _ = withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            hiddenStoreIds.insert(cleanId)
        }
        saveHiddenStoresToCache()

        Task {
            _ = try? await SupabaseManager.shared.hideStore(storeId: cleanId, storeName: storeName)
        }
    }

    func unhideStore(storeId: String) {
        let cleanId = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        _ = withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            hiddenStoreIds.remove(cleanId)
        }
        saveHiddenStoresToCache()

        Task {
            _ = try? await SupabaseManager.shared.unhideStore(storeId: cleanId)
        }
    }

    func fetchHiddenStores() async {
        do {
            let list = try await SupabaseManager.shared.fetchHiddenStores()
            if !list.isEmpty {
                self.hiddenStoreIds = Set(list)
                saveHiddenStoresToCache()
            }
        } catch {
            print("FollowedStoresManager fetchHiddenStores note: \(error)")
        }
    }

    func reportStore(storeId: String, storeName: String, reason: String = "Prezzi non aggiornati o violazione", details: String? = nil) {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        print("FitMatch Store Report recorded for \(storeName) (\(storeId)): \(reason)")

        Task {
            _ = try? await SupabaseManager.shared.reportStore(storeId: storeId, storeName: storeName, reason: reason, details: details)
        }
    }

    // MARK: - Actions

    func toggleFollow(storeId: String, storeName: String, storeLogo: String? = nil) {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()

        if isFollowing(storeId: storeId) {
            unfollowStore(storeId: storeId)
        } else {
            followStore(storeId: storeId, storeName: storeName, storeLogo: storeLogo)
        }
    }

    func followStore(storeId: String, storeName: String, storeLogo: String? = nil) {
        let cleanId = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isFollowing(storeId: cleanId) else { return }

        let item = FollowedStoreItem(
            store_id: cleanId,
            store_name: storeName,
            store_logo: storeLogo,
            created_at: ISO8601DateFormatter().string(from: Date())
        )

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            followedStores.insert(item, at: 0)
        }
        saveToCache()

        // Background Sync to Supabase & Backend API
        Task {
            _ = try? await SupabaseManager.shared.followStore(storeId: cleanId, storeName: storeName, storeLogo: storeLogo)
            _ = try? await APIService.shared.followStore(storeId: cleanId, storeName: storeName, storeLogo: storeLogo)
        }
    }

    func unfollowStore(storeId: String) {
        let cleanId = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            followedStores.removeAll { $0.store_id.lowercased() == cleanId }
        }
        saveToCache()

        // Background Sync to Supabase & Backend API
        Task {
            _ = try? await SupabaseManager.shared.unfollowStore(storeId: cleanId)
            _ = try? await APIService.shared.unfollowStore(storeId: cleanId)
        }
    }

    // MARK: - Database Sync

    func fetchFollowedStores() async {
        isLoading = true
        defer { isLoading = false }

        // 1. Try Supabase direct PostgREST
        do {
            let supaList = try await SupabaseManager.shared.fetchFollowedStores()
            if !supaList.isEmpty {
                self.followedStores = supaList
                saveToCache()
                return
            }
        } catch {
            print("Supabase fetchFollowedStores: \(error)")
        }

        // 2. Try Backend API
        do {
            let apiList = try await APIService.shared.getFollowedStores()
            if !apiList.isEmpty {
                self.followedStores = apiList
                saveToCache()
            }
        } catch {
            print("APIService fetchFollowedStores: \(error)")
        }
    }

    private func setupPromoPosts() {
        self.promoPosts = [
            StorePromoPost(
                id: "promo_1",
                storeId: "cisalfa",
                storeName: "Cisalfa Sport",
                title: "MID SEASON SALE",
                badge: "25% OFF SITEWIDE",
                description: "Usa il codice FINAL25 su tutta la selezione running & outdoor.",
                bgGradient: [Color(red: 24/255, green: 24/255, blue: 27/255), Color(red: 45/255, green: 25/255, blue: 60/255)],
                expiresText: "Scade tra 48h"
            ),
            StorePromoPost(
                id: "promo_2",
                storeId: "misterrunning",
                storeName: "Mister Running",
                title: "FLASH DROP CORSA",
                badge: "EXTRA -20%",
                description: "Nuovi arrivi Nike Alphafly 3 & Asics Nimbus 26 a prezzo shock.",
                bgGradient: [Color(red: 30/255, green: 40/255, blue: 55/255), Color(red: 20/255, green: 25/255, blue: 35/255)],
                expiresText: "Solo per oggi"
            ),
            StorePromoPost(
                id: "promo_3",
                storeId: "maxisport",
                storeName: "Maxi Sport",
                title: "SNEAKER MANIA",
                badge: "FINO A -50%",
                description: "Centinaia di sneaker lifestyle Jordan, Samba e New Balance scontate.",
                bgGradient: [Color(red: 40/255, green: 30/255, blue: 20/255), Color(red: 18/255, green: 18/255, blue: 20/255)],
                expiresText: "Fino a esaurimento"
            ),
            StorePromoPost(
                id: "promo_4",
                storeId: "top4running",
                storeName: "Top4Running",
                title: "PREZZI GARA",
                badge: "EXTRA 15€",
                description: "Risparmia 15€ extra su ordini da 100€ con coupon RUN2026.",
                bgGradient: [Color(red: 20/255, green: 40/255, blue: 35/255), Color(red: 15/255, green: 20/255, blue: 25/255)],
                expiresText: "Weekend Special"
            )
        ]
    }
}
