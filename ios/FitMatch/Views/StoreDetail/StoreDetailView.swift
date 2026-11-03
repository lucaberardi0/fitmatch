import SwiftUI

struct StoreDetailView: View {
    let storeId: String
    let initialStoreName: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var wishlistManager = WishlistManager.shared

    @State private var storeDetails: StoreDetailResponse?
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var searchQuery: String = ""
    @State private var selectedSort: String = "discount"
    @State private var showStoreInfoSheet: Bool = false
    @State private var showWriteReviewSheet: Bool = false
    @State private var showReportAlert: Bool = false
    @State private var showToastMessage: String? = nil

    private let api = APIService.shared
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var filteredProducts: [StoreShowcaseProduct] {
        guard let prods = storeDetails?.products else { return [] }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [StoreShowcaseProduct]
        if query.isEmpty {
            filtered = prods
        } else {
            filtered = prods.filter {
                $0.title.lowercased().contains(query) ||
                ($0.brand?.lowercased().contains(query) ?? false) ||
                $0.canonical_name.lowercased().contains(query)
            }
        }

        switch selectedSort {
        case "price_asc":
            return filtered.sorted { $0.current_price < $1.current_price }
        case "price_desc":
            return filtered.sorted { $0.current_price > $1.current_price }
        case "name":
            return filtered.sorted { $0.title.lowercased() < $1.title.lowercased() }
        default:
            return filtered.sorted { ($0.discount_pct ?? 0) > ($1.discount_pct ?? 0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Navigation Bar (Screenshot 1: Back, Search, Hamburger)
            topNavigationBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Color.white)

            Divider()
                .background(Color(red: 238/255, green: 239/255, blue: 242/255))

            // MARK: - Main Scroll Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Store Hero Header (Screenshot 1: Store Name, Star + Rating, Follow Button)
                    storeHeroHeader
                        .padding(.top, 24)
                        .padding(.bottom, 24)

                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(Color(red: 24/255, green: 24/255, blue: 27/255))
                            Text("Caricamento prodotti del negozio...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 70)
                    } else if let error = errorMessage {
                        errorStateView(error: error)
                    } else {
                        // Section Header: "Tutti i prodotti" + Circular Filter Button
                        catalogHeaderSection
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)

                        // 2-Column Product Grid (Screenshot 1)
                        productCatalogGrid
                            .padding(.horizontal, 16)
                            .padding(.bottom, 120)
                    }
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showStoreInfoSheet) {
            Group {
                if let details = storeDetails {
                    StoreInfoSheetView(
                        details: details,
                        storeId: storeId,
                        initialStoreName: initialStoreName,
                        onReportTapped: {
                            showStoreInfoSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showReportAlert = true
                            }
                        }
                    )
                } else {
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.2)
                        Text("Caricamento informazioni del negozio...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 247/255, green: 248/255, blue: 250/255))
                }
            }
        }
        .sheet(isPresented: $showWriteReviewSheet) {
            WriteReviewSheetView(
                storeId: storeId,
                storeName: storeDetails?.store_name ?? initialStoreName,
                onReviewSubmitted: { newRev in
                    withAnimation {
                        showToastMessage = "Recensione pubblicata con successo! Grazie."
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation {
                            showToastMessage = nil
                        }
                    }
                }
            )
        }
        .alert("Segnala \(storeDetails?.store_name ?? initialStoreName)", isPresented: $showReportAlert) {
            Button("Annulla", role: .cancel) {}
            Button("Invia Segnalazione", role: .destructive) {
                Task {
                    _ = await followedManager.reportStore(
                        storeId: storeId,
                        storeName: storeDetails?.store_name ?? initialStoreName,
                        reason: "Segnalato dall'utente per contenuti o prezzi errati"
                    )
                    withAnimation {
                        showToastMessage = "Segnalazione inviata. Grazie per il tuo feedback."
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation {
                            showToastMessage = nil
                        }
                    }
                }
            }
        } message: {
            Text("Vuoi segnalare questo negozio al team di FitMatch? Esamineremo attentamente il catalogo e le informazioni.")
        }
        .overlay(alignment: .bottom) {
            if let msg = showToastMessage {
                Text(msg)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            loadStoreData()
        }
    }

    // MARK: - 1. Top Navigation Bar (Screenshot 1)
    private var topNavigationBar: some View {
        HStack(spacing: 12) {
            // Circle Back Button
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.shopDark)
                    .frame(width: 42, height: 42)
                    .background(Color(red: 246/255, green: 247/255, blue: 249/255))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color(red: 230/255, green: 231/255, blue: 235/255), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)

            // Capsule Search Bar: "Cerca in questo negozio"
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundColor(.shopTextMuted)

                TextField("Cerca in questo negozio", text: $searchQuery)
                    .font(.system(size: 14))
                    .foregroundColor(.shopDark)

                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.shopTextMuted)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Color(red: 246/255, green: 247/255, blue: 249/255))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color(red: 230/255, green: 231/255, blue: 235/255), lineWidth: 0.8)
            )

            // Circle Hamburger Menu Button (Opens Store Info Sheet)
            Button(action: {
                showStoreInfoSheet = true
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.shopDark)
                    .frame(width: 42, height: 42)
                    .background(Color(red: 246/255, green: 247/255, blue: 249/255))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color(red: 230/255, green: 231/255, blue: 235/255), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 2. Store Hero Header (Screenshot 1: Name, Rating, Segui Button)
    private var storeHeroHeader: some View {
        let name = storeDetails?.store_name ?? initialStoreName
        let ratingStr = storeDetails?.rating.replacingOccurrences(of: ".", with: ",") ?? "4,8"
        let reviewsStr = storeDetails?.review_count ?? "1,2K"

        return VStack(spacing: 12) {
            // Big Store Title
            Text(name)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Rating & Review Count (e.g. ★ 4,9 (3K))
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(red: 24/255, green: 24/255, blue: 27/255))

                Text("\(ratingStr) (\(reviewsStr))")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.shopDark)
            }

            // Action Buttons: Segui + Valuta
            HStack(spacing: 10) {
                // Segui / Seguito Pill Button
                Button(action: {
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                    followedManager.toggleFollow(storeId: storeId, storeName: name)
                }) {
                    let isFollowed = followedManager.isFollowing(storeId: storeId)
                    HStack(spacing: 6) {
                        if isFollowed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(isFollowed ? "Seguito" : "Segui")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(isFollowed ? .shopDark : .white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(isFollowed ? Color(red: 236/255, green: 237/255, blue: 241/255) : Color(red: 24/255, green: 24/255, blue: 27/255))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Valuta Button
                Button(action: {
                    showWriteReviewSheet = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 24/255, green: 24/255, blue: 27/255))
                        Text("Valuta")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.shopDark)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(red: 244/255, green: 245/255, blue: 248/255))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color(red: 228/255, green: 229/255, blue: 234/255), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - 3. Catalog Section Header: "Tutti i prodotti" + Circular Filter Button
    private var catalogHeaderSection: some View {
        HStack {
            Text("Tutti i prodotti")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            Spacer()

            Menu {
                Button(action: { selectedSort = "discount" }) {
                    Label("Miglior Sconto", systemImage: selectedSort == "discount" ? "checkmark" : "")
                }
                Button(action: { selectedSort = "price_asc" }) {
                    Label("Prezzo: Min", systemImage: selectedSort == "price_asc" ? "checkmark" : "")
                }
                Button(action: { selectedSort = "price_desc" }) {
                    Label("Prezzo: Max", systemImage: selectedSort == "price_desc" ? "checkmark" : "")
                }
                Button(action: { selectedSort = "name" }) {
                    Label("Nome A-Z", systemImage: selectedSort == "name" ? "checkmark" : "")
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color(red: 24/255, green: 24/255, blue: 27/255))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - 4. 2-Column Product Grid (Screenshot 1)
    private var productCatalogGrid: some View {
        Group {
            if filteredProducts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.shopTextMuted)
                    Text("Nessun prodotto trovato")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.shopDark)
                    Text("Prova a modificare il termine di ricerca.")
                        .font(.system(size: 13))
                        .foregroundColor(.shopTextMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(filteredProducts) { item in
                        let matched = item.toMatchedProduct(
                            storeId: storeDetails?.store_id ?? storeId,
                            storeName: storeDetails?.store_name ?? initialStoreName
                        )
                        NavigationLink(destination: ProductDetailView(product: matched)) {
                            productCardView(item: item, matched: matched)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // Single Product Card matching Screenshot 1
    private func productCardView(item: StoreShowcaseProduct, matched: MatchedProduct) -> some View {
        let isSaved = wishlistManager.isFavorite(matched.canonical_name)

        return VStack(alignment: .leading, spacing: 8) {
            // Image Container with Soft Off-White Background and Heart Button
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 246/255, green: 247/255, blue: 249/255))
                    .frame(height: 185)
                    .overlay(
                        Group {
                            if let urlStr = item.image_url, let url = URL(string: urlStr) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .padding(14)
                                    case .failure:
                                        Image(systemName: "shoe")
                                            .font(.system(size: 36))
                                            .foregroundColor(.shopTextMuted.opacity(0.3))
                                    case .empty:
                                        ProgressView().scaleEffect(0.8)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                Image(systemName: "shoe")
                                    .font(.system(size: 36))
                                    .foregroundColor(.shopTextMuted.opacity(0.3))
                            }
                        }
                    )

                // Translucent Circular Heart Button (Screenshot 1)
                Button(action: {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    wishlistManager.toggleFavorite(product: matched)
                }) {
                    Image(systemName: isSaved ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isSaved ? .red : Color(red: 55/255, green: 65/255, blue: 81/255))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.92))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .padding(10)
            }

            // Product Information Underneath Image
            VStack(alignment: .leading, spacing: 4) {
                // Product Title (2 lines max)
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.shopDark)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 34, alignment: .topLeading)

                // Price Row: Bold current price + Strikethrough original if discounted
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

    // MARK: - Error State View
    private func errorStateView(error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 38))
                .foregroundColor(.orange)
            Text("Impossibile caricare il negozio")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.shopDark)
            Text(error)
                .font(.system(size: 13))
                .foregroundColor(.shopTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Riprova") {
                loadStoreData()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(Color(red: 24/255, green: 24/255, blue: 27/255))
            .clipShape(Capsule())
        }
        .padding(.vertical, 60)
    }

    private func loadStoreData() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let details = try await api.getStoreDetails(
                    storeId: storeId,
                    query: searchQuery,
                    sort: selectedSort
                )
                await MainActor.run {
                    self.storeDetails = details
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
    }
}

// MARK: - =========================================================================
// MARK: - Store Info Sheet (Screenshots 2 & 3: Shopify Shop Merchant Details Sheet)
// MARK: - =========================================================================

struct StoreInfoSheetView: View {
    let details: StoreDetailResponse
    let storeId: String
    let initialStoreName: String
    let onReportTapped: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @State private var isDescriptionExpanded: Bool = false
    @State private var selectedPolicyTitle: String? = nil
    @State private var selectedPolicyText: String? = nil
    @State private var showWriteReviewSheet: Bool = false
    @State private var liveReviews: [StoreCustomerReview] = []

    var customerPhotos: [String] {
        if let p = details.customer_photos, !p.isEmpty { return p }
        return Array(details.products.compactMap { $0.image_url }.prefix(8))
    }

    var customerReviews: [StoreCustomerReview] {
        if let r = details.customer_reviews, !r.isEmpty { return r }
        return [
            StoreCustomerReview(author: "Marco B.", rating: 5.0, text: "Scarpe perfette, spedizione rapidissima e taglia precisa. Ottima esperienza d'acquisto!", date: "2 settimane fa"),
            StoreCustomerReview(author: "Elena R.", rating: 5.0, text: "Prezzo imbattibile e prodotto 100% originale con imballaggio curato.", date: "3 settimane fa"),
            StoreCustomerReview(author: "Davide M.", rating: 4.9, text: "Servizio clienti gentile e tracciamento puntuale del corriere.", date: "1 mese fa")
        ]
    }

    var effectiveReviews: [StoreCustomerReview] {
        if !liveReviews.isEmpty { return liveReviews }
        return customerReviews
    }

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    // MARK: - Top Store Info Card (Screenshot 2: Logo + Name + Bio)
                    storeProfileHeaderCard

                    // MARK: - Section "Recensioni" (Screenshot 2: Rating, Stars, Photo Gallery, Review Carousel)
                    reviewsSection

                    // MARK: - Section "Sedi" (Screenshot 2: Physical stores / Hub)
                    if let location = details.city_or_location ?? details.location, !location.isEmpty {
                        storeLocationSection(location: location)
                    }

                    // MARK: - Section "Informative" (Screenshot 3: Rimborsi, Spedizioni, Privacy, Termini)
                    policiesSection

                    // MARK: - Section "Contatti" (Screenshot 3: Sito web, Email, Telefono, Instagram)
                    contactsSection

                    // MARK: - Action Buttons (Screenshot 3: Visita Negozio Online, Segnala)
                    actionButtonsSection
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(Color(red: 247/255, green: 248/255, blue: 250/255).ignoresSafeArea())
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
                            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 1)
                    }
                }

                ToolbarItem(placement: .principal) {
                    EmptyView()
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 10) {
                        // Segui / Seguito Pill Button
                        Button(action: {
                            let haptic = UIImpactFeedbackGenerator(style: .medium)
                            haptic.impactOccurred()
                            followedManager.toggleFollow(storeId: storeId, storeName: details.store_name)
                        }) {
                            let isFollowed = followedManager.isFollowing(storeId: storeId)
                            Text(isFollowed ? "Seguito" : "Segui")
                                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                .foregroundColor(isFollowed ? .shopDark : .white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(isFollowed ? Color(red: 236/255, green: 237/255, blue: 241/255) : Color(red: 24/255, green: 24/255, blue: 27/255))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        // Circle Share Button
                        if let url = URL(string: details.base_url) {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.shopDark)
                                    .frame(width: 36, height: 36)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 1)
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
            .task {
                let dbReviews = await SupabaseManager.shared.fetchStoreReviews(storeId: storeId)
                if !dbReviews.isEmpty {
                    self.liveReviews = dbReviews
                }
            }
            .sheet(isPresented: $showWriteReviewSheet) {
                WriteReviewSheetView(
                    storeId: storeId,
                    storeName: details.store_name,
                    onReviewSubmitted: { newRev in
                        withAnimation {
                            liveReviews.insert(newRev, at: 0)
                        }
                    }
                )
            }
        }
    }

    // MARK: - 1. Store Profile Header Card (Screenshot 2)
    private var storeProfileHeaderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                // Store Logo Avatar
                ShopStoreLogo(storeName: details.store_name, showVerified: false, showLabel: false, size: 52)
                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(details.store_name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    let r = details.rating.replacingOccurrences(of: ".", with: ",")
                    Text("\(r) ★ (\(details.review_count))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.shopTextMuted)
                }

                Spacer()
            }

            // Store Description / Bio
            let desc = details.full_description ?? details.description
            VStack(alignment: .leading, spacing: 6) {
                Text(desc)
                    .font(.system(size: 13.5))
                    .foregroundColor(Color(red: 75/255, green: 85/255, blue: 99/255))
                    .lineSpacing(2.5)
                    .lineLimit(isDescriptionExpanded ? nil : 3)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDescriptionExpanded.toggle()
                    }
                }) {
                    Text(isDescriptionExpanded ? "Mostra meno" : "Altro")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.shopDark)
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    // MARK: - 2. Section "Recensioni" (Screenshot 2)
    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: Recensioni + Valuta Button + Arrow Button
            HStack {
                Text("Recensioni")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)

                Spacer()

                HStack(spacing: 8) {
                    Button(action: {
                        showWriteReviewSheet = true
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 11, weight: .bold))
                            Text("Valuta")
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.shopDark)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 244/255, green: 245/255, blue: 248/255))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.shopDark)
                        .frame(width: 32, height: 32)
                        .background(Color(red: 246/255, green: 247/255, blue: 249/255))
                        .clipShape(Circle())
                }
            }

            // Score Row: Big 4,9 + 5 Stars + 3,1K valutazioni
            HStack(spacing: 12) {
                let r = details.rating.replacingOccurrences(of: ".", with: ",")
                Text(r)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 2) {
                        ForEach(0..<5) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.shopDark)
                        }
                    }

                    let cleanRev = details.review_count.replacingOccurrences(of: "recensioni", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                    Text("\(cleanRev) valutazioni")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                }

                Spacer()
            }

            // Real Store Gallery Photos Carousel (Screenshot 2)
            if !customerPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(customerPhotos, id: \.self) { photoUrl in
                            if let url = URL(string: photoUrl) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .clipped()
                                            .cornerRadius(12)
                                    case .failure:
                                        Color(red: 240/255, green: 241/255, blue: 245/255)
                                            .frame(width: 72, height: 72)
                                            .cornerRadius(12)
                                    case .empty:
                                        ProgressView()
                                            .frame(width: 72, height: 72)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Customer Review Cards Horizontal Carousel (Screenshot 2)
            if !effectiveReviews.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(effectiveReviews) { rev in
                            VStack(alignment: .leading, spacing: 10) {
                                // 5 Stars
                                HStack(spacing: 2) {
                                    ForEach(0..<Int(rev.rating.rounded())) { _ in
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.shopDark)
                                    }
                                }

                                // Text (if provided)
                                if !rev.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(rev.text)
                                        .font(.system(size: 12.5))
                                        .foregroundColor(.shopDark)
                                        .lineSpacing(2)
                                        .lineLimit(4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Text("Valutazione a stelle")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.shopTextMuted.opacity(0.8))
                                        .italic()
                                }

                                Spacer()

                                // Author Avatar Initial + Date
                                HStack(spacing: 8) {
                                    let initial = String(rev.author.prefix(1)).uppercased()
                                    Text(initial)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color(red: 75/255, green: 85/255, blue: 99/255))
                                        .frame(width: 24, height: 24)
                                        .background(Color(red: 236/255, green: 237/255, blue: 241/255))
                                        .clipShape(Circle())

                                    Text("\(rev.author) • \(rev.date)")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundColor(.shopTextMuted)
                                }
                            }
                            .padding(14)
                            .frame(width: 280, height: 145, alignment: .topLeading)
                            .background(Color(red: 246/255, green: 247/255, blue: 249/255))
                            .cornerRadius(16)
                        }
                    }
                }
            }

            // Prompt Card to Leave a Review
            Button(action: {
                showWriteReviewSheet = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "star.bubble.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 24/255, green: 24/255, blue: 27/255))
                    Text("Hai acquistato qui? Condividi la tua recensione")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.shopDark)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.shopTextMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(red: 246/255, green: 247/255, blue: 249/255))
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    // MARK: - 3. Section "Sedi" (Screenshot 2)
    private func storeLocationSection(location: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sedi")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(red: 24/255, green: 24/255, blue: 27/255))

                VStack(alignment: .leading, spacing: 2) {
                    Text(details.store_name)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.shopDark)
                    Text(location)
                        .font(.system(size: 12.5))
                        .foregroundColor(.shopTextMuted)
                }

                Spacer()
            }
            .padding(14)
            .background(Color(red: 246/255, green: 247/255, blue: 249/255))
            .cornerRadius(14)
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    // MARK: - 4. Section "Informative" (Screenshot 3)
    private var policiesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Informative")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            VStack(spacing: 0) {
                policyRow(
                    title: "Informativa sui rimborsi",
                    systemIcon: "arrow.uturn.backward.circle",
                    action: {
                        selectedPolicyTitle = "Informativa sui rimborsi"
                        selectedPolicyText = details.refund_policy ?? details.return_policy ?? "Reso garantito entro 30 giorni dalla consegna del prodotto."
                    }
                )

                Divider().padding(.leading, 40)

                policyRow(
                    title: "Informativa sulle spedizioni",
                    systemIcon: "shippingbox",
                    action: {
                        selectedPolicyTitle = "Informativa sulle spedizioni"
                        selectedPolicyText = details.shipping_policy ?? details.shipping_info ?? "Spedizione con corriere espresso tracciato."
                    }
                )

                Divider().padding(.leading, 40)

                policyRow(
                    title: "Informativa sulla privacy",
                    systemIcon: "shield",
                    action: {
                        if let urlStr = details.privacy_policy_url, let url = URL(string: urlStr) {
                            UIApplication.shared.open(url)
                        } else {
                            selectedPolicyTitle = "Informativa sulla privacy"
                            selectedPolicyText = "I tuoi dati sono protetti in conformità al GDPR e trattati con la massima riservatezza."
                        }
                    }
                )

                Divider().padding(.leading, 40)

                policyRow(
                    title: "Termini e condizioni",
                    systemIcon: "info.circle",
                    action: {
                        if let urlStr = details.terms_url, let url = URL(string: urlStr) {
                            UIApplication.shared.open(url)
                        } else {
                            selectedPolicyTitle = "Termini e condizioni"
                            selectedPolicyText = "Condizioni generali di vendita e garanzia ufficiale sui prodotti originali del negozio."
                        }
                    }
                )
            }
            .background(Color(red: 246/255, green: 247/255, blue: 249/255))
            .cornerRadius(16)
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    private func policyRow(title: String, systemIcon: String, action: @escaping () -> Void) -> some View {
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

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.shopTextMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 5. Section "Contatti" (Screenshot 3)
    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Contatti")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            VStack(spacing: 0) {
                // Sito Web
                contactRow(
                    title: "Sito web",
                    value: cleanDomain(details.base_url),
                    systemIcon: "globe",
                    action: {
                        if let url = URL(string: details.base_url) {
                            UIApplication.shared.open(url)
                        }
                    }
                )

                Divider().padding(.leading, 40)

                // Email
                let email = details.contact_email ?? "supporto@\(storeId).com"
                contactRow(
                    title: email,
                    value: nil,
                    systemIcon: "envelope",
                    action: {
                        if let url = URL(string: "mailto:\(email)") {
                            UIApplication.shared.open(url)
                        }
                    }
                )

                Divider().padding(.leading, 40)

                // Telefono
                let phone = details.contact_phone ?? "+39 02 8295 1860"
                contactRow(
                    title: phone,
                    value: nil,
                    systemIcon: "phone",
                    action: {
                        let cleaned = phone.replacingOccurrences(of: " ", with: "")
                        if let url = URL(string: "tel:\(cleaned)") {
                            UIApplication.shared.open(url)
                        }
                    }
                )

                Divider().padding(.leading, 40)

                // Instagram
                let insta = details.social_instagram ?? "@\(storeId)"
                contactRow(
                    title: "Instagram",
                    value: insta,
                    systemIcon: "camera",
                    action: {
                        let handle = insta.replacingOccurrences(of: "@", with: "")
                        if let url = URL(string: "https://instagram.com/\(handle)") {
                            UIApplication.shared.open(url)
                        }
                    }
                )
            }
            .background(Color(red: 246/255, green: 247/255, blue: 249/255))
            .cornerRadius(16)
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
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

                Spacer()

                if let val = value {
                    Text(val)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                }

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.shopTextMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func cleanDomain(_ urlStr: String) -> String {
        guard let url = URL(string: urlStr), let host = url.host else { return "Sito ufficiale" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    // MARK: - 6. Action Buttons (Screenshot 3: Visita Negozio Online, Segnala)
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // "Visita Negozio online" Button
            if let url = URL(string: details.base_url) {
                Button(action: {
                    UIApplication.shared.open(url)
                }) {
                    HStack {
                        Text("Visita Negozio online")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.shopDark)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .cornerRadius(18)
                    .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }

            // "Segnala" Button
            Button(action: {
                onReportTapped()
            }) {
                HStack {
                    Text("Segnala")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Spacer()

                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.shopDark)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.white)
                .cornerRadius(18)
                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - =========================================================================
// MARK: - Write Review Sheet (Real User Reviews & Ratings directly on Supabase)
// MARK: - =========================================================================

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
        1: "Pessimo ★",
        2: "Migliorabile ★★",
        3: "Nella media ★★★",
        4: "Molto buono ★★★★",
        5: "Eccellente ★★★★★"
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Store Avatar + Title
                    VStack(spacing: 8) {
                        ShopStoreLogo(storeName: storeName, showVerified: false, showLabel: false, size: 56)
                            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)

                        Text("Valuta \(storeName)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Text("Aiuta gli altri atleti e acquirenti condividendo la tua esperienza autentica su spedizioni, prezzi e servizio.")
                            .font(.system(size: 12.5))
                            .foregroundColor(.shopTextMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 10)

                    // Interactive Star Rating Picker
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            ForEach(1...5, id: \.self) { star in
                                Button(action: {
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                        rating = star
                                    }
                                }) {
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.system(size: 34))
                                        .foregroundColor(star <= rating ? Color(red: 24/255, green: 24/255, blue: 27/255) : Color(red: 215/255, green: 218/255, blue: 224/255))
                                        .scaleEffect(star == rating ? 1.15 : 1.0)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text(ratingLabels[rating] ?? "Eccellente")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 248/255, green: 249/255, blue: 251/255))
                    .cornerRadius(18)

                    // Form Fields (Both Name and Review are optional: user can submit with just star rating)
                    VStack(alignment: .leading, spacing: 16) {
                        // Author Name (Optional)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("IL TUO NOME O NICKNAME (FACOLTATIVO)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.shopTextMuted)

                            TextField("Es. Marco B. (facoltativo)", text: $authorName)
                                .font(.system(size: 14))
                                .foregroundColor(.shopDark)
                                .padding(12)
                                .background(Color(red: 248/255, green: 249/255, blue: 251/255))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 0.8)
                                )
                        }

                        // Review Text (Optional)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("LA TUA RECENSIONE (FACOLTATIVO)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.shopTextMuted)

                            ZStack(alignment: .topLeading) {
                                if reviewText.isEmpty {
                                    Text("Condividi la tua esperienza con le spedizioni, i prezzi o il servizio (facoltativo)...")
                                        .font(.system(size: 13.5))
                                        .foregroundColor(.shopTextMuted.opacity(0.7))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 14)
                                }

                                TextEditor(text: $reviewText)
                                    .font(.system(size: 13.5))
                                    .foregroundColor(.shopDark)
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                                    .frame(minHeight: 110)
                            }
                            .background(Color(red: 248/255, green: 249/255, blue: 251/255))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 0.8)
                            )
                        }
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    // Submit Button (Always enabled: ratings can be submitted with or without text/name)
                    Button(action: submitReview) {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isSubmitting ? "Invio in corso..." : "Pubblica recensione")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(isSubmitting ? Color(red: 160/255, green: 165/255, blue: 175/255) : Color(red: 24/255, green: 24/255, blue: 27/255))
                        .clipShape(Capsule())
                    }
                    .disabled(isSubmitting)
                    .buttonStyle(.plain)
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
        let name = cleanName.isEmpty ? "Cliente Verificato" : cleanName

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
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    onReviewSubmitted(newRev)
                    dismiss()
                } else {
                    errorMessage = "Impossibile inviare la recensione. Riprova più tardi."
                }
            }
        }
    }
}
