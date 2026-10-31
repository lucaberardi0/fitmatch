import Foundation
import SwiftUI
import Combine

@MainActor
class UserPreferencesManager: ObservableObject {
    static let shared = UserPreferencesManager()

    private let storageKey = "fitmatch_user_preferences_v1"

    @Published var preferences: UserPreferences {
        didSet {
            save()
        }
    }

    @Published var updaterStatus: UpdaterStatusResponse?
    @Published var isRefreshingPrices: Bool = false
    @Published var refreshMessage: String?
    @Published var activeStores: [ActiveStoreItem] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            self.preferences = decoded
        } else {
            self.preferences = .default
        }
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    func toggleSport(_ sport: String) {
        if let idx = preferences.selectedSports.firstIndex(of: sport) {
            preferences.selectedSports.remove(at: idx)
        } else {
            preferences.selectedSports.append(sport)
        }
    }

    func toggleBrand(_ brand: String) {
        if let idx = preferences.favoriteBrands.firstIndex(of: brand) {
            preferences.favoriteBrands.remove(at: idx)
        } else {
            preferences.favoriteBrands.append(brand)
        }
    }

    func calculateTotalWishlistSavings(wishlistItems: [WishlistItem]) -> Double {
        var total: Double = 0.0
        for item in wishlistItems {
            if let drop = item.lastPriceDrop {
                total += drop
            }
        }
        return total
    }

    func fetchActiveStores(apiService: APIService) async {
        guard let url = URL(string: "\(apiService.baseURL)/api/stores") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(ActiveStoresResponse.self, from: data)
            self.activeStores = decoded.active_stores
        } catch {
            print("Errore caricamento store attivi: \(error)")
        }
    }

    func checkUpdaterStatus(apiService: APIService) async {
        guard let url = URL(string: "\(apiService.baseURL)/api/updater/status") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(UpdaterStatusResponse.self, from: data)
            self.updaterStatus = decoded
        } catch {
            print("Errore caricamento stato updater: \(error)")
        }
    }

    func triggerPriceRefresh(apiService: APIService) async {
        guard let url = URL(string: "\(apiService.baseURL)/api/updater/run?limit=15") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        isRefreshingPrices = true
        refreshMessage = "Sincronizzazione in corso su 9 negozi partner..."

        let haptic = UINotificationFeedbackGenerator()

        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            haptic.notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await checkUpdaterStatus(apiService: apiService)
            self.isRefreshingPrices = false
            self.refreshMessage = "Sincronizzazione avviata in background!"
        } catch {
            haptic.notificationOccurred(.error)
            self.isRefreshingPrices = false
            self.refreshMessage = "Errore durante la connessione."
        }
    }
}
