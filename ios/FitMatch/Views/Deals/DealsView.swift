import SwiftUI

struct DealCategoryFilter: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let accentColor: Color
    let bgTint: Color
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
    @State private var showingCategoriesSheet = false

    init(embedded: Bool = false, onSelectPerTe: (() -> Void)? = nil) {
        self.embedded = embedded
        self.onSelectPerTe = onSelectPerTe
    }

    // Real categories matching Image 1 & Image 3, mapped to FitMatch database
    private let categories: [DealCategoryFilter] = [
        DealCategoryFilter(
            id: "tutti",
            name: "Tutte",
            icon: "flame.fill",
            accentColor: Color(red: 245/255, green: 75/255, blue: 45/255),
            bgTint: Color(red: 254/255, green: 242/255, blue: 240/255)
        ),
        DealCategoryFilter(
            id: "donna",
            name: "Donna",
            icon: "figure.walk",
            accentColor: Color(red: 235/255, green: 65/255, blue: 85/255),
            bgTint: Color(red: 253/255, green: 240/255, blue: 244/255)
        ),
        DealCategoryFilter(
            id: "uomo",
            name: "Uomo",
            icon: "figure.stand",
            accentColor: Color(red: 35/255, green: 115/255, blue: 235/255),
            bgTint: Color(red: 238/255, green: 246/255, blue: 255/255)
        ),
        DealCategoryFilter(
            id: "running",
            name: "Scarpe Running",
            icon: "figure.run",
            accentColor: Color(red: 20/255, green: 160/255, blue: 120/255),
            bgTint: Color(red: 236/255, green: 250/255, blue: 245/255)
        ),
        DealCategoryFilter(
            id: "abbigliamento",
            name: "Abbigliamento",
            icon: "tshirt.fill",
            accentColor: Color(red: 120/255, green: 60/255, blue: 215/255),
            bgTint: Color(red: 246/255, green: 240/255, blue: 254/255)
        ),
        DealCategoryFilter(
            id: "smartwatch",
            name: "Smartwatch & GPS",
            icon: "applewatch",
            accentColor: Color(red: 15/255, green: 140/255, blue: 195/255),
            bgTint: Color(red: 238/255, green: 248/255, blue: 253/255)
        ),
        DealCategoryFilter(
            id: "accessori",
            name: "Accessori",
            icon: "bag.fill",
            accentColor: Color(red: 225/255, green: 145/255, blue: 20/255),
            bgTint: Color(red: 254/255, green: 248/255, blue: 238/255)
        ),
        DealCategoryFilter(
            id: "outdoor",
            name: "Outdoor & Trail",
            icon: "mountain.2.fill",
            accentColor: Color(red: 45/255, green: 135/255, blue: 75/255),
            bgTint: Color(red: 240/255, green: 249/255, blue: 242/255)
        ),
        DealCategoryFilter(
            id: "padel",
            name: "Padel",
            icon: "tennisball.fill",
            accentColor: Color(red: 135/255, green: 185/255, blue: 25/255),
            bgTint: Color(red: 248/255, green: 252/255, blue: 238/255)
        ),
        DealCategoryFilter(
            id: "cycling",
            name: "Ciclismo",
            icon: "bicycle",
            accentColor: Color(red: 70/255, green: 75/255, blue: 210/255),
            bgTint: Color(red: 242/255, green: 243/255, blue: 254/255)
        ),
        DealCategoryFilter(
            id: "fitness",
            name: "Fitness & Gym",
            icon: "dumbbell.fill",
            accentColor: Color(red: 215/255, green: 50/255, blue: 120/255),
            bgTint: Color(red: 253/255, green: 240/255, blue: 248/255)
        )
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        Color.clear.frame(height: 0).id("deals_top")

                        // MARK: - 1. Hero Promo Banner (Matching Image 3)
                        heroBannerSection
                            .padding(.top, 4)

                        // MARK: - 2. Category Filter Pills Bar (Matching Image 3)
                        categoryPillsBar

                        // MARK: - 3. Featured Deals Spotlight Card (Matching Image 3)
                        dealsSpotlightCard

                        // MARK: - 4. Store Deals Sections in 2-Column Grid (Matching Image 2 & 3)
                        if isCategorySwitching || (isLoading && showcases.isEmpty) {
                            ShopDealsSkeletonView()
                                .transition(.opacity)
                        } else if showcases.isEmpty {
                            emptyStateView
                        } else {
                            if selectedCategory != "tutti" {
                                categoryCountHeader
                            }

                            ForEach(showcases) { showcase in
                                storeDealsSection(showcase: showcase)
                            }
                        }

                        // Spacer for bottom dock and floating filter pill
                        Color.clear.frame(height: 140)
                    }
                }
                .refreshable {
                    dealsCache[selectedCategory] = nil
                    await loadDeals(category: selectedCategory)
                }
                .onReceive(TabCoordinator.shared.$scrollToTopEvent) { event in
                    guard let event, event.tab == 0 else { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        scrollProxy.scrollTo("deals_top", anchor: .top)
                    }
                }
            }

            // MARK: - 5. Floating "Filtra" Button (Matching Image 2)
            floatingFilterButton
        }
        .sheet(isPresented: $showingCategoriesSheet) {
            DealsCategoriesSheetView(
                categories: categories,
                selectedCategory: $selectedCategory,
                onSelect: { catId in
                    selectCategory(catId)
                }
            )
        }
        .task {
            if showcases.isEmpty {
                await loadDeals(category: selectedCategory)
            }
        }
    }

    // MARK: - 1. Hero Promo Banner (Matching Image 3)

    private var heroBannerSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Elegant gradient background with soft winter/deals aesthetic
            LinearGradient(
                colors: [
                    Color(red: 255/255, green: 105/255, blue: 80/255),
                    Color(red: 240/255, green: 70/255, blue: 95/255),
                    Color(red: 160/255, green: 40/255, blue: 105/255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Stylized background graphics
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 68, weight: .ultraLight))
                        .foregroundColor(.white.opacity(0.18))
                        .offset(x: -12, y: 16)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Text("SCONTI DEL GIORNO")
                        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .tracking(0.8)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.22))
                .clipShape(Capsule())

                Text("Scopri le migliori offerte,\na prezzi imperdibili")
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Fino all'80% di sconto reale dai migliori negozi partner")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
            }
            .padding(20)
        }
        .frame(height: 195)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 16)
        .shadow(color: Color(red: 240/255, green: 70/255, blue: 95/255).opacity(0.20), radius: 14, x: 0, y: 6)
    }

    // MARK: - 2. Category Filter Pills Bar (Matching Image 3)

    private var categoryPillsBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { cat in
                        let isSelected = selectedCategory == cat.id

                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.impactOccurred()
                            selectCategory(cat.id)
                        }) {
                            HStack(spacing: 6) {
                                Text(cat.name)
                                    .font(.system(size: 13.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .foregroundColor(isSelected ? .white : Color(red: 35/255, green: 38/255, blue: 46/255))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8.5)
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
                            .shadow(color: isSelected ? Color.black.opacity(0.12) : Color.black.opacity(0.02), radius: isSelected ? 5 : 2, x: 0, y: isSelected ? 2 : 1)
                        }
                        .buttonStyle(.plain)
                        .id(cat.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear {
                proxy.scrollTo(selectedCategory, anchor: .center)
            }
            .onChange(of: selectedCategory) { _, newValue in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onChange(of: showingCategoriesSheet) { _, isPresented in
                if !isPresented {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            proxy.scrollTo(selectedCategory, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 3. Featured Deals Spotlight Card (Matching Image 3)

    private var dealsSpotlightCard: some View {
        Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                selectedCategory = "running"
            }
            selectCategory("running")
        }) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        Color(red: 24/255, green: 40/255, blue: 75/255),
                        Color(red: 45/255, green: 80/255, blue: 135/255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Best of running sale")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Dai top brand alle scarpe da gara al miglior prezzo.")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }

                    Spacer()

                    Circle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 38, height: 38)
                        .overlay(
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .padding(18)
            }
            .frame(height: 125)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 16)
            .shadow(color: Color(red: 24/255, green: 40/255, blue: 75/255).opacity(0.16), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Store Deals Section with 2-Column Product Grid (Matching Image 2 & 3)

    private func storeDealsSection(showcase: StoreShowcase) -> some View {
        let promoText = showcase.dynamicPromoSubtitle(category: selectedCategory)
        let reviewCount = StoreRatingHelper.reviewCount(for: showcase.store_name)
        let rating = StoreRatingHelper.rating(for: showcase.store_name)

        return VStack(alignment: .leading, spacing: 14) {
            // Header: Store Logo with Red Ring + Name + Coral Subtitle + Ellipsis
            HStack(spacing: 12) {
                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 44, hasRedRing: true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(showcase.store_name)
                                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            // Coral / Red Promo Text (Matching Image 2: "Risparmia 15 € su ordini superiori a 140 €")
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

            // MARK: - 2-Column Product Grid (Matching Image 2)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 16
            ) {
                ForEach(showcase.products.prefix(4)) { prod in
                    let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                    ShopDealGridCard(
                        product: prod,
                        matchedProduct: matched,
                        storeRating: rating,
                        storeReviewCount: reviewCount
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 5. Floating "Filtra" Button (Matching Image 2)

    private var floatingFilterButton: some View {
        VStack {
            Spacer()
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                showingCategoriesSheet = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 13, weight: .bold))

                    Text("Filtra")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Color.white)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 5)
                .overlay(
                    Capsule().stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 0.9)
                )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 85) // Floats cleanly above the bottom dock
        }
    }

    private var categoryCountHeader: some View {
        let totalProducts = showcases.reduce(0) { $0 + $1.products.count }
        return HStack(spacing: 6) {
            Image(systemName: "tag.fill")
                .font(.system(size: 11))
                .foregroundColor(.shopPurple)
            Text("\(totalProducts) offerte selezionate in \(showcases.count) negozi")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundColor(Color(red: 100/255, green: 104/255, blue: 116/255))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, -6)
        .transition(.opacity)
    }

    private var emptyStateView: some View {
        let activeCategory = categories.first(where: { $0.id == selectedCategory })
        return FitMatchEmptyStateView(
            icon: activeCategory?.icon ?? "tag.slash",
            accentColor: activeCategory?.accentColor ?? .shopPurple,
            badgeText: "STATO CATEGORIA",
            title: "Nessuno sconto attivo in \(categoryTitle(for: selectedCategory))",
            subtitle: "Al momento gli store partner non hanno ribassi verificati in questa categoria. Esplora tutte le offerte o torna più tardi per i nuovi drop.",
            primaryTitle: "Vedi tutte le offerte",
            primaryIcon: "sparkles",
            primaryColor: .shopPurple,
            onPrimaryTap: {
                selectCategory("tutti")
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func categoryTitle(for id: String) -> String {
        categories.first(where: { $0.id == id })?.name ?? "offerte"
    }

    private func selectCategory(_ catId: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            self.selectedCategory = catId
        }
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
            if selectedCategory == category {
                isLoading = false
                isCategorySwitching = false
            }
        }
        do {
            let sc = try await api.getDealsShowcases(category: category == "tutti" ? nil : category)
            await MainActor.run {
                self.dealsCache[category] = sc
                guard self.selectedCategory == category else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.showcases = sc
                }
            }
        } catch {
            print("DealsView loadDeals error: \(error)")
        }
    }
}

// MARK: - Deal Product Grid Card (Matching Image 2: Seamless White Container, Red Discount Badge, Stars & Prices)

struct ShopDealGridCard: View {
    let product: StoreShowcaseProduct
    let matchedProduct: MatchedProduct
    let storeRating: String
    let storeReviewCount: String

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
            VStack(alignment: .leading, spacing: 6) {
                // 1. Image Container (matching Image 2)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)

                    // Image
                    if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                        ShopCachedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 180)
                                    .padding(8)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 180)
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: 18, height: 180)
                                    .frame(maxWidth: .infinity)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Color(red: 220/255, green: 220/255, blue: 225/255))
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                    }

                    // Stroke Border
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.9)
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)

                    // Top-Left Coral Red Discount Pill (Matching Image 2: "4% di sconto")
                    if let disc = discountPercentText {
                        Text(disc)
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
                    .frame(height: 180)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)

                // 2. Title (1 line with clean ellipsis)
                Text(product.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 2)

                // 3. Rating Stars & Review Count (Matching Image 2: ★★★★★ (48))
                HStack(spacing: 3) {
                    HStack(spacing: 1.5) {
                        ForEach(0..<5) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                        }
                    }
                    Text("(\(storeReviewCount))")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(red: 100/255, green: 104/255, blue: 116/255))
                }

                // 4. Price Row: Bold current price + strikethrough original price
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
        }
        .buttonStyle(.plain)
        .contextMenu {
            let isSaved = wishlist.isFavorite(matchedProduct.canonical_name)
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                wishlist.toggleFavorite(product: matchedProduct)
            }) {
                Label(
                    isSaved ? "Rimuovi dai preferiti" : "Salva nei preferiti",
                    systemImage: isSaved ? "heart.slash" : "heart.fill"
                )
            }

            if let url = URL(string: product.product_url) {
                Button(action: {
                    UIApplication.shared.open(url)
                }) {
                    Label("Apri offerta sullo store", systemImage: "arrow.up.right.square")
                }
            }
        }
    }
}

// MARK: - "Categorie" Bottom Sheet (Matching Image 1)

struct DealsCategoriesSheetView: View {
    let categories: [DealCategoryFilter]
    @Binding var selectedCategory: String
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(categories) { cat in
                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .medium)
                            gen.impactOccurred()
                            onSelect(cat.id)
                            dismiss()
                        }) {
                            HStack(spacing: 16) {
                                // Thumbnail Icon Box (Matching Image 1)
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(cat.bgTint)
                                        .frame(width: 48, height: 48)

                                    Image(systemName: cat.icon)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(cat.accentColor)
                                }

                                Text(cat.name)
                                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(.shopDark)

                                Spacer()

                                if selectedCategory == cat.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.shopPurple)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if cat.id != categories.last?.id {
                            Divider()
                                .padding(.leading, 80)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .navigationTitle("Categorie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(.shopDark)
                            .frame(width: 32, height: 32)
                            .background(Color(red: 242/255, green: 242/255, blue: 245/255))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
