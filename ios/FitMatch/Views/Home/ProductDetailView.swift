import SwiftUI
import Charts

// MARK: - Store Rating & Review Statistics Helper

struct StoreRatingHelper {
    private static let italianCountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "it_IT")
        return f
    }()

    static func rating(for storeName: String, storeId: String? = nil) -> String {
        if let item = DynamicCatalogRegistry.shared.storeItem(for: storeId ?? storeName)
            ?? DynamicCatalogRegistry.shared.storeItem(for: storeName),
           let r = item.rating, r > 0 {
            return String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")
        }
        let s = storeName.lowercased()
        if s.contains("top4") { return "4,8" }
        if s.contains("mister") { return "4,9" }
        if s.contains("cisalfa") { return "2,6" }
        if s.contains("maxi") { return "3,9" }
        if s.contains("nencini") { return "4,8" }
        if s.contains("running") || s.contains("warehouse") { return "3,5" }
        if s.contains("deporvillage") { return "4,5" }
        if s.contains("alltricks") { return "4,2" }
        if s.contains("decathlon") { return "1,5" }
        if s.contains("sportler") { return "3,6" }
        if s.contains("df sport") || s.contains("sportspecialist") { return "4,6" }
        if s.contains("tradeinn") { return "3,3" }
        if s.contains("sportit") { return "4,8" }
        if s.contains("tennis") { return "4,1" }
        if s.contains("basketball") { return "4,9" }
        if s.contains("nonsolosport") { return "4,5" }
        if s.contains("intersport") { return "4,3" }
        if s.contains("bshopzone") { return "4,5" }
        if s.contains("nike") { return "1,5" }
        if s.contains("adidas") { return "1,5" }
        return "4,5"
    }

    static func reviewCount(for storeName: String, storeId: String? = nil) -> String {
        if let item = DynamicCatalogRegistry.shared.storeItem(for: storeId ?? storeName)
            ?? DynamicCatalogRegistry.shared.storeItem(for: storeName) {
            if let formatted = item.formatted_review_count, !formatted.isEmpty {
                return formatted
            }
            if let count = item.review_count, count > 0 {
                return italianCountFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
            }
        }
        let s = storeName.lowercased()
        if s.contains("top4") { return "7,9K" }
        if s.contains("mister") { return "37,3K" }
        if s.contains("cisalfa") { return "1,9K" }
        if s.contains("maxi") { return "1,5K" }
        if s.contains("nencini") { return "170K" }
        if s.contains("running") || s.contains("warehouse") { return "32" }
        if s.contains("deporvillage") { return "486K" }
        if s.contains("alltricks") { return "1,3K" }
        if s.contains("decathlon") { return "2,7K" }
        if s.contains("nike") { return "13,2K" }
        if s.contains("adidas") { return "603" }
        return "1,2K"
    }

    struct TrustDisplay {
        let isOfficial: Bool
        let badgeText: String
        let ratingText: String?
        let reviewsText: String?
    }

    /// Presents official brand stores / major trusted chains cleanly without misleading skewed Trustpilot scores (< 3.0).
    static func trustDisplay(for storeName: String, storeId: String? = nil) -> TrustDisplay {
        let low = "\(storeId ?? "") \(storeName)".lowercased()
        let officialMonoBrands = ["nike", "adidas"]
        if officialMonoBrands.contains(where: { low.contains($0) }) {
            return TrustDisplay(isOfficial: true, badgeText: "Sito Ufficiale", ratingText: nil, reviewsText: nil)
        }

        let item = DynamicCatalogRegistry.shared.storeItem(for: storeId ?? storeName)
            ?? DynamicCatalogRegistry.shared.storeItem(for: storeName)
        let numericRating: Double = {
            if let r = item?.rating, r > 0 { return r }
            let fallbackStr = rating(for: storeName, storeId: storeId).replacingOccurrences(of: ",", with: ".")
            return Double(fallbackStr) ?? 4.5
        }()

        let majorRetailers = ["decathlon", "cisalfa"]
        if numericRating < 3.0 || majorRetailers.contains(where: { low.contains($0) }) {
            return TrustDisplay(isOfficial: true, badgeText: "Rivenditore Ufficiale", ratingText: nil, reviewsText: nil)
        }

        return TrustDisplay(
            isOfficial: false,
            badgeText: "Store Partner Verificato",
            ratingText: rating(for: storeName, storeId: storeId),
            reviewsText: reviewCount(for: storeName, storeId: storeId)
        )
    }
}

private struct PrimaryCTAMaxYKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Main Product Detail View

struct ProductDetailView: View {
    @State private var product: MatchedProduct
    var openedFromSearch: Bool = false
    private let userPreferredSize: String?
    private let initialTappedOffer: Offer?
    private let initialTappedOfferURL: String?
    private let initialTappedStoreId: String?

    @State private var selectedOfferIndex: Int = 0
    @State private var isHydratingOffers: Bool = false
    @State private var hasHydratedOffers: Bool = false
    @State private var selectedSize: String? = nil
    @State private var selectedVariant: String? = nil
    @State private var selectedImageIndex: Int = 0
    @State private var scrolledImageIndex: Int? = 0
    @State private var showingFullScreenGallery: Bool = false
    @State private var inlineZoomScale: CGFloat = 1.0
    @State private var inlineZoomAnchor: UnitPoint = .center
    @Namespace private var galleryThumbNamespace

    // Collapsible Accordion & Offer List States (Comparator-First Layout)
    @State private var isExpandedSizes: Bool = false
    @State private var isExpandedOffers: Bool = false
    @State private var isDescriptionExpanded: Bool = false
    @State private var isDeliveryExpanded: Bool = false
    @State private var showStickyCTA: Bool = false

    // Sheets & Navigation
    @State private var showingAlertSheet: Bool = false
    @State private var showingMoveToCollection: Bool = false
    @State private var showingShareSheet: Bool = false
    @State private var showingReturnPolicySheet: Bool = false
    @State private var showingShippingInfoSheet: Bool = false
    @State private var navigateToStore: Bool = false

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

    init(product: MatchedProduct, initialSize: String? = nil, openedFromSearch: Bool = false) {
        self._product = State(initialValue: product)
        self.openedFromSearch = openedFromSearch
        let firstOffer = product.offers.first
        self.initialTappedOffer = firstOffer
        self.initialTappedOfferURL = firstOffer?.url
        self.initialTappedStoreId = firstOffer?.store_id
        self._selectedVariant = State(initialValue: firstOffer?.displayVariant)

        let prefs = UserPreferencesManager.shared.preferences
        let prefSize = product.isComparable ? prefs.preferredShoeSize : prefs.preferredApparelSize
        let normPref = prefSize.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        self.userPreferredSize = normPref.isEmpty ? nil : normPref

        var initialIdx = 0
        if let explicit = initialSize, !explicit.isEmpty {
            self._selectedSize = State(initialValue: explicit)
            if firstOffer?.hasSize(explicit) != true,
               let bestForExplicit = product.bestOffer(for: explicit),
               bestForExplicit.hasSize(explicit),
               let idx = product.offers.firstIndex(where: { $0.id == bestForExplicit.id }) {
                initialIdx = idx
            }
        } else if !normPref.isEmpty, firstOffer?.hasSize(normPref) == true {
            // Only auto-select preferred size if the tapped/initial offer itself has it,
            // so opening a card never hijacks the user to a different store or colorway.
            self._selectedSize = State(initialValue: normPref)
        } else {
            self._selectedSize = State(initialValue: nil)
        }
        self._selectedOfferIndex = State(initialValue: initialIdx)
    }

    // MARK: - Computed Properties

    /// Always bind the hero gallery strictly to `currentOffer` so the displayed photo
    /// always matches the exact product/colorway opened by the outbound store link.
    private var displayedImages: [String] {
        if let offer = currentOffer {
            let offerImgs = offer.allImages
            if !offerImgs.isEmpty {
                return offerImgs
            }
        }
        if let primary = product.image_url?.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
            return [primary]
        }
        return product.allImages
    }

    var currentOffer: Offer? {
        if product.offers.indices.contains(selectedOfferIndex) {
            return product.offers[selectedOfferIndex]
        }
        if let sz = selectedSize, let bestForSize = product.bestOffer(for: sz) {
            return bestForSize
        }
        return product.bestOffer
    }

    private var wishlistProductSnapshot: MatchedProduct {
        guard let active = currentOffer else { return product }
        let activeImg = active.allImages.first ?? product.image_url
        var reorderedOffers = product.offers
        if let idx = reorderedOffers.firstIndex(where: { $0.id == active.id }), idx != 0 {
            let chosen = reorderedOffers.remove(at: idx)
            reorderedOffers.insert(chosen, at: 0)
        }
        return MatchedProduct(
            id_val: product.id_val,
            canonical_name: product.canonical_name,
            brand: product.brand,
            category: product.category,
            image_url: activeImg,
            gallery_images: active.allImages.isEmpty ? product.gallery_images : active.allImages,
            gender: product.gender,
            offers: reorderedOffers,
            best_price: active.price,
            highest_price: product.highest_price,
            cross_store_savings: product.cross_store_savings
        )
    }

    private var wishlistItem: WishlistItem? {
        wishlist.getItem(product.canonical_name)
    }

    private var isWishlisted: Bool {
        wishlist.isFavorite(product.canonical_name)
    }

    private var distinctStoreCount: Int {
        max(1, Set(product.offers.map { $0.store_id.lowercased() }).count)
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
        var slice = Array(allSizes.prefix(6))
        // Always surface the user's preferred size (or active selected size) so it is never hidden behind "+N"
        let prioritySize = selectedSize ?? userPreferredSize
        if let pref = prioritySize,
           let matchedInAll = allSizes.first(where: { $0 == pref || currentOffer?.hasSize(pref) == true && $0 == pref }),
           !slice.contains(matchedInAll) {
            slice[slice.count - 1] = matchedInAll
        }
        return slice
    }

    private struct VariantOption: Identifiable {
        let id: String
        let label: String?
        let previewImage: String?
        let bestOfferIndex: Int
        let minPrice: Double
        let offerIndices: [Int]
    }

    /// Builds variant swatches from either parsed colorway names (`displayVariant`) or distinct offer images
    /// so multi-colorway products always expose a visual switcher even when store titles omit color suffixes.
    private var availableVariantOptions: [VariantOption] {
        var order: [String] = []
        var grouped: [String: (label: String?, previewImage: String?, indices: [Int])] = [:]

        let hasAnyTextVariant = product.offers.contains {
            ($0.displayVariant?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        }
        let distinctImageCount = Set(
            product.offers.compactMap { $0.image_url?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        ).count

        // Need either named variants or >=2 distinct colorway photos
        guard hasAnyTextVariant || distinctImageCount > 1 else { return [] }

        for (idx, off) in product.offers.enumerated() {
            let textVar = off.displayVariant?.trimmingCharacters(in: .whitespacesAndNewlines)
            let imgKey = off.image_url?.trimmingCharacters(in: .whitespacesAndNewlines)

            let groupKey: String
            let label: String?
            if let v = textVar, !v.isEmpty {
                groupKey = "v:\(v.lowercased())"
                label = v
            } else if distinctImageCount > 1, let img = imgKey, !img.isEmpty {
                groupKey = "img:\(img)"
                label = nil
            } else {
                continue
            }

            if grouped[groupKey] == nil {
                order.append(groupKey)
                grouped[groupKey] = (label: label, previewImage: imgKey, indices: [idx])
            } else {
                grouped[groupKey]?.indices.append(idx)
                if grouped[groupKey]?.previewImage == nil, let img = imgKey, !img.isEmpty {
                    grouped[groupKey]?.previewImage = img
                }
            }
        }

        let options: [VariantOption] = order.compactMap { key in
            guard let entry = grouped[key] else { return nil }
            let bestIdx: Int = {
                if let sz = selectedSize {
                    let matchingSize = entry.indices.filter { product.offers[$0].hasSize(sz) }
                    if let cheapestWithSize = matchingSize.min(by: { product.offers[$0].calculatedTotalPrice < product.offers[$1].calculatedTotalPrice }) {
                        return cheapestWithSize
                    }
                }
                return entry.indices.min(by: { product.offers[$0].calculatedTotalPrice < product.offers[$1].calculatedTotalPrice }) ?? entry.indices[0]
            }()
            let previewImg = product.offers[bestIdx].image_url
                ?? entry.previewImage
                ?? entry.indices.compactMap({ product.offers[$0].image_url }).first
            let minP = entry.indices.map { product.offers[$0].price }.min() ?? product.offers[bestIdx].price
            return VariantOption(
                id: key,
                label: entry.label,
                previewImage: previewImg,
                bestOfferIndex: bestIdx,
                minPrice: minP,
                offerIndices: entry.indices
            )
        }

        // Only hide a single unlabeled image swatch; keep named color or >=2 visual swatches
        if options.count == 1 && options[0].label == nil {
            return []
        }
        return options
    }

    private var hasMultipleDistinctOfferImages: Bool {
        let distinct = Set(
            product.offers.compactMap { $0.image_url?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        return distinct.count > 1
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
                if abs($0.offer.calculatedTotalPrice - $1.offer.calculatedTotalPrice) > 0.01 {
                    return $0.offer.calculatedTotalPrice < $1.offer.calculatedTotalPrice
                }
                return $0.offer.price < $1.offer.price
            }
        }
        return list.sorted {
            if abs($0.offer.calculatedTotalPrice - $1.offer.calculatedTotalPrice) > 0.01 {
                return $0.offer.calculatedTotalPrice < $1.offer.calculatedTotalPrice
            }
            return $0.offer.price < $1.offer.price
        }
    }

    /// True lowest total-price offer (honoring selected size when active) — never confused with `currentOffer`.
    private var bestMarketOffer: Offer? {
        if selectedSize != nil {
            if let firstWithSize = sortedOffers.first(where: { $0.hasSize })?.offer {
                return firstWithSize
            }
        }
        return sortedOffers.first?.offer
    }

    private var visibleSortedOffers: [(index: Int, offer: Offer, hasSize: Bool)] {
        let all = sortedOffers
        let collapseLimit = 5
        if isExpandedOffers || all.count <= collapseLimit {
            return all
        }
        var top = Array(all.prefix(collapseLimit))
        // Keep the user's currently selected offer visible even if it ranks below position 5
        if let activeEntry = all.first(where: { $0.index == selectedOfferIndex }),
           !top.contains(where: { $0.offer.id == activeEntry.offer.id }) {
            top.append(activeEntry)
        }
        return top
    }

    private var hasVerifiedPriceHistoryChart: Bool {
        guard let h = priceHistory else { return false }
        var days = Set<String>()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for pt in h.history_points {
            days.insert(df.string(from: pt.parsedDate))
        }
        return days.count >= 2
    }

    private var shareAffiliateURL: URL {
        if let offer = currentOffer {
            return APIService.shared.affiliateShareURL(
                targetUrl: offer.url,
                storeId: offer.store_id,
                offerId: nil
            )
        } else if let first = product.offers.first {
            return APIService.shared.affiliateShareURL(
                targetUrl: first.url,
                storeId: first.store_id,
                offerId: nil
            )
        }
        return URL(string: "https://fitmatch.it")!
    }

    // MARK: - Body View

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background Navigation Links (Hidden)
            if let offer = currentOffer {
                NavigationLink(
                    destination: StoreDetailView(storeId: offer.store_id, initialStoreName: offer.store_name),
                    isActive: $navigateToStore
                ) { EmptyView() }
            }

            VStack(spacing: 0) {
                // Top Fixed Navigation Bar
                topNavigationBar
                    .shopHeaderBarPadding()
                    .background(Color.white)

                Divider()
                    .background(Color.shopBorder)

                // Main Scrollable Page (Comparator-First Architecture)
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            // 1. Store Header Profile Row
                            storeHeaderRow
                                .padding(.horizontal, ShopLayout.screenPadding)
                                .padding(.top, 14)
                                .padding(.bottom, 12)

                            // 2. Hero Product Image Showcase Card
                            heroImageCard
                                .padding(.horizontal, ShopLayout.screenPadding)
                                .padding(.bottom, displayedImages.count > 1 ? 10 : ShopLayout.cardSpacing)

                            if displayedImages.count > 1 {
                                galleryThumbnailStrip
                                    .padding(.bottom, ShopLayout.cardSpacing)
                            }

                            // 3. Product Title & Wishlist Heart
                            titleAndActionRow
                                .padding(.horizontal, ShopLayout.screenPadding)
                                .padding(.bottom, ShopLayout.tightSpacing)

                            // 4. Status / Verified All-Time-Low Badge (only when meaningful, zero duplication)
                            stockBadgeRow
                                .padding(.horizontal, ShopLayout.screenPadding)

                            // 5. Price, Real Shipping Summary & Quick Jump to Comparison
                            priceAndShippingSection(onJumpToOffers: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    scrollProxy.scrollTo("partner_offers_section", anchor: .top)
                                }
                            })
                            .padding(.horizontal, ShopLayout.screenPadding)
                            .padding(.bottom, ShopLayout.sectionSpacing)

                            // 6. Visual Colorway / Variant Selector (placed before sizes like Nike/Zalando)
                            if !availableVariantOptions.isEmpty {
                                colorSelectionSection
                                    .padding(.horizontal, ShopLayout.screenPadding)
                                    .padding(.bottom, ShopLayout.sectionSpacing)
                            }

                            // 7. Smart Size Selection Pills
                            if !allSizes.isEmpty {
                                sizeSelectionSection
                                    .padding(.horizontal, ShopLayout.screenPadding)
                                    .padding(.bottom, ShopLayout.sectionSpacing)
                            }

                            // 8. Primary CTA (Acquista) & Price Alert CTA (tracked for Sticky Bottom Bar)
                            ctaButtonsSection
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: PrimaryCTAMaxYKey.self,
                                            value: geo.frame(in: .named("productDetailScroll")).maxY
                                        )
                                    }
                                )
                                .padding(.horizontal, ShopLayout.screenPadding)
                                .padding(.bottom, 22)

                            Divider()
                                .background(Color.shopBorder)
                                .padding(.horizontal, ShopLayout.screenPadding)

                            // 9. Core Value First: Andamento Prezzi e Offerte Partner
                            partnerOffersSection
                                .id("partner_offers_section")
                                .padding(.horizontal, ShopLayout.screenPadding)

                            // 10. Accordion: Consegna e resi (collapsed by default, real store policies)
                            deliveryAccordion
                                .padding(.horizontal, ShopLayout.screenPadding)

                            // 11. Accordion: Dettagli prodotto (collapsed by default)
                            descriptionAccordion
                                .padding(.horizontal, ShopLayout.screenPadding)

                            // 12. Section: Potrebbe piacerti anche (category + gender + price aligned)
                            recommendationsSection
                                .padding(.top, ShopLayout.sectionSpacing)
                                .padding(.bottom, ShopLayout.bottomDetailClearance + 28)
                        }
                    }
                    .coordinateSpace(name: "productDetailScroll")
                    .onPreferenceChange(PrimaryCTAMaxYKey.self) { maxY in
                        let shouldShow = maxY < 10
                        if shouldShow != showStickyCTA {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                showStickyCTA = shouldShow
                            }
                        }
                    }
                }
            }

            // Sticky Bottom CTA Bar (appears cleanly once primary CTA scrolls out of view)
            if showStickyCTA, let offer = currentOffer {
                stickyBottomBar(offer: offer)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

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
                    .padding(.bottom, showStickyCTA ? 92 : 34)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAlertSheet) {
            PriceAlertSheet(product: wishlistProductSnapshot)
        }
        .sheet(isPresented: $showingMoveToCollection) {
            if let item = wishlistItem {
                MoveToCollectionSheet(item: item)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            let shareUrl = shareAffiliateURL
            let priceText = currentOffer?.formattedPrice ?? product.formattedBestPrice
            ShareSheet(items: [
                "Guarda \(product.cleanTitle) su FitMatch a \(priceText):",
                shareUrl
            ])
        }
        .sheet(isPresented: $showingReturnPolicySheet) {
            ReturnPolicySheetView(
                storeId: currentOffer?.store_id,
                storeName: currentOffer?.store_name ?? "Partner Store"
            )
        }
        .sheet(isPresented: $showingShippingInfoSheet) {
            ShippingInfoSheetView(
                storeId: currentOffer?.store_id,
                storeName: currentOffer?.store_name ?? "Partner Store",
                offer: currentOffer
            )
        }
        .fullScreenCover(isPresented: $showingFullScreenGallery) {
            FullScreenProductGalleryView(
                images: displayedImages,
                selectedIndex: $selectedImageIndex,
                productTitle: product.cleanTitle
            )
            .presentationBackground(.clear)
        }
        .onAppear {
            TabBarVisibilityManager.shared.hide(for: "product_detail")
            RecentActivityManager.shared.recordProductView(wishlistProductSnapshot)
        }
        .onDisappear {
            TabBarVisibilityManager.shared.show(for: "product_detail")
        }
        .onChange(of: currentOffer?.id) { _, _ in
            selectedImageIndex = 0
            scrolledImageIndex = 0
            inlineZoomScale = 1.0
            selectedVariant = currentOffer?.displayVariant
            let urls = displayedImages.compactMap { URL(string: $0) }
            ImageCacheManager.shared.prefetch(urls: urls, maxPixelSize: 1200)
        }
        .task {
            let galleryUrls = displayedImages.compactMap { URL(string: $0) }
            ImageCacheManager.shared.prefetch(urls: galleryUrls, maxPixelSize: 1200)
            async let historyTask: Void = loadPriceHistory()
            await hydrateMultiStoreOffersIfNeeded()
            await loadRelatedProducts()
            _ = await historyTask
        }
    }

    // MARK: - 1. Top Navigation Bar (Back Button, Search Pill & Share Button)

    private var topNavigationBar: some View {
        HStack(spacing: 12) {
            // Circular Back Button
            Button(action: {
                dismiss()
            }) {
                Circle()
                    .fill(Color.shopSurface)
                    .frame(width: ShopLayout.navButtonSize, height: ShopLayout.navButtonSize)
                    .overlay(
                        Circle().stroke(Color.shopBorder, lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.shopDark)
                    )
            }
            .buttonStyle(.plain)

            // Pill Search Bar (Tapping navigates cleanly to Search tab or dismisses if already from Search)
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                if openedFromSearch {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        NotificationCenter.default.post(name: NSNotification.Name("FitMatchFocusSearch"), object: nil)
                    }
                } else {
                    TabCoordinator.shared.selectTab(1, focusSearch: true, fromSource: "product_detail")
                }
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
                .frame(height: ShopLayout.navButtonSize)
                .background(Color.shopSurface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.shopBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Quick Share Button
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                showingShareSheet = true
            }) {
                Circle()
                    .fill(Color.shopSurface)
                    .frame(width: ShopLayout.navButtonSize, height: ShopLayout.navButtonSize)
                    .overlay(
                        Circle().stroke(Color.shopBorder, lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.shopDark)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 2. Store Header Row (Store Logo, Name, Verified Partner Badge, Menu ...)

    private var storeHeaderRow: some View {
        let storeName = currentOffer?.store_name ?? "Partner Store"
        let trust = StoreRatingHelper.trustDisplay(for: storeName, storeId: currentOffer?.store_id)

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

                            Text(trust.badgeText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            if let freshness = currentOffer?.freshnessLabel {
                                Text("·")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)
                                Text(freshness)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(currentOffer?.isStaleOffer == true ? Color(red: 175/255, green: 105/255, blue: 15/255) : .secondary)
                                    .lineLimit(1)
                            }
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
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(displayedImages.enumerated()), id: \.offset) { index, imgUrl in
                            Group {
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
                                                .scaleEffect(index == selectedImageIndex ? inlineZoomScale : 1.0, anchor: inlineZoomAnchor)
                                                .transition(.opacity)
                                        } else {
                                            ShopSkeletonBlock(cornerRadius: 24, height: 290)
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(height: 330)
                            .containerRelativeFrame(.horizontal)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1.0 : 0.92)
                                    .opacity(phase.isIdentity ? 1.0 : 0.65)
                            }
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .frame(height: 330)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrolledImageIndex)
                .scrollDisabled(inlineZoomScale > 1.02)
                .id(currentOffer?.id ?? product.id)
                .onChange(of: scrolledImageIndex) { _, newValue in
                    if let idx = newValue, idx != selectedImageIndex {
                        withAnimation(ShopMotion.gallerySpring) {
                            selectedImageIndex = idx
                        }
                    }
                }
                .onChange(of: selectedImageIndex) { _, newValue in
                    if scrolledImageIndex != newValue {
                        withAnimation(ShopMotion.gallerySpring) {
                            scrolledImageIndex = newValue
                        }
                    }
                }

                // Bottom Overlay: Modern Pill Indicator Dots + Fullscreen Expand Button
                ZStack {
                    HStack(spacing: 5) {
                        ForEach(0..<min(displayedImages.count, 7), id: \.self) { idx in
                            Capsule()
                                .fill(selectedImageIndex == idx ? Color.shopDark : Color.black.opacity(0.18))
                                .frame(width: selectedImageIndex == idx ? 16 : 6, height: 6)
                                .animation(ShopMotion.pillSlide, value: selectedImageIndex)
                        }
                        if displayedImages.count > 7 {
                            Text("+\(displayedImages.count - 7)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.88))
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)

                    HStack {
                        Spacer()
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showingFullScreenGallery = true
                        }) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.shopDark)
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.9))
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.90))
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 12)
                .opacity(inlineZoomScale > 1.04 ? 0 : 1)
                .animation(.easeOut(duration: 0.16), value: inlineZoomScale > 1.04)
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
                            .scaleEffect(inlineZoomScale, anchor: inlineZoomAnchor)
                            .transition(.opacity)
                    } else {
                        ShopSkeletonBlock(cornerRadius: 24, height: 290)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 330)
                .overlay(alignment: .bottomTrailing) {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingFullScreenGallery = true
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.shopDark)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.9))
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.90))
                    .padding(12)
                    .opacity(inlineZoomScale > 1.04 ? 0 : 1)
                }
            } else {
                Rectangle()
                    .fill(Color(red: 244/255, green: 244/255, blue: 246/255))
                    .frame(height: 330)
                    .frame(maxWidth: .infinity)
            }

            if inlineZoomScale > 1.04 {
                VStack {
                    HStack {
                        Spacer()
                        Text(String(format: "%.1fx", inlineZoomScale))
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.shopDark.opacity(0.82))
                            .clipShape(Capsule())
                            .padding(12)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .frame(height: 330)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color(red: 236/255, green: 237/255, blue: 240/255), lineWidth: 0.8)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    guard !displayedImages.isEmpty || product.image_url != nil else { return }
                    inlineZoomAnchor = value.startAnchor
                    let raw = value.magnification
                    inlineZoomScale = raw > 2.8 ? 2.8 + (raw - 2.8) * 0.25 : max(0.96, raw)
                }
                .onEnded { _ in
                    withAnimation(ShopMotion.gallerySpring) {
                        inlineZoomScale = 1.0
                        inlineZoomAnchor = .center
                    }
                }
        )
        .onTapGesture {
            guard !displayedImages.isEmpty || product.image_url != nil else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showingFullScreenGallery = true
        }
        .contextMenu {
            let isSaved = wishlist.isFavorite(product.canonical_name)
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                wishlist.toggleFavorite(product: wishlistProductSnapshot, selectedSize: selectedSize)
            }) {
                Label(
                    isSaved ? "Rimuovi dai preferiti" : "Salva nei preferiti",
                    systemImage: isSaved ? "heart.slash" : "heart.fill"
                )
            }

            Button(action: { showingFullScreenGallery = true }) {
                Label("Espandi galleria immagini", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Button(action: { showingShareSheet = true }) {
                Label("Condividi prodotto", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var galleryThumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(displayedImages.enumerated()), id: \.offset) { idx, imgUrl in
                        let isSelected = selectedImageIndex == idx
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(ShopMotion.gallerySpring) {
                                selectedImageIndex = idx
                                scrolledImageIndex = idx
                            }
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.shopSurface)

                                if let url = URL(string: imgUrl) {
                                    ShopCachedAsyncImage(url: url, maxPixelSize: 280) { phase in
                                        if let image = phase.image {
                                            image
                                                .resizable()
                                                .scaledToFit()
                                                .padding(5)
                                                .transition(.opacity)
                                        } else {
                                            ShopSkeletonBlock(cornerRadius: 12)
                                        }
                                    }
                                }
                            }
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.shopBorder, lineWidth: 1)
                            )
                            .overlay {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.shopPurple, lineWidth: 2)
                                        .matchedGeometryEffect(id: "detail_thumb_ring", in: galleryThumbNamespace)
                                }
                            }
                            .opacity(isSelected ? 1.0 : 0.74)
                            .scaleEffect(isSelected ? 1.0 : 0.96)
                            .animation(ShopMotion.pillSlide, value: selectedImageIndex)
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.94))
                        .id(idx)
                    }
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.vertical, 2)
            }
            .onChange(of: selectedImageIndex) { _, newIndex in
                withAnimation(ShopMotion.gallerySpring) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - 4. Title & Wishlist Heart (Share lives cleanly in topNavigationBar without duplication)

    private var titleAndActionRow: some View {
        HStack(alignment: .top, spacing: 12) {
            // Product Title
            Text(product.cleanTitle)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Heart Wishlist Toggle Button
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                    wishlist.toggleFavorite(product: wishlistProductSnapshot, selectedSize: selectedSize)
                }
                cartToastMessage = isWishlisted ? "Salvato nei tuoi preferiti" : "Rimosso dai preferiti"
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showCartToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation { showCartToast = false }
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
            .accessibilityLabel(isWishlisted ? "Rimuovi dai preferiti" : "Salva nei preferiti")
        }
    }

    // MARK: - 5. Stock & Verified All-Time Low Badge (no duplicate discount badge)

    @ViewBuilder
    private var stockBadgeRow: some View {
        if let current = currentOffer, current.in_stock == false {
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
            .padding(.bottom, 8)
        } else if hasVerifiedPriceHistoryChart, priceHistory?.is_all_time_low == true {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                    Text("Minimo storico verificato")
                        .font(.system(size: 11.5, weight: .bold))
                }
                .foregroundColor(.shopPurple)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.shopPurpleLight)
                .clipShape(Capsule())
                Spacer()
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - 6. Price, Real Shipping Summary & Quick Multi-Store Comparison Pill

    private func priceAndShippingSection(onJumpToOffers: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(currentOffer?.formattedPrice ?? product.formattedBestPrice)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                    .contentTransition(.numericText())

                if let current = currentOffer, let orig = current.formattedOriginalPrice {
                    Text(orig)
                        .font(.system(size: 16))
                        .strikethrough()
                        .foregroundColor(.shopTextMuted)
                        .contentTransition(.numericText())
                }

                if let current = currentOffer, let badge = current.discountBadge {
                    DiscountBadge(discountText: badge)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .animation(ShopMotion.pillSlide, value: currentOffer?.id ?? "")

            // Real Shipping Summary (replaces hardcoded "Spedizione calcolata al check-out")
            if let offer = currentOffer {
                HStack(spacing: 6) {
                    Image(systemName: offer.isFreeShipping ? "shippingbox.fill" : "box.truck")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(offer.isFreeShipping ? .shopGreen : .shopTextMuted)

                    Text(offer.shippingSummaryLine)
                        .font(.system(size: 13, weight: offer.isFreeShipping ? .semibold : .regular))
                        .foregroundColor(offer.isFreeShipping ? .shopGreen : .shopTextMuted)
                        .lineLimit(2)
                }
            }

            // Quick Multi-Store Comparison Jump Pill
            if distinctStoreCount > 1, let best = bestMarketOffer {
                let savings = product.cross_store_savings ?? 0
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onJumpToOffers()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.shopPurple)

                        if savings > 1.0 {
                            Text("Confronta \(distinctStoreCount) negozi · da \(best.formattedPrice) (risparmi €\(String(format: "%.0f", savings)))")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(.shopDark)
                                .lineLimit(1)
                        } else {
                            Text("Confronta \(distinctStoreCount) negozi · da \(best.formattedPrice)")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(.shopDark)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.shopPurple)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.shopPurpleLight.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.shopPurple.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - 7. Smart Size Selection Pills

    private var sizeSelectionSection: some View {
        let storesWithSelectedSize: Int = {
            guard let sz = selectedSize else { return 0 }
            return Set(product.offers.filter { $0.hasSize(sz) }.map { $0.store_id.lowercased() }).count
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Taglia")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.shopDark)

                Spacer()

                if let sz = selectedSize {
                    if let pref = userPreferredSize, sz == pref {
                        Text("Tua taglia (\(pref))\(storesWithSelectedSize > 1 ? " · \(storesWithSelectedSize) negozi" : "")")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.shopPurple)
                    } else if storesWithSelectedSize > 0 {
                        Text("\(storesWithSelectedSize) \(storesWithSelectedSize == 1 ? "negozio" : "negozi") con tg. \(sz)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.shopGreen)
                    }
                } else if let pref = userPreferredSize, allSizes.contains(pref) {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectSize(pref)
                    }) {
                        Text("Seleziona tua tg. \(pref)")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.shopPurple)
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74, maximum: 92), spacing: 8)], spacing: 8) {
                ForEach(visibleSizes, id: \.self) { sz in
                    let isSel = (selectedSize == sz)
                    let onCurrentOffer = currentOffer?.hasSize(sz) ?? true
                    let isOtherStoreOnly = !onCurrentOffer && (currentOffer?.hasKnownSizes == true)
                    let isPref = (userPreferredSize == sz)

                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectSize(sz)
                    }) {
                        HStack(spacing: 3) {
                            Text(sz)
                                .font(.system(size: 14, weight: isSel ? .bold : .semibold))
                            if isPref && !isSel {
                                Circle()
                                    .fill(Color.shopPurple)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .foregroundColor(isSel ? .white : (isOtherStoreOnly ? .shopTextMuted : .shopDark))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(isSel ? Color.shopDark : (isOtherStoreOnly ? Color.shopSurface.opacity(0.65) : Color.white))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(
                                isSel ? Color.shopDark : (isPref ? Color.shopPurple.opacity(0.55) : Color(red: 226/255, green: 227/255, blue: 231/255)),
                                style: isOtherStoreOnly && !isSel ? StrokeStyle(lineWidth: 1, dash: [4, 3]) : StrokeStyle(lineWidth: 1)
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Expand / Collapse Pill Button
                if allSizes.count > 6 {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            isExpandedSizes.toggle()
                        }
                    }) {
                        Text(isExpandedSizes ? "Mostra meno" : "+\(allSizes.count - 6) taglie")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.shopDark)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Color.shopSurface)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color(red: 226/255, green: 227/255, blue: 231/255), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if currentOffer?.hasKnownSizes == true,
               allSizes.contains(where: { currentOffer?.hasSize($0) == false }) {
                Text("Le taglie tratteggiate sono disponibili su un altro negozio o colorazione partner.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.shopTextMuted)
            }
        }
    }

    private func selectSize(_ sz: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            if selectedSize == sz {
                selectedSize = nil
            } else {
                selectedSize = sz
                // Keep current offer/colorway if it already has this size;
                // otherwise switch to the best total-price store offer carrying it.
                let currentHasSize = product.offers.indices.contains(selectedOfferIndex)
                    && product.offers[selectedOfferIndex].hasSize(sz)
                if !currentHasSize,
                   let bestForSize = product.bestOffer(for: sz),
                   bestForSize.hasSize(sz),
                   let idx = product.offers.firstIndex(where: { $0.id == bestForSize.id }) {
                    selectedOfferIndex = idx
                }
            }
        }
    }

    // MARK: - 8. Visual Color / Variant Selection (works with or without color text in titles)

    private var colorSelectionSection: some View {
        let options = availableVariantOptions
        let activeOption = options.first(where: { $0.offerIndices.contains(selectedOfferIndex) })
            ?? options.first(where: {
                guard let lbl = $0.label?.lowercased(),
                      let cur = (currentOffer?.displayVariant ?? selectedVariant)?.lowercased() else { return false }
                return lbl == cur
            })
        let allVisualOnly = options.allSatisfy { $0.label == nil }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(allVisualOnly ? "Colorazione" : "Colore")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.shopDark)

                if let activeLabel = activeOption?.label {
                    Text("· \(activeLabel)")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                        .lineLimit(1)
                }

                Spacer()

                if options.count > 1 {
                    Text("\(options.count) varianti")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.shopTextMuted)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(options) { opt in
                        let isSel = (activeOption?.id == opt.id)
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selectedVariant = opt.label
                                selectedOfferIndex = opt.bestOfferIndex
                            }
                        }) {
                            if let label = opt.label {
                                HStack(spacing: 7) {
                                    if let imgStr = opt.previewImage, let url = URL(string: imgStr) {
                                        ShopCachedAsyncImage(url: url, maxPixelSize: 120) { phase in
                                            if let img = phase.image {
                                                img
                                                    .resizable()
                                                    .scaledToFit()
                                                    .padding(2)
                                            } else {
                                                Color.shopSurface
                                            }
                                        }
                                        .frame(width: 26, height: 26)
                                        .background(Color.shopSurface)
                                        .clipShape(Circle())
                                    }

                                    Text(label)
                                        .font(.system(size: 13.5, weight: isSel ? .bold : .semibold))
                                        .foregroundColor(isSel ? .white : .shopDark)
                                        .lineLimit(1)
                                }
                                .padding(.leading, opt.previewImage != nil ? 7 : 14)
                                .padding(.trailing, 14)
                                .frame(height: 40)
                                .background(isSel ? Color.shopDark : Color.white)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(
                                        isSel ? Color.shopDark : Color(red: 226/255, green: 227/255, blue: 231/255),
                                        lineWidth: isSel ? 1.5 : 1
                                    )
                                )
                            } else {
                                // Visual swatch card when store titles do not include color names
                                VStack(spacing: 4) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.shopSurface)

                                        if let imgStr = opt.previewImage, let url = URL(string: imgStr) {
                                            ShopCachedAsyncImage(url: url, maxPixelSize: 200) { phase in
                                                if let img = phase.image {
                                                    img
                                                        .resizable()
                                                        .scaledToFit()
                                                        .padding(5)
                                                } else {
                                                    ShopSkeletonBlock(cornerRadius: 12)
                                                }
                                            }
                                        }
                                    }
                                    .frame(width: 58, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(isSel ? Color.shopPurple : Color.shopBorder, lineWidth: isSel ? 2 : 1)
                                    )

                                    Text(String(format: "€%.0f", opt.minPrice))
                                        .font(.system(size: 11, weight: isSel ? .bold : .semibold, design: .rounded))
                                        .foregroundColor(isSel ? .shopPurple : .shopTextMuted)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 9. Primary CTA (Acquista) & Price Alert CTA (replaces duplicate Wishlist button)

    private var ctaButtonsSection: some View {
        VStack(spacing: 10) {
            // 1. Primary Vibrant CTA Button: "Acquista su [Store]" with size verification
            if let offer = currentOffer, let _ = URL(string: offer.url) {
                let hasSize = (selectedSize == nil) || offer.hasSize(selectedSize)
                let outboundUrl = APIService.shared.outboundRedirectURL(
                    targetUrl: offer.url,
                    storeId: offer.store_id,
                    offerId: offer.id,
                    source: "product_detail"
                )

                if hasSize {
                    Link(destination: outboundUrl) {
                        HStack(spacing: 8) {
                            Image(systemName: "cart.fill")
                                .font(.system(size: 15))
                            if let sz = selectedSize {
                                Text("Acquista tg. \(sz) su \(offer.store_name)")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                            } else {
                                Text("Acquista su \(offer.store_name)")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                            }
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12.5, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .padding(.horizontal, 14)
                        .background(Color.shopPurple)
                        .clipShape(Capsule())
                        .shadow(color: Color.shopPurple.opacity(0.28), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                } else if let sz = selectedSize, let altOffer = product.bestOffer(for: sz), altOffer.hasSize(sz) {
                    // Current store does not have size, but partner store has it!
                    Button(action: {
                        if let idx = product.offers.firstIndex(where: { $0.id == altOffer.id }) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                selectedOfferIndex = idx
                            }
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 14, weight: .bold))
                            Text("Tg. \(sz) disp. su \(altOffer.store_name) (\(altOffer.formattedPrice))")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .padding(.horizontal, 14)
                        .background(Color.shopGreen)
                        .clipShape(Capsule())
                        .shadow(color: Color.shopGreen.opacity(0.28), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                } else if let sz = selectedSize {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 15))
                        Text("Taglia \(sz) esaurita in tutti gli store")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(red: 240/255, green: 241/255, blue: 245/255))
                    .clipShape(Capsule())
                }
            }

            // 2. Secondary High-Value Comparator CTA: "Avvisami quando il prezzo scende"
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingAlertSheet = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(.shopPurple)
                    Text("Avvisami quando il prezzo scende")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.shopSurface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.shopBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sticky Bottom Purchase Bar

    private func stickyBottomBar(offer: Offer) -> some View {
        let hasSize = (selectedSize == nil) || offer.hasSize(selectedSize)
        let outboundUrl = APIService.shared.outboundRedirectURL(
            targetUrl: offer.url,
            storeId: offer.store_id,
            offerId: offer.id,
            source: "product_detail_sticky"
        )

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(offer.formattedPrice)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.shopDark)
                        .contentTransition(.numericText())
                    Text(offer.isFreeShipping ? "Sped. gratis" : offer.formattedShipping)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(offer.isFreeShipping ? .shopGreen : .shopTextMuted)
                        .lineLimit(1)
                }
                Text(offer.store_name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.shopTextMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingAlertSheet = true
            }) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.shopDark)
                    .frame(width: 42, height: 42)
                    .background(Color.shopSurface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.shopBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Avviso prezzo")

            if hasSize {
                Link(destination: outboundUrl) {
                    HStack(spacing: 5) {
                        Text(selectedSize != nil ? "Acquista tg. \(selectedSize!)" : "Acquista")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .background(Color.shopPurple)
                    .clipShape(Capsule())
                    .shadow(color: Color.shopPurple.opacity(0.25), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            } else if let sz = selectedSize, let altOffer = product.bestOffer(for: sz), altOffer.hasSize(sz) {
                Button(action: {
                    if let idx = product.offers.firstIndex(where: { $0.id == altOffer.id }) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedOfferIndex = idx
                        }
                    }
                }) {
                    Text("Vedi su \(altOffer.store_name)")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(Color.shopGreen)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ShopLayout.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().background(Color.shopBorder)
        }
    }

    // MARK: - 10. Dettagli prodotto Accordion

    private var descriptionAccordion: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isDescriptionExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Dettagli prodotto")
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

                    if let cat = product.category, !cat.isEmpty, cat.lowercased() != "gear" {
                        HStack(spacing: 6) {
                            Text("Categoria:")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundColor(.shopDark)
                            Text(cat.replacingOccurrences(of: "_", with: " ").capitalized)
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
                            Text("Store attivo:")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundColor(.shopDark)
                            Text(current.store_name)
                                .font(.system(size: 13.5))
                                .foregroundColor(.shopTextMuted)
                        }

                        if let freshness = current.freshnessLabel {
                            HStack(spacing: 6) {
                                Text("Ultimo controllo:")
                                    .font(.system(size: 13.5, weight: .bold))
                                    .foregroundColor(.shopDark)
                                Text(freshness)
                                    .font(.system(size: 13.5))
                                    .foregroundColor(current.isStaleOffer ? Color(red: 175/255, green: 105/255, blue: 15/255) : .shopTextMuted)
                            }
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
                            Text("Taglie rilevate:")
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

    // MARK: - 11. Consegna e resi Accordion (Real Store Policies from Supabase)

    private var deliveryAccordion: some View {
        let storeMeta = currentOffer.flatMap {
            DynamicCatalogRegistry.shared.storeItem(for: $0.store_id)
                ?? DynamicCatalogRegistry.shared.storeItem(for: $0.store_name)
        }
        let refundSummary = storeMeta?.refund_policy?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shippingPolicy = storeMeta?.shipping_policy?.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 0) {
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

                    if !isDeliveryExpanded, let offer = currentOffer {
                        Text(offer.isFreeShipping ? "Sped. gratis" : offer.formattedShipping)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(offer.isFreeShipping ? .shopGreen : .shopTextMuted)
                            .padding(.trailing, 4)
                    }

                    Image(systemName: isDeliveryExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.shopDark)
                }
                .padding(.vertical, 18)
            }
            .buttonStyle(.plain)

            if isDeliveryExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Truck: Real Shipping Summary & Policy
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "box.truck.fill")
                            .font(.system(size: 16))
                            .foregroundColor(currentOffer?.isFreeShipping == true ? .shopGreen : .shopDark)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(currentOffer?.shippingSummaryLine ?? "Spedizione calcolata al check-out")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.shopDark)

                            if let policy = shippingPolicy, !policy.isEmpty {
                                Text(policy)
                                    .font(.system(size: 12.5))
                                    .foregroundColor(.shopTextMuted)
                            }
                        }
                    }

                    // Return Box: Real Store Refund Policy
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.shopDark)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Reso e rimborso")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.shopDark)
                            Text(
                                (refundSummary != nil && !refundSummary!.isEmpty)
                                    ? refundSummary!
                                    : "Gestito direttamente da \(currentOffer?.store_name ?? "store partner") secondo i termini del rivenditore."
                            )
                            .font(.system(size: 12.5))
                            .foregroundColor(.shopTextMuted)
                        }
                    }

                    // Action Pill Buttons (clean full labels, zero manual truncation)
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
                            Text("Info spedizioni")
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
                                Image(systemName: "storefront")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Visita vetrina \(offer.store_name)")
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

    // MARK: - 12. Andamento Prezzi e Offerte Partner (Comparator Core Section)

    private var partnerOffersSection: some View {
        let bestId = bestMarketOffer?.id
        let totalOfferCount = sortedOffers.count
        let displayedList = visibleSortedOffers

        return VStack(alignment: .leading, spacing: 18) {
            // Section Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Offerte e andamento prezzi")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Spacer()

                    Text(
                        product.offers.count > distinctStoreCount
                            ? "\(distinctStoreCount) \(distinctStoreCount == 1 ? "negozio" : "negozi") · \(product.offers.count) off."
                            : "\(distinctStoreCount) \(distinctStoreCount == 1 ? "negozio" : "negozi")"
                    )
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.shopPurple)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.shopPurpleLight)
                    .clipShape(Capsule())

                    if isHydratingOffers {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.shopPurple)
                    }
                }

                if distinctStoreCount > 1, let savings = product.cross_store_savings, savings > 1.0 {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Risparmi fino a €\(String(format: "%.2f", savings)) confrontando i negozi · ordinati per prezzo totale")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundColor(.shopGreen)
                } else {
                    Text("Ordinate per prezzo totale inclusa spedizione")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                }
            }
            .padding(.top, 16)

            // 1. Partner Offers List (shown immediately for fast comparison)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(totalOfferCount > 1 ? "Tutte le offerte (\(totalOfferCount))" : "Offerta verificata")
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Spacer()

                    if let sz = selectedSize {
                        HStack(spacing: 4) {
                            Text("Filtro:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                            Text("Tg. \(sz)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.shopPurple)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.shopPurpleLight)
                        .clipShape(Capsule())
                    }
                }
                .padding(.top, 2)

                ForEach(displayedList, id: \.offer.id) { item in
                    let index = item.index
                    let offer = item.offer
                    let hasSize = item.hasSize
                    let isSelected = (index == selectedOfferIndex)
                    let isBest = (offer.id == bestId)
                    let trust = StoreRatingHelper.trustDisplay(for: offer.store_name, storeId: offer.store_id)
                    let outboundUrl = APIService.shared.outboundRedirectURL(
                        targetUrl: offer.url,
                        storeId: offer.store_id,
                        offerId: offer.id,
                        source: "partner_offers_list"
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        // Header Row: Optional Offer Colorway Thumb, Store Logo, Store Name, Trust & Pricing
                        HStack(alignment: .top, spacing: 11) {
                            if hasMultipleDistinctOfferImages,
                               let imgStr = offer.image_url?.trimmingCharacters(in: .whitespacesAndNewlines),
                               let thumbUrl = URL(string: imgStr) {
                                ShopCachedAsyncImage(url: thumbUrl, maxPixelSize: 220) { phase in
                                    if let img = phase.image {
                                        img
                                            .resizable()
                                            .scaledToFit()
                                            .padding(4)
                                    } else {
                                        ShopSkeletonBlock(cornerRadius: 10)
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .background(Color.shopSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: isSelected ? 1.5 : 0.8)
                                )
                            } else {
                                ShopStoreLogo(storeName: offer.store_name, showVerified: false, showLabel: false, size: 38)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    Text(offer.store_name)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopDark)
                                        .lineLimit(1)

                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.shopPurple)
                                }

                                // Official Store Badge or Trustpilot Rating + Freshness
                                HStack(spacing: 4) {
                                    if let ratingText = trust.ratingText, let reviewsText = trust.reviewsText {
                                        HStack(spacing: 2) {
                                            Image(systemName: "star.fill")
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.shopOrange)
                                            Text(ratingText)
                                                .font(.system(size: 11.5, weight: .bold))
                                                .foregroundColor(.shopDark)
                                        }
                                        Text("(\(reviewsText))")
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.shopTextMuted)
                                    } else {
                                        Text(trust.badgeText)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.shopPurple)
                                    }

                                    if let freshness = offer.freshnessLabel {
                                        Text("· \(freshness)")
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundColor(offer.isStaleOffer ? Color(red: 175/255, green: 105/255, blue: 15/255) : .shopTextMuted)
                                            .lineLimit(1)
                                    }
                                }
                            }

                            Spacer()

                            // Price & Discount Column
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(offer.formattedPrice)
                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                    .foregroundColor(.shopDark)

                                HStack(spacing: 4) {
                                    if let orig = offer.formattedOriginalPrice {
                                        Text(orig)
                                            .font(.system(size: 11.5))
                                            .strikethrough()
                                            .foregroundColor(.shopTextMuted)
                                    }

                                    if let badge = offer.discountBadge {
                                        Text(badge)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(Color(red: 220/255, green: 38/255, blue: 38/255))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(Color(red: 254/255, green: 242/255, blue: 242/255))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        // Middle Row: Badges, Availability & Shipping Detail
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                if isBest {
                                    BestPriceBadge()
                                }

                                if let v = offer.displayVariant, !v.isEmpty {
                                    HStack(spacing: 3) {
                                        Image(systemName: "paintpalette.fill")
                                            .font(.system(size: 9))
                                        Text(v)
                                            .font(.system(size: 10.5, weight: .medium))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(.shopTextMuted)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(Color(red: 244/255, green: 245/255, blue: 248/255))
                                    .clipShape(Capsule())
                                }

                                Spacer()

                                // Shipping badge / total cost
                                HStack(spacing: 4) {
                                    if offer.isFreeShipping {
                                        HStack(spacing: 3) {
                                            Image(systemName: "shippingbox.fill")
                                                .font(.system(size: 9.5))
                                            Text("Sped. Gratis")
                                                .font(.system(size: 10.5, weight: .bold))
                                        }
                                        .foregroundColor(.shopGreen)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2.5)
                                        .background(Color.shopGreenLight)
                                        .clipShape(Capsule())
                                    } else {
                                        Text(offer.formattedShipping)
                                            .font(.system(size: 11))
                                            .foregroundColor(.shopTextMuted)
                                    }

                                    Text("• Tot. \(offer.formattedTotalPrice)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.shopDark)
                                }
                            }

                            // Size Availability Info (transparent handling of verified vs unverified feed sizes)
                            let hasUnverifiedSizes = (offer.available_sizes ?? []).isEmpty
                            if let sz = selectedSize {
                                let sizeDisplay = sz.first?.isNumber == true ? "EU \(sz)" : sz
                                if hasSize {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.shopGreen)
                                        Text("Disponibile in taglia \(sizeDisplay)")
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundColor(.shopGreen)
                                    }
                                } else if hasUnverifiedSizes {
                                    HStack(spacing: 4) {
                                        Image(systemName: "info.circle")
                                            .font(.system(size: 10.5))
                                            .foregroundColor(Color(red: 180/255, green: 110/255, blue: 20/255))
                                        Text("Taglia \(sizeDisplay) da verificare sul sito")
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundColor(Color(red: 160/255, green: 98/255, blue: 18/255))
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.circle")
                                            .font(.system(size: 10.5))
                                            .foregroundColor(Color.secondary)
                                        Text("Taglia \(sizeDisplay) non disponibile su questo store")
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundColor(Color.secondary)
                                    }
                                }
                            } else if let sizes = offer.available_sizes, !sizes.isEmpty {
                                HStack(spacing: 4) {
                                    Text("Taglie:")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.shopTextMuted)
                                    Text(sizes.prefix(7).joined(separator: ", ") + (sizes.count > 7 ? "..." : ""))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.shopDark.opacity(0.85))
                                        .lineLimit(1)
                                }
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 10))
                                        .foregroundColor(.shopTextMuted)
                                    Text("Taglie da verificare sul sito")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.shopTextMuted)
                                }
                            }
                        }

                        // Direct Action CTA Button to Open Store Link
                        let ctaUnverifiedSizes = (offer.available_sizes ?? []).isEmpty
                        Link(destination: outboundUrl) {
                            HStack(spacing: 8) {
                                Image(systemName: "cart.fill")
                                    .font(.system(size: 13, weight: .semibold))

                                if let sz = selectedSize, !hasSize {
                                    if ctaUnverifiedSizes {
                                        Text("Verifica tg. \(sz) su \(offer.store_name)")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .lineLimit(1)
                                    } else {
                                        Text("Offerta \(offer.store_name) (tg. \(sz) esaurita)")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .lineLimit(1)
                                    }
                                } else {
                                    Text("Vedi offerta su \(offer.store_name)")
                                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                        .lineLimit(1)
                                }

                                Spacer()

                                HStack(spacing: 4) {
                                    Text(offer.formattedTotalPrice)
                                        .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 11, weight: .bold))
                                }
                            }
                            .foregroundColor((isBest && hasSize) ? .white : .shopDark)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background((isBest && hasSize) ? Color.shopPurple : Color(red: 244/255, green: 245/255, blue: 248/255))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke((isBest && hasSize) ? Color.clear : Color(red: 228/255, green: 229/255, blue: 234/255), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(isSelected ? Color.shopPurpleLight.opacity(0.25) : Color.white)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.shopPurple.opacity(0.45) : Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: isSelected ? 1.5 : 1)
                    )
                    .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                            selectedOfferIndex = index
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }

                // Expand / Collapse Button for large multi-variant clusters (> 5 offers)
                if totalOfferCount > 5 {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isExpandedOffers.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text(
                                isExpandedOffers
                                    ? "Mostra meno offerte"
                                    : "Mostra tutte le \(totalOfferCount) offerte (+\(totalOfferCount - displayedList.count))"
                            )
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            Image(systemName: isExpandedOffers ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11.5, weight: .bold))
                        }
                        .foregroundColor(.shopPurple)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.shopPurpleLight.opacity(0.5))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)

            // 2. Honest Price History Card (renders chart only with >=2 real observations, else compact alert card)
            if let history = priceHistory {
                PriceHistorySectionView(history: history, onRequestPriceAlert: {
                    showingAlertSheet = true
                })
            } else if isLoadingPriceHistory {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        ProgressView().tint(.shopPurple)
                        Text("Caricamento andamento prezzi...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .background(Color.white)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
                )
            }

            Divider()
                .background(Color(red: 235/255, green: 236/255, blue: 240/255))
                .padding(.top, 8)
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
                            .buttonStyle(ShopCardPressStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Data Fetching

    private func hydrateMultiStoreOffersIfNeeded() async {
        guard !hasHydratedOffers else { return }
        // Hydrate sibling partner store offers whenever opened from a single-offer card (Deals / Home / StoreDetail / Wishlist)
        let candidateProductId = product.offers.first?.product_id ?? product.id_val
        guard let pid = candidateProductId?.trimmingCharacters(in: .whitespacesAndNewlines), !pid.isEmpty else {
            hasHydratedOffers = true
            return
        }
        // Only skip when we already have multiple distinct stores, gallery, category, and freshness timestamps
        let currentDistinctStores = Set(product.offers.map { $0.store_id.lowercased() }).count
        let hasFreshness = product.offers.contains { ($0.last_checked_at ?? "").isEmpty == false }
        if currentDistinctStores > 1 && !(product.gallery_images ?? []).isEmpty && product.category != nil && hasFreshness {
            hasHydratedOffers = true
            return
        }

        await MainActor.run { isHydratingOffers = true }
        defer {
            Task { @MainActor in
                self.isHydratingOffers = false
                self.hasHydratedOffers = true
            }
        }

        guard let hydrated = await SupabaseManager.shared.fetchHydratedProductDirect(
            productId: pid,
            preferredOfferUrl: initialTappedOfferURL
        ) else {
            return
        }

        await MainActor.run {
            // Ensure the exact offer tapped by the user is NEVER dropped (even if the cluster has >80 offers)
            var mergedOffers = hydrated.offers
            if let tapped = initialTappedOffer,
               !tapped.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !mergedOffers.contains(where: { $0.url == tapped.url }) {
                mergedOffers.append(tapped)
                mergedOffers.sort { $0.price < $1.price }
            }

            // Preserve the user's tapped store/offer index so the hero image, price, and link never swap unexpectedly
            var targetIdx = 0
            if let tappedURL = initialTappedOfferURL,
               let exactIdx = mergedOffers.firstIndex(where: { $0.url == tappedURL }) {
                targetIdx = exactIdx
            } else if let tappedStore = initialTappedStoreId?.lowercased(),
                      let storeIdx = mergedOffers.firstIndex(where: { $0.store_id.lowercased() == tappedStore }) {
                targetIdx = storeIdx
            }

            let targetOffer = mergedOffers.indices.contains(targetIdx) ? mergedOffers[targetIdx] : mergedOffers.first
            let minPrice = mergedOffers.map(\.price).min() ?? hydrated.best_price
            let maxPrice = mergedOffers.map(\.price).max() ?? hydrated.highest_price
            let distinctStoreCount = Set(mergedOffers.map { $0.store_id.lowercased() }).count
            let crossSavings: Double? = {
                if let mn = minPrice, let mx = maxPrice, distinctStoreCount > 1, mx - mn > 1.0 {
                    return mx - mn
                }
                return hydrated.cross_store_savings
            }()

            let finalProduct = MatchedProduct(
                id_val: hydrated.id_val,
                canonical_name: hydrated.canonical_name,
                brand: hydrated.brand,
                category: hydrated.category ?? product.category,
                image_url: targetOffer?.allImages.first ?? hydrated.image_url,
                gallery_images: hydrated.gallery_images,
                gender: hydrated.gender,
                offers: mergedOffers,
                best_price: minPrice,
                highest_price: maxPrice,
                cross_store_savings: crossSavings
            )

            withAnimation(.easeInOut(duration: 0.22)) {
                self.product = finalProduct
                self.selectedOfferIndex = targetIdx
                self.selectedVariant = targetOffer?.displayVariant
                // Only auto-select preferred size if the user's tapped offer actually has it,
                // preventing hydration from jumping away from the clicked product/colorway.
                if self.selectedSize == nil, let pref = self.userPreferredSize,
                   targetOffer?.hasSize(pref) == true {
                    self.selectedSize = pref
                }
            }

            let activeUrls = (targetOffer?.allImages ?? []).compactMap { URL(string: $0) }
            ImageCacheManager.shared.prefetch(urls: activeUrls, maxPixelSize: 1200)
            let partnerThumbs = mergedOffers.prefix(15).compactMap { $0.image_url.flatMap(URL.init) }
            ImageCacheManager.shared.prefetch(urls: partnerThumbs, maxPixelSize: 400)
        }
    }

    private func loadPriceHistory() async {
        guard priceHistory == nil else { return }
        isLoadingPriceHistory = true
        let resolvedPid = product.offers.first?.product_id ?? product.id_val
        do {
            let res = try await APIService.shared.fetchPriceHistory(
                canonicalName: product.canonical_name,
                productId: resolvedPid
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
        await MainActor.run { isLoadingRelated = true }

        let resolvedPid = product.offers.first?.product_id ?? product.id_val
        let refPrice = currentOffer?.price ?? product.best_price
        var fetched = await SupabaseManager.shared.fetchRelatedProductsDirect(
            excludingProductId: resolvedPid,
            excludingCanonicalName: product.canonical_name,
            category: product.category,
            brand: product.effectiveBrand,
            gender: product.gender,
            referencePrice: refPrice,
            limit: 8
        )

        // Fallback if category was unknown and returned few items
        if fetched.count < 4 {
            let catKw = product.isComparable ? ["running"] : ["fitness"]
            let extra = await SupabaseManager.shared.fetchSmartProductsDirect(
                category: product.category,
                keywords: catKw,
                gender: product.gender,
                limit: 12
            )
            for item in extra where item.id != product.id && item.canonical_name != product.canonical_name {
                if !fetched.contains(where: { $0.id == item.id || $0.canonical_name == item.canonical_name }) {
                    fetched.append(item)
                }
            }
        }

        let limited = Array(fetched.prefix(8))
        let prefetchUrls = limited.compactMap { URL(string: $0.image_url ?? "") }
        ImageCacheManager.shared.prefetch(urls: prefetchUrls, maxPixelSize: 400)
        await MainActor.run {
            withAnimation(ShopMotion.gridReflow) {
                self.relatedProducts = limited
                self.isLoadingRelated = false
            }
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

// MARK: - Price History & Market Intelligence Chart Card

struct PriceHistorySectionView: View {
    let history: PriceHistoryResponse
    var onRequestPriceAlert: (() -> Void)? = nil

    /// Real distinct-day observations only (never fabricates a synthetic "Listino" drop point).
    var realDailyTrendPoints: [PriceHistoryPoint] {
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

        return byDay.values.sorted(by: { $0.parsedDate < $1.parsedDate })
    }

    private var hasRealChartData: Bool {
        realDailyTrendPoints.count >= 2
    }

    private var chartMinPrice: Double {
        let prices = realDailyTrendPoints.map(\.price)
        let minP = prices.min() ?? history.lowest_price
        return max(0, minP * 0.92)
    }

    private var chartMaxPrice: Double {
        let prices = realDailyTrendPoints.map(\.price)
        let maxP = prices.max() ?? history.highest_price
        return max(maxP * 1.06, chartMinPrice + 1.0)
    }

    var body: some View {
        if !hasRealChartData {
            // Honest compact monitoring card when fewer than 2 historical observations exist
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.shopPurple)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Monitoraggio prezzi attivo")
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                        Text("Stiamo raccogliendo lo storico di questo modello. Attiva un avviso per non perdere il prossimo calo.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.shopTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let onAlert = onRequestPriceAlert {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onAlert()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 12.5, weight: .bold))
                            Text("Imposta avviso di prezzo")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.shopPurple)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Color.shopPurpleLight.opacity(0.65))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
            )
        } else {
            VStack(alignment: .leading, spacing: 16) {
                // 1. Top Header: Title, Lowest Price & Badges
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Storico prezzi")
                                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            if history.is_all_time_low {
                                HStack(spacing: 3) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("Minimo storico")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.shopPurple)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.shopPurpleLight)
                                .clipShape(Capsule())
                            }
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(history.formattedLowestPrice)
                                .font(.system(size: 24, weight: .heavy, design: .rounded))
                                .foregroundColor(.shopDark)

                            Text("\(realDailyTrendPoints.count) rilevazioni reali")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let dropPct = history.price_drop_percentage, dropPct > 1 {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .bold))
                            Text("-\(Int(dropPct.rounded()))%")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.shopGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.shopGreenLight)
                        .clipShape(Capsule())
                    }
                }

                // 2. Metrics Bar: Minimo | Media | Massimo
                HStack(spacing: 8) {
                    metricPill(
                        label: "Minimo",
                        value: history.formattedLowestPrice,
                        icon: "arrow.down.right",
                        iconColor: .shopGreen,
                        bgColor: Color.shopGreenLight.opacity(0.4)
                    )

                    metricPill(
                        label: "Media",
                        value: history.formattedAveragePrice,
                        icon: "chart.bar.fill",
                        iconColor: .shopPurple,
                        bgColor: Color(red: 246/255, green: 247/255, blue: 250/255)
                    )

                    metricPill(
                        label: "Massimo",
                        value: history.formattedHighestPrice,
                        icon: "arrow.up.right",
                        iconColor: .shopTextMuted,
                        bgColor: Color(red: 246/255, green: 247/255, blue: 250/255)
                    )
                }

                // 3. Swift Chart (real multi-day history)
                VStack(spacing: 0) {
                    Chart {
                        ForEach(realDailyTrendPoints) { point in
                            AreaMark(
                                x: .value("Data", point.parsedDate),
                                y: .value("Prezzo", point.price)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color.shopPurple.opacity(0.24),
                                        Color.shopPurple.opacity(0.06),
                                        Color.shopPurple.opacity(0.0)
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
                            .lineStyle(StrokeStyle(lineWidth: 2.6))
                            .foregroundStyle(Color.shopPurple)

                            PointMark(
                                x: .value("Data", point.parsedDate),
                                y: .value("Prezzo", point.price)
                            )
                            .foregroundStyle(Color.shopPurple)
                            .symbolSize(CGSize(width: 5, height: 5))
                        }

                        RuleMark(y: .value("Media", history.average_price))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.35))
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
                                .foregroundStyle(Color.black.opacity(0.04))
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                .font(.system(size: 9.5, weight: .medium))
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
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(Color.shopTextMuted)
                                }
                            }
                        }
                    }
                    .frame(height: 155)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
                }

                // 4. Market Advice Insight + Quick Price Alert Action
                HStack(spacing: 8) {
                    Image(systemName: history.is_all_time_low ? "sparkles" : "shield.checkmark.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(history.is_all_time_low ? .shopPurple : .shopGreen)

                    Text(history.is_all_time_low ?
                         "Minimo storico registrato tra i partner monitorati." :
                         (history.formattedSavingsVsAverage != nil ? "Prezzo attuale \(history.formattedSavingsVsAverage!)." : "Andamento monitorato tra i rivenditori partner.")
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.shopDark.opacity(0.85))
                    .lineLimit(2)

                    Spacer(minLength: 4)

                    if let onAlert = onRequestPriceAlert {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onAlert()
                        }) {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.shopPurple)
                                .frame(width: 30, height: 30)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Imposta avviso di prezzo")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(history.is_all_time_low ? Color.shopPurpleLight.opacity(0.6) : Color(red: 246/255, green: 247/255, blue: 250/255))
                .cornerRadius(12)
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        }
    }

    private func metricPill(label: String, value: String, icon: String, iconColor: Color, bgColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.shopTextMuted)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(iconColor)
            }

            Text(value)
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bgColor)
        .cornerRadius(12)
    }
}

// MARK: - Helper Sheets

struct ReturnPolicySheetView: View {
    let storeId: String?
    let storeName: String
    @Environment(\.dismiss) private var dismiss

    private var storeMeta: ActiveStoreItem? {
        DynamicCatalogRegistry.shared.storeItem(for: storeId ?? storeName)
            ?? DynamicCatalogRegistry.shared.storeItem(for: storeName)
    }

    var body: some View {
        let realPolicy = storeMeta?.refund_policy?.trimmingCharacters(in: .whitespacesAndNewlines)

        return NavigationStack {
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
                        Text("Condizioni di \(storeName)")
                            .font(.system(size: 15, weight: .bold))

                        if let policy = realPolicy, !policy.isEmpty {
                            Text(policy)
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundColor(.shopDark)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.shopSurface)
                                .cornerRadius(14)
                        }

                        Text("• Il prodotto deve essere restituito integro, non utilizzato e con confezione e cartellini originali.")
                            .font(.system(size: 14))
                            .foregroundColor(.shopTextMuted)

                        Text("• Il reso e il rimborso vengono gestiti direttamente da \(storeName) secondo i termini indicati sul sito ufficiale.")
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
    let storeId: String?
    let storeName: String
    let offer: Offer?
    @Environment(\.dismiss) private var dismiss

    private var storeMeta: ActiveStoreItem? {
        DynamicCatalogRegistry.shared.storeItem(for: storeId ?? offer?.store_id ?? storeName)
            ?? DynamicCatalogRegistry.shared.storeItem(for: storeName)
    }

    var body: some View {
        let realPolicy = storeMeta?.shipping_policy?.trimmingCharacters(in: .whitespacesAndNewlines)
        let courier = offer?.effectiveCourier ?? storeMeta?.courier
        let freeThreshold = offer?.effectiveFreeShippingThreshold ?? storeMeta?.free_shipping_threshold

        return NavigationStack {
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
                                Text("Per questa offerta:")
                                    .font(.system(size: 14, weight: .bold))
                                Spacer()
                                Text(off.isFreeShipping ? "Gratuita" : off.formattedShipping)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(off.isFreeShipping ? .shopGreen : .shopDark)
                            }

                            HStack {
                                Text("Totale stimato:")
                                    .font(.system(size: 14, weight: .bold))
                                Spacer()
                                Text(off.formattedTotalPrice)
                                    .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                                    .foregroundColor(.shopDark)
                            }
                            Divider()
                        }

                        if let policy = realPolicy, !policy.isEmpty {
                            Text("Condizioni di spedizione")
                                .font(.system(size: 15, weight: .bold))

                            Text(policy)
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundColor(.shopDark)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.shopSurface)
                                .cornerRadius(14)
                        }

                        if let courier, !courier.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "shippingbox.fill")
                                    .foregroundColor(.shopPurple)
                                Text("Corriere: \(courier)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.shopDark)
                            }
                        }

                        if let thresh = freeThreshold, thresh > 0 {
                            let tStr = thresh.truncatingRemainder(dividingBy: 1) == 0
                                ? "€\(Int(thresh))"
                                : String(format: "€%.2f", thresh)
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.shopGreen)
                                Text("Spedizione gratuita per ordini da \(tStr)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.shopDark)
                            }
                        }

                        Text("Tempi e tariffe definitive vengono sempre confermati al checkout sul sito ufficiale di \(storeName).")
                            .font(.system(size: 13))
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

// MARK: - Fullscreen Interactive Product Gallery (Native UIScrollView Pinch/Pan, Anchor Double-Tap, Drag-to-Dismiss)

private struct FullScreenProductGalleryView: View {
    let images: [String]
    @Binding var selectedIndex: Int
    let productTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var scrolledIndex: Int?
    @State private var dragOffset: CGSize = .zero
    @State private var activeZoomScale: CGFloat = 1.0
    @State private var resetZoomTrigger: UUID = UUID()
    @State private var showChrome: Bool = true
    @Namespace private var fsThumbNamespace

    private var isZoomed: Bool {
        activeZoomScale > 1.03
    }

    var body: some View {
        let dragProgress = min(abs(dragOffset.height) / 260.0, 1.0)

        ZStack {
            // Translucent blurred dark backdrop so ProductDetailView peeks smoothly during vertical drag-to-dismiss
            Color.black
                .opacity(max(0.15, 0.94 - dragProgress * 0.72))
                .background(.ultraThinMaterial.opacity(max(0.0, 1.0 - dragProgress)))
                .ignoresSafeArea()

            // Main Paging & Zoomable Stage
            Group {
                if images.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(Array(images.enumerated()), id: \.offset) { idx, imgUrl in
                                ZoomableRemoteImagePage(
                                    urlString: imgUrl,
                                    isActive: idx == selectedIndex,
                                    resetToken: resetZoomTrigger,
                                    onZoomScaleChanged: { newScale in
                                        if idx == selectedIndex {
                                            activeZoomScale = newScale
                                        }
                                    },
                                    onSingleTap: {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            showChrome.toggle()
                                        }
                                    }
                                )
                                .containerRelativeFrame(.horizontal)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1.0 : 0.92)
                                        .opacity(phase.isIdentity ? 1.0 : 0.55)
                                }
                                .id(idx)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $scrolledIndex)
                    .scrollDisabled(isZoomed)
                } else if let first = images.first {
                    ZoomableRemoteImagePage(
                        urlString: first,
                        isActive: true,
                        resetToken: resetZoomTrigger,
                        onZoomScaleChanged: { newScale in
                            activeZoomScale = newScale
                        },
                        onSingleTap: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showChrome.toggle()
                            }
                        }
                    )
                }
            }
            .offset(y: dragOffset.height)
            .scaleEffect(max(0.84, 1.0 - dragProgress * 0.14))

            // Top & Bottom Floating Chrome
            if showChrome {
                VStack(spacing: 0) {
                    // Header bar
                    HStack(spacing: 10) {
                        Text(productTitle)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.95))
                            .lineLimit(1)

                        Spacer()

                        if images.count > 1 {
                            Text("\(min(selectedIndex + 1, images.count)) / \(images.count)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .contentTransition(.numericText())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.16))
                                .clipShape(Capsule())
                        }

                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.20))
                                .clipShape(Circle())
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.90))
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.vertical, 12)

                    Spacer()

                    // Zoom scale pill / Gesture hint
                    VStack(spacing: 12) {
                        if isZoomed {
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                resetZoomTrigger = UUID()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(String(format: "%.1fx • Reimposta", activeZoomScale))
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.black.opacity(0.65))
                                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(ShopCardPressStyle(scale: 0.94))
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                        } else {
                            Text("Pizzica o fai doppio tap per zoomare")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.75))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Capsule())
                                .transition(.opacity)
                        }

                        // Fullscreen Bottom Thumbnail Strip
                        if images.count > 1 {
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(images.enumerated()), id: \.offset) { idx, imgUrl in
                                            let isSelected = selectedIndex == idx
                                            Button(action: {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                withAnimation(ShopMotion.gallerySpring) {
                                                    resetZoomTrigger = UUID()
                                                    selectedIndex = idx
                                                    scrolledIndex = idx
                                                }
                                            }) {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .fill(Color.white)

                                                    if let url = URL(string: imgUrl) {
                                                        ShopCachedAsyncImage(url: url, maxPixelSize: 280) { phase in
                                                            if let image = phase.image {
                                                                image
                                                                    .resizable()
                                                                    .scaledToFit()
                                                                    .padding(4)
                                                            }
                                                        }
                                                    }
                                                }
                                                .frame(width: 48, height: 48)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                .overlay {
                                                    if isSelected {
                                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                            .stroke(Color.shopPurple, lineWidth: 2.5)
                                                            .matchedGeometryEffect(id: "fs_thumb_ring", in: fsThumbNamespace)
                                                    }
                                                }
                                                .opacity(isSelected ? 1.0 : 0.65)
                                                .scaleEffect(isSelected ? 1.04 : 0.95)
                                            }
                                            .buttonStyle(ShopCardPressStyle(scale: 0.92))
                                            .id(idx)
                                        }
                                    }
                                    .padding(.horizontal, ShopLayout.screenPadding)
                                    .padding(.vertical, 4)
                                }
                                .onChange(of: selectedIndex) { _, newIndex in
                                    withAnimation(ShopMotion.gallerySpring) {
                                        proxy.scrollTo(newIndex, anchor: .center)
                                    }
                                }
                                .onAppear {
                                    proxy.scrollTo(selectedIndex, anchor: .center)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .opacity(1.0 - dragProgress)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showChrome)
        .animation(ShopMotion.pillSlide, value: isZoomed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    guard !isZoomed else { return }
                    if abs(value.translation.height) > abs(value.translation.width) * 1.2 {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    guard !isZoomed else { return }
                    if abs(value.translation.height) > 120 || abs(value.predictedEndTranslation.height) > 320 {
                        dismiss()
                    } else {
                        withAnimation(ShopMotion.gallerySpring) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .onAppear {
            scrolledIndex = selectedIndex
            let hiResUrls = images.compactMap { URL(string: $0) }
            ImageCacheManager.shared.prefetch(urls: hiResUrls, maxPixelSize: 2400)
        }
        .onChange(of: scrolledIndex) { _, newValue in
            if let idx = newValue, idx != selectedIndex {
                withAnimation(ShopMotion.gallerySpring) {
                    selectedIndex = idx
                    activeZoomScale = 1.0
                    resetZoomTrigger = UUID()
                }
            }
        }
    }
}

/// Loads up to 2400px image from cache/network (showing cached preview immediately) and renders inside a native zoomable UIScrollView.
private struct ZoomableRemoteImagePage: View {
    let urlString: String
    let isActive: Bool
    let resetToken: UUID
    let onZoomScaleChanged: (CGFloat) -> Void
    let onSingleTap: () -> Void

    @State private var uiImage: UIImage?

    var body: some View {
        let url = URL(string: urlString)

        ZStack {
            if let image = uiImage {
                NativeZoomableImageView(
                    image: image,
                    isActive: isActive,
                    resetToken: resetToken,
                    onZoomScaleChanged: onZoomScaleChanged,
                    onSingleTap: onSingleTap
                )
                .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }
        }
        .task(id: urlString) {
            guard let url else { return }
            if let hiRes = ImageCacheManager.shared.cachedImage(for: url, maxPixelSize: 2400) {
                uiImage = hiRes
                return
            }
            if let preview = ImageCacheManager.shared.cachedImage(for: url, maxPixelSize: 1200) {
                uiImage = preview
            }
            if let fullImg = await ImageCacheManager.shared.loadImage(for: url, maxPixelSize: 2400) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.uiImage = fullImg
                }
            }
        }
    }
}

/// UIKit UIScrollView subclass ensuring image bounds re-center immediately on first layout & size changes.
private final class CenteringZoomScrollView: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// UIKit UIScrollView wrapper delivering native pinch-to-zoom, focal-point double-tap zoom, rubber-banding, and momentum panning.
private struct NativeZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let isActive: Bool
    let resetToken: UUID
    let onZoomScaleChanged: (CGFloat) -> Void
    let onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onZoomScaleChanged: onZoomScaleChanged, onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = CenteringZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.5
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast

        // Clean bright showcase card container inside zoom canvas for transparent/studio product shots
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        imageView.layer.cornerRadius = 20
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        scrollView.addSubview(imageView)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        context.coordinator.lastResetToken = resetToken
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.layoutImageIfNeeded()
        }

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onZoomScaleChanged = onZoomScaleChanged
        context.coordinator.onSingleTap = onSingleTap

        if let imageView = context.coordinator.imageView {
            if imageView.image !== image {
                imageView.image = image
            }
            context.coordinator.layoutImageIfNeeded()
        }

        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1.0, animated: true)
            }
        }

        if !isActive && scrollView.zoomScale > 1.01 {
            scrollView.setZoomScale(1.0, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        var onZoomScaleChanged: (CGFloat) -> Void
        var onSingleTap: () -> Void
        var lastResetToken: UUID = UUID()
        private var lastBoundsSize: CGSize = .zero

        init(onZoomScaleChanged: @escaping (CGFloat) -> Void, onSingleTap: @escaping () -> Void) {
            self.onZoomScaleChanged = onZoomScaleChanged
            self.onSingleTap = onSingleTap
        }

        func layoutImageIfNeeded() {
            guard let scrollView, let imageView, let img = imageView.image else { return }
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }

            if boundsSize != lastBoundsSize || imageView.frame.size == .zero {
                lastBoundsSize = boundsSize
                let maxWidth = max(boundsSize.width - 28, 100)
                let maxHeight = max(boundsSize.height * 0.68, 200)
                let aspect = img.size.width / max(img.size.height, 1)

                var fitWidth = maxWidth
                var fitHeight = fitWidth / max(aspect, 0.2)
                if fitHeight > maxHeight {
                    fitHeight = maxHeight
                    fitWidth = fitHeight * aspect
                }

                // Ensure a minimum clean stage for square/wide product photography
                fitWidth = max(fitWidth, min(maxWidth, boundsSize.width - 32))
                fitHeight = max(fitHeight, min(maxHeight, 360))

                scrollView.zoomScale = 1.0
                imageView.frame = CGRect(x: 0, y: 0, width: fitWidth, height: fitHeight)
                scrollView.contentSize = imageView.frame.size
                centerImage()
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage()
            onZoomScaleChanged(scrollView.zoomScale)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            centerImage()
            onZoomScaleChanged(scale)
        }

        private func centerImage() {
            guard let scrollView, let imageView else { return }
            let boundsSize = scrollView.bounds.size
            var frameToCenter = imageView.frame

            if frameToCenter.size.width < boundsSize.width {
                frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) * 0.5
            } else {
                frameToCenter.origin.x = 0
            }

            if frameToCenter.size.height < boundsSize.height {
                frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) * 0.5
            } else {
                frameToCenter.origin.y = 0
            }

            imageView.frame = frameToCenter
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView, let imageView else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            if scrollView.zoomScale > 1.2 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let targetScale: CGFloat = 2.6
                let point = gesture.location(in: imageView)
                let width = scrollView.bounds.size.width / targetScale
                let height = scrollView.bounds.size.height / targetScale
                let zoomRect = CGRect(
                    x: point.x - width * 0.5,
                    y: point.y - height * 0.5,
                    width: width,
                    height: height
                )
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            onSingleTap()
        }
    }
}
