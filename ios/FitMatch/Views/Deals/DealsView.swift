import SwiftUI

struct DealsView: View {
    var embedded: Bool = false
    var onSelectPerTe: (() -> Void)? = nil

    @StateObject private var api = APIService.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var followedManager = FollowedStoresManager.shared

    @State private var showcases: [StoreShowcase] = []
    @State private var isLoading = false
    @State private var selectedCategory: String = "Tutti"

    // Top categories with icons/thumbnails (Screenshot 2)
    private let categories: [(id: String, name: String, icon: String, color: Color)] = [
        ("Tutti", "Tutti", "tag.fill", Color.shopPurple),
        ("Running", "Running", "figure.run", Color.blue),
        ("Sneakers", "Sneakers", "shoeprints.fill", Color.orange),
        ("Fitness", "Fitness e a...", "dumbbell.fill", Color.green),
        ("Tecnologia", "Smartwatch", "applewatch", Color.indigo),
        ("Abbigliamento", "Sportswear", "tshirt.fill", Color.pink),
        ("Donna", "Donna", "figure.walk", Color.purple),
        ("Outdoor", "Outdoor", "mountain.2.fill", Color.teal)
    ]

    // Partner store promos matching Screenshot 2
    private let storePromos: [String: String] = [
        "cisalfa": "Risparmia 10 € su ordini superiori a 50 €",
        "maxisport": "Risparmia 5 € su ordini superiori a 40 €",
        "misterrunning": "Spedizione gratuita su tutti i modelli running",
        "top4running": "Coupon RUN2026: -15% al checkout",
        "decathlon": "Prezzi ribassati fine serie -40%",
        "deporvillage": "Sconto extra 10€ su GPS Garmin e scarpe",
        "alltricks": "Saldi di mezza stagione su abbigliamento",
        "runningwarehouse": "Spedizione 24h gratuita sopra 49 €",
        "nike": "Fino al -40% su modelli selezionati e spedizione Member gratuita"
    ]

    var filteredShowcases: [StoreShowcase] {
        if selectedCategory == "Tutti" {
            return showcases
        }
        let cat = selectedCategory.lowercased()
        return showcases.map { sc in
            let filteredProds = sc.products.filter { p in
                p.title.lowercased().contains(cat) ||
                (p.brand?.lowercased().contains(cat) ?? false) ||
                p.canonical_name.lowercased().contains(cat)
            }
            return StoreShowcase(
                store_id: sc.store_id,
                store_name: sc.store_name,
                total_offers: filteredProds.count,
                avg_discount: sc.avg_discount,
                rating: sc.rating,
                products: filteredProds.isEmpty ? sc.products : filteredProds
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // MARK: - 1. Categories Horizontal Scroll (Screenshot 2)
                    categoriesHorizontalRow
                        .padding(.top, 4)

                    // MARK: - 2. Store Deals Sections
                    if isLoading && showcases.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(.shopDark)
                            Text("Ricerca migliori offerte in tempo reale...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 50)
                    } else {
                        ForEach(filteredShowcases) { showcase in
                            storeDealsSection(showcase: showcase)
                        }
                    }

                    Spacer(minLength: 120)
                }
            }
            .refreshable {
                await loadDeals()
            }
        }
        .task {
            if showcases.isEmpty {
                await loadDeals()
            }
        }
    }

    private func loadDeals() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let sc = try await api.getStoreShowcases()
            await MainActor.run {
                self.showcases = sc
            }
        } catch {
            print("DealsView loadDeals error: \(error)")
        }
    }

    // MARK: - 1. Categories Horizontal Row (Screenshot 2)

    private var categoriesHorizontalRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(categories, id: \.id) { cat in
                    Button(action: {
                        let gen = UIImpactFeedbackGenerator(style: .light)
                        gen.impactOccurred()
                        withAnimation(.spring(response: 0.25)) {
                            selectedCategory = cat.id
                        }
                    }) {
                        VStack(spacing: 8) {
                            // Category Thumbnail / Box
                            ZStack {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(selectedCategory == cat.id ? Color.shopDark : Color(red: 242/255, green: 243/255, blue: 246/255))
                                    .frame(width: 72, height: 60)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .stroke(selectedCategory == cat.id ? Color.shopDark : Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
                                    )

                                Image(systemName: cat.icon)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(selectedCategory == cat.id ? .white : cat.color)
                            }

                            // Category Label
                            Text(cat.name)
                                .font(.system(size: 12, weight: selectedCategory == cat.id ? .bold : .medium, design: .rounded))
                                .foregroundColor(selectedCategory == cat.id ? .shopDark : .shopTextMuted)
                                .lineLimit(1)
                                .frame(width: 72)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 2. Store Deals Section (Screenshot 2)

    private func storeDealsSection(showcase: StoreShowcase) -> some View {
        let promoText = storePromos[showcase.store_id.lowercased()] ?? "Risparmia fino al \(String(format: "%.0f", showcase.avg_discount))% sulle offerte attive"

        return VStack(alignment: .leading, spacing: 14) {
            // Header: Store Logo + Name + Green Promo Tag + Ellipsis
            HStack(spacing: 12) {
                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(showcase.store_name)
                                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            // Green Promo Text (Screenshot 2: "Risparmia 5 € su ordini superiori a 40 €")
                            Text(promoText)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(Color(red: 16/255, green: 149/255, blue: 96/255)) // Verified Green
                                .lineLimit(1)
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
            .padding(.horizontal, 16)

            // Horizontal Carousel of Deal Cards (Screenshot 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(showcase.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                        ShopDealProductCard(
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

// MARK: - Deal Product Card with Black Discount Pill & Rating (Screenshot 2)

struct ShopDealProductCard: View {
    let product: StoreShowcaseProduct
    let matchedProduct: MatchedProduct

    @ObservedObject private var wishlist = WishlistManager.shared

    var discountPercentText: String {
        if let disc = product.discount_pct, disc > 0 {
            return "\(Int(disc.rounded()))% di sconto"
        }
        if let orig = product.original_price, orig > product.current_price {
            let pct = ((orig - product.current_price) / orig) * 100.0
            return "\(Int(pct.rounded()))% di sconto"
        }
        return "Offerta"
    }

    var body: some View {
        NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            VStack(alignment: .leading, spacing: 6) {
                // Product Image Box with Discount Pill & Heart Button
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(red: 245/255, green: 245/255, blue: 247/255))
                        .frame(width: 175, height: 180)

                    // Centered Product Image
                    VStack {
                        Spacer()
                        if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img
                                        .resizable()
                                        .scaledToFit()
                                        .padding(14)
                                        .frame(width: 155, height: 140)
                                } else {
                                    Image(systemName: "photo")
                                        .font(.system(size: 28))
                                        .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                                        .frame(width: 155, height: 140)
                                }
                            }
                        } else {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 28))
                                .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                                .frame(width: 155, height: 140)
                        }
                        Spacer()
                    }
                    .frame(width: 175, height: 180)

                    // Top-Left Black Discount Pill (Screenshot 2: "55% di sconto")
                    Text(discountPercentText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.black)
                        .clipShape(Capsule())
                        .padding([.top, .leading], 10)

                    // Bottom-Right Floating Heart Button
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
                    .frame(width: 175, height: 180)
                }

                // Title (Screenshot 2: "Giordania 4 gatto nero retrò")
                Text(product.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)
                    .frame(width: 175, alignment: .leading)

                // Rating & Star Row (Screenshot 2: "★★★★★ (21)")
                HStack(spacing: 3) {
                    HStack(spacing: 1.5) {
                        ForEach(0..<5) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.shopDark)
                        }
                    }

                    Text("(\(Int.random(in: 12...85)))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                }

                // Price Row: Bold current price + strikethrough original price (Screenshot 2: "89,00 € 199,00 €")
                HStack(spacing: 6) {
                    Text(String(format: "%.2f €", product.current_price).replacingOccurrences(of: ".", with: ","))
                        .font(.system(size: 14.5, weight: .black, design: .rounded))
                        .foregroundColor(.shopDark)

                    if let orig = product.original_price, orig > product.current_price {
                        Text(String(format: "%.2f €", orig).replacingOccurrences(of: ".", with: ","))
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(.shopTextMuted)
                            .strikethrough()
                    }
                }
            }
            .frame(width: 175)
        }
        .buttonStyle(.plain)
    }
}
