import Foundation
import UIKit
import UserNotifications
import Combine
import SwiftUI

@MainActor
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published var notifications: [AppNotification] = []
    @Published var unreadCount: Int = 0
    @Published var isAuthorized: Bool = false
    @Published var isChecking: Bool = false
    @Published var lastCheckDate: Date? = nil

    private let storageKey = "fitmatch_notifications_cache_v2"
    private let lastCheckKey = "fitmatch_last_notif_check"

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorization()
        loadNotifications()
        if let ts = UserDefaults.standard.object(forKey: lastCheckKey) as? Date {
            self.lastCheckDate = ts
        }
    }

    // MARK: - Push Authorization

    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isAuthorized = (settings.authorizationStatus == .authorized)
            }
        }
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            Task { @MainActor in
                self.isAuthorized = granted
                completion?(granted)
            }
        }
    }

    // MARK: - Notifications Cache Persistence

    private func loadNotifications() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AppNotification].self, from: data) {
            // Purge any legacy mock seed notifications or test notifications
            let realOnly = decoded.filter {
                !$0.id.hasPrefix("notif-nb-drop") &&
                !$0.id.hasPrefix("notif-nike-drop") &&
                !$0.id.hasPrefix("notif-depor-promo") &&
                !$0.title.contains("Istantaneo") &&
                !$0.title.contains("Weekend Decathlon")
            }
            self.notifications = realOnly
            self.updateUnreadCount()
            if realOnly.count != decoded.count {
                saveNotifications()
            }
        } else {
            // Start clean: zero fake seed notifications
            self.notifications = []
            self.updateUnreadCount()
        }
    }

    private func saveNotifications() {
        if let encoded = try? JSONEncoder().encode(notifications) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
        updateUnreadCount()
    }

    private func updateUnreadCount() {
        self.unreadCount = notifications.filter { !$0.isRead }.count
        // Update iOS application badge
        UNUserNotificationCenter.current().setBadgeCount(self.unreadCount) { _ in }
    }

    // MARK: - Notification Management

    func addNotification(_ notif: AppNotification, schedulePush: Bool = true) {
        // Prevent duplicate notifications for same product/store within 6 hours
        if notifications.contains(where: {
            $0.type == notif.type &&
            $0.title == notif.title &&
            abs($0.timestamp.timeIntervalSince(notif.timestamp)) < 21600
        }) {
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            notifications.insert(notif, at: 0)
        }
        saveNotifications()

        if schedulePush {
            scheduleLocalPush(for: notif)
        }
    }

    func markAsRead(id: String) {
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                notifications[idx].isRead = true
            }
            saveNotifications()
        }
    }

    func markAllAsRead() {
        withAnimation(.easeInOut(duration: 0.25)) {
            for i in 0..<notifications.count {
                notifications[i].isRead = true
            }
        }
        saveNotifications()
    }

    func deleteNotification(id: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            notifications.removeAll { $0.id == id }
        }
        saveNotifications()
    }

    func clearAll() {
        withAnimation(.easeInOut(duration: 0.25)) {
            notifications.removeAll()
        }
        saveNotifications()
    }

    // MARK: - Push Dispatch via UNUserNotificationCenter

    private func scheduleLocalPush(for notif: AppNotification) {
        let content = UNMutableNotificationContent()
        content.title = notif.title
        if let sub = notif.subtitle, !sub.isEmpty {
            content.subtitle = sub
        }
        content.body = notif.body
        content.sound = .default
        content.badge = NSNumber(value: unreadCount)

        var userInfo: [String: Any] = [
            "notification_id": notif.id,
            "type": notif.type.rawValue
        ]
        if let p = notif.productCanonicalName { userInfo["product"] = p }
        if let s = notif.storeId { userInfo["store_id"] = s }
        if let u = notif.actionUrl { userInfo["url"] = u }
        content.userInfo = userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let request = UNNotificationRequest(identifier: notif.id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Errore invio notifica locale: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Legacy / Direct Send Methods (Backward Compatibility)

    func sendPriceDropNotification(
        productTitle: String,
        oldPrice: Double,
        newPrice: Double,
        storeName: String,
        targetPrice: Double? = nil,
        url: String? = nil,
        imageUrl: String? = nil
    ) {
        let savings = oldPrice - newPrice
        let discPct = oldPrice > 0 ? ((oldPrice - newPrice) / oldPrice) * 100.0 : 0.0

        let subtitle: String
        if let target = targetPrice, newPrice <= target {
            subtitle = "\(productTitle) è sceso sotto la tua soglia!"
        } else {
            subtitle = "\(productTitle) è calato di €\(String(format: "%.2f", savings))"
        }

        let body = "Nuovo miglior prezzo: €\(String(format: "%.2f", newPrice)) su \(storeName) (era €\(String(format: "%.2f", oldPrice))). Tocca per visualizzare l'offerta."

        let notif = AppNotification(
            type: .priceDrop,
            title: "🔥 Calo Prezzo FitMatch!",
            subtitle: subtitle,
            body: body,
            timestamp: Date(),
            isRead: false,
            productCanonicalName: productTitle,
            storeName: storeName,
            imageUrl: imageUrl,
            oldPrice: oldPrice,
            newPrice: newPrice,
            discountPct: discPct > 0 ? discPct : nil,
            actionUrl: url
        )

        addNotification(notif, schedulePush: true)
    }

    func sendStoreDropNotification(
        storeId: String,
        storeName: String,
        itemsCount: Int,
        category: String = "running",
        imageUrl: String? = nil
    ) {
        let notif = AppNotification(
            type: .storeDrop,
            title: "✨ Nuovo Drop \(storeName)",
            subtitle: "\(itemsCount) nuovi articoli aggiunti",
            body: "\(storeName) ha appena aggiunto nuovi arrivi per la categoria \(category). Scopri subito i nuovi modelli.",
            timestamp: Date(),
            isRead: false,
            storeId: storeId,
            storeName: storeName,
            imageUrl: imageUrl
        )

        addNotification(notif, schedulePush: true)
    }

    // MARK: - Live Intelligent Notification Engine

    /// Automatically inspects saved products for price drops and followed stores for new drops
    func checkIntelligentNotifications(force: Bool = false) async {
        guard !isChecking else { return }

        // Respect 15-minute cooldown unless force is true
        if !force, let last = lastCheckDate, Date().timeIntervalSince(last) < 900 {
            return
        }

        isChecking = true
        defer {
            isChecking = false
            lastCheckDate = Date()
            UserDefaults.standard.set(lastCheckDate, forKey: lastCheckKey)
        }

        // 1. Intelligent Check: Saved Products (Wishlist)
        let savedItems = WishlistManager.shared.items
        for item in savedItems {
            // Priority 1: Direct Supabase store_offers lookup (fast, 100% reliable)
            if let directMatch = await SupabaseManager.shared.findBestLiveOfferDirect(canonicalName: item.canonical_name) {
                let liveBest = directMatch.price
                let oldPrice = item.currentBestPrice

                if liveBest < oldPrice {
                    let savings = oldPrice - liveBest
                    let store = directMatch.storeName

                    sendPriceDropNotification(
                        productTitle: item.canonical_name,
                        oldPrice: oldPrice,
                        newPrice: liveBest,
                        storeName: store,
                        targetPrice: item.targetAlertPrice,
                        url: directMatch.url,
                        imageUrl: directMatch.imageUrl ?? item.image_url
                    )

                    if let idx = WishlistManager.shared.items.firstIndex(where: { $0.canonical_name == item.canonical_name }) {
                        WishlistManager.shared.items[idx].currentBestPrice = liveBest
                        WishlistManager.shared.items[idx].lastPriceDrop = savings
                    }
                    continue
                }
            }

            // Priority 2: Fallback to APIService search engine
            do {
                let searchResults = try await APIService.shared.search(query: item.canonical_name, size: item.selectedSize)
                if let matched = searchResults.first, let liveBest = matched.best_price {
                    let oldPrice = item.currentBestPrice
                    if liveBest < oldPrice {
                        let savings = oldPrice - liveBest
                        let store = matched.bestOffer?.store_name ?? item.bestStore ?? "Negozio Partner"

                        // Notify user of price drop
                        sendPriceDropNotification(
                            productTitle: item.canonical_name,
                            oldPrice: oldPrice,
                            newPrice: liveBest,
                            storeName: store,
                            targetPrice: item.targetAlertPrice,
                            url: matched.bestOffer?.url ?? item.bestStoreUrl,
                            imageUrl: matched.image_url ?? item.image_url
                        )

                        // Update local item price
                        if let idx = WishlistManager.shared.items.firstIndex(where: { $0.canonical_name == item.canonical_name }) {
                            WishlistManager.shared.items[idx].currentBestPrice = liveBest
                            WishlistManager.shared.items[idx].lastPriceDrop = savings
                        }
                    }
                }
            } catch {
                // Silently skip item if network temporarily fails
            }
        }

        // 2. Intelligent Check: Followed Stores New Drops
        let followed = FollowedStoresManager.shared.followedStores
        for store in followed.prefix(4) {
            if let count = await SupabaseManager.shared.fetchStoreCatalogCountDirect(storeId: store.store_id) {
                let cacheKey = "store_catalog_count_\(store.store_id)"
                let previousCount = UserDefaults.standard.integer(forKey: cacheKey)

                if previousCount > 0 && count > previousCount {
                    let newItems = count - previousCount
                    sendStoreDropNotification(
                        storeId: store.store_id,
                        storeName: store.store_name,
                        itemsCount: newItems,
                        category: "running & outdoor",
                        imageUrl: store.store_logo
                    )
                }
                UserDefaults.standard.set(count, forKey: cacheKey)
            }
        }
    }

    // MARK: - Simulation for Demos & Testing

    func simulateTestNotification(type: NotificationType = .priceDrop) {
        let notif: AppNotification
        switch type {
        case .priceDrop:
            notif = AppNotification(
                type: .priceDrop,
                title: "🔥 Calo Prezzo Istantaneo!",
                subtitle: "Nike Air Zoom Pegasus 41",
                body: "Il prezzo è sceso da 149,99 € a 104,90 € (-30%) su Cisalfa Sport. Risparmi 45,09 €!",
                timestamp: Date(),
                isRead: false,
                productCanonicalName: "Nike Air Zoom Pegasus 41",
                storeId: "cisalfa",
                storeName: "Cisalfa Sport",
                imageUrl: "https://www.cisalfasport.it/dw/image/v2/BDLT_PRD/on/demandware.static/-/Sites-cisalfa-master/default/dw112345/FD2722-001_1.jpg",
                oldPrice: 149.99,
                newPrice: 104.90,
                discountPct: 30.0
            )
        case .storeDrop:
            notif = AppNotification(
                type: .storeDrop,
                title: "✨ Nuovo Drop Mister Running",
                subtitle: "18 nuovi modelli Asics & Saucony",
                body: "Mister Running ha appena aggiunto nuovi arrivi per la mezza maratona e sconti fino al 40%.",
                timestamp: Date(),
                isRead: false,
                storeId: "misterrunning",
                storeName: "Mister Running",
                imageUrl: nil
            )
        case .promo:
            notif = AppNotification(
                type: .promo,
                title: "🏷️ Promo Weekend Decathlon",
                subtitle: "Spedizione gratuita su ordini superiori a 40 €",
                body: "Approfitta delle promozioni esclusive per gli appassionati di corsa e fitness.",
                timestamp: Date(),
                isRead: false,
                storeId: "decathlon",
                storeName: "Decathlon"
            )
        }

        addNotification(notif, schedulePush: true)

        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }

    // MARK: - Foreground & Response Handling

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let notifId = userInfo["notification_id"] as? String {
            Task { @MainActor in
                NotificationManager.shared.markAsRead(id: notifId)
            }
        }
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            Task { @MainActor in
                UIApplication.shared.open(url)
            }
        }
        completionHandler()
    }
}
