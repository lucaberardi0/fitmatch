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
    @Published var deviceToken: String? = nil

    private let storageKey = "fitmatch_notifications_cache_v2"
    private let lastCheckKey = "fitmatch_last_notif_check"
    private let notifiedHistoryKey = "fitmatch_notified_price_history_v2"
    private let notifiedDateKey = "fitmatch_notified_date_history_v2"
    private var notifiedPriceHistory: [String: Double] = [:]
    private var notifiedDateHistory: [String: Double] = [:]

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        self.deviceToken = UserDefaults.standard.string(forKey: "fitmatch_apns_device_token")
        if let ph = UserDefaults.standard.dictionary(forKey: notifiedHistoryKey) as? [String: Double] {
            self.notifiedPriceHistory = ph
        }
        if let dh = UserDefaults.standard.dictionary(forKey: notifiedDateKey) as? [String: Double] {
            self.notifiedDateHistory = dh
        }
        checkAuthorization()
        loadNotifications()
        if let ts = UserDefaults.standard.object(forKey: lastCheckKey) as? Date {
            self.lastCheckDate = ts
        }
    }

    // MARK: - Push Authorization & APNs

    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isAuthorized = (settings.authorizationStatus == .authorized)
                if self.isAuthorized {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func setupRemoteNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            Task { @MainActor in
                self.isAuthorized = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            Task { @MainActor in
                self.isAuthorized = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                completion?(granted)
            }
        }
    }

    func registerDeviceToken(_ token: String) {
        self.deviceToken = token
        UserDefaults.standard.set(token, forKey: "fitmatch_apns_device_token")

        #if targetEnvironment(simulator)
        let env = "sandbox"
        #else
        #if DEBUG
        let env = "sandbox"
        #else
        let env = "production"
        #endif
        #endif

        Task {
            await SupabaseManager.shared.registerDeviceTokenDirect(token: token, environment: env)
        }
    }

    // MARK: - Notifications Cache Persistence

    private func loadNotifications() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AppNotification].self, from: data) {
            // Purge any legacy mock seed notifications, store drops spam or test notifications
            let realOnly = decoded.filter {
                !$0.id.hasPrefix("notif-nb-drop") &&
                !$0.id.hasPrefix("notif-nike-drop") &&
                !$0.id.hasPrefix("notif-depor-promo") &&
                !$0.title.contains("Istantaneo") &&
                !$0.title.contains("Weekend Decathlon") &&
                $0.type != .storeDrop
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

    // MARK: - Price Drop Throttling & Deduplication

    func shouldNotifyPriceDrop(
        canonicalName: String,
        oldPrice: Double,
        newPrice: Double,
        targetPrice: Double? = nil
    ) -> Bool {
        let canonicalKey = canonicalName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 1. Must be a real reduction of at least €0.99
        guard (oldPrice - newPrice) >= 0.99 else { return false }

        // 2. Target price check: if user set a target, newPrice must meet or beat it
        if let target = targetPrice, newPrice > target {
            return false
        }

        // 3. Check previously notified price for this canonical product
        if let lastNotified = notifiedPriceHistory[canonicalKey] {
            // If we already notified at a price lower than or within €0.50 of newPrice, do not re-notify
            if newPrice >= (lastNotified - 0.50) {
                return false
            }

            // If notified recently (< 6 hours), only allow re-notification if it's a significant drop (> 10% lower than last notified)
            if let lastDateTimestamp = notifiedDateHistory[canonicalKey] {
                let elapsed = Date().timeIntervalSince1970 - lastDateTimestamp
                if elapsed < 21600 { // 6 hours
                    let dropFromLast = (lastNotified - newPrice) / lastNotified
                    if dropFromLast < 0.10 {
                        return false
                    }
                }
            }
        }

        return true
    }

    func recordNotifiedPriceDrop(canonicalName: String, price: Double) {
        let canonicalKey = canonicalName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        notifiedPriceHistory[canonicalKey] = price
        notifiedDateHistory[canonicalKey] = Date().timeIntervalSince1970
        UserDefaults.standard.set(notifiedPriceHistory, forKey: notifiedHistoryKey)
        UserDefaults.standard.set(notifiedDateHistory, forKey: notifiedDateKey)
    }

    // MARK: - Notification Management

    func addNotification(_ notif: AppNotification, schedulePush: Bool = true) {
        // Prevent duplicate notifications
        if notif.type == .priceDrop, let prodName = notif.productCanonicalName?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
            let alreadyExists = notifications.contains { existing in
                guard existing.type == .priceDrop,
                      let exProd = existing.productCanonicalName?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                      exProd == prodName else {
                    return false
                }
                // Same product: if within 6 hours and price is within 50 cents, it's a duplicate
                if let exPrice = existing.newPrice, let nPrice = notif.newPrice, abs(exPrice - nPrice) < 0.50 {
                    return true
                }
                return abs(existing.timestamp.timeIntervalSince(notif.timestamp)) < 21600
            }
            if alreadyExists {
                return
            }
        } else {
            if notifications.contains(where: {
                $0.type == notif.type &&
                $0.title == notif.title &&
                abs($0.timestamp.timeIntervalSince(notif.timestamp)) < 21600
            }) {
                return
            }
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
        Task {
            await SupabaseManager.shared.markRemoteNotificationReadDirect(id: id)
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
        Task {
            await SupabaseManager.shared.deleteRemoteNotificationDirect(id: id)
        }
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
        guard shouldNotifyPriceDrop(
            canonicalName: productTitle,
            oldPrice: oldPrice,
            newPrice: newPrice,
            targetPrice: targetPrice
        ) else {
            return
        }

        recordNotifiedPriceDrop(canonicalName: productTitle, price: newPrice)

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

    /// Inspects saved products for price drops and syncs real-time remote push notifications from Supabase
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

        // 1. Sync real-time push notifications from Supabase cloud table (generated by server-side watcher)
        let remote = await SupabaseManager.shared.fetchRemoteNotificationsDirect()
        if !remote.isEmpty {
            var existingIds = Set(self.notifications.map { $0.id })
            var added = false
            for r in remote {
                if !existingIds.contains(r.id) {
                    self.notifications.append(r)
                    existingIds.insert(r.id)
                    added = true
                    if let prod = r.productCanonicalName, let p = r.newPrice {
                        self.recordNotifiedPriceDrop(canonicalName: prod, price: p)
                    }
                }
            }
            if added {
                self.notifications.sort { $0.timestamp > $1.timestamp }
                saveNotifications()
            }
        }

        // 2. Intelligent Check: Real-time scan of user's saved wishlist items
        let savedItems = WishlistManager.shared.items
        for item in savedItems {
            // Respect user alert toggle
            guard item.isAlertEnabled else { continue }

            // Priority 1: Direct Supabase store_offers lookup (fast, 100% reliable)
            if let directMatch = await SupabaseManager.shared.findBestLiveOfferDirect(
                canonicalName: item.canonical_name,
                requiredSize: item.selectedSize
            ) {
                let liveBest = directMatch.price
                let oldPrice = item.currentBestPrice

                if liveBest < oldPrice {
                    let savings = oldPrice - liveBest
                    let store = directMatch.storeName

                    let shouldAlert = shouldNotifyPriceDrop(
                        canonicalName: item.canonical_name,
                        oldPrice: oldPrice,
                        newPrice: liveBest,
                        targetPrice: item.targetAlertPrice
                    )

                    if shouldAlert {
                        sendPriceDropNotification(
                            productTitle: item.canonical_name,
                            oldPrice: oldPrice,
                            newPrice: liveBest,
                            storeName: store,
                            targetPrice: item.targetAlertPrice,
                            url: directMatch.url,
                            imageUrl: directMatch.imageUrl ?? item.image_url
                        )
                    }

                    if let idx = WishlistManager.shared.items.firstIndex(where: { $0.canonical_name == item.canonical_name }) {
                        WishlistManager.shared.items[idx].currentBestPrice = liveBest
                        WishlistManager.shared.items[idx].lastPriceDrop = savings
                        WishlistManager.shared.saveItems()
                        let updated = WishlistManager.shared.items[idx]
                        Task {
                            _ = try? await SupabaseManager.shared.upsertWishlistItem(item: updated)
                        }
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

                        let shouldAlert = shouldNotifyPriceDrop(
                            canonicalName: item.canonical_name,
                            oldPrice: oldPrice,
                            newPrice: liveBest,
                            targetPrice: item.targetAlertPrice
                        )

                        if shouldAlert {
                            sendPriceDropNotification(
                                productTitle: item.canonical_name,
                                oldPrice: oldPrice,
                                newPrice: liveBest,
                                storeName: store,
                                targetPrice: item.targetAlertPrice,
                                url: matched.bestOffer?.url ?? item.bestStoreUrl,
                                imageUrl: matched.image_url ?? item.image_url
                            )
                        }

                        if let idx = WishlistManager.shared.items.firstIndex(where: { $0.canonical_name == item.canonical_name }) {
                            WishlistManager.shared.items[idx].currentBestPrice = liveBest
                            WishlistManager.shared.items[idx].lastPriceDrop = savings
                            WishlistManager.shared.saveItems()
                            let updated = WishlistManager.shared.items[idx]
                            Task {
                                _ = try? await SupabaseManager.shared.upsertWishlistItem(item: updated)
                            }
                        }
                    }
                }
            } catch {
                // Silently skip item if network temporarily fails
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
                type: .priceDrop,
                title: "🔥 Calo Prezzo Mister Running",
                subtitle: "Asics Novablast 5",
                body: "Il prezzo è sceso da 150,00 € a 119,90 € (-20%) su Mister Running. Disponibile nella tua taglia!",
                timestamp: Date(),
                isRead: false,
                productCanonicalName: "Asics Novablast 5",
                storeId: "misterrunning",
                storeName: "Mister Running",
                imageUrl: "https://img.runningwarehouse.eu/watermark/rs.php?path=ANB5M4-1.jpg&nw=500",
                oldPrice: 150.00,
                newPrice: 119.90,
                discountPct: 20.0
            )
        case .promo:
            notif = AppNotification(
                type: .promo,
                title: "🏷️ Promo Esclusiva Cisalfa Sport",
                subtitle: "Spedizione gratuita su ordini superiori a 40 €",
                body: "Approfitta delle offerte esclusive dedicate alla tua wishlist.",
                timestamp: Date(),
                isRead: false,
                storeId: "cisalfa",
                storeName: "Cisalfa Sport"
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
