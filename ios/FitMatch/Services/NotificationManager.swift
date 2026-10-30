import Foundation
import UIKit
import UserNotifications
import Combine

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published var isAuthorized: Bool = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorization()
    }

    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = (settings.authorizationStatus == .authorized)
            }
        }
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
                completion?(granted)
            }
        }
    }

    func sendPriceDropNotification(
        productTitle: String,
        oldPrice: Double,
        newPrice: Double,
        storeName: String,
        targetPrice: Double? = nil,
        url: String? = nil
    ) {
        let content = UNMutableNotificationContent()
        let savings = oldPrice - newPrice
        
        content.title = "🔥 Calo Prezzo FitMatch!"
        if let target = targetPrice, newPrice <= target {
            content.subtitle = "\(productTitle) è sceso sotto la tua soglia!"
        } else {
            content.subtitle = "\(productTitle) è calato di €\(String(format: "%.2f", savings))"
        }
        
        content.body = "Nuovo miglior prezzo: €\(String(format: "%.2f", newPrice)) su \(storeName) (era €\(String(format: "%.2f", oldPrice))). Tocca per visualizzare l'offerta."
        content.sound = .default
        content.badge = 1
        
        var userInfo: [String: Any] = [
            "product_title": productTitle,
            "new_price": newPrice,
            "store_name": storeName
        ]
        if let url = url {
            userInfo["url"] = url
        }
        content.userInfo = userInfo

        // Trigger in 1 second
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Errore aggiunta notifica: \(error.localizedDescription)")
            } else {
                print("Notifica calo prezzo programmata per \(productTitle)")
            }
        }
    }

    // Displays notification banners even when the app is running in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
        completionHandler()
    }
}
