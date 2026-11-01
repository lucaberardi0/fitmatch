import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: Int
    @StateObject private var api = APIService.shared
    @State private var showcases: [StoreShowcase] = []
    @State private var isLoading = false
    @State private var showingNotificationsAlert = false
    @State private var showingFollowedStoresSheet = false
    @State private var showingAccountSheet = false

    // Real database products for "Riprendi da dove hai lasciato" (takes top offer from each real store showcase)
    private var recentProducts: [(product: StoreShowcaseProduct, storeId: String, storeName: String)] {
        var items: [(product: StoreShowcaseProduct, storeId: String, storeName: String)] = []
        for sc in showcases {
            if let first = sc.products.first {
                items.append((product: first, storeId: sc.store_id, storeName: sc.store_name))
            }
        }
        return items
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - 1. Pinned Top Quick Action Bar (Profile, Bell, Offerte, Segui già, Salvati)
                topActionBar
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .background(Color(red: 245/255, green: 246/255, blue: 248/255))

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // MARK: - 2. Novità! Promo Banner
                        NavigationLink(destination: DealsView()) {
                            HStack(spacing: 14) {
                                // Blue Scalloped Starburst "S" Badge
                                ZStack {
                                    Image(systemName: "seal.fill")
                                        .font(.system(size: 38))
                                        .foregroundColor(Color(red: 24/255, green: 119/255, blue: 242/255))

                                    Text("S")
                                        .font(.system(size: 18, weight: .black, design: .rounded))
                                        .foregroundColor(.white)

                                    Image(systemName: "sparkle")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                        .offset(x: 10, y: -9)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Novità!")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopDark)

                                    Text("Ottieni offerte esclusive create apposta per te.")
                                        .font(.system(size: 12.5))
                                        .foregroundColor(.shopTextMuted)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.shopTextMuted.opacity(0.8))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .cornerRadius(22)
                            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)

                        // MARK: - 2.5 Coach IA Biomeccanico Card
                        NavigationLink(destination: AIAdvisorView()) {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [Color.shopPurple, Color.shopDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 44, height: 44)

                                    Image(systemName: "sparkles")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.white)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("Coach IA Biomeccanico")
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundColor(.shopDark)

                                        Text("NUOVO")
                                            .font(.system(size: 9, weight: .heavy))
                                            .foregroundColor(.shopPurple)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.shopPurpleLight)
                                            .cornerRadius(6)
                                    }

                                    Text("Consigli su peso, appoggio e confronto modelli con IA.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.shopTextMuted)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.shopTextMuted.opacity(0.8))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .cornerRadius(22)
                            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)

                        // MARK: - 3. Big Card: "Riprendi da dove hai lasciato" (Matte Black)
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Riprendi da dove hai lasciato")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(Color(red: 170/255, green: 170/255, blue: 175/255))
                                .padding(.horizontal, 18)
                                .padding(.top, 16)

                            // Horizontal Carousel of Real Product Cards from Database
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    if recentProducts.isEmpty {
                                        if isLoading {
                                            ForEach(0..<4, id: \.self) { _ in
                                                RoundedRectangle(cornerRadius: 20)
                                                    .fill(Color(white: 0.16))
                                                    .frame(width: 146, height: 160)
                                                    .overlay(
                                                        ProgressView()
                                                            .tint(.white)
                                                    )
                                            }
                                        } else {
                                            Button(action: { fetchShowcases() }) {
                                                VStack(spacing: 8) {
                                                    Image(systemName: "arrow.clockwise")
                                                        .font(.system(size: 20, weight: .bold))
                                                    Text("Tocca per caricare")
                                                        .font(.system(size: 11, weight: .medium))
                                                }
                                                .foregroundColor(.white.opacity(0.8))
                                                .frame(width: 146, height: 160)
                                                .background(Color(white: 0.16))
                                                .cornerRadius(20)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    } else {
                                        ForEach(recentProducts, id: \.product.id) { item in
                                            let matched = item.product.toMatchedProduct(
                                                storeId: item.storeId,
                                                storeName: item.storeName
                                            )

                                            ShopCarouselProductCard(
                                                title: item.product.canonical_name,
                                                brand: item.product.brand,
                                                price: item.product.current_price,
                                                originalPrice: item.product.original_price,
                                                imageUrl: item.product.image_url,
                                                matchedProduct: matched,
                                                isWhiteCardTheme: false
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal, 18)
                            }

                            // Bottom Row: "Visti di recente" + Arrow Button
                            HStack {
                                Text("Visti di recente")
                                    .font(.system(size: 23, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)

                                Spacer()

                                NavigationLink(destination: SearchView()) {
                                    Circle()
                                        .fill(Color(red: 48/255, green: 48/255, blue: 50/255))
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
                            .padding(.bottom, 18)
                        }
                        .background(Color(red: 24/255, green: 24/255, blue: 26/255)) // Matte Black Card
                        .cornerRadius(26)
                        .padding(.horizontal, 16)

                        // MARK: - 4. Dynamic Real Database Stores (All 8 verified stores)
                        if isLoading && showcases.isEmpty {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .tint(.shopDark)
                                Text("Caricamento negozi dal database...")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.shopTextMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(Array(showcases.enumerated()), id: \.element.id) { index, sc in
                                if index == 1 {
                                    // Deep Slate / Violet Gradient Card for visual cadence (like in Shop)
                                    ShopAccentStoreCard(showcase: sc)
                                        .padding(.horizontal, 16)
                                } else {
                                    // Clean White Shop Card
                                    ShopWhiteStoreCard(showcase: sc)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }

                        Spacer(minLength: 110)
                    }
                }
            }
            .background(Color(red: 245/255, green: 246/255, blue: 248/255).ignoresSafeArea())
            .navigationBarHidden(true)
            .refreshable {
                fetchShowcases()
            }
            .onAppear {
                if showcases.isEmpty {
                    fetchShowcases()
                }
            }
            .alert("Notifiche Attive", isPresented: $showingNotificationsAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Riceverai avvisi non appena i prezzi dei tuoi articoli preferiti scenderanno.")
            }
            .sheet(isPresented: $showingFollowedStoresSheet) {
                FollowedStoresSheet()
            }
            .sheet(isPresented: $showingAccountSheet) {
                AccountView()
            }
        }
    }

    private var topActionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Profile Button
                Button(action: { showingAccountSheet = true }) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.shopDark)
                        .frame(width: 42, height: 42)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
                }
                .buttonStyle(.plain)

                // Notifications Button
                Button(action: { showingNotificationsAlert = true }) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.shopDark)
                        .frame(width: 42, height: 42)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
                }
                .buttonStyle(.plain)

                // Offerte Pill
                Button(action: {
                    withAnimation { selectedTab = 3 }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 12))
                        Text("Offerte")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.shopDark)
                    .padding(.horizontal, 15)
                    .frame(height: 42)
                    .background(Color.white)
                    .cornerRadius(21)
                    .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
                }
                .buttonStyle(.plain)

                // Segui già (Negozi partner) Pill
                Button(action: { showingFollowedStoresSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                        Text("Segui già")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.shopDark)
                    .padding(.horizontal, 15)
                    .frame(height: 42)
                    .background(Color.white)
                    .cornerRadius(21)
                    .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
                }
                .buttonStyle(.plain)

                // Salvati Pill
                Button(action: {
                    withAnimation { selectedTab = 2 }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12))
                        Text("Salvati")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.shopDark)
                    .padding(.horizontal, 15)
                    .frame(height: 42)
                    .background(Color.white)
                    .cornerRadius(21)
                    .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
    }

    private func fetchShowcases(retries: Int = 2) {
        isLoading = true
        Task {
            do {
                let sc = try await api.getStoreShowcases()
                await MainActor.run {
                    self.showcases = sc
                    self.isLoading = false
                }
            } catch {
                if retries > 0 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    fetchShowcases(retries: retries - 1)
                } else {
                    await MainActor.run {
                        self.isLoading = false
                    }
                }
            }
        }
    }
}

// MARK: - Shop White Store Card (Driven 100% by Real Store Showcase from Database)

struct ShopWhiteStoreCard: View {
    let showcase: StoreShowcase

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Store Logo + Store Name + Rating + Ellipsis
            HStack(spacing: 12) {
                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 46)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(showcase.store_name)
                                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            Text("★ \(showcase.rating) (\(showcase.total_offers) offerte)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.shopTextMuted)
                        .padding(.trailing, 2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            // Horizontal Carousel of Product Cards with Light-Gray Container
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(showcase.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                        ShopCarouselProductCard(
                            title: prod.canonical_name,
                            brand: prod.brand,
                            price: prod.current_price,
                            originalPrice: prod.original_price,
                            imageUrl: prod.image_url,
                            matchedProduct: matched,
                            isWhiteCardTheme: true
                        )
                    }
                }
                .padding(.horizontal, 18)
            }

            // Bottom Row: "Acquista tutto" + Light Gray Arrow Button
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
            .padding(.bottom, 18)
        }
        .background(Color.white)
        .cornerRadius(26)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Shop Accent Store Card (Deep Slate / Violet Gradient Card for visual cadence)

struct ShopAccentStoreCard: View {
    let showcase: StoreShowcase

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Store Logo + Store Name + Rating + Ellipsis
            HStack(spacing: 12) {
                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 46)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(showcase.store_name)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("★ \(showcase.rating) (\(showcase.total_offers) offerte)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.8))
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.8))
                        .padding(.trailing, 2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            // Horizontal Carousel of Real Product Cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(showcase.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                        ShopCarouselProductCard(
                            title: prod.canonical_name,
                            brand: prod.brand,
                            price: prod.current_price,
                            originalPrice: prod.original_price,
                            imageUrl: prod.image_url,
                            matchedProduct: matched,
                            isWhiteCardTheme: false
                        )
                    }
                }
                .padding(.horizontal, 18)
            }

            // Bottom Row: "Acquista <StoreName>" + Arrow Button
            HStack {
                Text("Acquista \(showcase.store_name)")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    Circle()
                        .fill(Color.white.opacity(0.22))
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
            .padding(.bottom, 18)
        }
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color(red: 45/255, green: 54/255, blue: 90/255), location: 0.0),
                    .init(color: Color(red: 82/255, green: 68/255, blue: 110/255), location: 0.5),
                    .init(color: Color(red: 48/255, green: 92/255, blue: 118/255), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(26)
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Shop Carousel Product Card (Supports both Light & Dark Theme)

struct ShopCarouselProductCard: View {
    let title: String
    let brand: String?
    let price: Double
    let originalPrice: Double?
    let imageUrl: String?
    let matchedProduct: MatchedProduct
    var isWhiteCardTheme: Bool = false
    @ObservedObject private var wishlist = WishlistManager.shared

    var formattedPrice: String {
        String(format: "%.2f €", price).replacingOccurrences(of: ".", with: ",")
    }

    var cardBackground: Color {
        isWhiteCardTheme ? Color(red: 247/255, green: 247/255, blue: 250/255) : Color.white
    }

    var body: some View {
        NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            ZStack(alignment: .topLeading) {
                // Card Container Background
                cardBackground
                    .frame(width: 146, height: 160)
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(red: 236/255, green: 236/255, blue: 240/255), lineWidth: isWhiteCardTheme ? 0.8 : 0)
                    )
                    .shadow(color: isWhiteCardTheme ? Color.clear : Color.black.opacity(0.04), radius: 5, x: 0, y: 2)

                // Product Image centered
                VStack {
                    Spacer()
                    if let imgUrl = imageUrl, imgUrl.hasPrefix("http"), let url = URL(string: imgUrl) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img
                                    .resizable()
                                    .scaledToFit()
                                    .padding(8)
                                    .frame(width: 130, height: 110)
                            } else if phase.error != nil {
                                Image(systemName: "photo")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                                    .frame(width: 130, height: 110)
                            } else {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.shopDark)
                                    .frame(width: 130, height: 110)
                            }
                        }
                    } else {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 26))
                            .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                            .frame(width: 130, height: 110)
                    }
                    Spacer()
                }
                .frame(width: 146, height: 160)

                // Top-Left Floating Price Pill
                Text(formattedPrice)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Color.black.opacity(0.55))
                    .cornerRadius(12)
                    .padding([.top, .leading], 10)

                // Bottom-Right Floating Heart Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            withAnimation(.spring()) {
                                wishlist.toggleFavorite(product: matchedProduct)
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 30, height: 30)
                                    .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
                                    .overlay(
                                        Circle()
                                            .stroke(Color(red: 235/255, green: 235/255, blue: 238/255), lineWidth: 0.8)
                                    )

                                Image(systemName: wishlist.isFavorite(matchedProduct.canonical_name) ? "heart.fill" : "heart")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(wishlist.isFavorite(matchedProduct.canonical_name) ? Color.red : Color.black)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding([.bottom, .trailing], 10)
                    }
                }
                .frame(width: 146, height: 160)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Followed Stores Sheet

struct FollowedStoresSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let stores: [(id: String, name: String, rating: String)] = [
        ("cisalfa", "Cisalfa Sport", "4.8"),
        ("maxisport", "Maxi Sport", "4.9"),
        ("misterrunning", "Mister Running", "4.9"),
        ("nencini", "Nencini Sport", "4.7"),
        ("top4running", "Top4Running", "4.8"),
        ("runningwarehouse", "Running Warehouse", "4.9"),
        ("deporvillage", "Deporvillage", "4.3"),
        ("alltricks", "Alltricks", "4.4"),
        ("decathlon", "Decathlon", "4.8")
    ]

    var body: some View {
        NavigationStack {
            List(stores, id: \.id) { store in
                NavigationLink(destination: StoreDetailView(storeId: store.id, initialStoreName: store.name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: store.name, showVerified: false, showLabel: false, size: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(store.name)
                                    .font(.system(size: 14.5, weight: .bold))
                                    .foregroundColor(.shopDark)
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.shopPurple)
                            }

                            Text("★ \(store.rating) • Store verificato")
                                .font(.system(size: 12))
                                .foregroundColor(.shopTextMuted)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("I tuoi Negozi Partner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}
