import SwiftUI

struct FollowingView: View {
    var onGoShopping: (() -> Void)? = nil

    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @StateObject private var api = APIService.shared

    @State private var showcases: [StoreShowcase] = []
    @State private var fallbackStoreProducts: [String: [StoreShowcaseProduct]] = [:]
    @State private var fallbackStoreCounts: [String: Int] = [:]
    @State private var isLoading = false

    // 10 Real verified partner sports stores from database
    private let partnerStores: [(id: String, name: String, subtitle: String)] = [
        ("nike", "Nike", "81 novità e modelli serie ZoomX"),
        ("cisalfa", "Cisalfa Sport", "107 offerte running & sneaker a catalogo"),
        ("misterrunning", "Mister Running", "175 modelli corsa con sconti fino al 68%"),
        ("maxisport", "Maxi Sport", "106 articoli streetwear e scarpe running"),
        ("top4running", "Top4Running", "103 modelli top con sconti fino al 55%"),
        ("decathlon", "Decathlon", "65 modelli per corsa, trail e palestra"),
        ("deporvillage", "Deporvillage", "128 offerte outdoor, scarpe e GPS Garmin"),
        ("alltricks", "Alltricks", "171 articoli per running, trail e ciclismo"),
        ("runningwarehouse", "Running Warehouse Europe", "102 modelli scarpe da gara e allenamento"),
        ("nencini", "Nencini Sport", "110 articoli sportivi multimarca")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if followedManager.followedStores.isEmpty {
                    // MARK: - Empty State
                    emptyFollowedBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    suggestedBrandsFeed
                } else {
                    // MARK: - Followed State (Matching Reference Image)
                    // 1. Followed Stores Avatars Row (Circular store logos, clean)
                    followedStoriesRow
                        .padding(.top, 6)

                    // 2. Followed Stores Products Carousels
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

    // MARK: - 1. Followed Stores Avatars Row (Matching Reference Image: Circular store logos, clean spacing)

    private var followedStoriesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(followedManager.followedStores) { store in
                    NavigationLink(destination: StoreDetailView(storeId: store.store_id, initialStoreName: store.store_name)) {
                        ShopStoreLogo(storeName: store.store_name, showVerified: false, showLabel: false, size: 62)
                    }
                    .buttonStyle(.plain)
                }

                // Add More Stores Button
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
                    ZStack {
                        Circle()
                            .stroke(Color(red: 225/255, green: 225/255, blue: 230/255), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .frame(width: 62, height: 62)

                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.shopDark)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 2. Followed Stores Products Carousels (Matching Reference Image)

    private var followedStoresFeed: some View {
        VStack(spacing: 28) {
            ForEach(followedManager.followedStores) { store in
                let sId = store.store_id.lowercased()
                let storeShowcase = showcases.first(where: { $0.store_id.lowercased() == sId })
                let products = (storeShowcase?.products.isEmpty == false) ? (storeShowcase?.products ?? []) : (fallbackStoreProducts[sId] ?? [])
                let totalOffers = storeShowcase?.total_offers ?? (fallbackStoreCounts[sId] ?? products.count)

                VStack(alignment: .leading, spacing: 14) {
                    // Header: Store Logo + Name + "X articoli aggiunti di recente"
                    HStack(spacing: 12) {
                        NavigationLink(destination: StoreDetailView(storeId: store.store_id, initialStoreName: store.store_name)) {
                            HStack(spacing: 12) {
                                ShopStoreLogo(storeName: store.store_name, showVerified: false, showLabel: false, size: 42)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.store_name)
                                        .font(.system(size: 16.5, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopDark)

                                    Text("\(max(totalOffers, products.count)) articoli aggiunti di recente")
                                        .font(.system(size: 12.5, weight: .regular))
                                        .foregroundColor(Color(red: 120/255, green: 120/255, blue: 125/255))
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

                            NavigationLink(destination: StoreDetailView(storeId: store.store_id, initialStoreName: store.store_name)) {
                                Label("Visualizza negozio", systemImage: "arrow.right.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Color(red: 140/255, green: 140/255, blue: 145/255))
                                .frame(width: 32, height: 32)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Horizontal Carousel of Product Cards (Matching Reference Screenshot)
                    if products.isEmpty && isLoading {
                        HStack(spacing: 14) {
                            ForEach(0..<2, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color(red: 242/255, green: 242/255, blue: 246/255))
                                    .frame(width: 165, height: 170)
                                    .overlay(ProgressView().controlSize(.small))
                            }
                        }
                        .padding(.horizontal, 16)
                    } else if products.isEmpty {
                        Text("Nessun articolo disponibile al momento")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                            .padding(.horizontal, 16)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(products) { prod in
                                    let matched = prod.toMatchedProduct(storeId: store.store_id, storeName: store.store_name)
                                    FollowedHorizontalProductCard(
                                        product: prod,
                                        matchedProduct: matched
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .task(id: store.store_id) {
                    if products.isEmpty {
                        if let direct = try? await SupabaseManager.shared.fetchStoreOffersDirect(storeId: store.store_id, limit: 12), !direct.isEmpty {
                            await MainActor.run {
                                fallbackStoreProducts[sId] = direct
                            }
                        }
                    }
                    if totalOffers == 0 {
                        if let count = await SupabaseManager.shared.fetchStoreCatalogCountDirect(storeId: store.store_id) {
                            await MainActor.run {
                                fallbackStoreCounts[sId] = count
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 4. Empty State Banner

    private var emptyFollowedBanner: some View {
        VStack(spacing: 12) {
            Text("Non segui ancora nessun brand")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Text("Segui i tuoi negozi preferiti per vedere i nuovi arrivi e le offerte esclusive")
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
                    .background(Color.shopDark)
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

    // MARK: - 5. Suggested Brands Feed (When nothing is followed)

    private var suggestedBrandsFeed: some View {
        VStack(spacing: 20) {
            Text("Brand consigliati")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

            ForEach(partnerStores, id: \.id) { partner in
                HStack(spacing: 12) {
                    ShopStoreLogo(storeName: partner.name, showVerified: false, showLabel: false, size: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(partner.name)
                            .font(.system(size: 15.5, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Text(partner.subtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.shopTextMuted)
                            .lineLimit(1)
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
            }
        }
    }
}

// MARK: - Followed Store Horizontal Product Card (Matching Reference Image)

struct FollowedHorizontalProductCard: View {
    let product: StoreShowcaseProduct
    let matchedProduct: MatchedProduct

    @ObservedObject private var wishlist = WishlistManager.shared

    var body: some View {
        NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            VStack(alignment: .leading, spacing: 4) {
                // Product Image Box: Soft Gray Rounded Container (Matching Reference Image)
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(red: 247/255, green: 247/255, blue: 249/255))
                        .frame(width: 165, height: 170)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.black.opacity(0.04), lineWidth: 1)
                        )

                    // Product Image centered with comfortable padding
                    if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 144, height: 144)
                                    .clipped()
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                    .frame(width: 140, height: 140)
                            case .empty:
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.shopDark)
                                    .frame(width: 140, height: 140)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Color(red: 220/255, green: 220/255, blue: 225/255))
                            .frame(width: 140, height: 140)
                    }

                    // Floating Heart Button (Matching Reference Image: Translucent circle with heart)
                    Button(action: {
                        let gen = UIImpactFeedbackGenerator(style: .medium)
                        gen.impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            wishlist.toggleFavorite(product: matchedProduct)
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.35))
                                .frame(width: 32, height: 32)

                            Image(systemName: wishlist.isFavorite(matchedProduct.canonical_name) ? "heart.fill" : "heart")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(wishlist.isFavorite(matchedProduct.canonical_name) ? .red : .white)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding([.bottom, .trailing], 9)
                }
                .frame(width: 165, height: 170)

                // Title: 1 line with trailing ellipsis (Matching Reference Image)
                Text(product.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 165, alignment: .leading)
                    .padding(.top, 3)

                // Price: Bold Price (Matching Reference Image)
                Text(String(format: "%.2f €", product.current_price).replacingOccurrences(of: ".", with: ","))
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
            }
            .frame(width: 165)
        }
        .buttonStyle(.plain)
    }
}
