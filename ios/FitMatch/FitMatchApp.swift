import SwiftUI

@main
struct FitMatchApp: App {
    init() {
        // Initialize NotificationManager & register delegate
        _ = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-testStoreDetail") {
                NavigationStack {
                    StoreDetailView(storeId: "misterrunning", initialStoreName: "Mister Running")
                }
            } else if ProcessInfo.processInfo.arguments.contains("-testAccount") {
                AccountView()
            } else if ProcessInfo.processInfo.arguments.contains("-testWishlist") {
                MainTabView(initialTab: 3)
            } else if ProcessInfo.processInfo.arguments.contains("-testMoveSheet") {
                MoveToCollectionSheet(
                    item: WishlistManager.shared.items.first ?? WishlistItem(
                        canonical_name: "Nike Air Zoom Pegasus 41",
                        brand: "Nike",
                        initialPrice: 149.99,
                        currentBestPrice: 112.49,
                        bestStore: "Mister Running",
                        collectionName: "Scarpe da Corsa"
                    )
                )
            } else {
                MainTabView()
            }
        }
    }
}
