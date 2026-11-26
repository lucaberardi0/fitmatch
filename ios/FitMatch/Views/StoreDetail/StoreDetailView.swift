import SwiftUI

private enum StoreSortOption: String, CaseIterable, Identifiable {
    case recommended = "recommended"
    case discount = "discount"
    case priceAsc = "price_asc"
    case priceDesc = "price_desc"
    case name = "name"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recommended: return "Consigliati"
        case .discount: return "Miglior sconto"
        case .priceAsc: return "Prezzo crescente"
        case .priceDesc: return "Prezzo decrescente"
        case .name: return "Nome A–Z"
        }
    }

    var compactLabel: String {
        switch self {
        case .recommended: return "Ordina"
        case .discount: return "Sconto"
        case .priceAsc: return "Prezzo ↑"
        case .priceDesc: return "Prezzo ↓"
        case .name: return "A–Z"
        }
    }
}

struct StoreDetailView: View {
    let storeId: String
    let initialStoreName: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var wishlistManager = WishlistManager.shared
    @ObservedObject private var prefsManager = UserPreferencesManager.shared

    @State private var storeDetails: StoreDetailResponse?
    @State private var products: [StoreShowcaseProduct] = []
    @State private var totalMatching: Int = 0

    @State private var isLoading: Bool = true
    @State private var isFilteringCatalog: Bool = false
    @State private var isLoadingMore: Bool = false
    @State private var errorMessage: String?

    // Filters & Query
    @State private var searchQuery: String = ""
    @State private var selectedCategory: String = "tutti"
    @State private var selectedBrand: String? = nil
    @State private var onlyMySize: Bool = false
    @State private var onlyDiscounted: Bool = false
    @State private var selectedSort: StoreSortOption = .recommended

    // Sheets & Feedback
    @State private var showStoreInfoSheet: Bool = false
    @State private var showWriteReviewSheet: Bool = false
    @State private var showReportAlert: Bool = false
    @State private var showToastMessage: String? = nil

    // Async Tasks
    @State private var catalogTask: Task<Void, Never>? = nil
    @State private var paginationTask: Task<Void, Never>? = nil

    private let api = APIService.shared
    private let pageSize = 40
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private static let italianNumberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "it_IT")
        return f
    }()

    // MARK: - Computed Helpers

    private var storeDisplayName: String {
        storeDetails?.store_name ?? initialStoreName
    }

    private var activePreferredSize: String? {
        let p = prefsManager.preferences
        if selectedCategory == "abbigliamento" {
            let app = p.preferredApparelSize.trimmingCharacters(in: .whitespacesAndNewlines)
            return app.isEmpty ? nil : app
        }
        let shoe = p.preferredShoeSize.trimmingCharacters(in: .whitespacesAndNewlines)
        if !shoe.isEmpty { return shoe }
        let app = p.preferredApparelSize.trimmingCharacters(in: .whitespacesAndNewlines)
        return app.isEmpty ? nil : app
    }

    private var hasActiveFilters: Bool {
        selectedCategory != "tutti"
            || selectedBrand != nil
            || onlyMySize
            || onlyDiscounted
            || selectedSort != .recommended
    }

    private var hasActiveSearch: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var detectedCorrection: String? {
        StoreSearchMatcher.detectCorrection(for: searchQuery)
    }

    private var effectiveRemoteQuery: String {
        let clean = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }
        return detectedCorrection ?? clean
    }

    private var dynamicCategories: [StoreCategoryFacet] {
        storeDetails?.categories ?? []
    }

    private var dynamicBrands: [StoreBrandFacet] {
        storeDetails?.top_brands ?? []
    }

    private var isMultiBrandStore: Bool {
        dynamicBrands.count >= 3
    }

    private var hasDiscountsInStore: Bool {
        (storeDetails?.discounted_products ?? 0) > 0
    }

    private var hasMoreProducts: Bool {
        products.count < totalMatching
    }

    private var shippingSummaryLine: String? {
        guard let details = storeDetails else { return nil }
        if let thresh = details.free_shipping_threshold, thresh > 0 {
            return "Spedizione gratis da \(Int(thresh.rounded())) €"
        }
        if let std = details.standard_shipping_cost, std > 0 {
            return String(format: "Spedizione da %.2f €", std).replacingOccurrences(of: ".", with: ",")
        }
        return nil
    }

    private func formattedCount(_ value: Int) -> String {
        Self.italianNumberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            topNavigationBar
                .shopHeaderBarPadding()
                .background(Color.white)

            Divider()
                .background(Color.shopBorder)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    storeHeroHeader
                        .padding(.top, 18)
                        .padding(.bottom, 16)

                    if isLoading {
                        ShopStoreDetailSkeletonView()
                            .transition(.opacity)
                    } else if let error = errorMessage {
                        errorStateView(error: error)
                    } else {
                        VStack(spacing: 12) {
                            if dynamicCategories.count >= 2 {
                                categoryPillsStrip
                            }

                            filterAndSortStrip

                            if hasActiveSearch || hasActiveFilters {
                                activeResultsStatusRow
                                    .padding(.horizontal, ShopLayout.screenPadding)
                            }
                        }
                        .padding(.bottom, 14)

                        productCatalogGrid
                            .padding(.horizontal, ShopLayout.screenPadding)
                            .padding(.bottom, ShopLayout.bottomDetailClearance)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await refreshStoreDataAsync()
            }
        }
        .background(Color.white.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showStoreInfoSheet) {
            Group {
                if let details = storeDetails {
                    StoreInfoSheetView(
                        details: details,
                        storeId: storeId,
                        initialStoreName: initialStoreName,
                        onReviewAdded: { newRev in
                            prependReviewLocally(newRev)
                        },
                        onReportTapped: {
                            showStoreInfoSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showReportAlert = true
                            }
                        }
                    )
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(.shopDark)
                        Text("Caricamento informazioni...")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.shopSurface)
                }
            }
        }
        .sheet(isPresented: $showWriteReviewSheet) {
            WriteReviewSheetView(
                storeId: storeId,
                storeName: storeDisplayName,
                onReviewSubmitted: { newRev in
                    prependReviewLocally(newRev)
                    showToast("Recensione pubblicata. Grazie!")
                }
            )
        }
        .alert("Segnala \(storeDisplayName)", isPresented: $showReportAlert) {
            Button("Annulla", role: .cancel) {}
            Button("Invia segnalazione", role: .destructive) {
                Task {
                    _ = await followedManager.reportStore(
                        storeId: storeId,
                        storeName: storeDisplayName,
                        reason: "Segnalato dall'utente per contenuti o prezzi errati"
                    )
                    showToast("Segnalazione inviata. Grazie.")
                }
            }
        } message: {
            Text("Vuoi segnalare questo negozio al team di FitMatch? Verificheremo catalogo e informazioni.")
        }
        .overlay(alignment: .bottom) {
            if let msg = showToastMessage {
                Text(msg)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.shopDark.opacity(0.92))
                    .clipShape(Capsule())
                    .padding(.bottom, 36)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            TabBarVisibilityManager.shared.hide(for: "store_detail")
        }
        .onDisappear {
            catalogTask?.cancel()
            paginationTask?.cancel()
            TabBarVisibilityManager.shared.show(for: "store_detail")
        }
        .task {
            if storeDetails == nil {
                loadStoreData()
            }
        }
        .onChange(of: searchQuery) { _ in
            scheduleCatalogReload(debounceMs: 320)
        }
        .onChange(of: selectedCategory) { _ in
            scheduleCatalogReload(debounceMs: 0)
        }
        .onChange(of: selectedBrand) { _ in
            scheduleCatalogReload(debounceMs: 0)
        }
        .onChange(of: onlyMySize) { _ in
            scheduleCatalogReload(debounceMs: 0)
        }
        .onChange(of: onlyDiscounted) { _ in
            scheduleCatalogReload(debounceMs: 0)
        }
        .onChange(of: selectedSort) { _ in
            scheduleCatalogReload(debounceMs: 0)
        }
    }

    // MARK: - 1. Top Navigation Bar

    private var topNavigationBar: some View {
        HStack(spacing: 10) {
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.shopDark)
                    .frame(width: ShopLayout.navButtonSize, height: ShopLayout.navButtonSize)
                    .background(Color.shopSurface)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.shopBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundColor(.shopTextMuted)

                TextField("Cerca in \(storeDisplayName)", text: $searchQuery)
                    .font(.system(size: 14.5))
                    .foregroundColor(.shopDark)
                    .submitLabel(.search)

                if isFilteringCatalog {
                    ProgressView()
                        .scaleEffect(0.72)
                        .tint(.shopTextMuted)
                } else if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.shopTextMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: ShopLayout.navButtonSize)
            .background(Color.shopSurface)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.shopBorder, lineWidth: 1)
            )

            Button(action: {
                showStoreInfoSheet = true
            }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.shopDark)
                    .frame(width: ShopLayout.navButtonSize, height: ShopLayout.navButtonSize)
                    .background(Color.shopSurface)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.shopBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 2. Store Hero Header

    private var storeHeroHeader: some View {
        let name = storeDisplayName
        let isFollowed = followedManager.isFollowing(storeId: storeId)

        return VStack(spacing: 10) {
            ShopStoreLogo(storeName: name, showVerified: false, showLabel: false, size: 58)
                .overlay(
                    Circle()
                        .stroke(Color.shopBorder.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)

            Text(name)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let details = storeDetails {
                VStack(spacing: 4) {
                    Button(action: {
                        showStoreInfoSheet = true
                    }) {
                        HStack(spacing: 6) {
                            if !details.rating.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.shopDark)
                                    Text(details.rating.replacingOccurrences(of: ".", with: ","))
                                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                        .foregroundColor(.shopDark)
                                    if !details.review_count.isEmpty {
                                        Text("(\(details.review_count))")
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundColor(.shopTextMuted)
                                    }
                                }
                            }

                            if !details.rating.isEmpty && details.total_offers > 0 {
                                Text("·")
                                    .foregroundColor(.shopTextMuted)
                            }

                            if details.total_offers > 0 {
                                Text("\(formattedCount(details.total_offers)) prodotti")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.shopTextMuted)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if let shipLine = shippingSummaryLine {
                        Text(shipLine)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(.shopTextMuted)
                    }
                }
            } else {
                ShopSkeletonTextLine(width: 150, height: 14, cornerRadius: 6)
                    .padding(.vertical, 2)
            }

            HStack(spacing: 10) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    followedManager.toggleFollow(storeId: storeId, storeName: name)
                }) {
                    HStack(spacing: 6) {
                        if isFollowed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(isFollowed ? "Seguito" : "Segui")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(isFollowed ? .shopDark : .white)
                    .padding(.horizontal, 22)
                    .frame(height: 38)
                    .background(isFollowed ? Color.shopSurface : Color.shopDark)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(isFollowed ? Color.shopBorder : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.97, pressedOpacity: 0.92))

                Button(action: {
                    showWriteReviewSheet = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "star")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Valuta")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.shopDark)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background(Color.shopSurface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.shopBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.97, pressedOpacity: 0.92))
            }
            .padding(.top, 4)
        }
    }

    // MARK: - 3. Dynamic Category Pills

    private var categoryPillsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryPill(id: "tutti", label: "Tutti")

                ForEach(dynamicCategories) { cat in
                    categoryPill(id: cat.id, label: cat.label)
                }
            }
            .padding(.horizontal, ShopLayout.screenPadding)
        }
    }

    private func categoryPill(id: String, label: String) -> some View {
        let isSelected = selectedCategory == id
        return Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.18)) {
                selectedCategory = id
            }
        }) {
            Text(label)
                .font(.system(size: 13.5, weight: isSelected ? .bold : .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : .shopDark)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(isSelected ? Color.shopDark : Color.shopSurface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : Color.shopBorder, lineWidth: 1)
                )
        }
        .buttonStyle(ShopCardPressStyle(scale: 0.97, pressedOpacity: 0.92))
    }

    // MARK: - 4. Compact Filter & Sort Strip

    private var filterAndSortStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Sort Menu Chip
                Menu {
                    ForEach(StoreSortOption.allCases) { option in
                        if option != .discount || hasDiscountsInStore {
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedSort = option
                            }) {
                                Label(
                                    option.label,
                                    systemImage: selectedSort == option ? "checkmark" : ""
                                )
                            }
                        }
                    }
                } label: {
                    let active = selectedSort != .recommended
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(selectedSort.compactLabel)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(active ? .white : .shopDark)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(active ? Color.shopDark : Color.white)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(active ? Color.clear : Color.shopBorder, lineWidth: 1)
                    )
                }

                // Preferred Size Quick Filter
                if let prefSize = activePreferredSize {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onlyMySize.toggle()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "ruler")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("Taglia \(prefSize)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(onlyMySize ? .white : .shopDark)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(onlyMySize ? Color.shopDark : Color.white)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(onlyMySize ? Color.clear : Color.shopBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.97, pressedOpacity: 0.92))
                }

                // On Sale Quick Toggle (only if store has discounts)
                if hasDiscountsInStore {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onlyDiscounted.toggle()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "tag")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("In sconto")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(onlyDiscounted ? .white : .shopDark)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(onlyDiscounted ? Color.shopDark : Color.white)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(onlyDiscounted ? Color.clear : Color.shopBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.97, pressedOpacity: 0.92))
                }

                // Brand Picker Menu (only for multi-brand stores)
                if isMultiBrandStore {
                    Menu {
                        Button(action: { selectedBrand = nil }) {
                            Label("Tutti i brand", systemImage: selectedBrand == nil ? "checkmark" : "")
                        }
                        Divider()
                        ForEach(dynamicBrands) { brand in
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedBrand = brand.name
                            }) {
                                Label(
                                    "\(brand.name) (\(brand.count))",
                                    systemImage: selectedBrand?.caseInsensitiveCompare(brand.name) == .orderedSame ? "checkmark" : ""
                                )
                            }
                        }
                    } label: {
                        let active = selectedBrand != nil
                        HStack(spacing: 5) {
                            Text(selectedBrand ?? "Brand")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(active ? .white : .shopDark)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(active ? Color.shopDark : Color.white)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(active ? Color.clear : Color.shopBorder, lineWidth: 1)
                        )
                    }
                }

                // Quick Reset Chip when any filter is active
                if hasActiveFilters {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        resetFilters()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Azzera")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.shopTextMuted)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ShopLayout.screenPadding)
        }
    }

    private var activeResultsStatusRow: some View {
        HStack(spacing: 6) {
            Text(totalMatching == 1 ? "1 prodotto" : "\(formattedCount(totalMatching)) prodotti")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.shopTextMuted)

            if let corrected = detectedCorrection, hasActiveSearch {
                Text("·")
                    .foregroundColor(.shopTextMuted)
                Text("Risultati per «\(corrected.capitalized)»")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    // MARK: - 5. 2-Column Product Grid + Automatic Infinite Scroll

    private var productCatalogGrid: some View {
        Group {
            if products.isEmpty && !isFilteringCatalog {
                FitMatchEmptyStateView(
                    icon: hasActiveSearch ? "magnifyingglass" : "line.3.horizontal.decrease.circle",
                    title: hasActiveSearch
                        ? "Nessun risultato su \(storeDisplayName)"
                        : "Nessun prodotto con questi filtri",
                    subtitle: hasActiveSearch
                        ? "Nessun articolo corrisponde a «\(searchQuery)»."
                        : "Prova a rimuovere o modificare uno dei filtri attivi.",
                    primaryTitle: hasActiveSearch && !hasActiveFilters
                        ? "Azzera ricerca"
                        : "Rimuovi filtri",
                    primaryIcon: "arrow.counterclockwise",
                    onPrimaryTap: {
                        if hasActiveSearch && !hasActiveFilters {
                            searchQuery = ""
                        } else {
                            searchQuery = ""
                            resetFilters()
                        }
                    }
                )
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 18) {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(Array(products.enumerated()), id: \.element.id) { index, item in
                            let matched = item.toMatchedProduct(
                                storeId: storeDetails?.store_id ?? storeId,
                                storeName: storeDisplayName
                            )
                            NavigationLink(destination: ProductDetailView(product: matched)) {
                                productCardView(item: item, matched: matched)
                            }
                            .buttonStyle(ShopCardPressStyle())
                            .onAppear {
                                if hasMoreProducts && !isLoadingMore && !isFilteringCatalog && index >= max(0, products.count - 6) {
                                    loadMoreProducts()
                                }
                            }
                        }
                    }
                    .opacity(isFilteringCatalog ? 0.55 : 1.0)
                    .animation(.easeOut(duration: 0.18), value: isFilteringCatalog)

                    if isLoadingMore {
                        ProgressView()
                            .tint(.shopTextMuted)
                            .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private func productCardView(item: StoreShowcaseProduct, matched: MatchedProduct) -> some View {
        let isSaved = wishlistManager.isFavorite(matched.canonical_name)
        let brandLabel = item.effectiveBrand
        let showBrandCaption = isMultiBrandStore
            && !brandLabel.isEmpty
            && brandLabel.caseInsensitiveCompare(storeDisplayName) != .orderedSame
        let displayTitle = showBrandCaption ? item.titleWithoutLeadingBrand : item.cleanDisplayTitle

        return VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.shopSurface)
                    .frame(height: 182)
                    .overlay(
                        Group {
                            if let urlStr = item.image_url, let url = URL(string: urlStr) {
                                ShopCachedAsyncImage(url: url, maxPixelSize: 420) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .padding(14)
                                            .transition(.opacity)
                                    case .failure:
                                        Image(systemName: "bag")
                                            .font(.system(size: 28, weight: .light))
                                            .foregroundColor(.shopTextMuted.opacity(0.35))
                                    case .empty:
                                        ShopSkeletonBlock(cornerRadius: 14)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                Image(systemName: "bag")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundColor(.shopTextMuted.opacity(0.35))
                            }
                        }
                    )

                // Top-left discount badge
                if let badge = item.discountBadge {
                    VStack {
                        HStack {
                            Text(badge)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.shopDark)
                                .clipShape(Capsule())
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(10)
                }

                // Bottom-right favorite button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            wishlistManager.toggleFavorite(product: matched)
                        }) {
                            Image(systemName: isSaved ? "heart.fill" : "heart")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isSaved ? .shopRed : .shopDark)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.94))
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }

            VStack(alignment: .leading, spacing: 3) {
                if showBrandCaption {
                    Text(brandLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.shopTextMuted)
                        .lineLimit(1)
                }

                Text(displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.shopDark)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 34, alignment: .topLeading)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.formattedPrice)
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    if let orig = item.formattedOriginalPrice {
                        Text(orig)
                            .font(.system(size: 12))
                            .foregroundColor(.shopTextMuted)
                            .strikethrough()
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Error State

    private func errorStateView(error: String) -> some View {
        FitMatchEmptyStateView(
            icon: "wifi.exclamationmark",
            accentColor: .shopRed,
            title: "Impossibile caricare il negozio",
            subtitle: error,
            primaryTitle: "Riprova",
            primaryIcon: "arrow.clockwise",
            onPrimaryTap: {
                loadStoreData()
            }
        )
        .padding(.horizontal, ShopLayout.screenPadding)
        .padding(.vertical, 24)
    }

    // MARK: - Data Loading, Filtering & Pagination

    private func resetFilters() {
        selectedCategory = "tutti"
        selectedBrand = nil
        onlyMySize = false
        onlyDiscounted = false
        selectedSort = .recommended
    }

    private func loadStoreData() {
        isLoading = true
        errorMessage = nil
        Task {
            await refreshStoreDataAsync()
        }
    }

    private func refreshStoreDataAsync() async {
        do {
            let details = try await api.getStoreDetails(
                storeId: storeId,
                query: effectiveRemoteQuery,
                sort: selectedSort.rawValue,
                preferredSize: activePreferredSize
            )
            await MainActor.run {
                self.storeDetails = details
                self.products = details.products
                self.totalMatching = details.total_matching ?? details.products.count
                self.errorMessage = nil
                self.isLoading = false
                RecentActivityManager.shared.recordStoreView(
                    storeId: storeId,
                    storeName: details.store_name,
                    logoUrl: nil
                )
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func scheduleCatalogReload(debounceMs: UInt64) {
        guard !isLoading else { return }
        catalogTask?.cancel()
        paginationTask?.cancel()
        isLoadingMore = false

        let queryCopy = effectiveRemoteQuery
        let categoryCopy = selectedCategory
        let brandCopy = selectedBrand
        let sizeFilterCopy = onlyMySize ? activePreferredSize : nil
        let prefSizeCopy = activePreferredSize
        let onlyDiscCopy = onlyDiscounted
        let sortCopy = selectedSort.rawValue

        catalogTask = Task {
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: debounceMs * 1_000_000)
                guard !Task.isCancelled else { return }
            }

            await MainActor.run { isFilteringCatalog = true }

            do {
                let page = try await api.getStoreCatalogPage(
                    storeId: storeId,
                    query: queryCopy,
                    category: categoryCopy,
                    brand: brandCopy,
                    size: sizeFilterCopy,
                    onlyDiscounted: onlyDiscCopy,
                    sort: sortCopy,
                    preferredSize: prefSizeCopy,
                    limit: pageSize,
                    offset: 0
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.products = page.products
                    self.totalMatching = page.totalMatching
                    self.isFilteringCatalog = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isFilteringCatalog = false
                }
            }
        }
    }

    private func loadMoreProducts() {
        guard hasMoreProducts, !isLoadingMore, !isFilteringCatalog else { return }
        isLoadingMore = true

        let nextOffset = products.count
        let queryCopy = effectiveRemoteQuery
        let categoryCopy = selectedCategory
        let brandCopy = selectedBrand
        let sizeFilterCopy = onlyMySize ? activePreferredSize : nil
        let prefSizeCopy = activePreferredSize
        let onlyDiscCopy = onlyDiscounted
        let sortCopy = selectedSort.rawValue

        paginationTask?.cancel()
        paginationTask = Task {
            do {
                let page = try await api.getStoreCatalogPage(
                    storeId: storeId,
                    query: queryCopy,
                    category: categoryCopy,
                    brand: brandCopy,
                    size: sizeFilterCopy,
                    onlyDiscounted: onlyDiscCopy,
                    sort: sortCopy,
                    preferredSize: prefSizeCopy,
                    limit: pageSize,
                    offset: nextOffset
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let existingIds = Set(self.products.map(\.id))
                    let uniqueNew = page.products.filter { !existingIds.contains($0.id) }
                    if uniqueNew.isEmpty {
                        self.totalMatching = self.products.count
                    } else {
                        self.products.append(contentsOf: uniqueNew)
                        self.totalMatching = max(page.totalMatching, self.products.count)
                    }
                    self.isLoadingMore = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isLoadingMore = false
                }
            }
        }
    }

    private func prependReviewLocally(_ review: StoreCustomerReview) {
        var existing = storeDetails?.customer_reviews ?? []
        existing.insert(review, at: 0)
        storeDetails?.customer_reviews = existing
    }

    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            showToastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            withAnimation(.easeOut(duration: 0.2)) {
                if showToastMessage == message {
                    showToastMessage = nil
                }
            }
        }
    }
}

// MARK: - Store Intelligent Search Matcher (Typo Correction)

struct StoreSearchMatcher {
    static let knownAthleticModels: [String] = [
        "alphafly", "vaporfly", "ultrafly", "streakfly", "pegasus", "vomero",
        "invincible", "infinity", "metaspeed", "adizero", "boston", "adios",
        "supercomp", "endorphin", "speedgoat", "forerunner", "nimbus", "kayano",
        "cumulus", "novablast", "clifton", "bondi", "mach", "glycerin", "ghost",
        "tempo", "terrakiger", "wildhorse", "zegama", "gt-2000", "garmin", "fenix"
    ]

    static func levenshtein(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1.utf8)
        let b = Array(s2.utf8)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var dp = [Int](0...b.count)
        for (i, ca) in a.enumerated() {
            var newDp = [i + 1] + [Int](repeating: 0, count: b.count)
            for (j, cb) in b.enumerated() {
                let cost = ca == cb ? 0 : 1
                newDp[j + 1] = min(newDp[j] + 1, dp[j + 1] + 1, dp[j] + cost)
            }
            dp = newDp
        }
        return dp[b.count]
    }

    static func normalizeWord(_ w: String) -> String {
        var word = w.lowercased()
        while word.count > 4, let last = word.last, word.dropLast().last == last {
            word.removeLast()
        }
        for m in knownAthleticModels {
            let maxDist = m.count >= 7 ? 2 : 1
            if levenshtein(word, m) <= maxDist {
                return m
            }
        }
        return word
    }

    static func detectCorrection(for query: String) -> String? {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return nil }
        let tokens = clean.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
        var changed = false
        let normalizedTokens = tokens.map { tok -> String in
            let norm = normalizeWord(tok)
            if norm != tok { changed = true }
            return norm
        }
        return changed ? normalizedTokens.joined(separator: " ") : nil
    }
}

// MARK: - Accurate 5-Star Renderer

private struct StoreStarRatingRow: View {
    let rating: Double
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                let threshold = Double(index) + 1.0
                let symbol: String = {
                    if rating >= threshold - 0.2 {
                        return "star.fill"
                    } else if rating >= threshold - 0.7 {
                        return "star.leadinghalf.filled"
                    } else {
                        return "star"
                    }
                }()
                Image(systemName: symbol)
                    .font(.system(size: size))
                    .foregroundColor(symbol == "star" ? Color.shopBorder : .shopDark)
            }
        }
    }
}

// MARK: - Store Info Sheet (Verified Data Only)

struct StoreInfoSheetView: View {
    let details: StoreDetailResponse
    let storeId: String
    let initialStoreName: String
    var onReviewAdded: ((StoreCustomerReview) -> Void)? = nil
    let onReportTapped: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @State private var isDescriptionExpanded: Bool = false
    @State private var selectedPolicyTitle: String? = nil
    @State private var selectedPolicyText: String? = nil
    @State private var showWriteReviewSheet: Bool = false
    @State private var liveReviews: [StoreCustomerReview]

    init(
        details: StoreDetailResponse,
        storeId: String,
        initialStoreName: String,
        onReviewAdded: ((StoreCustomerReview) -> Void)? = nil,
        onReportTapped: @escaping () -> Void
    ) {
        self.details = details
        self.storeId = storeId
        self.initialStoreName = initialStoreName
        self.onReviewAdded = onReviewAdded
        self.onReportTapped = onReportTapped
        self._liveReviews = State(initialValue: details.customer_reviews ?? [])
    }

    private var numericRating: Double {
        Double(details.rating.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var formattedCatalogCount: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "it_IT")
        return f.string(from: NSNumber(value: details.total_offers)) ?? "\(details.total_offers)"
    }

    private var contactEntries: [(id: String, title: String, value: String?, icon: String, url: URL)] {
        var entries: [(String, String, String?, String, URL)] = []

        if let siteUrl = URL(string: details.base_url), !details.base_url.isEmpty {
            entries.append(("site", "Sito web", cleanDomain(details.base_url), "globe", siteUrl))
        }
        if let email = details.contact_email?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty,
           let mailUrl = URL(string: "mailto:\(email)") {
            entries.append(("email", email, nil, "envelope", mailUrl))
        }
        if let phone = details.contact_phone?.trimmingCharacters(in: .whitespacesAndNewlines),
           !phone.isEmpty {
            let cleaned = phone.replacingOccurrences(of: " ", with: "")
            if let telUrl = URL(string: "tel:\(cleaned)") {
                entries.append(("phone", phone, nil, "phone", telUrl))
            }
        }
        if let insta = details.social_instagram?.trimmingCharacters(in: .whitespacesAndNewlines),
           !insta.isEmpty {
            let handle = insta.replacingOccurrences(of: "@", with: "")
            if let igUrl = URL(string: "https://instagram.com/\(handle)") {
                entries.append(("ig", "Instagram", insta, "camera", igUrl))
            }
        }
        return entries
    }

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    storeProfileHeaderCard

                    shippingAndCatalogCard

                    reviewsSection

                    if let location = details.city_or_location ?? details.location, !location.isEmpty {
                        storeLocationSection(location: location)
                    }

                    policiesSection

                    if !contactEntries.isEmpty {
                        contactsSection
                    }

                    actionButtonsSection
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, ShopLayout.screenPadding)
            }
            .background(Color.shopSurface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.shopDark)
                            .frame(width: 36, height: 36)
                            .background(Color.white)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.shopBorder, lineWidth: 1))
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 8) {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            followedManager.toggleFollow(storeId: storeId, storeName: details.store_name)
                        }) {
                            let isFollowed = followedManager.isFollowing(storeId: storeId)
                            Text(isFollowed ? "Seguito" : "Segui")
                                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                .foregroundColor(isFollowed ? .shopDark : .white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(isFollowed ? Color.white : Color.shopDark)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(isFollowed ? Color.shopBorder : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        if let url = URL(string: details.base_url), !details.base_url.isEmpty {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                    .frame(width: 36, height: 36)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.shopBorder, lineWidth: 1))
                            }
                        }
                    }
                }
            }
            .alert(selectedPolicyTitle ?? "Informativa", isPresented: Binding(
                get: { selectedPolicyTitle != nil },
                set: { if !$0 { selectedPolicyTitle = nil } }
            )) {
                Button("Chiudi", role: .cancel) { selectedPolicyTitle = nil }
            } message: {
                Text(selectedPolicyText ?? "")
            }
            .sheet(isPresented: $showWriteReviewSheet) {
                WriteReviewSheetView(
                    storeId: storeId,
                    storeName: details.store_name,
                    onReviewSubmitted: { newRev in
                        withAnimation {
                            liveReviews.insert(newRev, at: 0)
                        }
                        onReviewAdded?(newRev)
                    }
                )
            }
        }
    }

    // MARK: - 1. Store Profile Header Card

    private var storeProfileHeaderCard: some View {
        let desc = details.full_description ?? details.description

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ShopStoreLogo(storeName: details.store_name, showVerified: false, showLabel: false, size: 50)
                    .overlay(Circle().stroke(Color.shopBorder.opacity(0.8), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(details.store_name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    if !details.rating.isEmpty {
                        let r = details.rating.replacingOccurrences(of: ".", with: ",")
                        let rev = details.review_count.isEmpty ? "" : " (\(details.review_count))"
                        Text("\(r) ★\(rev)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.shopTextMuted)
                    }
                }

                Spacer()
            }

            if !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(desc)
                        .font(.system(size: 13.5))
                        .foregroundColor(.shopTextMuted)
                        .lineSpacing(2.5)
                        .lineLimit(isDescriptionExpanded ? nil : 3)

                    if desc.count > 130 {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isDescriptionExpanded.toggle()
                            }
                        }) {
                            Text(isDescriptionExpanded ? "Mostra meno" : "Altro")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.shopDark)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .shopCard(padding: ShopLayout.cardPadding, cornerRadius: ShopLayout.cardRadius, shadowOpacity: 0.025, shadowRadius: 8, shadowY: 2)
    }

    // MARK: - 2. Shipping & Catalog Card

    private var shippingAndCatalogCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Catalogo e spedizioni")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            VStack(spacing: 0) {
                infoRow(
                    icon: "bag",
                    label: "Catalogo attivo",
                    value: "\(formattedCatalogCount) prodotti"
                )

                if details.avg_discount > 0 {
                    Divider().padding(.leading, 40)
                    infoRow(
                        icon: "tag",
                        label: "Sconto medio",
                        value: String(format: "-%.0f%%", details.avg_discount)
                    )
                }

                if let thresh = details.free_shipping_threshold, thresh > 0 {
                    Divider().padding(.leading, 40)
                    infoRow(
                        icon: "shippingbox",
                        label: "Spedizione gratuita",
                        value: "da \(Int(thresh.rounded())) €"
                    )
                }

                if let std = details.standard_shipping_cost, std > 0 {
                    Divider().padding(.leading, 40)
                    infoRow(
                        icon: "truck.box",
                        label: "Spedizione standard",
                        value: String(format: "%.2f €", std).replacingOccurrences(of: ".", with: ",")
                    )
                }

                if let courier = details.courier, !courier.isEmpty {
                    Divider().padding(.leading, 40)
                    infoRow(
                        icon: "box.truck",
                        label: "Corriere",
                        value: courier
                    )
                }
            }
            .background(Color.shopSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .shopCard(padding: ShopLayout.cardPadding, cornerRadius: ShopLayout.cardRadius, shadowOpacity: 0.025, shadowRadius: 8, shadowY: 2)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.shopDark)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(.shopTextMuted)

            Spacer()

            Text(value)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundColor(.shopDark)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 3. Reviews Section (Real Reviews Only)

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recensioni")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)

                Spacer()

                Button(action: {
                    showWriteReviewSheet = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("Valuta")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.shopDark)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.shopSurface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.shopBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            if numericRating > 0 {
                HStack(spacing: 12) {
                    Text(details.rating.replacingOccurrences(of: ".", with: ","))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    VStack(alignment: .leading, spacing: 3) {
                        StoreStarRatingRow(rating: numericRating, size: 12.5)

                        if !details.review_count.isEmpty {
                            let cleanRev = details.review_count
                                .replacingOccurrences(of: "recensioni", with: "", options: .caseInsensitive)
                                .trimmingCharacters(in: .whitespaces)
                            Text("\(cleanRev) valutazioni")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                        }
                    }

                    Spacer()
                }
            }

            if liveReviews.isEmpty {
                Button(action: {
                    showWriteReviewSheet = true
                }) {
                    FitMatchInlineEmptyRow(
                        icon: "star",
                        title: "Nessuna recensione su FitMatch",
                        subtitle: "Hai acquistato qui? Scrivi la prima recensione",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(liveReviews) { rev in
                            VStack(alignment: .leading, spacing: 10) {
                                StoreStarRatingRow(rating: rev.rating, size: 10.5)

                                if !rev.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(rev.text)
                                        .font(.system(size: 13))
                                        .foregroundColor(.shopDark)
                                        .lineSpacing(2)
                                        .lineLimit(4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Text("Valutazione a stelle")
                                        .font(.system(size: 12.5, weight: .regular))
                                        .foregroundColor(.shopTextMuted)
                                }

                                Spacer()

                                HStack(spacing: 8) {
                                    let initial = String(rev.author.prefix(1)).uppercased()
                                    Text(initial)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.shopDark)
                                        .frame(width: 24, height: 24)
                                        .background(Color.white)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.shopBorder, lineWidth: 1))

                                    Text("\(rev.author) · \(rev.date)")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundColor(.shopTextMuted)
                                }
                            }
                            .padding(14)
                            .frame(width: 268, height: 142, alignment: .topLeading)
                            .background(Color.shopSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
            }
        }
        .shopCard(padding: ShopLayout.cardPadding, cornerRadius: ShopLayout.cardRadius, shadowOpacity: 0.025, shadowRadius: 8, shadowY: 2)
    }

    // MARK: - 4. Location Section

    private func storeLocationSection(location: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sedi")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.shopDark)

                VStack(alignment: .leading, spacing: 2) {
                    Text(details.store_name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.shopDark)
                    Text(location)
                        .font(.system(size: 12.5))
                        .foregroundColor(.shopTextMuted)
                }

                Spacer()
            }
            .padding(14)
            .background(Color.shopSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .shopCard(padding: ShopLayout.cardPadding, cornerRadius: ShopLayout.cardRadius, shadowOpacity: 0.025, shadowRadius: 8, shadowY: 2)
    }

    // MARK: - 5. Policies Section

    private var policiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Informative")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            VStack(spacing: 0) {
                policyRow(
                    title: "Resi e rimborsi",
                    systemIcon: "arrow.uturn.backward.circle",
                    action: {
                        selectedPolicyTitle = "Resi e rimborsi"
                        selectedPolicyText = details.refund_policy ?? details.return_policy ?? "Consulta le condizioni di reso direttamente sul sito ufficiale del negozio."
                    }
                )

                Divider().padding(.leading, 40)

                policyRow(
                    title: "Spedizioni",
                    systemIcon: "shippingbox",
                    action: {
                        selectedPolicyTitle = "Spedizioni"
                        selectedPolicyText = details.shipping_policy ?? details.shipping_info ?? "Consulta i tempi e costi di spedizione direttamente sul sito del negozio."
                    }
                )

                if let privStr = details.privacy_policy_url, !privStr.isEmpty, let privUrl = URL(string: privStr) {
                    Divider().padding(.leading, 40)
                    policyRow(
                        title: "Privacy",
                        systemIcon: "shield",
                        isExternal: true,
                        action: { UIApplication.shared.open(privUrl) }
                    )
                }

                if let termsStr = details.terms_url, !termsStr.isEmpty, let termsUrl = URL(string: termsStr) {
                    Divider().padding(.leading, 40)
                    policyRow(
                        title: "Termini e condizioni",
                        systemIcon: "doc.text",
                        isExternal: true,
                        action: { UIApplication.shared.open(termsUrl) }
                    )
                }
            }
            .background(Color.shopSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .shopCard(padding: ShopLayout.cardPadding, cornerRadius: ShopLayout.cardRadius, shadowOpacity: 0.025, shadowRadius: 8, shadowY: 2)
    }

    private func policyRow(title: String, systemIcon: String, isExternal: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemIcon)
                    .font(.system(size: 15))
                    .foregroundColor(.shopDark)
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(.shopDark)

                Spacer()

                Image(systemName: isExternal ? "arrow.up.right" : "chevron.right")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.shopTextMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 6. Contacts Section (Real Contacts Only)

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contatti")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            VStack(spacing: 0) {
                ForEach(Array(contactEntries.enumerated()), id: \.element.id) { idx, entry in
                    if idx > 0 {
                        Divider().padding(.leading, 40)
                    }
                    contactRow(
                        title: entry.title,
                        value: entry.value,
                        systemIcon: entry.icon,
                        action: { UIApplication.shared.open(entry.url) }
                    )
                }
            }
            .background(Color.shopSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .shopCard(padding: ShopLayout.cardPadding, cornerRadius: ShopLayout.cardRadius, shadowOpacity: 0.025, shadowRadius: 8, shadowY: 2)
    }

    private func contactRow(title: String, value: String?, systemIcon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemIcon)
                    .font(.system(size: 15))
                    .foregroundColor(.shopDark)
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)

                Spacer()

                if let val = value {
                    Text(val)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                        .lineLimit(1)
                }

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.shopTextMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private func cleanDomain(_ urlStr: String) -> String {
        guard let url = URL(string: urlStr), let host = url.host else { return "Sito ufficiale" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    // MARK: - 7. Action Buttons

    private var actionButtonsSection: some View {
        VStack(spacing: 10) {
            if let url = URL(string: details.base_url), !details.base_url.isEmpty {
                Button(action: {
                    UIApplication.shared.open(url)
                }) {
                    HStack {
                        Text("Visita negozio online")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 15)
                    .background(Color.shopDark)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.98, pressedOpacity: 0.92))
            }

            Button(action: {
                onReportTapped()
            }) {
                HStack {
                    Text("Segnala un problema")
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Spacer()

                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.shopTextMuted)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.shopBorder, lineWidth: 1)
                )
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.98, pressedOpacity: 0.92))
        }
    }
}

// MARK: - Write Review Sheet (Real User Reviews & Ratings on Supabase)

struct WriteReviewSheetView: View {
    let storeId: String
    let storeName: String
    let onReviewSubmitted: (StoreCustomerReview) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int = 5
    @State private var authorName: String = ""
    @State private var reviewText: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    private let ratingLabels = [
        1: "Pessimo",
        2: "Migliorabile",
        3: "Nella media",
        4: "Molto buono",
        5: "Eccellente"
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        ShopStoreLogo(storeName: storeName, showVerified: false, showLabel: false, size: 54)
                            .overlay(Circle().stroke(Color.shopBorder.opacity(0.8), lineWidth: 1))

                        Text("Valuta \(storeName)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Text("Condividi la tua esperienza su spedizioni, prezzi e servizio.")
                            .font(.system(size: 13))
                            .foregroundColor(.shopTextMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            ForEach(1...5, id: \.self) { star in
                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                                        rating = star
                                    }
                                }) {
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.system(size: 32))
                                        .foregroundColor(star <= rating ? .shopDark : Color.shopBorder)
                                        .scaleEffect(star == rating ? 1.12 : 1.0)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text(ratingLabels[rating] ?? "Eccellente")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.shopDark)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.shopSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nome (facoltativo)")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(.shopTextMuted)

                            TextField("Es. Marco B.", text: $authorName)
                                .font(.system(size: 14.5))
                                .foregroundColor(.shopDark)
                                .padding(12)
                                .background(Color.shopSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.shopBorder, lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Recensione (facoltativa)")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(.shopTextMuted)

                            ZStack(alignment: .topLeading) {
                                if reviewText.isEmpty {
                                    Text("Scrivi come ti sei trovato con spedizione, taglie o prezzi...")
                                        .font(.system(size: 13.5))
                                        .foregroundColor(.shopTextMuted.opacity(0.75))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 14)
                                }

                                TextEditor(text: $reviewText)
                                    .font(.system(size: 13.5))
                                    .foregroundColor(.shopDark)
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                                    .frame(minHeight: 104)
                            }
                            .background(Color.shopSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.shopBorder, lineWidth: 1)
                            )
                        }
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.shopRed)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: submitReview) {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isSubmitting ? "Invio in corso..." : "Pubblica recensione")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(isSubmitting ? Color.shopTextMuted : Color.shopDark)
                        .clipShape(Capsule())
                    }
                    .disabled(isSubmitting)
                    .buttonStyle(ShopCardPressStyle(scale: 0.98, pressedOpacity: 0.92))
                }
                .padding(20)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.shopDark)
                }
            }
        }
    }

    private func submitReview() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil

        let text = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleanName.isEmpty ? "Utente FitMatch" : cleanName

        Task {
            let ok = await SupabaseManager.shared.submitStoreReview(
                storeId: storeId,
                authorName: name,
                rating: rating,
                reviewText: text
            )

            await MainActor.run {
                isSubmitting = false
                if ok {
                    let newRev = StoreCustomerReview(
                        author: name,
                        rating: Double(rating),
                        text: text,
                        date: "Oggi"
                    )
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onReviewSubmitted(newRev)
                    dismiss()
                } else {
                    errorMessage = "Impossibile inviare la recensione. Riprova più tardi."
                }
            }
        }
    }
}
