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

        NotificationManager.shared.checkAuthorization()
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
            #if DEBUG
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
            } else if ProcessInfo.processInfo.arguments.contains("-testFollowing") {
                let _ = {
                    if FollowedStoresManager.shared.followedStores.isEmpty {
                        FollowedStoresManager.shared.followedStores = [
                            FollowedStoreItem(store_id: "misterrunning", store_name: "Mister Running", store_logo: nil, created_at: nil),
                            FollowedStoreItem(store_id: "nike", store_name: "Nike", store_logo: nil, created_at: nil),
                            FollowedStoreItem(store_id: "cisalfa", store_name: "Cisalfa Sport", store_logo: nil, created_at: nil),
                            FollowedStoreItem(store_id: "maxisport", store_name: "Maxi Sport", store_logo: nil, created_at: nil)
                        ]
                    }
                    if UserPreferencesManager.shared.preferences.preferredShoeSize.isEmpty {
                        UserPreferencesManager.shared.preferences.preferredShoeSize = "42"
                    }
                }()
                HomeView(selectedTab: .constant(0), initialSubTab: .seguiGia)
            } else if ProcessInfo.processInfo.arguments.contains("-testFollowingEmpty") {
                let _ = {
                    FollowedStoresManager.shared.followedStores = []
                }()
                HomeView(selectedTab: .constant(0), initialSubTab: .seguiGia)
            } else if ProcessInfo.processInfo.arguments.contains("-testWishlist") {
                MainTabView(initialTab: 2, skipOnboarding: true)
            } else if ProcessInfo.processInfo.arguments.contains("-testOnboarding") {
                OnboardingView()
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
                ShopVisualSearchSheet(onSelectModel: { _, _ in })
            } else if ProcessInfo.processInfo.arguments.contains("-testSearch") {
                MainTabView(initialTab: 1)
            } else if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-testSearchQuery"),
                      idx + 1 < ProcessInfo.processInfo.arguments.count {
                SearchView(initialSearchQuery: ProcessInfo.processInfo.arguments[idx + 1])
            } else if ProcessInfo.processInfo.arguments.contains("-testAiSearchDeepDive") {
                SearchView(initialSearchQuery: "scarpe running ammortizzate per ginocchia pesanti sotto 150 euro")
            } else if ProcessInfo.processInfo.arguments.contains("-testAiSearchScrolled") {
                SearchView(initialSearchQuery: "scarpe running ammortizzate per ginocchia pesanti sotto 150 euro")
            } else if ProcessInfo.processInfo.arguments.contains("-testClassicMode") {
                SearchView(initialSearchQuery: "scarpe running ammortizzate per ginocchia pesanti sotto 150 euro")
            } else if ProcessInfo.processInfo.arguments.contains("-testAiSearchMaisonMargiela") {
                SearchView(initialSearchQuery: "Maison margiela scarpe nere")
            } else if ProcessInfo.processInfo.arguments.contains("-testSalvatiHome") {
                MainTabView(initialTab: 2, skipOnboarding: true)
            } else if ProcessInfo.processInfo.arguments.contains("-testSalvatiPopulated") {
                MainTabView(initialTab: 2, skipOnboarding: true)
                    .onAppear {
                        let previewItems: [WishlistItem] = [
                            WishlistItem(
                                productId: "asics superblast 2 [shoes] [Adult]",
                                canonical_name: "Asics Superblast 2",
                                brand: "Asics",
                                category: "running_shoes",
                                image_url: "https://i1.t4s.cz/products/1013a142-401/asics-superblast-2-954461-1013a142-405.png",
                                initialPrice: 220.00,
                                savedPrice: 165.00,
                                currentBestPrice: 142.90,
                                highestPrice: 220.00,
                                discountPct: 35.0,
                                bestStoreId: "top4running",
                                bestStore: "Top4Running",
                                bestStoreUrl: "https://top4running.it/p/asics-superblast-2-1013a142-401",
                                offersCount: 14,
                                storeCount: 6,
                                selectedSize: "42.5",
                                collectionNames: ["Maratona", "Gara"],
                                targetAlertPrice: 145.0,
                                isAlertEnabled: true,
                                dateAdded: Date(),
                                isInStock: true,
                                availableSizes: ["41.5", "42", "42.5", "43.5", "44"],
                                monitoredSize: "42.5",
                                isMonitoredSizeAvailable: true,
                                histMinPrice: 142.90,
                                isAllTimeLow: true,
                                priceChangeSinceSaved: -22.10,
                                targetReached: true
                            ),
                            WishlistItem(
                                productId: "nike metcon 10 [shoes] [Adult]",
                                canonical_name: "Nike Metcon 10",
                                brand: "Nike",
                                category: "running_shoes",
                                image_url: "https://static.nike.com/a/images/t_default/u_9ddf04c7-2a9a-4d76-add1-d15af8f0263d,c_scale,fl_relative,w_1.0,h_1.0,fl_layer_apply/898ac37d-5900-4fd6-aaab-a03e7cdb0385/M+NIKE+METCON+10.png",
                                initialPrice: 139.99,
                                savedPrice: 99.99,
                                currentBestPrice: 83.99,
                                highestPrice: 139.99,
                                discountPct: 40.0,
                                bestStoreId: "nike",
                                bestStore: "Nike",
                                bestStoreUrl: "https://www.nike.com/it/t/scarpa-da-allenamento-nike-metcon-10-uomo-KVNayU12/HJ1875-500",
                                offersCount: 9,
                                storeCount: 4,
                                selectedSize: "42.5",
                                collectionNames: ["Hyrox"],
                                targetAlertPrice: 80.0,
                                isAlertEnabled: true,
                                dateAdded: Date().addingTimeInterval(-60),
                                isInStock: true,
                                availableSizes: ["40", "41", "42", "42.5", "43"],
                                monitoredSize: "42.5",
                                isMonitoredSizeAvailable: true,
                                isAllTimeLow: false,
                                priceChangeSinceSaved: -16.00,
                                targetReached: false
                            ),
                            WishlistItem(
                                productId: "hoka gaviota 6 [shoes] [Adult]",
                                canonical_name: "Hoka Gaviota 6",
                                brand: "Hoka",
                                category: "running_shoes",
                                image_url: "https://maxi.gumlet.io/media/catalog/product/cache/49229e27a07aec1fba01f3faa4d67bfd/h/o/hoka-1171932-gaviota-6-scarpe-running-uomo-052895401-vtlb_1.jpg",
                                initialPrice: 179.95,
                                savedPrice: 125.95,
                                currentBestPrice: 125.95,
                                highestPrice: 179.95,
                                discountPct: 30.0,
                                bestStoreId: "maxisport",
                                bestStore: "Maxi Sport",
                                bestStoreUrl: "https://www.maxisport.com/hoka-1171932-gaviota-6-scarpe-running-uomo-052895401-vtlb",
                                offersCount: 8,
                                storeCount: 3,
                                selectedSize: "42.5",
                                collectionNames: ["Maratona"],
                                targetAlertPrice: 110.0,
                                isAlertEnabled: true,
                                dateAdded: Date().addingTimeInterval(-120),
                                isInStock: true,
                                availableSizes: ["41", "42", "43", "44"],
                                monitoredSize: "42.5",
                                isMonitoredSizeAvailable: false,
                                isAllTimeLow: true,
                                priceChangeSinceSaved: 0.0,
                                targetReached: false
                            ),
                            WishlistItem(
                                productId: "asics metarun maglietta [top] [Donna]",
                                canonical_name: "Asics Metarun Maglietta",
                                brand: "Asics",
                                category: "top",
                                image_url: "https://www.misterrunning.com/media/products/2026-media-06/asics-metarun-maglietta-da-running-donna-cream-2012d418-100_A-600x600.jpg",
                                initialPrice: 75.00,
                                savedPrice: 41.17,
                                currentBestPrice: 41.17,
                                highestPrice: 75.00,
                                discountPct: 45.1,
                                bestStoreId: "misterrunning",
                                bestStore: "Mister Running",
                                bestStoreUrl: "https://www.misterrunning.com/it/asics-metarun-maglietta-da-running-donna-cream-2012d418-100.html",
                                offersCount: 5,
                                storeCount: 2,
                                selectedSize: "M",
                                collectionNames: ["Maratona"],
                                targetAlertPrice: nil,
                                isAlertEnabled: true,
                                dateAdded: Date().addingTimeInterval(-180),
                                isInStock: true,
                                availableSizes: ["XS", "S", "M", "L"],
                                monitoredSize: "M",
                                isMonitoredSizeAvailable: true,
                                isAllTimeLow: false,
                                priceChangeSinceSaved: 0.0,
                                targetReached: false
                            )
                        ]
                        WishlistManager.shared.items = previewItems
                        WishlistManager.shared.collections = [
                            WishlistCollection(name: "Maratona", item_count: 3),
                            WishlistCollection(name: "Hyrox", item_count: 1),
                            WishlistCollection(name: "Gara", item_count: 1)
                        ]
                    }
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
            #else
            MainTabView()
            #endif
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                appDelegate.scheduleAppRefresh()
            }
        }
    }
}
