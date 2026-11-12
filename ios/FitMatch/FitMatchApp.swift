import SwiftUI
import UIKit
import UserNotifications
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {
    private let bgTaskIdentifier = "com.lucaberardi06.frontend.pricecheck"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Boost global URLCache limits for smooth network streaming
        let memLimit = 80 * 1024 * 1024
        let diskLimit = 300 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: memLimit, diskCapacity: diskLimit, diskPath: "fitmatch_network_cache")

        NotificationManager.shared.setupRemoteNotifications()
        registerBackgroundTasks()
        return true
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: bgTaskIdentifier,
            using: nil
        ) { task in
            if let refreshTask = task as? BGAppRefreshTask {
                self.handleAppRefresh(task: refreshTask)
            }
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()
        task.expirationHandler = {
            print("⚠️ [Background] Task scaduto prima del completamento")
        }

        Task { @MainActor in
            await NotificationManager.shared.checkIntelligentNotifications(force: false)
            task.setTaskCompleted(success: true)
        }
    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("⏰ [Background] Task programmato con successo tra 30 minuti")
        } catch {
            print("⚠️ [Background] Impossibile programmare task di refresh: \(error.localizedDescription)")
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📲 [APNs] Token ricevuto con successo: \(token)")
        Task { @MainActor in
            NotificationManager.shared.registerDeviceToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("ℹ️ [APNs] Registrazione push: \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("📩 [APNs] Ricevuta notifica remota in background")
        Task { @MainActor in
            await NotificationManager.shared.checkIntelligentNotifications(force: true)
            completionHandler(.newData)
        }
    }
}

@main
struct FitMatchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

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
            } else if ProcessInfo.processInfo.arguments.contains("-testAuthSheet") {
                AuthSheetView()
            } else if ProcessInfo.processInfo.arguments.contains("-testNotifications") {
                NotificationsView()
            } else if ProcessInfo.processInfo.arguments.contains("-testNotificationsFeed") {
                let _ = {
                    NotificationManager.shared.notifications = [
                        AppNotification(
                            type: .priceDrop,
                            title: "🔥 Calo Prezzo FitMatch!",
                            subtitle: "Nike Zoom Fly 6 è calato di €64.24",
                            body: "Nuovo miglior prezzo: €105.75 su Mister Running (era €169.99). Spedizione gratuita inclusa.",
                            timestamp: Date().addingTimeInterval(-300),
                            isRead: false,
                            productCanonicalName: "Nike Zoom Fly 6",
                            storeName: "Mister Running",
                            imageUrl: "https://www.misterrunning.com/images/catalog/1000/FD8313-400_1.jpg",
                            oldPrice: 169.99,
                            newPrice: 105.75,
                            discountPct: 38.0
                        ),
                        AppNotification(
                            type: .promo,
                            title: "🏷️ Offerta Dedicata Cisalfa Sport",
                            subtitle: "Extra 15% sulla categoria Running",
                            body: "Promozione speciale per gli utenti con articoli salvati nella collezione Hyrox.",
                            timestamp: Date().addingTimeInterval(-7200),
                            isRead: true,
                            storeId: "cisalfa",
                            storeName: "Cisalfa Sport"
                        )
                    ]
                }()
                NotificationsView()
            } else if ProcessInfo.processInfo.arguments.contains("-testWishlist") {
                MainTabView(initialTab: 2)
            } else if ProcessInfo.processInfo.arguments.contains("-testAgentLoading") {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 20) {
                            ShopAgentThinkingCardView(query: "Occhiali da sport sotto i 35 euro", isFollowUp: false)
                            ShopAgentThinkingCardView(query: "e per la pioggia?", isFollowUp: true)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                    .background(Color(red: 247/255, green: 247/255, blue: 250/255).ignoresSafeArea())
                    .navigationTitle("AI Agent Preview")
                    .navigationBarTitleDisplayMode(.inline)
                }
            } else if ProcessInfo.processInfo.arguments.contains("-testFollowUpCards") {
                NavigationStack {
                    ZStack {
                        Color(red: 247/255, green: 247/255, blue: 250/255).ignoresSafeArea()
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Opzioni di Approfondimento")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.shopDark)
                                .padding(.top, 16)

                            ShopFollowUpPillButton(title: "Qual è il tuo livello di allenamento?") { }
                            ShopFollowUpPillButton(title: "Stai cercando scarpe per running su strada o su sentieri?") { }
                            ShopFollowUpPillButton(title: "Scarpe con ammortizzazione massima") { }
                            ShopFollowUpPillButton(title: "Alternative sotto i 120 euro") { }
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                    }
                    .navigationTitle("Follow-up Cards")
                    .navigationBarTitleDisplayMode(.inline)
                }
            } else if ProcessInfo.processInfo.arguments.contains("-testFollowUpSheet") {
                NavigationStack {
                    ZStack {
                        Color(red: 247/255, green: 247/255, blue: 250/255).ignoresSafeArea()
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Ricerca Nike").font(.headline)
                            ShopFollowUpPillButton(title: "Qual è il tuo livello di allenamento?") { }
                            Spacer()
                        }
                        .padding(18)
                    }
                    .sheet(isPresented: .constant(true)) {
                        FollowUpQuestionSheet(
                            question: "Qual è il tuo livello di allenamento?",
                            baseQuery: "Nike",
                            onAnswerSelected: { _ in }
                        )
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                    }
                }
            } else if ProcessInfo.processInfo.arguments.contains("-testVisualSearch") {
                ShopVisualSearchSheet(onSelectModel: { _ in })
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
                MainTabView(initialTab: 2)
            } else if ProcessInfo.processInfo.arguments.contains("-testChartDirect") {
                NavigationStack {
                    ScrollView {
                        PriceHistorySectionView(
                            history: PriceHistoryResponse(
                                canonical_name: "Nike Zoom Fly 6",
                                product_id: "zoomfly6",
                                current_price: 105.75,
                                lowest_price: 105.75,
                                highest_price: 169.99,
                                average_price: 132.50,
                                is_all_time_low: true,
                                price_drop_percentage: 20.2,
                                price_drop_amount: 26.75,
                                history_points: [
                                    PriceHistoryPoint(date: "2026-10-15T10:00:00Z", price: 169.99, store_name: "Nike Official", offer_id: nil),
                                    PriceHistoryPoint(date: "2026-10-22T10:00:00Z", price: 152.00, store_name: "Top4Running", offer_id: nil),
                                    PriceHistoryPoint(date: "2026-10-29T10:00:00Z", price: 139.90, store_name: "Alltricks", offer_id: nil),
                                    PriceHistoryPoint(date: "2026-11-05T10:00:00Z", price: 119.90, store_name: "Maxi Sport", offer_id: nil),
                                    PriceHistoryPoint(date: "2026-11-12T10:00:00Z", price: 105.75, store_name: "Mister Running", offer_id: nil)
                                ],
                                total_data_points: 5,
                                first_recorded_date: "2026-10-15",
                                last_recorded_date: "2026-11-12"
                            )
                        )
                        .padding(16)
                    }
                    .background(Color(red: 247/255, green: 248/255, blue: 250/255).ignoresSafeArea())
                    .navigationTitle("Andamento Prezzi")
                }
            } else if ProcessInfo.processInfo.arguments.contains("-testZoomFly") {
                NavigationStack {
                    ProductDetailView(
                        product: MatchedProduct(
                            canonical_name: "Nike Zoom Fly 6",
                            brand: "Nike",
                            image_url: "https://www.misterrunning.com/images/catalog/1000/FD8313-400_1.jpg",
                            gallery_images: [
                                "https://www.misterrunning.com/images/catalog/1000/FD8313-400_1.jpg"
                            ],
                            gender: "Uomo",
                            offers: [
                                Offer(
                                    store_id: "misterrunning",
                                    store_name: "Mister Running",
                                    title: "Nike Zoom Fly 6 - Racer Blue/White",
                                    brand: "Nike",
                                    price: 105.75,
                                    original_price: 169.99,
                                    discount_pct: 38.0,
                                    url: "https://www.misterrunning.com",
                                    image_url: "https://www.misterrunning.com/images/catalog/1000/FD8313-400_1.jpg",
                                    available_sizes: ["40.5", "42", "42.5", "43", "44", "44.5", "45", "45.5"],
                                    variant_name: "Racer Blue/White",
                                    in_stock: true
                                ),
                                Offer(
                                    store_id: "alltricks",
                                    store_name: "Alltricks",
                                    title: "Nike Zoom Fly 6 - Glam Blu/Verde",
                                    brand: "Nike",
                                    price: 107.99,
                                    original_price: 169.99,
                                    discount_pct: 36.0,
                                    url: "https://www.alltricks.it",
                                    available_sizes: ["42", "42.5", "43", "44"],
                                    variant_name: "Glam Blu/Verde",
                                    in_stock: true
                                ),
                                Offer(
                                    store_id: "runningwarehouse",
                                    store_name: "Running Warehouse Europe",
                                    title: "Nike Zoom Fly 6 - Black/White/Smoke",
                                    brand: "Nike",
                                    price: 109.90,
                                    original_price: 170.00,
                                    discount_pct: 35.0,
                                    url: "https://www.runningwarehouse.eu",
                                    available_sizes: ["45.5"],
                                    variant_name: "Black/White/Smoke",
                                    in_stock: true
                                ),
                                Offer(
                                    store_id: "maxisport",
                                    store_name: "Maxi Sport",
                                    title: "Nike Zoom Fly 6 - Black/Grey",
                                    brand: "Nike",
                                    price: 118.95,
                                    original_price: 169.99,
                                    discount_pct: 30.0,
                                    url: "https://www.maxisport.com",
                                    available_sizes: ["40", "41", "42", "43", "44"],
                                    variant_name: "Black/Grey",
                                    in_stock: true
                                )
                            ],
                            best_price: 105.75,
                            highest_price: 170.00,
                            cross_store_savings: 64.25
                        )
                    )
                }
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
            } else if ProcessInfo.processInfo.arguments.contains("-testNikeStrap") {
                NavigationStack {
                    ProductDetailView(
                        product: MatchedProduct(
                            canonical_name: "Nike Sport Strap Fascia Porta Ipod Nano - Volt/black",
                            brand: "Nike",
                            image_url: "https://www.misterrunning.com/media/products/nike/accessori/nike_sport_strap_VOLT-600x600.jpg",
                            gallery_images: [
                                "https://www.misterrunning.com/media/products/nike/accessori/nike_sport_strap_VOLT-600x600.jpg"
                            ],
                            gender: "Unisex",
                            offers: [
                                Offer(
                                    store_id: "misterrunning",
                                    store_name: "Mister Running",
                                    title: "Nike Sport Strap Fascia Porta Ipod Nano - Volt/black",
                                    brand: "Nike",
                                    price: 6.90,
                                    original_price: 23.00,
                                    discount_pct: 70.0,
                                    savings: 16.10,
                                    url: "https://www.misterrunning.com",
                                    image_url: "https://www.misterrunning.com/media/products/nike/accessori/nike_sport_strap_VOLT-600x600.jpg",
                                    available_sizes: [],
                                    variant_name: "Volt/black",
                                    in_stock: true,
                                    shipping_cost: 0.0,
                                    is_free_shipping: true
                                )
                            ],
                            best_price: 6.90,
                            highest_price: 23.00,
                            cross_store_savings: nil
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
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                appDelegate.scheduleAppRefresh()
            }
        }
    }
}
