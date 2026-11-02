import SwiftUI

struct FollowingView: View {
    var onGoShopping: (() -> Void)? = nil

    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @StateObject private var api = APIService.shared

    @State private var showcases: [StoreShowcase] = []
    @State private var isLoading = false
    @State private var selectedProduct: MatchedProduct? = nil

    // 9 Real verified partner sports stores from database
    private let partnerStores: [(id: String, name: String, subtitle: String, rating: String)] = [
        ("cisalfa", "Cisalfa Sport", "110 offerte running & sneaker a catalogo", "4.8"),
        ("misterrunning", "Mister Running", "178 modelli corsa con sconti fino al 68%", "4.9"),
        ("maxisport", "Maxi Sport", "109 articoli streetwear e scarpe running", "4.9"),
        ("top4running", "Top4Running", "84 modelli top con sconti fino al 55%", "4.8"),
        ("decathlon", "Decathlon", "60 modelli per corsa, trail e palestra", "4.8"),
        ("deporvillage", "Deporvillage", "144 offerte outdoor, scarpe e GPS Garmin", "4.3"),
        ("alltricks", "Alltricks", "140 articoli per running, trail e ciclismo", "4.4"),
        ("runningwarehouse", "Running Warehouse Europe", "102 modelli scarpe da gara e allenamento", "4.9"),
        ("nencini", "Nencini Sport", "110 articoli sportivi multimarca", "4.7"),
        ("nike", "Nike Official Store", "Store ufficiale con le ultime novità e serie ZoomX", "4.9")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if followedManager.followedStores.isEmpty {
                    // MARK: - Empty State Card (Screenshot 3)
                    emptyFollowedBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    // Suggested stores feed with "Segui" action
                    suggestedBrandsFeed
                } else {
                    // MARK: - Followed State (Screenshot 4)
                    // 1. Followed Stores Stories Row
                    followedStoriesRow
                        .padding(.top, 4)

                    // 2. "Post recenti" Promo Stories Carousel
                    recentPostsSection

                    // 3. Followed Stores Products Feed
                    followedStoresFeed
                }

                Spacer(minLength: 120)
            }
        }
        .refreshable {
            await refreshData()
        }
        .task {
            if showcases.isEmpty {
                await refreshData()
            }
        }
    }

    private func refreshData() async {
        isLoading = true
        defer { isLoading = false }
        await followedManager.fetchFollowedStores()
        do {
            let sc = try await api.getStoreShowcases()
            await MainActor.run {
                self.showcases = sc
            }
        } catch {
            print("FollowingView refresh error: \(error)")
        }
    }

    // MARK: - 1. Empty Followed Banner (Screenshot 3)

    private var emptyFollowedBanner: some View {
        VStack(spacing: 12) {
            Text("Non segui ancora nessun brand")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Text("Ecco i nuovi prodotti dei brand che potrebbero piacerti")
                .font(.system(size: 13.5, weight: .regular))
                .foregroundColor(.shopTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                onGoShopping?()
            }) {
                Text("Fai shopping")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(red: 99/255, green: 59/255, blue: 238/255)) // Vibrant Shop Purple
                    .cornerRadius(24)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(Color.white)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color(red: 236/255, green: 237/255, blue: 242/255), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
    }

    // MARK: - 2. Followed Stories Avatars Row (Screenshot 4)

    private var followedStoriesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(followedManager.followedStores) { store in
                    NavigationLink(destination: StoreDetailView(storeId: store.store_id, initialStoreName: store.store_name)) {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .stroke(Color.black, lineWidth: 2)
                                    .frame(width: 66, height: 66)

                                ShopStoreLogo(storeName: store.store_name, showVerified: false, showLabel: false, size: 58)
                            }

                            Text(store.store_name)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.shopDark)
                                .lineLimit(1)
                                .frame(maxWidth: 68)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Add More Stores Story Button
                Menu {
                    ForEach(partnerStores, id: \.id) { partner in
                        if !followedManager.isFollowing(storeId: partner.id) {
                            Button(action: {
                                followedManager.followStore(storeId: partner.id, storeName: partner.name)
                            }) {
                                Label("Segui \(partner.name)", systemImage: "plus")
                            }
                        }
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .stroke(Color(red: 220/255, green: 220/255, blue: 225/255), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .frame(width: 66, height: 66)

                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.shopDark)
                        }

                        Text("Aggiungi")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 3. "Post recenti" Promo Stories Carousel (Screenshot 4)

    private var recentPostsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Post recenti")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(followedManager.promoPosts) { post in
                        NavigationLink(destination: StoreDetailView(storeId: post.storeId, initialStoreName: post.storeName)) {
                            ZStack(alignment: .bottomLeading) {
                                // Background Gradient Card
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(
                                        LinearGradient(
                                            colors: post.bgGradient,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 155, height: 220)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 22)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )

                                // Card Content
                                VStack(alignment: .leading, spacing: 6) {
                                    // Store Tag
                                    HStack(spacing: 4) {
                                        ShopStoreLogo(storeName: post.storeName, showVerified: false, showLabel: false, size: 20)
                                        Text(post.storeName)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white.opacity(0.85))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(post.title)
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundColor(.white.opacity(0.7))
                                        .tracking(1.0)

                                    Text(post.badge)
                                        .font(.system(size: 16, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(2)

                                    Text(post.description)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white.opacity(0.75))
                                        .lineLimit(2)
                                        .padding(.top, 2)

                                    Text(post.expiresText)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(Color.shopPurpleLight)
                                        .padding(.top, 2)
                                }
                                .padding(14)
                                .frame(width: 155, height: 220, alignment: .bottomLeading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - 4. Suggested Brands Feed (Screenshot 3)

    private var suggestedBrandsFeed: some View {
        VStack(spacing: 24) {
            ForEach(partnerStores, id: \.id) { partner in
                let storeShowcase = showcases.first(where: { $0.store_id.lowercased() == partner.id.lowercased() })
                let products = storeShowcase?.products ?? []

                VStack(alignment: .leading, spacing: 14) {
                    // Brand Header
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: partner.name, showVerified: false, showLabel: false, size: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(partner.name)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            Text(partner.subtitle)
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundColor(.shopTextMuted)
                        }

                        Spacer()

                        Button(action: {
                            followedManager.followStore(storeId: partner.id, storeName: partner.name)
                        }) {
                            Text("Segui")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(Color.shopDark)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)

                    // 2-Column Product Grid (Matching Screenshot 3)
                    if products.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .frame(height: 120)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                            spacing: 14
                        ) {
                            ForEach(Array(products.prefix(2))) { prod in
                                let matched = prod.toMatchedProduct(storeId: partner.id, storeName: partner.name)
                                FollowedGridProductCard(
                                    product: prod,
                                    matchedProduct: matched
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    // MARK: - 5. Followed Stores Products Feed (Screenshot 4)

    private var followedStoresFeed: some View {
        VStack(spacing: 26) {
            ForEach(followedManager.followedStores) { store in
                let storeShowcase = showcases.first(where: { $0.store_id.lowercased() == store.store_id.lowercased() })
                let products = storeShowcase?.products ?? []

                VStack(alignment: .leading, spacing: 14) {
                    // Header
                    HStack(spacing: 12) {
                        NavigationLink(destination: StoreDetailView(storeId: store.store_id, initialStoreName: store.store_name)) {
                            HStack(spacing: 12) {
                                ShopStoreLogo(storeName: store.store_name, showVerified: false, showLabel: false, size: 44)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.store_name)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopDark)

                                    Text("\(products.count) offerte reali disponibili")
                                        .font(.system(size: 12.5, weight: .regular))
                                        .foregroundColor(.shopTextMuted)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Menu {
                            Button(role: .destructive, action: {
                                followedManager.unfollowStore(storeId: store.store_id)
                            }) {
                                Label("Non seguire più", systemImage: "person.badge.minus")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.shopTextMuted)
                                .frame(width: 32, height: 32)
                        }
                    }
                    .padding(.horizontal, 16)

                    // 2-Column Product Grid with Real Database Products
                    if products.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .frame(height: 120)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                            spacing: 14
                        ) {
                            ForEach(Array(products.prefix(4))) { prod in
                                let matched = prod.toMatchedProduct(storeId: store.store_id, storeName: store.store_name)
                                FollowedGridProductCard(
                                    product: prod,
                                    matchedProduct: matched
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
}

// MARK: - 2-Column Clean Product Card (Screenshots 3 & 4)

struct FollowedGridProductCard: View {
    let product: StoreShowcaseProduct
    let matchedProduct: MatchedProduct

    @ObservedObject private var wishlist = WishlistManager.shared

    var body: some View {
        NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            VStack(alignment: .leading, spacing: 8) {
                // Product Image Box with Heart Button
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 244/255, green: 245/255, blue: 248/255))
                        .aspectRatio(1.0, contentMode: .fit)

                    if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img
                                    .resizable()
                                    .scaledToFit()
                                    .padding(14)
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                            }
                        }
                    } else {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                    }

                    // Floating Heart Button (Screenshots 3 & 4: semi-translucent circular button)
                    Button(action: {
                        let gen = UIImpactFeedbackGenerator(style: .medium)
                        gen.impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            wishlist.toggleFavorite(product: matchedProduct)
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.28))
                                .frame(width: 34, height: 34)

                            Image(systemName: wishlist.isFavorite(matchedProduct.canonical_name) ? "heart.fill" : "heart")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(wishlist.isFavorite(matchedProduct.canonical_name) ? .red : .white)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }

                // Title
                Text(product.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.shopDark)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 34, alignment: .topLeading)

                // Price
                Text(String(format: "%.2f €", product.current_price).replacingOccurrences(of: ".", with: ","))
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
            }
        }
        .buttonStyle(.plain)
    }
}
