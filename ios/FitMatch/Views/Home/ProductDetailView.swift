import SwiftUI
import Charts

// MARK: - Main Product Detail View

struct ProductDetailView: View {
    let product: MatchedProduct
    private let userPreferredSize: String?

    @State private var selectedOfferIndex: Int = 0
    @State private var selectedSize: String? = nil
    @State private var selectedVariant: String? = nil
    @State private var selectedImageIndex: Int = 0

    // Collapsible Accordion States (Shopify Shop Style)
    @State private var isExpandedSizes: Bool = false
    @State private var isDescriptionExpanded: Bool = true
    @State private var isDeliveryExpanded: Bool = true
    @State private var isOffersExpanded: Bool = false

    // Sheets & Navigation
    @State private var showingAlertSheet: Bool = false
    @State private var showingMoveToCollection: Bool = false
    @State private var showingComparisonSheet: Bool = false
    @State private var showingShareSheet: Bool = false
    @State private var showingReturnPolicySheet: Bool = false
    @State private var showingShippingInfoSheet: Bool = false
    @State private var navigateToStore: Bool = false
    @State private var navigateToSearch: Bool = false

    // Data Loading
    @State private var priceHistory: PriceHistoryResponse? = nil
    @State private var isLoadingPriceHistory: Bool = false
    @State private var relatedProducts: [MatchedProduct] = []
    @State private var isLoadingRelated: Bool = false

    // In-App Toast
    @State private var showCartToast: Bool = false
    @State private var cartToastMessage: String = ""

    @ObservedObject private var wishlist = WishlistManager.shared
    @Environment(\.dismiss) private var dismiss

    init(product: MatchedProduct, initialSize: String? = nil) {
        self.product = product
        let prefs = UserPreferencesManager.shared.preferences
        let prefSize = product.isComparable ? prefs.preferredShoeSize : prefs.preferredApparelSize
        let normPref = prefSize.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        self.userPreferredSize = normPref.isEmpty ? nil : normPref

        if let explicit = initialSize, !explicit.isEmpty {
            self._selectedSize = State(initialValue: explicit)
        } else if !normPref.isEmpty && product.allAvailableSizes.contains(where: {
            $0.replacingOccurrences(of: ",", with: ".") == normPref
        }) {
            self._selectedSize = State(initialValue: normPref)
        } else {
            self._selectedSize = State(initialValue: nil)
        }
    }

    // MARK: - Computed Properties

    private var displayedImages: [String] {
        let imgs = product.allImages
        if imgs.isEmpty, let img = product.image_url {
            return [img]
        }
        return imgs
    }

    var currentOffer: Offer? {
        if product.offers.indices.contains(selectedOfferIndex) {
            return product.offers[selectedOfferIndex]
        }
        if let sz = selectedSize {
            return product.bestOffer(for: sz)
        }
        return product.bestOffer
    }

    private var wishlistItem: WishlistItem? {
        wishlist.getItem(product.canonical_name)
    }

    private var isWishlisted: Bool {
        wishlist.isFavorite(product.canonical_name)
    }

    private var allSizes: [String] {
        if !product.allAvailableSizes.isEmpty {
            return product.allAvailableSizes
        }
        if let offerSizes = currentOffer?.available_sizes, !offerSizes.isEmpty {
            return currentOffer?.normalizedSizes() ?? offerSizes
        }
        return []
    }

    private var visibleSizes: [String] {
        if isExpandedSizes || allSizes.count <= 6 {
            return allSizes
        }
        return Array(allSizes.prefix(6))
    }

    private var availableVariants: [String] {
        var list: [String] = []
        for off in product.offers {
            if let v = off.displayVariant, !v.isEmpty && !list.contains(v) {
                list.append(v)
            }
        }
        return list
    }

    private var sortedOffers: [(index: Int, offer: Offer, hasSize: Bool)] {
        var list: [(index: Int, offer: Offer, hasSize: Bool)] = []
        for (idx, off) in product.offers.enumerated() {
            let has = off.hasSize(selectedSize)
            list.append((index: idx, offer: off, hasSize: has))
        }
        if selectedSize != nil {
            return list.sorted {
                let s0 = $0.offer.sizeMatchStatus(selectedSize)
                let s1 = $1.offer.sizeMatchStatus(selectedSize)
                if s0 != s1 {
                    return s0 > s1
                }
                return $0.offer.price < $1.offer.price
            }
        }
        return list
    }

    // MARK: - Body View

    var body: some View {
        ZStack(alignment: .top) {
            // Background Navigation Links (Hidden)
            if let offer = currentOffer {
                NavigationLink(
                    destination: StoreDetailView(storeId: offer.store_id, initialStoreName: offer.store_name),
                    isActive: $navigateToStore
                ) { EmptyView() }
            }

            NavigationLink(
                destination: SearchView(),
                isActive: $navigateToSearch
            ) { EmptyView() }

            // Main Scrollable Page
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Safe Area Offset for top bar
                    Color.clear.frame(height: 52)

                    // 1. Store Header Profile Row (Screenshot 1)
                    storeHeaderRow
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 12)

                    // 2. Hero Product Image Showcase Card (Screenshot 1)
                    heroImageCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    // 3. Product Title, Heart & Share Actions (Screenshot 1)
                    titleAndActionRow
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    // 4. Stock Badge (Screenshot 1)
                    stockBadgeRow
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    // 5. Price & Shipping Subtext (Screenshot 1 & 2)
                    priceAndShippingSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)

                    // 6. Size Selection Pills (Screenshot 1 & 2)
                    if !allSizes.isEmpty {
                        sizeSelectionSection
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                    }

                    // 7. Color Selection (only if real variants exist in database)
                    if !availableVariants.isEmpty {
                        colorSelectionSection
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                    }

                    // 8. CTA Buttons: Acquista & Preferiti
                    ctaButtonsSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)

                    Divider()
                        .background(Color(red: 235/255, green: 236/255, blue: 240/255))
                        .padding(.horizontal, 16)

                    // 10. Accordion: Descrizione (Screenshot 2 & 3)
                    descriptionAccordion
                        .padding(.horizontal, 16)

                    // 11. Accordion: Consegna e resi (Screenshot 3)
                    deliveryAccordion
                        .padding(.horizontal, 16)

                    // 12. Accordion: Confronta offerte partner (FitMatch Comparator Superpower)
                    partnerOffersAccordion
                        .padding(.horizontal, 16)

                    // 13. Section: Potrebbe piacerti anche (Screenshot 3 & 4)
                    recommendationsSection
                        .padding(.top, 24)
                        .padding(.bottom, 140) // Space for bottom dock
                }
            }

            // Top Floating Navigation Header (Screenshot 1)
            topNavigationBar
                .background(
                    Color.white
                        .opacity(0.96)
                        .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
                )

            // Floating Cart Success Toast
            if showCartToast {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)

                        Text(cartToastMessage)
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.shopDark)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.20), radius: 10, x: 0, y: 4)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAlertSheet) {
            PriceAlertSheet(product: product)
        }
        .sheet(isPresented: $showingMoveToCollection) {
            if let item = wishlistItem {
                MoveToCollectionSheet(item: item)
            }
        }
        .sheet(isPresented: $showingComparisonSheet) {
            ModelCompareView(initialModelA: product.cleanTitle)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let offer = currentOffer, let u = URL(string: offer.url) {
                ShareSheet(items: [
                    "Guarda \(product.cleanTitle) su FitMatch a \(offer.formattedPrice):",
                    u
                ])
            }
        }
        .sheet(isPresented: $showingReturnPolicySheet) {
            ReturnPolicySheetView(storeName: currentOffer?.store_name ?? "Partner Store")
        }
        .sheet(isPresented: $showingShippingInfoSheet) {
            ShippingInfoSheetView(
                storeName: currentOffer?.store_name ?? "Partner Store",
                offer: currentOffer
            )
        }
        .onAppear {
            RecentActivityManager.shared.recordProductView(product)
        }
        .task {
            await loadPriceHistory()
            await loadRelatedProducts()
        }
    }

    // MARK: - 1. Top Navigation Bar (Screenshot 1: Back Button & Search Pill)

    private var topNavigationBar: some View {
        HStack(spacing: 12) {
            // Circular Back Button
            Button(action: {
                dismiss()
            }) {
                Circle()
                    .fill(Color(red: 246/255, green: 247/255, blue: 249/255))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle().stroke(Color(red: 232/255, green: 233/255, blue: 237/255), lineWidth: 0.8)
                    )
                    .overlay(
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.shopDark)
                    )
            }
            .buttonStyle(.plain)

            // Pill Search Bar (Tapping navigates to Search or dismisses to Search tab)
            Button(action: {
                navigateToSearch = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.shopTextMuted)

                    Text("Cerca")
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundColor(.shopTextMuted)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Color(red: 246/255, green: 247/255, blue: 249/255))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color(red: 232/255, green: 233/255, blue: 237/255), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: - 2. Store Header Row (Store Logo, Name, Verified Partner Badge, Menu ...)

    private var storeHeaderRow: some View {
        let storeName = currentOffer?.store_name ?? "Partner Store"

        return HStack(spacing: 10) {
            // Store Avatar
            Button(action: {
                navigateToStore = true
            }) {
                HStack(spacing: 10) {
                    ShopStoreLogo(
                        storeName: storeName,
                        showVerified: false,
                        showLabel: false,
                        size: 38,
                        hasRedRing: false
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(storeName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.shopDark)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.shopPurple)

                            Text("Store Partner Ufficiale")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // More Options Menu Button (...)
            Menu {
                Button(action: { navigateToStore = true }) {
                    Label("Visita \(storeName)", systemImage: "arrow.up.right.square")
                }

                Button(action: { showingAlertSheet = true }) {
                    Label("Avvisami quando il prezzo scende", systemImage: "bell.badge")
                }

                if let item = wishlistItem {
                    Button(action: { showingMoveToCollection = true }) {
                        Label("Organizza in collezione", systemImage: "folder")
                    }
                }

                Button(action: { showingShareSheet = true }) {
                    Label("Condividi prodotto", systemImage: "square.and.arrow.up")
                }

                Button(action: { showingReturnPolicySheet = true }) {
                    Label("Politica di reso", systemImage: "arrow.uturn.backward")
                }

                Button(action: { showingShippingInfoSheet = true }) {
                    Label("Informativa spedizioni", systemImage: "box.truck")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.shopDark)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
        }
    }

    // MARK: - 3. Hero Product Image Showcase (Screenshot 1)

    private var heroImageCard: some View {
        ZStack(alignment: .bottom) {
            Color(red: 244/255, green: 244/255, blue: 246/255) // #F4F4F6 Shop Canvas

            if displayedImages.count > 1 {
                TabView(selection: $selectedImageIndex) {
                    ForEach(Array(displayedImages.enumerated()), id: \.offset) { index, imgUrl in
                        if let url = URL(string: imgUrl) {
                            ShopCachedAsyncImage(url: url, maxPixelSize: 1200) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 290)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 20)
                                        .padding(.horizontal, 16)
                                } else {
                                    ShopSkeletonBlock(cornerRadius: 24, height: 290)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .tag(index)
                        }
                    }
                }
                .frame(height: 330)
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Modern Pill Indicator Dots
                HStack(spacing: 5) {
                    ForEach(0..<min(displayedImages.count, 7), id: \.self) { idx in
                        Capsule()
                            .fill(selectedImageIndex == idx ? Color.shopDark : Color.black.opacity(0.18))
                            .frame(width: selectedImageIndex == idx ? 16 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedImageIndex)
                    }
                    if displayedImages.count > 7 {
                        Text("+\(displayedImages.count - 7)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.85))
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
                .padding(.bottom, 12)
            } else if let firstImg = displayedImages.first ?? product.image_url, let url = URL(string: firstImg) {
                ShopCachedAsyncImage(url: url, maxPixelSize: 1200) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(height: 290)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .padding(.horizontal, 16)
                    } else {
                        ShopSkeletonBlock(cornerRadius: 24, height: 290)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 330)
            } else {
                Rectangle()
                    .fill(Color(red: 244/255, green: 244/255, blue: 246/255))
                    .frame(height: 330)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 330)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color(red: 236/255, green: 237/255, blue: 240/255), lineWidth: 0.8)
        )
    }

    // MARK: - 4. Title & Action Row (Screenshot 1: Title, Wishlist Heart, Share)

    private var titleAndActionRow: some View {
        HStack(alignment: .top, spacing: 12) {
            // Product Title
            Text(product.cleanTitle)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Right Action Buttons: Wishlist Heart & Share
            HStack(spacing: 8) {
                // Heart Wishlist Toggle Button
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                        wishlist.toggleFavorite(product: product, selectedSize: selectedSize)
                    }
                }) {
                    Circle()
                        .stroke(Color(red: 230/255, green: 231/255, blue: 235/255), lineWidth: 1)
                        .background(Circle().fill(Color.white))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: isWishlisted ? "heart.fill" : "heart")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isWishlisted ? Color(red: 235/255, green: 40/255, blue: 60/255) : Color.shopDark)
                                .scaleEffect(isWishlisted ? 1.15 : 1.0)
                        )
                }
                .buttonStyle(.plain)

                // Share Button
                Button(action: {
                    showingShareSheet = true
                }) {
                    Circle()
                        .stroke(Color(red: 230/255, green: 231/255, blue: 235/255), lineWidth: 1)
                        .background(Circle().fill(Color.white))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.shopDark)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 5. Stock & Deal Badge Row

    @ViewBuilder
    private var stockBadgeRow: some View {
        if let current = currentOffer {
            if current.in_stock == false {
                HStack {
                    Text("Non disponibile")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(Color(red: 220/255, green: 38/255, blue: 38/255))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color(red: 254/255, green: 242/255, blue: 242/255))
                        .clipShape(Capsule())

                    Spacer()
                }
            } else if let badge = current.discountBadge {
                HStack {
                    Text("In offerta \(badge)")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(Color(red: 220/255, green: 38/255, blue: 38/255))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color(red: 254/255, green: 242/255, blue: 242/255))
                        .clipShape(Capsule())

                    Spacer()
                }
            }
        }
    }

    // MARK: - 6. Price & Shipping (Screenshot 1 & 2)

    private var priceAndShippingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(currentOffer?.formattedPrice ?? product.formattedBestPrice)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)

                if let current = currentOffer, let orig = current.formattedOriginalPrice {
                    Text(orig)
                        .font(.system(size: 16))
                        .strikethrough()
                        .foregroundColor(.shopTextMuted)
                }

                if let current = currentOffer, let badge = current.discountBadge {
                    DiscountBadge(discountText: badge)
                }
            }

            Text("Spedizione calcolata al check-out")
                .font(.system(size: 13.5, weight: .regular))
                .foregroundColor(.shopTextMuted)
        }
    }

    // MARK: - 7. Size Selection Pills (Screenshot 1 & 2: Taglia)

    private var sizeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Taglia")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.shopDark)

                Spacer()

                if let pref = userPreferredSize {
                    if selectedSize == pref {
                        Text("Tua taglia (\(pref))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.shopPurple)
                    }
                }
            }

            // Grid of Size Chips matching Screenshot 2 (e.g. 7 US, 7.5 US, 8 US, 8.5 US...)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74, maximum: 92), spacing: 8)], spacing: 8) {
                ForEach(visibleSizes, id: \.self) { sz in
                    let isSel = (selectedSize == sz)
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            selectedSize = (selectedSize == sz) ? nil : sz
                        }
                    }) {
                        Text(sz)
                            .font(.system(size: 14, weight: isSel ? .bold : .semibold))
                            .foregroundColor(isSel ? .white : .shopDark)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(isSel ? Color.shopDark : Color.white)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(isSel ? Color.shopDark : Color(red: 226/255, green: 227/255, blue: 231/255), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                // Expand / Collapse Pill Button: "Visualizza 5 in più" (Screenshot 2)
                if allSizes.count > 6 {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            isExpandedSizes.toggle()
                        }
                    }) {
                        Text(isExpandedSizes ? "Mostra meno" : "Visualizza \(allSizes.count - 6) in più")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.shopDark)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Color.white)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color(red: 226/255, green: 227/255, blue: 231/255), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 8. Color Selection (Screenshot 2: Colore)

    private var colorSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Colore")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.shopDark)

            HStack(spacing: 8) {
                ForEach(availableVariants, id: \.self) { variant in
                    let isSel = (selectedVariant == variant) || (selectedVariant == nil && variant == availableVariants.first)
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            selectedVariant = variant
                        }
                    }) {
                        Text(variant)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.shopDark)
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background(Color.white)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(isSel ? Color.shopDark : Color(red: 226/255, green: 227/255, blue: 231/255), lineWidth: isSel ? 1.5 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 8. CTA Buttons (Acquista su Store & Preferiti)

    private var ctaButtonsSection: some View {
        VStack(spacing: 12) {
            // 1. Primary Vibrant Purple Button: "Acquista su [Store]"
            if let offer = currentOffer, let _ = URL(string: offer.url) {
                let outboundUrl = APIService.shared.outboundRedirectURL(
                    targetUrl: offer.url,
                    storeId: offer.store_id,
                    offerId: offer.id,
                    source: "product_detail"
                )
                Link(destination: outboundUrl) {
                    HStack(spacing: 8) {
                        Image(systemName: "cart.fill")
                            .font(.system(size: 15))
                        Text("Acquista su \(offer.store_name)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.shopPurple)
                    .clipShape(Capsule())
                    .shadow(color: Color.shopPurple.opacity(0.28), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            }

            // 2. Secondary Solid Black Button: "Salva nei preferiti"
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                    wishlist.toggleFavorite(product: product, selectedSize: selectedSize)
                }
                cartToastMessage = isWishlisted ? "Salvato nei tuoi preferiti" : "Rimosso dai preferiti"
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showCartToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation { showCartToast = false }
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isWishlisted ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isWishlisted ? Color(red: 235/255, green: 40/255, blue: 60/255) : .white)
                    Text(isWishlisted ? "Salvato nei preferiti" : "Salva nei preferiti")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.shopDark)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 9. Descrizione Accordion

    private var descriptionAccordion: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isDescriptionExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Descrizione")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.shopDark)

                    Spacer()

                    Image(systemName: isDescriptionExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.shopDark)
                }
                .padding(.vertical, 18)
            }
            .buttonStyle(.plain)

            if isDescriptionExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if !product.effectiveBrand.isEmpty {
                        HStack(spacing: 6) {
                            Text("Brand:")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundColor(.shopDark)
                            Text(product.effectiveBrand)
                                .font(.system(size: 13.5))
                                .foregroundColor(.shopTextMuted)
                        }
                    }

                    if let gender = product.gender, !gender.isEmpty {
                        HStack(spacing: 6) {
                            Text("Genere:")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundColor(.shopDark)
                            Text(gender.capitalized)
                                .font(.system(size: 13.5))
                                .foregroundColor(.shopTextMuted)
                        }
                    }

                    if let current = currentOffer {
                        HStack(spacing: 6) {
                            Text("Store di riferimento:")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundColor(.shopDark)
                            Text(current.store_name)
                                .font(.system(size: 13.5))
                                .foregroundColor(.shopTextMuted)
                        }

                        if !current.title.isEmpty && current.title.lowercased() != product.cleanTitle.lowercased() {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Titolo catalogo fornitore:")
                                    .font(.system(size: 13.5, weight: .bold))
                                    .foregroundColor(.shopDark)
                                Text(current.title)
                                    .font(.system(size: 13))
                                    .foregroundColor(.shopTextMuted)
                            }
                        }
                    }

                    if !allSizes.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Text("Taglie a catalogo:")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundColor(.shopDark)
                            Text(allSizes.joined(separator: ", "))
                                .font(.system(size: 13))
                                .foregroundColor(.shopTextMuted)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.bottom, 18)
            }

            Divider()
                .background(Color(red: 235/255, green: 236/255, blue: 240/255))
        }
    }

    // MARK: - 10. Consegna e resi Accordion

    private var deliveryAccordion: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isDeliveryExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Consegna e resi")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.shopDark)

                    Spacer()

                    Image(systemName: isDeliveryExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.shopDark)
                }
                .padding(.vertical, 18)
            }
            .buttonStyle(.plain)

            if isDeliveryExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Location: Spedizione
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.shopDark)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Destinazione:")
                                .font(.system(size: 12))
                                .foregroundColor(.shopTextMuted)
                            Text("Consegna in tutta Italia")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.shopDark)
                        }

                        Spacer()
                    }

                    // Truck: Spedizione
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "box.truck.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.shopDark)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentOffer?.isFreeShipping == true ? "Spedizione gratuita inclusa" : "Spedizione calcolata al check-out")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.shopDark)

                            if let off = currentOffer, !off.isFreeShipping {
                                Text("Costo verificato: \(off.formattedShipping)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.shopTextMuted)
                            }
                        }
                    }

                    // Return Box
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.shopDark)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Diritto di recesso garantito")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.shopDark)
                            Text("Gestito direttamente da \(currentOffer?.store_name ?? "store partner") secondo i termini del rivenditore.")
                                .font(.system(size: 12))
                                .foregroundColor(.shopTextMuted)
                        }
                    }

                    // Action Pill Buttons: Politica di reso & Informativa sulle spedizioni
                    HStack(spacing: 10) {
                        Button(action: { showingReturnPolicySheet = true }) {
                            Text("Politica di reso")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.shopDark)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(red: 244/255, green: 244/255, blue: 246/255))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(action: { showingShippingInfoSheet = true }) {
                            Text("Informativa sulle sp...")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.shopDark)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(red: 244/255, green: 244/255, blue: 246/255))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // Visit Store Pill Button
                    if let offer = currentOffer {
                        Button(action: {
                            navigateToStore = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Visita \(offer.store_name)")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundColor(.shopDark)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color(red: 244/255, green: 244/255, blue: 246/255))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 18)
            }

            Divider()
                .background(Color(red: 235/255, green: 236/255, blue: 240/255))
        }
    }

    // MARK: - 13. Partner Offers & Price Comparison Accordion (FitMatch Core Value)

    private var partnerOffersAccordion: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isOffersExpanded.toggle()
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Offerte negozi partner (\(product.offers.count))")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.shopDark)

                        if let savings = product.cross_store_savings, savings > 1.0 {
                            Text("Risparmi fino a €\(String(format: "%.2f", savings)) tra i negozi")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.shopGreen)
                        }
                    }

                    Spacer()

                    Image(systemName: isOffersExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.shopDark)
                }
                .padding(.vertical, 18)
            }
            .buttonStyle(.plain)

            if isOffersExpanded {
                VStack(spacing: 14) {
                    // Versus Mode AI Button
                    if product.isComparable {
                        Button(action: {
                            showingComparisonSheet = true
                        }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.shopPurpleLight)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.shopPurple)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Confronta con modelli simili (IA)")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopDark)
                                    Text("Analisi tecnica su peso, drop e prestazioni")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.shopTextMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.shopPurple)
                            }
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.shopPurple.opacity(0.18), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Price History Chart
                    if let history = priceHistory {
                        PriceHistorySectionView(history: history)
                    } else if isLoadingPriceHistory {
                        HStack(spacing: 10) {
                            ProgressView().tint(.shopPurple)
                            Text("Caricamento storico prezzi...")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                        }
                        .padding(.vertical, 8)
                    }

                    // Offers List
                    VStack(spacing: 10) {
                        ForEach(sortedOffers, id: \.offer.id) { item in
                            let index = item.index
                            let offer = item.offer
                            let hasSize = item.hasSize
                            let isSelected = (index == selectedOfferIndex)
                            let isBest = (offer.price == (currentOffer?.price ?? product.best_price))

                            Button(action: {
                                selectedOfferIndex = index
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }) {
                                HStack(spacing: 12) {
                                    ShopStoreLogo(storeName: offer.store_name, showVerified: false, showLabel: false, size: 28)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(offer.store_name)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.shopDark)
                                            .lineLimit(1)

                                        if offer.isFreeShipping {
                                            Text("Sped. Gratis")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.shopGreen)
                                        } else {
                                            Text(offer.formattedShipping)
                                                .font(.system(size: 11))
                                                .foregroundColor(.shopTextMuted)
                                        }
                                    }

                                    Spacer()

                                    if isBest {
                                        BestPriceBadge()
                                    }

                                    Text(offer.formattedPrice)
                                        .font(.system(size: 15.5, weight: .black, design: .rounded))
                                        .foregroundColor(.shopDark)

                                    // Radio checkmark
                                    ZStack {
                                        Circle()
                                            .fill(isSelected ? Color.shopPurple : Color.clear)
                                            .frame(width: 20, height: 20)
                                            .overlay(
                                                Circle().stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1.5)
                                            )
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(isSelected ? Color.shopPurpleLight.opacity(0.40) : Color.white)
                                .opacity(hasSize ? 1.0 : 0.6)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 18)
            }

            Divider()
                .background(Color(red: 235/255, green: 236/255, blue: 240/255))
        }
    }

    // MARK: - 12. Recommendations Section ("Potrebbe piacerti anche")

    @ViewBuilder
    private var recommendationsSection: some View {
        if !relatedProducts.isEmpty || isLoadingRelated {
            VStack(alignment: .leading, spacing: 16) {
                Text("Potrebbe piacerti anche")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.shopDark)
                    .padding(.horizontal, 16)

                if isLoadingRelated && relatedProducts.isEmpty {
                    HStack(spacing: 14) {
                        ShopSkeletonBlock(cornerRadius: 18, height: 210)
                        ShopSkeletonBlock(cornerRadius: 18, height: 210)
                    }
                    .padding(.horizontal, 16)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                        ForEach(relatedProducts) { item in
                            NavigationLink(destination: ProductDetailView(product: item)) {
                                ShopRelatedProductCard(product: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Data Fetching

    private func loadPriceHistory() async {
        guard priceHistory == nil else { return }
        isLoadingPriceHistory = true
        do {
            let res = try await APIService.shared.fetchPriceHistory(
                canonicalName: product.canonical_name,
                productId: product.id_val
            )
            await MainActor.run {
                self.priceHistory = res
                self.isLoadingPriceHistory = false
            }
        } catch {
            await MainActor.run {
                self.isLoadingPriceHistory = false
            }
        }
    }

    private func loadRelatedProducts() async {
        guard relatedProducts.isEmpty else { return }
        isLoadingRelated = true
        let brand = product.effectiveBrand
        var fetched: [MatchedProduct] = []

        // 1. Fetch real related products for the same brand from Supabase
        if !brand.isEmpty {
            fetched = await SupabaseManager.shared.fetchSmartProductsDirect(
                category: nil,
                keywords: [brand],
                limit: 12
            )
        }

        // 2. If fewer than 6 products, enrich with category products
        if fetched.count < 6 {
            let catKw = product.isComparable ? ["running"] : ["fitness"]
            let extra = await SupabaseManager.shared.fetchSmartProductsDirect(
                category: nil,
                keywords: catKw,
                limit: 12
            )
            for item in extra {
                if !fetched.contains(where: { $0.id == item.id || $0.canonical_name == item.canonical_name }) {
                    fetched.append(item)
                }
            }
        }

        let filtered = fetched.filter { $0.id != product.id && $0.canonical_name != product.canonical_name }
        await MainActor.run {
            self.relatedProducts = Array(filtered.prefix(8))
            self.isLoadingRelated = false
        }
    }
}

// MARK: - Recommended Product Card (Screenshot 4)

struct ShopRelatedProductCard: View {
    let product: MatchedProduct
    @ObservedObject private var wishlist = WishlistManager.shared

    private var isFavorite: Bool {
        wishlist.isFavorite(product.canonical_name)
    }

    private var discountPct: Double? {
        product.bestOffer?.discount_pct
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Rounded Image Card with Heart in bottom-right (Screenshot 4)
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Color(red: 244/255, green: 244/255, blue: 246/255)

                    if let img = product.image_url, let url = URL(string: img) {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 500) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .padding(12)
                            } else {
                                ShopSkeletonBlock(cornerRadius: 18, height: 165)
                            }
                        }
                    } else {
                        Rectangle()
                            .fill(Color(red: 244/255, green: 244/255, blue: 246/255))
                    }
                }
                .frame(height: 165)
                .frame(maxWidth: .infinity)
                .cornerRadius(18)

                // Heart Button on bottom-right of image (Screenshot 4)
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        wishlist.toggleFavorite(product: product)
                    }
                }) {
                    Circle()
                        .fill(Color.white.opacity(0.88))
                        .frame(width: 32, height: 32)
                        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                        .overlay(
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(isFavorite ? Color(red: 235/255, green: 40/255, blue: 60/255) : Color.shopDark)
                        )
                }
                .buttonStyle(.plain)
                .padding(10)
            }

            // Info rows
            VStack(alignment: .leading, spacing: 3) {
                // Discount Badge (Screenshot 4)
                if let disc = discountPct, disc >= 15 {
                    Text("\(Int(disc))% di sconto")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(Color(red: 220/255, green: 38/255, blue: 38/255))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color(red: 254/255, green: 242/255, blue: 242/255))
                        .clipShape(Capsule())
                }

                // Store Name (Screenshot 4)
                Text(product.bestOffer?.store_name ?? "Partner Store")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                // Product Title (Screenshot 4)
                Text(product.cleanTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)

                // Price (Screenshot 4)
                Text(product.formattedBestPrice)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.shopDark)
            }
        }
    }
}

// MARK: - Price History & Market Intelligence Chart

struct PriceHistorySectionView: View {
    let history: PriceHistoryResponse
    @State private var selectedPoint: PriceHistoryPoint? = nil

    var dailyTrendPoints: [PriceHistoryPoint] {
        var byDay: [String: PriceHistoryPoint] = [:]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)

        for pt in history.history_points {
            let dayKey = df.string(from: pt.parsedDate)
            if let existing = byDay[dayKey] {
                if pt.price < existing.price {
                    byDay[dayKey] = pt
                }
            } else {
                byDay[dayKey] = pt
            }
        }

        let sorted = byDay.values.sorted(by: { $0.parsedDate < $1.parsedDate })
        if sorted.count >= 2 {
            return sorted
        }
        if let single = sorted.first {
            let prevDate = Calendar.current.date(byAdding: .day, value: -3, to: single.parsedDate) ?? single.parsedDate
            let basePrice = max(single.price, history.highest_price)
            let basePoint = PriceHistoryPoint(
                date: ISO8601DateFormatter().string(from: prevDate),
                price: basePrice,
                store_name: "Listino",
                offer_id: nil
            )
            return [basePoint, single]
        }
        return sorted
    }

    private var chartMinPrice: Double {
        let prices = dailyTrendPoints.map(\.price)
        let minP = prices.min() ?? history.lowest_price
        return max(0, minP * 0.90)
    }

    private var chartMaxPrice: Double {
        let prices = dailyTrendPoints.map(\.price)
        let maxP = prices.max() ?? history.highest_price
        return maxP * 1.08
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("STORICO PREZZI & MERCATO")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.shopTextMuted)
                            .tracking(0.8)

                        if history.is_all_time_low {
                            HStack(spacing: 3) {
                                Text("🔥 MINIMO STORICO")
                                    .font(.system(size: 9.5, weight: .heavy))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.shopPurple)
                            .clipShape(Capsule())
                        }
                    }

                    Text("Rilevamento cross-store tra i 14 partner")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                }

                Spacer()

                if let dropPct = history.price_drop_percentage, dropPct > 3 {
                    Text("-\(String(format: "%.0f", dropPct))% vs media")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.shopGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.shopGreenLight)
                        .clipShape(Capsule())
                }
            }

            // Stat capsules: Minimo, Media, Massimo
            HStack(spacing: 8) {
                PriceStatPill(
                    title: "Minimo",
                    value: history.formattedLowestPrice,
                    accent: .shopGreen,
                    icon: "arrow.down.right"
                )
                PriceStatPill(
                    title: "Media",
                    value: history.formattedAveragePrice,
                    accent: .shopDark,
                    icon: "chart.bar.fill"
                )
                PriceStatPill(
                    title: "Massimo",
                    value: history.formattedHighestPrice,
                    accent: .secondary,
                    icon: "arrow.up.right"
                )
            }

            // Interactive Swift Chart with Scrubbing & Tooltip
            if dailyTrendPoints.count >= 2 {
                VStack(alignment: .leading, spacing: 6) {
                    if let sel = selectedPoint {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.shopPurple)
                                .frame(width: 8, height: 8)

                            Text(sel.formattedDateFull)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.shopDark)

                            Text(sel.formattedPrice)
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundColor(.shopPurple)

                            Text("• \(sel.store_name)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                                .lineLimit(1)

                            Spacer()

                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    selectedPoint = nil
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.secondary.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.shopPurpleLight)
                        .cornerRadius(10)
                    }

                    Chart {
                        ForEach(dailyTrendPoints) { point in
                            AreaMark(
                                x: .value("Data", point.parsedDate),
                                y: .value("Prezzo", point.price)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color.shopPurple.opacity(0.20),
                                        Color.shopPurple.opacity(0.01)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Data", point.parsedDate),
                                y: .value("Prezzo", point.price)
                            )
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.2))
                            .foregroundStyle(Color.shopPurple)

                            PointMark(
                                x: .value("Data", point.parsedDate),
                                y: .value("Prezzo", point.price)
                            )
                            .foregroundStyle(Color.shopPurple)
                            .symbolSize(CGSize(width: 4.5, height: 4.5))
                        }

                        if let sel = selectedPoint {
                            RuleMark(x: .value("Data Selezionata", sel.parsedDate))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                .foregroundStyle(Color.shopPurple)

                            PointMark(
                                x: .value("Data Selezionata", sel.parsedDate),
                                y: .value("Prezzo Selezionato", sel.price)
                            )
                            .symbolSize(CGSize(width: 10, height: 10))
                            .foregroundStyle(Color.shopPurple)
                        }

                        RuleMark(y: .value("Media", history.average_price))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.40))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("Media \(history.formattedAveragePrice)")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 4)
                            }
                    }
                    .chartYScale(domain: chartMinPrice...chartMaxPrice)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(Color.black.opacity(0.05))
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                .font(.system(size: 9))
                                .foregroundStyle(Color.shopTextMuted)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.black.opacity(0.04))
                            AxisValueLabel {
                                if let dbl = value.as(Double.self) {
                                    Text("€\(Int(dbl))")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(Color.shopTextMuted)
                                }
                            }
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let originX = geometry[proxy.plotAreaFrame].origin.x
                                            let xPosition = value.location.x - originX
                                            guard let date: Date = proxy.value(atX: xPosition) else { return }

                                            if let closest = dailyTrendPoints.min(by: {
                                                abs($0.parsedDate.timeIntervalSince(date)) < abs($1.parsedDate.timeIntervalSince(date))
                                            }) {
                                                if selectedPoint?.id != closest.id {
                                                    selectedPoint = closest
                                                    UISelectionFeedbackGenerator().selectionChanged()
                                                }
                                            }
                                        }
                                )
                        }
                    }
                    .frame(height: 155)
                    .padding(.top, 4)
                }
            }

            // Summary advice
            HStack(spacing: 6) {
                Image(systemName: history.is_all_time_low ? "sparkles" : "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(history.is_all_time_low ? .shopPurple : .shopTextMuted)
                Text(history.is_all_time_low ?
                     "Questo prodotto è attualmente al minimo storico mai registrato su FitMatch." :
                     (history.formattedSavingsVsAverage != nil ? "Prezzo attuale \(history.formattedSavingsVsAverage!)." : "Prezzo monitorato e verificato.")
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.shopTextMuted)
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.shopBorder, lineWidth: 1)
        )
    }
}

struct PriceStatPill: View {
    let title: String
    let value: String
    let accent: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundColor(.shopTextMuted)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(accent)
            }
            Text(value)
                .font(.system(size: 13.5, weight: .black, design: .rounded))
                .foregroundColor(accent == .shopGreen ? .shopGreen : .shopDark)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.shopSurface)
        .cornerRadius(10)
    }
}

// MARK: - Helper Sheets

struct ReturnPolicySheetView: View {
    let storeName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.shopPurple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Politica di reso")
                                .font(.system(size: 18, weight: .bold))
                            Text(storeName)
                                .font(.system(size: 13))
                                .foregroundColor(.shopTextMuted)
                        }
                    }
                    .padding(.top, 8)

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Condizioni generali")
                            .font(.system(size: 15, weight: .bold))

                        Text("• Hai a disposizione 14 giorni lavorativi dalla data di ricezione per richiedere il reso.")
                            .font(.system(size: 14))
                            .foregroundColor(.shopTextMuted)

                        Text("• Il prodotto deve essere integro, con confezione e cartellini originali mai rimossi.")
                            .font(.system(size: 14))
                            .foregroundColor(.shopTextMuted)

                        Text("• Spedizione di reso tramite corriere espresso convenzionato.")
                            .font(.system(size: 14))
                            .foregroundColor(.shopTextMuted)

                        Text("• Il rimborso viene accreditato sullo stesso metodo di pagamento utilizzato.")
                            .font(.system(size: 14))
                            .foregroundColor(.shopTextMuted)
                    }

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Politica di Reso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.shopDark)
                }
            }
        }
    }
}

struct ShippingInfoSheetView: View {
    let storeName: String
    let offer: Offer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: "box.truck.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.shopPurple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Informativa Spedizioni")
                                .font(.system(size: 18, weight: .bold))
                            Text(storeName)
                                .font(.system(size: 13))
                                .foregroundColor(.shopTextMuted)
                        }
                    }
                    .padding(.top, 8)

                    Divider()

                    VStack(alignment: .leading, spacing: 14) {
                        if let off = offer {
                            HStack {
                                Text("Costo stimato:")
                                    .font(.system(size: 14, weight: .bold))
                                Spacer()
                                Text(off.isFreeShipping ? "Gratuita" : off.formattedShipping)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(off.isFreeShipping ? .shopGreen : .shopDark)
                            }
                            Divider()
                        }

                        Text("Tempi di consegna stimati")
                            .font(.system(size: 15, weight: .bold))

                        Text("• Consegna espressa in Italia in 24-48 ore lavorative.")
                            .font(.system(size: 14))
                            .foregroundColor(.shopTextMuted)

                        Text("• Spedizione tracciata con codice inviato all'email del cliente al momento della partenza.")
                            .font(.system(size: 14))
                            .foregroundColor(.shopTextMuted)

                        Text("• Partner logistici: GLS, BRT, DHL Express.")
                            .font(.system(size: 14))
                            .foregroundColor(.shopTextMuted)
                    }

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Spedizioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.shopDark)
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
