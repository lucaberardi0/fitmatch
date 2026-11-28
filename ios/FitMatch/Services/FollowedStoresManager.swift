import Foundation
import SwiftUI
import Combine

struct FollowedStoreItem: Identifiable, Codable, Hashable {
    var id: String { store_id.lowercased() }
    let store_id: String
    let store_name: String
    let store_logo: String?
    let created_at: String?
}

@MainActor
class FollowedStoresManager: ObservableObject {
    static let shared = FollowedStoresManager()

    @Published var followedStores: [FollowedStoreItem] = []
    @Published var hiddenStoreIds: Set<String> = []
    @Published var isLoading: Bool = false

    private let storageKey = "fitmatch_followed_stores_cache"
    private let hiddenStorageKey = "fitmatch_hidden_stores_cache"
    private var authObserver: NSObjectProtocol?

    init() {
        loadFromCache()
        loadHiddenStoresFromCache()

        authObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("FitMatchAuthSessionDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.fetchFollowedStores()
                await self.fetchHiddenStores()
            }
        }

        Task {
            await fetchFollowedStores()
            await fetchHiddenStores()
        }
    }

    deinit {
        if let authObserver {
            NotificationCenter.default.removeObserver(authObserver)
        }
    }

    // MARK: - Normalization & Local Cache

    private func deduplicated(_ items: [FollowedStoreItem]) -> [FollowedStoreItem] {
        var seen = Set<String>()
        var result: [FollowedStoreItem] = []
        for item in items {
            let cleanId = item.store_id.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanId.isEmpty, seen.insert(cleanId).inserted else { continue }
            result.append(
                FollowedStoreItem(
                    store_id: cleanId,
                    store_name: item.store_name,
                    store_logo: item.store_logo,
                    created_at: item.created_at
                )
            )
        }
        return result
    }

    private func loadHiddenStoresFromCache() {
        if let data = UserDefaults.standard.data(forKey: hiddenStorageKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.hiddenStoreIds = Set(decoded.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        }
    }

    private func saveHiddenStoresToCache() {
        if let encoded = try? JSONEncoder().encode(Array(hiddenStoreIds)) {
            UserDefaults.standard.set(encoded, forKey: hiddenStorageKey)
        }
    }

    private func loadFromCache() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([FollowedStoreItem].self, from: data) {
            self.followedStores = deduplicated(decoded)
        } else {
            self.followedStores = []
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

    func resetLocalOnly() {
        followedStores.removeAll()
        hiddenStoreIds.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: hiddenStorageKey)
    }

    func hideStore(storeId: String, storeName: String? = nil) {
        let cleanId = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        ShopHaptics.impact(.medium)
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
        ShopHaptics.impact(.light)
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
            self.hiddenStoreIds = Set(list.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
            saveHiddenStoresToCache()
        } catch {
            print("FollowedStoresManager fetchHiddenStores note: \(error)")
        }
    }

    func reportStore(storeId: String, storeName: String, reason: String = "Prezzi non aggiornati o violazione", details: String? = nil) {
        ShopHaptics.notification(.success)
        print("FitMatch Store Report recorded for \(storeName) (\(storeId)): \(reason)")

        Task {
            _ = try? await SupabaseManager.shared.reportStore(storeId: storeId, storeName: storeName, reason: reason, details: details)
        }
    }

    // MARK: - Actions

    func toggleFollow(storeId: String, storeName: String, storeLogo: String? = nil) {
        ShopHaptics.impact(.medium)

        if isFollowing(storeId: storeId) {
            _ = unfollowStore(storeId: storeId)
        } else {
            followStore(storeId: storeId, storeName: storeName, storeLogo: storeLogo)
        }
    }

    func followStore(storeId: String, storeName: String, storeLogo: String? = nil) {
        let cleanId = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty, !isFollowing(storeId: cleanId) else { return }

        let resolvedLogo = storeLogo ?? DynamicCatalogRegistry.shared.storeItem(for: cleanId)?.logo_url
        let item = FollowedStoreItem(
            store_id: cleanId,
            store_name: storeName,
            store_logo: resolvedLogo,
            created_at: ISO8601DateFormatter().string(from: Date())
        )

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            followedStores.insert(item, at: 0)
        }
        saveToCache()

        // Background Sync directly to Supabase
        Task {
            _ = try? await SupabaseManager.shared.followStore(storeId: cleanId, storeName: storeName, storeLogo: resolvedLogo)
        }
    }

    @discardableResult
    func unfollowStore(storeId: String) -> FollowedStoreItem? {
        let cleanId = storeId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let removed = followedStores.first { $0.store_id.lowercased() == cleanId }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            followedStores.removeAll { $0.store_id.lowercased() == cleanId }
        }
        saveToCache()

        // Background Sync directly to Supabase
        Task {
            _ = try? await SupabaseManager.shared.unfollowStore(storeId: cleanId)
        }
        return removed
    }

    // MARK: - Database Sync

    func fetchFollowedStores() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-testFollowing") && !self.followedStores.isEmpty {
            return
        }
        #endif
        isLoading = true
        defer { isLoading = false }

        // 1. Primary path: Supabase direct PostgREST (scoped to user_id or device_id)
        do {
            let supaList = try await SupabaseManager.shared.fetchFollowedStores()
            let cleanList = deduplicated(supaList)
            self.followedStores = cleanList
            saveToCache()
            return
        } catch {
            print("Supabase fetchFollowedStores: \(error)")
        }

        // 2. Fallback: Backend API (also scoped to user_id / device_id)
        do {
            let apiList = try await APIService.shared.getFollowedStores()
            let cleanList = deduplicated(apiList)
            self.followedStores = cleanList
            saveToCache()
        } catch {
            print("APIService fetchFollowedStores: \(error)")
        }
    }
}
