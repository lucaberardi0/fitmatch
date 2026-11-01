import SwiftUI

struct WishlistView: View {
    @Binding var selectedTab: Int
    @ObservedObject private var wishlist = WishlistManager.shared
    @StateObject private var api = APIService.shared

    @State private var searchText: String = ""
    @State private var showingAccountSheet: Bool = false
    @State private var showingNotificationsAlert: Bool = false
    @State private var showingFollowedStoresSheet: Bool = false
    @State private var showingCreateCollectionAlert: Bool = false
    @State private var newCollectionName: String = ""
    @State private var selectedProductForDetail: MatchedProduct? = nil
    @State private var selectedCollectionFilter: String = "Tutti"

    init(selectedTab: Binding<Int>? = nil) {
        if let tab = selectedTab {
            self._selectedTab = tab
        } else {
            self._selectedTab = .constant(3)
        }
    }

    private var displayItems: [WishlistItem] {
        var list = wishlist.items

        // Filter by collection
        if selectedCollectionFilter != "Tutti" {
            list = list.filter {
                $0.collectionName?.caseInsensitiveCompare(selectedCollectionFilter) == .orderedSame
            }
        }

        // Filter by search text
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter {
                $0.canonical_name.lowercased().contains(query) ||
                ($0.brand?.lowercased().contains(query) ?? false) ||
                ($0.bestStore?.lowercased().contains(query) ?? false)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - 1. Pinned Header: Avatar 'L', Search Bar, Bell
                headerBar
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                // MARK: - 2. Nav Pills: Per te, Offerte, Segui già, Salvati
                navigationPills
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)

                // MARK: - Main Scroll Content
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // MARK: - 3. "Collezioni >" Section Card
                        collectionsSection
                            .padding(.horizontal, 16)

                        // MARK: - 4. Saved Items Grid (2 Columns matching Screenshot)
                        if displayItems.isEmpty {
                            emptySavedState
                                .padding(.horizontal, 16)
                                .padding(.top, 30)
                        } else {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 14),
                                    GridItem(.flexible(), spacing: 14)
                                ],
                                spacing: 20
                            ) {
                                ForEach(displayItems) { item in
                                    SavedProductCard(
                                        item: item,
                                        onTap: {
                                            selectedProductForDetail = item.toMatchedProduct()
                                        },
                                        onToggleFavorite: {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                                                wishlist.removeFromWishlist(item.canonical_name)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        // Space for floating island dock
                        Spacer(minLength: 120)
                    }
                    .padding(.top, 4)
                }
                .refreshable {
                    await wishlist.syncWithDatabase()
                }
            }
            .background(Color(red: 250/255, green: 250/255, blue: 252/255).ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAccountSheet) {
                AccountView()
            }
            .sheet(isPresented: $showingFollowedStoresSheet) {
                FollowedStoresSheet()
            }
            .sheet(item: $selectedProductForDetail) { product in
                ProductDetailView(product: product)
            }
            .alert("Nuova Collezione", isPresented: $showingCreateCollectionAlert) {
                TextField("Es. Sneakers, Running, Estate...", text: $newCollectionName)
                Button("Annulla", role: .cancel) { newCollectionName = "" }
                Button("Crea") {
                    if !newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        wishlist.createCollection(name: newCollectionName)
                        selectedCollectionFilter = newCollectionName
                        newCollectionName = ""
                    }
                }
            } message: {
                Text("Crea una raccolta per organizzare i tuoi articoli salvati.")
            }
            .alert("Notifiche Attive", isPresented: $showingNotificationsAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Riceverai avvisi e notifiche push appena i prezzi dei tuoi articoli preferiti scendono.")
            }
        }
    }

    // MARK: - Header Bar (Avatar "L", Search Bar, Bell)

    private var headerBar: some View {
        HStack(spacing: 12) {
            // User Avatar (Purple circle with 'L')
            Button(action: { showingAccountSheet = true }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 196/255, green: 181/255, blue: 253/255))
                        .frame(width: 42, height: 42)

                    Text("L")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)

            // Search Bar ("Cerca")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))

                TextField("Cerca", text: $searchText)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 170/255, green: 170/255, blue: 180/255))
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.white)
            .cornerRadius(22)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
            )

            // Bell Button
            Button(action: { showingNotificationsAlert = true }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 42, height: 42)
                        .overlay(
                            Circle()
                                .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
                        )

                    Image(systemName: "bell.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Navigation Pills (Per te, Offerte, Segui già, Salvati)

    private var navigationPills: some View {
        HStack(spacing: 4) {
            // Per te
            Button(action: {
                withAnimation(.spring(response: 0.25)) { selectedTab = 0 }
            }) {
                Text("Per te")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 50/255, green: 50/255, blue: 55/255))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Spacer()

            // Offerte
            Button(action: {
                withAnimation(.spring(response: 0.25)) { selectedTab = 2 }
            }) {
                Text("Offerte")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 50/255, green: 50/255, blue: 55/255))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Spacer()

            // Segui già
            Button(action: {
                showingFollowedStoresSheet = true
            }) {
                Text("Segui già")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 50/255, green: 50/255, blue: 55/255))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Spacer()

            // Salvati (Active Pill matching Screenshot)
            ZStack {
                Capsule()
                    .fill(Color.white)
                    .overlay(
                        Capsule()
                            .stroke(Color(red: 230/255, green: 230/255, blue: 235/255), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)

                Text("Salvati")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 20/255, green: 20/255, blue: 25/255))
            }
            .frame(width: 90, height: 38)
        }
    }

    // MARK: - "Collezioni >" Section

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title + Chevron
            HStack(spacing: 6) {
                Text("Collezioni")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 20/255, green: 20/255, blue: 25/255))

                Button(action: {
                    showingCreateCollectionAlert = true
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 80/255, green: 80/255, blue: 90/255))
                        .padding(5)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Circle())
                }

                Spacer()

                if selectedCollectionFilter != "Tutti" {
                    Button(action: {
                        withAnimation { selectedCollectionFilter = "Tutti" }
                    }) {
                        HStack(spacing: 4) {
                            Text(selectedCollectionFilter)
                                .font(.system(size: 12, weight: .bold))
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(red: 92/255, green: 60/255, blue: 245/255))
                        .cornerRadius(12)
                    }
                }
            }

            // Collection Big Card (+ Crea collezione + Mini thumbnails stack)
            VStack(spacing: 0) {
                Spacer()

                // Center: "+ Crea collezione"
                Button(action: { showingCreateCollectionAlert = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Crea collezione")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                }
                .buttonStyle(.plain)

                Spacer()

                // Bottom row: Thumbnail strip of saved products from Database with subtle perspective tilt
                HStack(spacing: 8) {
                    let items = Array(wishlist.items.prefix(6).enumerated())
                    let angles: [Double] = [-3, 2, -2, 3, -1, 2]

                    ForEach(items, id: \.element.id) { index, previewItem in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)

                            if let urlStr = previewItem.image_url, let url = URL(string: urlStr) {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable()
                                            .scaledToFit()
                                            .padding(4)
                                    } else {
                                        Image(systemName: "shoeprints.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(Color(red: 190/255, green: 190/255, blue: 200/255))
                                    }
                                }
                            } else {
                                Image(systemName: "shoeprints.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(red: 190/255, green: 190/255, blue: 200/255))
                            }
                        }
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(index < angles.count ? angles[index] : 0))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(Color(red: 243/255, green: 244/255, blue: 247/255))
            .cornerRadius(24)
        }
    }

    // MARK: - Empty State

    private var emptySavedState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(red: 237/255, green: 233/255, blue: 254/255))
                    .frame(width: 80, height: 80)

                Image(systemName: "heart.slash")
                    .font(.system(size: 34))
                    .foregroundColor(Color(red: 109/255, green: 40/255, blue: 217/255))
            }

            VStack(spacing: 6) {
                Text("Nessun articolo salvato")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

                Text("Tocca l'icona del cuore sui prodotti per monitorare prezzi e offerte in tempo reale dal database.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button(action: {
                Task {
                    await wishlist.syncWithDatabase()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Carica dal Database")
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color(red: 92/255, green: 60/255, blue: 245/255))
                .cornerRadius(20)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Saved Product Card (Exact Match to Reference Screenshot)

struct SavedProductCard: View {
    let item: WishlistItem
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: Image Box Container
            ZStack {
                // Background Rounded Card
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(red: 243/255, green: 244/255, blue: 247/255))
                    .frame(height: 195)

                // Product Image
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
                                Image(systemName: "shoe.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(Color(red: 200/255, green: 200/255, blue: 210/255))
                            case .empty:
                                ProgressView()
                                    .tint(Color(red: 92/255, green: 60/255, blue: 245/255))
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "shoe.fill")
                            .font(.system(size: 40))
                            .foregroundColor(Color(red: 200/255, green: 200/255, blue: 210/255))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: 195)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            .overlay(alignment: .topLeading) {
                // Top-Left Discount Badge ("23% di sconto")
                if let discountText = item.discountBadgeText {
                    Text(discountText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(Capsule().fill(Color.black))
                        .padding(.top, 10)
                        .padding(.leading, 10)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Bottom-Right Purple Heart Button
                Button(action: {
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    onToggleFavorite()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 92/255, green: 60/255, blue: 245/255))
                            .frame(width: 34, height: 34)
                            .shadow(color: Color(red: 92/255, green: 60/255, blue: 245/255).opacity(0.35), radius: 5, y: 2)

                        Image(systemName: "heart.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                .padding(.bottom, 10)
            }

            // MARK: Text Information Below Image
            VStack(alignment: .leading, spacing: 3) {
                // Store / Brand Name (e.g. SneakerAsk, Kith, Maxi Sport)
                Text(item.bestStore ?? item.brand ?? "Partner Store")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(red: 115/255, green: 115/255, blue: 125/255))
                    .lineLimit(1)

                // Product Title (e.g. Maison Mihara Yasuhiro Hank, Nuovo Balance 740)
                Text(item.canonical_name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 20/255, green: 20/255, blue: 25/255))
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Price Row: Bold current price + Strikethrough original price
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.formattedCurrentPrice)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(Color(red: 20/255, green: 20/255, blue: 25/255))

                    if let originalPriceText = item.formattedInitialPrice {
                        Text(originalPriceText)
                            .font(.system(size: 12.5, weight: .regular))
                            .strikethrough(true, color: Color(red: 140/255, green: 140/255, blue: 150/255))
                            .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                    }
                }

                // Size Tag (e.g. 36 EU, 7.5, 42 EU)
                if let size = item.selectedSize, !size.isEmpty {
                    Text(size)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
        }
    }
}

// MARK: - Extension to Convert WishlistItem to MatchedProduct

extension WishlistItem {
    func toMatchedProduct() -> MatchedProduct {
        let dummyOffer = Offer(
            store_id: bestStore?.lowercased().replacingOccurrences(of: " ", with: "") ?? "store",
            store_name: bestStore ?? "Store Partner",
            product_id: nil,
            title: canonical_name,
            brand: brand,
            price: currentBestPrice,
            original_price: initialPrice,
            discount_pct: discountPct,
            savings: (initialPrice > currentBestPrice) ? (initialPrice - currentBestPrice) : nil,
            url: bestStoreUrl ?? "https://fitmatch.it",
            image_url: image_url,
            available_sizes: selectedSize != nil ? [selectedSize!] : nil,
            in_stock: true,
            shipping_cost: 0.0,
            total_price: currentBestPrice,
            is_free_shipping: true,
            shipping_label: "Spedizione Gratuita",
            free_shipping_threshold: 50.0,
            courier: "Corriere Espresso"
        )
        return MatchedProduct(
            canonical_name: canonical_name,
            brand: brand,
            image_url: image_url,
            offers: [dummyOffer],
            best_price: currentBestPrice,
            highest_price: highestPrice ?? initialPrice,
            cross_store_savings: (initialPrice > currentBestPrice) ? (initialPrice - currentBestPrice) : nil
        )
    }
}
