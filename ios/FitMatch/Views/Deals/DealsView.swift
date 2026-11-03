import SwiftUI

struct DealCategoryFilter: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
}

struct DealsView: View {
    var embedded: Bool = false
    var onSelectPerTe: (() -> Void)? = nil

    @StateObject private var api = APIService.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var followedManager = FollowedStoresManager.shared

    @State private var showcases: [StoreShowcase] = []
    @State private var isLoading = false
    @State private var selectedCategory: String = "tutti"
    @State private var dealsCache: [String: [StoreShowcase]] = [:]
    @State private var isCategorySwitching = false

    // Top categories with clean visual cards matching Image 2
    private let categories: [DealCategoryFilter] = [
        DealCategoryFilter(id: "tutti", name: "Tutte", icon: "flame.fill"),
        DealCategoryFilter(id: "running", name: "Running", icon: "figure.run"),
        DealCategoryFilter(id: "smartwatch", name: "Smartwatch", icon: "applewatch"),
        DealCategoryFilter(id: "padel", name: "Padel", icon: "tennisball.fill"),
        DealCategoryFilter(id: "cycling", name: "Ciclismo", icon: "bicycle"),
        DealCategoryFilter(id: "abbigliamento", name: "Abbigliamento", icon: "tshirt.fill"),
        DealCategoryFilter(id: "donna", name: "Donna", icon: "figure.walk"),
        DealCategoryFilter(id: "fitness", name: "Fitness", icon: "dumbbell.fill"),
        DealCategoryFilter(id: "outdoor", name: "Outdoor", icon: "mountain.2.fill"),
        DealCategoryFilter(id: "accessori", name: "Accessori", icon: "eyeglasses"),
        DealCategoryFilter(id: "uomo", name: "Uomo", icon: "figure.stand")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. Pinned Category Pill Bar (Always visible at top, matching Image 2)
            categoryPillsBar
                .padding(.top, 4)
                .padding(.bottom, 12)

            // MARK: - 2. Store Deals Sections (Real DB Deals Ranked by Deepest Discount)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    if isCategorySwitching || (isLoading && showcases.isEmpty) {
                        VStack(spacing: 14) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(.shopDark)
                            Text("Caricamento offerte \(categoryTitle(for: selectedCategory))...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else if showcases.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tag.slash")
                                .font(.system(size: 36))
                                .foregroundColor(Color.shopTextMuted.opacity(0.6))
                            Text("Nessuna offerta trovata per \(categoryTitle(for: selectedCategory))")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.shopDark)
                            Button("Mostra tutte le offerte") {
                                selectedCategory = "tutti"
                                selectCategory("tutti")
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.shopPurple)
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 50)
                    } else {
                        if selectedCategory != "tutti" {
                            let totalProducts = showcases.reduce(0) { $0 + $1.products.count }
                            HStack(spacing: 6) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.shopPurple)
                                Text("\(totalProducts) offerte in \(showcases.count) negozi")
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color(red: 100/255, green: 104/255, blue: 116/255))
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 2)
                            .padding(.bottom, -6)
                            .transition(.opacity)
                        }

                        ForEach(showcases) { showcase in
                            storeDealsSection(showcase: showcase)
                        }
                    }

                    Spacer(minLength: 120)
                }
            }
            .refreshable {
                dealsCache[selectedCategory] = nil
                await loadDeals(category: selectedCategory)
            }
        }
        .task {
            if showcases.isEmpty {
                await loadDeals(category: selectedCategory)
            }
        }
    }

    private func categoryTitle(for id: String) -> String {
        categories.first(where: { $0.id == id })?.name ?? "offerte"
    }

    private func selectCategory(_ catId: String) {
        if let cached = dealsCache[catId] {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.showcases = cached
                self.isCategorySwitching = false
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isCategorySwitching = true
            }
        }
        Task {
            await loadDeals(category: catId)
        }
    }

    private func loadDeals(category: String) async {
        isLoading = true
        defer {
            isLoading = false
            isCategorySwitching = false
        }
        do {
            let sc = try await api.getDealsShowcases(category: category == "tutti" ? nil : category)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.showcases = sc
                    self.dealsCache[category] = sc
                }
            }
        } catch {
            print("DealsView loadDeals error: \(error)")
        }
    }

    // MARK: - 1. Visual Category Card Bar (Modern Segmented Capsule Filter Chips)

    private var categoryPillsBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { cat in
                        let isSelected = selectedCategory == cat.id

                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.impactOccurred()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                selectedCategory = cat.id
                            }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(cat.id, anchor: .center)
                            }
                            selectCategory(cat.id)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                                    .foregroundColor(
                                        isSelected
                                            ? (cat.id == "tutti" ? Color(red: 255/255, green: 110/255, blue: 50/255) : Color.white)
                                            : (cat.id == "tutti" ? Color(red: 230/255, green: 65/255, blue: 45/255) : Color(red: 90/255, green: 94/255, blue: 106/255))
                                    )

                                Text(cat.name)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .foregroundColor(isSelected ? .white : Color(red: 35/255, green: 38/255, blue: 46/255))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color(red: 22/255, green: 22/255, blue: 26/255) : Color.white)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isSelected ? Color.clear : Color(red: 228/255, green: 230/255, blue: 236/255),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: isSelected ? Color.black.opacity(0.12) : Color.black.opacity(0.02), radius: isSelected ? 6 : 2, x: 0, y: isSelected ? 2 : 1)
                            .scaleEffect(isSelected ? 1.02 : 1.0)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(cat.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - 2. Store Deals Section (Matching Image 2: Red Ring Logo, Coral Subtitle, 195pt Uniform Image Box)

    private func storeDealsSection(showcase: StoreShowcase) -> some View {
        let promoText = showcase.dynamicPromoSubtitle(category: selectedCategory)

        return VStack(alignment: .leading, spacing: 14) {
            // Header: Store Logo with Red Ring + Bold Name + Coral Promo Subtitle + Ellipsis
            HStack(spacing: 12) {
                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 44, hasRedRing: true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(showcase.store_name)
                                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            // Coral / Red Promo Text (Image 2: "Risparmia 15 € su ordini superiori a 50 €")
                            Text(promoText)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(Color(red: 220/255, green: 50/255, blue: 35/255))
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
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(red: 120/255, green: 120/255, blue: 125/255))
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 16)

            // Horizontal Carousel of Deal Cards with Uniform 195pt Pure-White Image Box (Matching Image 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(showcase.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                        ShopDealProductCard(
                            product: prod,
                            matchedProduct: matched,
                            storeReviewCount: showcase.review_count
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Deal Product Card (Redesigned matching Image 2: Seamless White Container, Sleek Red Badge, Dark Heart)

struct ShopDealProductCard: View {
    let product: StoreShowcaseProduct
    let matchedProduct: MatchedProduct
    var storeReviewCount: String? = nil

    @ObservedObject private var wishlist = WishlistManager.shared

    var discountPercentText: String? {
        if let disc = product.discount_pct, disc > 0 {
            return "\(Int(disc.rounded()))% di sconto"
        }
        if let orig = product.original_price, orig > product.current_price {
            let pct = ((orig - product.current_price) / orig) * 100.0
            if pct >= 5 {
                return "\(Int(pct.rounded()))% di sconto"
            }
        }
        return nil
    }

    var body: some View {
        NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            VStack(alignment: .leading, spacing: 5) {
                // Product Image Box: Edge-to-edge container matching Image 2 (no inner border lines)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white)
                        .frame(width: 168, height: 185)
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)

                    // Product Image: Edge-to-edge fill with clipped corner radius
                    if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 168, height: 185)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                    .frame(width: 168, height: 185)
                            case .empty:
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.shopDark)
                                    .frame(width: 168, height: 185)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Color(red: 220/255, green: 220/255, blue: 225/255))
                            .frame(width: 168, height: 185)
                    }

                    // Subtle border overlay matching Image 2
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                        .frame(width: 168, height: 185)

                    // Top-Left Coral Red Discount Pill (Matching Image 2: "5% di sconto")
                    if let discText = discountPercentText {
                        Text(discText)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color(red: 228/255, green: 42/255, blue: 38/255))
                            .clipShape(Capsule())
                            .padding([.top, .leading], 9)
                    }

                    // Bottom-Right Translucent Heart Button (Matching Image 2)
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
                    }
                    .frame(width: 168, height: 185)
                }
                .frame(width: 168, height: 185)

                // Title (Matching Image 2: 1 line with clean ellipsis)
                Text(product.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 168, alignment: .leading)
                    .padding(.top, 2)

                // Price Row: Bold current price + strikethrough original price (Matching Image 2)
                HStack(spacing: 5) {
                    Text(String(format: "%.2f €", product.current_price).replacingOccurrences(of: ".", with: ","))
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

                    if let orig = product.original_price, orig > product.current_price {
                        Text(String(format: "%.2f €", orig).replacingOccurrences(of: ".", with: ","))
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundColor(.shopTextMuted)
                            .strikethrough()
                    }
                }
            }
            .frame(width: 168)
        }
        .buttonStyle(.plain)
    }
}
