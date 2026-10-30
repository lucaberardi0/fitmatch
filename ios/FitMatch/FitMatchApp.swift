import SwiftUI

@main
struct FitMatchApp: App {
    init() {
        // Initialize NotificationManager & register delegate
        _ = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
