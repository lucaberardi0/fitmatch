import SwiftUI

enum HomeSubTab: Int, CaseIterable {
    case perTe = 0
    case offerte = 1
    case seguiGia = 2
    case salvati = 3

    var title: String {
        switch self {
        case .perTe: return "Per te"
        case .offerte: return "Offerte"
        case .seguiGia: return "Segui già"
        case .salvati: return "Salvati"
        }
    }
}

struct HomeView: View {
    @Binding var selectedTab: Int
    var initialSubTab: HomeSubTab = .perTe
    @State private var activeSubTab: HomeSubTab

    init(selectedTab: Binding<Int>, initialSubTab: HomeSubTab = .perTe) {
        self._selectedTab = selectedTab
        self.initialSubTab = initialSubTab
        self._activeSubTab = State(initialValue: initialSubTab)
    }

    @StateObject private var api = APIService.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var recentManager = RecentActivityManager.shared

    @State private var showcases: [StoreShowcase] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var showingAccountSheet = false
    @State private var showingNotificationsAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - 1. Pinned Top Header: Avatar "L" | Search Bar "Cerca" | Bell
                topHeaderBar
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                // MARK: - 2. Sub-Navigation Pills: Per te | Offerte | Segui già | Salvati
                subNavigationPills
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // MARK: - 3. Content Area based on Active Sub-Tab
                Group {
                    switch activeSubTab {
                    case .perTe:
                        perTeContent
                    case .offerte:
                        DealsView(embedded: true, onSelectPerTe: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                activeSubTab = .perTe
                            }
                        })
                    case .seguiGia:
                        FollowingView(onGoShopping: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                activeSubTab = .perTe
                            }
                        })
                    case .salvati:
                        WishlistView(selectedTab: $selectedTab, embedded: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(red: 245/255, green: 246/255, blue: 248/255).ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAccountSheet) {
                AccountView()
            }
            .alert("Notifiche Attive", isPresented: $showingNotificationsAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Riceverai avvisi e notifiche push appena i prezzi dei tuoi articoli e brand seguiti scendono.")
            }
            .task {
                if showcases.isEmpty {
                    await fetchShowcases()
                }
            }
        }
    }

    // MARK: - Top Header Bar (Screenshot 1: Avatar "L" | Search "Cerca" | Bell)

    private var topHeaderBar: some View {
        HStack(spacing: 12) {
            // User Avatar (Purple circle with 'L')
            Button(action: { showingAccountSheet = true }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 196/255, green: 181/255, blue: 253/255))
                        .frame(width: 42, height: 42)

                    Text("L")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)

            // Search Bar Capsule ("Cerca")
            NavigationLink(destination: SearchView()) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(red: 135/255, green: 135/255, blue: 145/255))

                    Text("Cerca")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(Color(red: 135/255, green: 135/255, blue: 145/255))

                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white)
                .cornerRadius(22)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Bell Notifications Button
            Button(action: { showingNotificationsAlert = true }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 42, height: 42)
                        .overlay(
                            Circle()
                                .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
                        )

                    Image(systemName: "bell.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sub-Navigation Pills (Screenshot 1: Per te | Offerte | Segui già | Salvati)

    private var subNavigationPills: some View {
        HStack(spacing: 6) {
            ForEach(HomeSubTab.allCases, id: \.self) { tab in
                Button(action: {
                    let gen = UIImpactFeedbackGenerator(style: .light)
                    gen.impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        activeSubTab = tab
                    }
                }) {
                    Text(tab.title)
                        .font(.system(size: 14, weight: activeSubTab == tab ? .bold : .medium, design: .rounded))
                        .foregroundColor(activeSubTab == tab ? Color(red: 20/255, green: 20/255, blue: 25/255) : Color(red: 90/255, green: 90/255, blue: 100/255))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(activeSubTab == tab ? Color.white : Color.clear)
                                .shadow(color: activeSubTab == tab ? Color.black.opacity(0.04) : Color.clear, radius: 4, x: 0, y: 1)
                        )
                        .overlay(
                            activeSubTab == tab ?
                                Capsule()
                                    .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
                                : nil
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if tab != .salvati {
                    Spacer()
                }
            }
        }
    }

    // MARK: - "Per te" Feed Content (100% Real Database Stores & Products)

    private var perTeContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // 1. "Elementi salvati" Preview Card (Real saved items or real top database picks)
                savedItemsPreviewCard
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                // 2. "Visti di recente" Preview Card
                recentlyViewedPreviewCard
                    .padding(.horizontal, 16)

                // 3. Real Database Partner Stores from Supabase & API
                if isLoading && showcases.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.shopDark)
                        Text("Caricamento negozi e offerte dal database...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(Array(showcases.enumerated()), id: \.element.id) { index, sc in
                        if index == 1 {
                            // Deep Slate Accent Card for visual cadence (using real store & products)
                            darkAccentShopStoreCard(showcase: sc)
                                .padding(.horizontal, 16)
                        } else {
                            // Clean White Shop Card (using real store & products)
                            genericShopStoreCard(showcase: sc)
                                .padding(.horizontal, 16)
                        }
                    }
                }

                Spacer(minLength: 120)
            }
        }
        .refreshable {
            await fetchShowcases()
        }
    }

    // MARK: - 1. "Elementi salvati" Section (Driven by Real Database)

    private var previewSavedItems: [StoreShowcaseProduct] {
        if !wishlist.items.isEmpty {
            return wishlist.items.prefix(3).map { item in
                StoreShowcaseProduct(
                    id: item.id,
                    title: item.canonical_name,
                    brand: item.brand,
                    image_url: item.image_url,
                    current_price: item.currentBestPrice,
                    original_price: item.initialPrice,
                    discount_pct: item.discountPct,
                    product_url: item.bestStoreUrl ?? "https://fitmatch.it",
                    canonical_name: item.canonical_name,
                    product_id: nil,
                    shipping_cost: 0.0,
                    total_price: item.currentBestPrice,
                    is_free_shipping: true,
                    shipping_label: "Sped. Gratis",
                    free_shipping_threshold: 50.0,
                    courier: nil
                )
            }
        }
        var list: [StoreShowcaseProduct] = []
        for sc in showcases {
            if let first = sc.products.first {
                list.append(first)
                if list.count == 3 { break }
            }
        }
        return list
    }

    private var savedItemsPreviewCard: some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                activeSubTab = .salvati
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                // Header: "Elementi salvati" + Chevron Button
                HStack {
                    Text("Elementi salvati")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Spacer()

                    Circle()
                        .fill(Color(red: 242/255, green: 243/255, blue: 246/255))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(red: 70/255, green: 70/255, blue: 75/255))
                        )
                }

                // Row of 3 Real Products (Thumbnails from Database)
                HStack(spacing: 12) {
                    let items = previewSavedItems
                    ForEach(0..<3, id: \.self) { idx in
                        let prod = items.count > idx ? items[idx] : nil
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 244/255, green: 245/255, blue: 248/255))
                                .aspectRatio(1.0, contentMode: .fit)

                            if let p = prod, let imgUrl = p.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img
                                            .resizable()
                                            .scaledToFit()
                                            .padding(10)
                                    } else {
                                        Image(systemName: "tag.fill")
                                            .font(.system(size: 26))
                                            .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                                    }
                                }
                            } else {
                                Image(systemName: "bag.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                            }
                        }
                    }
                }
            }
            .padding(18)
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.02), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. "Visti di recente" Section (Real User History & Database Recommendations)

    private var previewRecentProducts: [MatchedProduct] {
        // 1. User viewed products from RecentActivityManager
        let productActivities = recentManager.activities.compactMap { act -> MatchedProduct? in
            guard act.type == .product else { return nil }
            return act.productData
        }

        if !productActivities.isEmpty {
            var seen = Set<String>()
            var unique: [MatchedProduct] = []
            for p in productActivities {
                let key = p.canonical_name.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    unique.append(enrichMatchedProduct(p))
                }
            }
            if !unique.isEmpty {
                return Array(unique.prefix(3))
            }
        }

        // 2. Fallback: Show real products from showcases if no items viewed yet
        var fallback: [MatchedProduct] = []
        for sc in showcases {
            if sc.products.count > 1 {
                let p = sc.products[1]
                fallback.append(p.toMatchedProduct(storeId: sc.store_id, storeName: sc.store_name))
                if fallback.count == 3 { break }
            }
        }
        return fallback
    }

    private func enrichMatchedProduct(_ prod: MatchedProduct) -> MatchedProduct {
        if !prod.offers.isEmpty { return prod }
        for sc in showcases {
            if let found = sc.products.first(where: {
                $0.canonical_name.caseInsensitiveCompare(prod.canonical_name) == .orderedSame || $0.id == prod.id
            }) {
                return found.toMatchedProduct(storeId: sc.store_id, storeName: sc.store_name)
            }
        }
        return prod
    }

    private var recentlyViewedPreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: "Visti di recente" + Chevron Button
            HStack {
                HStack(spacing: 8) {
                    Text("Visti di recente")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    let productCount = recentManager.activities.filter { $0.type == .product }.count
                    if productCount > 0 {
                        Text("\(productCount)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.shopTextMuted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(red: 242/255, green: 243/255, blue: 246/255))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                NavigationLink(destination: RecentlyViewedView()) {
                    Circle()
                        .fill(Color(red: 242/255, green: 243/255, blue: 246/255))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(red: 70/255, green: 70/255, blue: 75/255))
                        )
                }
                .buttonStyle(.plain)
            }

            // Row of 3 Products (Thumbnails with subtle price tag & NavigationLink to ProductDetailView)
            HStack(spacing: 12) {
                let items = previewRecentProducts
                ForEach(0..<3, id: \.self) { idx in
                    if idx < items.count {
                        let prod = enrichMatchedProduct(items[idx])
                        NavigationLink(destination: ProductDetailView(product: prod)) {
                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color(red: 244/255, green: 245/255, blue: 248/255))
                                    .aspectRatio(1.0, contentMode: .fit)

                                if let imgUrl = prod.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                                    AsyncImage(url: url) { phase in
                                        if let img = phase.image {
                                            img
                                                .resizable()
                                                .scaledToFit()
                                                .padding(10)
                                        } else {
                                            Image(systemName: "photo")
                                                .font(.system(size: 26))
                                                .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                                        }
                                    }
                                } else {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 26))
                                        .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                }

                                if let price = prod.best_price ?? prod.bestOffer?.price {
                                    Text(String(format: "%.2f €", price).replacingOccurrences(of: ".", with: ","))
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.white.opacity(0.92))
                                        .clipShape(Capsule())
                                        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                                        .padding(6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 244/255, green: 245/255, blue: 248/255))
                                .aspectRatio(1.0, contentMode: .fit)

                            Image(systemName: "clock")
                                .font(.system(size: 24))
                                .foregroundColor(Color(red: 215/255, green: 215/255, blue: 220/255))
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.02), radius: 8, x: 0, y: 2)
    }

    // MARK: - Dark Slate Accent Card (Screenshot 1 Visual Cadence with Real Products)

    private func darkAccentShopStoreCard(showcase: StoreShowcase) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 12) {
                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(showcase.store_name)
                                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("★ \(showcase.rating) (\(showcase.total_offers) offerte reali)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    Button(action: {
                        followedManager.toggleFollow(storeId: showcase.store_id, storeName: showcase.store_name)
                    }) {
                        Label(
                            followedManager.isFollowing(storeId: showcase.store_id) ? "Non seguire più" : "Segui negozio",
                            systemImage: followedManager.isFollowing(storeId: showcase.store_id) ? "person.badge.minus" : "person.badge.plus"
                        )
                    }

                    NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                        Label("Visualizza negozio", systemImage: "arrow.right.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            // Horizontal Carousel of Real Product Cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(showcase.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                        ShopHomeProductCard(
                            product: prod,
                            matchedProduct: matched,
                            isDarkTheme: true
                        )
                    }
                }
                .padding(.horizontal, 18)
            }

            // Bottom Row: "Acquista tutto" + Arrow Button
            HStack {
                Text("Acquista tutto")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 28/255, green: 28/255, blue: 34/255), Color(red: 18/255, green: 18/255, blue: 22/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(26)
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    // MARK: - Reusable Clean Shop Store Card Component with Real Database Showcase

    private func genericShopStoreCard(showcase: StoreShowcase) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Avatar + Store Name + Rating + Three Dots
            HStack(spacing: 12) {
                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(showcase.store_name)
                                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            Text("★ \(showcase.rating) (\(showcase.total_offers) offerte reali)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    Button(action: {
                        followedManager.toggleFollow(storeId: showcase.store_id, storeName: showcase.store_name)
                    }) {
                        Label(
                            followedManager.isFollowing(storeId: showcase.store_id) ? "Non seguire più" : "Segui negozio",
                            systemImage: followedManager.isFollowing(storeId: showcase.store_id) ? "person.badge.minus" : "person.badge.plus"
                        )
                    }

                    NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                        Label("Visualizza negozio", systemImage: "arrow.right.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.shopTextMuted)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            // Horizontal Carousel of Real Product Cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(showcase.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                        ShopHomeProductCard(
                            product: prod,
                            matchedProduct: matched,
                            isDarkTheme: false
                        )
                    }
                }
                .padding(.horizontal, 18)
            }

            // Bottom Row: "Acquista tutto" + Circular Arrow Button
            HStack {
                Text("Acquista tutto")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)

                Spacer()

                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    Circle()
                        .fill(Color(red: 240/255, green: 241/255, blue: 244/255))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.shopDark)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .background(Color.white)
        .cornerRadius(26)
        .shadow(color: Color.black.opacity(0.02), radius: 8, x: 0, y: 2)
    }

    private func fetchShowcases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let sc = try await api.getStoreShowcases()
            await MainActor.run {
                self.showcases = sc
            }
        } catch {
            print("HomeView fetchShowcases error: \(error)")
        }
    }
}

// MARK: - Screenshot 1 Product Card (with Translucent Price Tag & Heart Button)

struct ShopHomeProductCard: View {
    let product: StoreShowcaseProduct
    let matchedProduct: MatchedProduct
    var isDarkTheme: Bool = false

    @ObservedObject private var wishlist = WishlistManager.shared

    var body: some View {
        NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            ZStack(alignment: .topLeading) {
                // Card Background
                RoundedRectangle(cornerRadius: 20)
                    .fill(isDarkTheme ? Color.white.opacity(0.12) : Color(red: 244/255, green: 245/255, blue: 248/255))
                    .frame(width: 152, height: 168)

                // Product Image Centered
                VStack {
                    Spacer()
                    if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img
                                    .resizable()
                                    .scaledToFit()
                                    .padding(12)
                                    .frame(width: 136, height: 120)
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                                    .frame(width: 136, height: 120)
                            }
                        }
                    } else {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 26))
                            .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                            .frame(width: 136, height: 120)
                    }
                    Spacer()
                }
                .frame(width: 152, height: 168)

                // Top-Left Translucent Price Tag Pill (Screenshot 1: "411,95 € 457,95 €")
                HStack(spacing: 4) {
                    Text(String(format: "%.2f €", product.current_price).replacingOccurrences(of: ".", with: ","))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let orig = product.original_price, orig > product.current_price {
                        Text(String(format: "%.2f €", orig).replacingOccurrences(of: ".", with: ","))
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                            .strikethrough()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.48))
                .clipShape(Capsule())
                .padding([.top, .leading], 10)

                // Bottom-Right Translucent Heart Button (Screenshot 1)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .medium)
                            gen.impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                wishlist.toggleFavorite(product: matchedProduct)
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.32))
                                    .frame(width: 32, height: 32)

                                Image(systemName: wishlist.isFavorite(matchedProduct.canonical_name) ? "heart.fill" : "heart")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(wishlist.isFavorite(matchedProduct.canonical_name) ? .red : .white)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding([.bottom, .trailing], 10)
                    }
                }
                .frame(width: 152, height: 168)
            }
        }
        .buttonStyle(.plain)
    }
}
