import SwiftUI

@main
struct FitMatchApp: App {
    init() {
        // Initialize NotificationManager & register delegate
        _ = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-testWriteReview") {
                WriteReviewSheetView(storeId: "nike", storeName: "Nike", onReviewSubmitted: { _ in })
            } else if ProcessInfo.processInfo.arguments.contains("-testStoreDetail") {
                NavigationStack {
                    StoreDetailView(storeId: "misterrunning", initialStoreName: "Mister Running")
                }
            } else if ProcessInfo.processInfo.arguments.contains("-testAccount") {
                AccountView()
            } else if ProcessInfo.processInfo.arguments.contains("-testNotifications") {
                NotificationsView()
            } else if ProcessInfo.processInfo.arguments.contains("-testWishlist") {
                MainTabView(initialTab: 3)
            } else if ProcessInfo.processInfo.arguments.contains("-testSearch") {
                MainTabView(initialTab: 1)
            } else if ProcessInfo.processInfo.arguments.contains("-testAiSearchDeepDive") {
                SearchView(initialSearchQuery: "scarpe running ammortizzate per ginocchia pesanti sotto 150 euro")
            } else if ProcessInfo.processInfo.arguments.contains("-testAiSearchScrolled") {
                SearchView(initialSearchQuery: "scarpe running ammortizzate per ginocchia pesanti sotto 150 euro")
            } else if ProcessInfo.processInfo.arguments.contains("-testClassicMode") {
                SearchView(initialSearchQuery: "scarpe running ammortizzate per ginocchia pesanti sotto 150 euro")
            } else if ProcessInfo.processInfo.arguments.contains("-testAiSearchMaisonMargiela") {
                SearchView(initialSearchQuery: "Maison margiela scarpe nere")
            } else if ProcessInfo.processInfo.arguments.contains("-testSalvatiHome") {
                ZStack(alignment: .bottom) {
                    HomeView(selectedTab: .constant(0), initialSubTab: .salvati)
                    ShopFloatingIslandDock(selectedTab: .constant(0))
                        .padding(.bottom, 16)
                }
                .ignoresSafeArea(.keyboard)
            } else if ProcessInfo.processInfo.arguments.contains("-testProductDetail") {
                NavigationStack {
                    ProductDetailView(
                        product: MatchedProduct(
                            canonical_name: "Asics Novablast 5",
                            brand: "Asics",
                            image_url: "https://img.runningwarehouse.eu/watermark/rs.php?path=ANB5M4-1.jpg&nw=500",
                            gallery_images: [
                                "https://img.runningwarehouse.eu/watermark/rs.php?path=ANB5M4-1.jpg&nw=500",
                                "https://img.runningwarehouse.eu/watermark/rs.php?path=ANB5M4-2.jpg&nw=500",
                                "https://img.runningwarehouse.eu/watermark/rs.php?path=ANB5M4-3.jpg&nw=500",
                                "https://img.runningwarehouse.eu/watermark/rs.php?path=ANB5M4-4.jpg&nw=500"
                            ],
                            gender: "Uomo",
                            offers: [
                                Offer(
                                    store_id: "runningwarehouse",
                                    store_name: "Running Warehouse Europe",
                                    title: "Asics Novablast 5",
                                    brand: "Asics",
                                    price: 119.90,
                                    original_price: 150.00,
                                    discount_pct: 20.0,
                                    savings: 30.10,
                                    url: "https://www.runningwarehouse.eu/asics-novablast-5",
                                    image_url: "https://img.runningwarehouse.eu/watermark/rs.php?path=ANB5M4-1.jpg&nw=500",
                                    gallery_images: [
                                        "https://img.runningwarehouse.eu/watermark/rs.php?path=ANB5M4-1.jpg&nw=500",
                                        "https://img.runningwarehouse.eu/watermark/rs.php?path=ANB5M4-2.jpg&nw=500"
                                    ],
                                    available_sizes: ["41.5", "42", "42.5", "43", "44"],
                                    in_stock: true
                                )
                            ],
                            best_price: 119.90,
                            highest_price: 150.00,
                            cross_store_savings: 30.10
                        )
                    )
                }
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
