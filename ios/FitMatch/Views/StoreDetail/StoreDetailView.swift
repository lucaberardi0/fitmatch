import SwiftUI

struct StoreDetailView: View {
    let storeId: String
    let initialStoreName: String

    @State private var storeDetails: StoreDetailResponse?
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var searchQuery: String = ""
    @State private var selectedSort: String = "discount"

    private let api = APIService.shared
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var filteredProducts: [StoreShowcaseProduct] {
        guard let prods = storeDetails?.products else { return [] }
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return prods
        }
        let q = searchQuery.lowercased()
        return prods.filter {
            $0.title.lowercased().contains(q) ||
            ($0.brand?.lowercased().contains(q) ?? false) ||
            $0.canonical_name.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: - Store Hero Header
                storeHeroSection

                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.shopPurple)
                        Text("Caricamento catalogo del negozio...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else if let details = storeDetails {
                    VStack(spacing: 18) {
                        // MARK: - Trust Badges
                        trustBadgesSection(details: details)

                        // MARK: - Store Key Stats
                        storeStatsSection(details: details)

                        // MARK: - Search & Sort Controls
                        filterSection(storeName: details.store_name)

                        // MARK: - Product Catalog Grid
                        productCatalogGrid(details: details)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 38))
                            .foregroundColor(.orange)
                        Text("Impossibile caricare i dati dello store")
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
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.shopPurple)
                        .cornerRadius(20)
                    }
                    .padding(.vertical, 60)
                }
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    ShopStoreLogo(storeName: storeDetails?.store_name ?? initialStoreName, showVerified: false, showLabel: false, size: 22)
                    Text(storeDetails?.store_name ?? initialStoreName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.shopDark)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if let urlStr = storeDetails?.base_url, let url = URL(string: urlStr) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.shopDark)
                    }
                }
            }
        }
        .task {
            loadStoreData()
        }
        .onChange(of: selectedSort) { _ in
            loadStoreData()
        }
    }

    // MARK: - Hero Section
    private var storeHeroSection: some View {
        let storeName = storeDetails?.store_name ?? initialStoreName
        return VStack(spacing: 14) {
            ZStack(alignment: .bottom) {
                // Branded top gradient banner
                LinearGradient(
                    colors: [
                        brandColor(for: storeName).opacity(0.18),
                        Color.shopSurface
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)

                // Large Store Logo Avatar
                ShopStoreLogo(storeName: storeName, showVerified: false, showLabel: false, size: 76)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
                    .offset(y: 38)
            }
            .padding(.bottom, 36)

            // Store Info
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(storeName)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.shopDark)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.shopPurple)
                }

                if let details = storeDetails {
                    // Rating & Reviews
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.shopYellow)
                            Text(details.rating)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.shopDark)
                        }

                        Text("•")
                            .foregroundColor(.shopTextMuted)

                        Text(details.review_count)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                    }

                    // Store Description
                    Text(details.description)
                        .font(.system(size: 13))
                        .foregroundColor(.shopTextMuted)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 24)
                        .padding(.top, 2)

                    // Visit Official Website Button
                    if let url = URL(string: details.base_url) {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.right.square.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Visita sito ufficiale")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.shopPurple)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.shopPurpleLight)
                            .clipShape(Capsule())
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Trust Badges
    private func trustBadgesSection(details: StoreDetailResponse) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(details.badges, id: \.self) { badge in
                    HStack(spacing: 5) {
                        Image(systemName: badgeIcon(for: badge))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.shopPurple)
                        Text(badge)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.shopDark)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.shopCardBg)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.shopBorder, lineWidth: 0.8)
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Key Stats
    private func storeStatsSection(details: StoreDetailResponse) -> some View {
        HStack(spacing: 12) {
            statCard(
                title: "Offerte",
                value: "\(details.total_offers)",
                subtitle: "nel catalogo",
                icon: "tag.fill"
            )

            statCard(
                title: "Sconto Medio",
                value: String(format: "-%.0f%%", details.avg_discount),
                subtitle: "risparmio",
                icon: "percent"
            )

            statCard(
                title: "A Partire Da",
                value: String(format: "€%.2f", details.min_price),
                subtitle: "prezzo minimo",
                icon: "eurosign.circle.fill"
            )
        }
        .padding(.horizontal, 16)
    }

    private func statCard(title: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.shopPurple)
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundColor(.shopTextMuted)
            }

            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(.shopDark)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.shopTextMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.shopCardBg)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.shopBorder, lineWidth: 0.8)
        )
    }

    // MARK: - Filter Section
    private func filterSection(storeName: String) -> some View {
        VStack(spacing: 10) {
            // Capsule Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.shopTextMuted)
                    .font(.system(size: 15))

                TextField("Cerca in \(storeName)...", text: $searchQuery)
                    .font(.system(size: 14))

                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.shopTextMuted)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.shopCardBg)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.shopBorder, lineWidth: 0.8)
            )

            // Sorting bar
            HStack {
                Text("\(filteredProducts.count) prodotti")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.shopTextMuted)

                Spacer()

                Menu {
                    Button("Miglior Sconto") { selectedSort = "discount" }
                    Button("Prezzo: Crescente") { selectedSort = "price_asc" }
                    Button("Prezzo: Decrescente") { selectedSort = "price_desc" }
                    Button("Nome: A-Z") { selectedSort = "name" }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                        Text(sortLabel(for: selectedSort))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.shopDark)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.shopCardBg)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.shopBorder, lineWidth: 0.8)
                    )
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Product Catalog Grid
    private func productCatalogGrid(details: StoreDetailResponse) -> some View {
        Group {
            if filteredProducts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.shopTextMuted)
                    Text("Nessun prodotto trovato")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.shopDark)
                    Text("Prova a cercare un altro termine in questo negozio.")
                        .font(.system(size: 12.5))
                        .foregroundColor(.shopTextMuted)
                }
                .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filteredProducts) { item in
                        let matched = item.toMatchedProduct(
                            storeId: details.store_id,
                            storeName: details.store_name
                        )
                        NavigationLink(destination: ProductDetailView(product: matched)) {
                            storeProductCard(item: item)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func storeProductCard(item: StoreShowcaseProduct) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Background image container
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .frame(height: 150)
                    .overlay(
                        Group {
                            if let urlStr = item.image_url, let url = URL(string: urlStr) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .padding(10)
                                    case .failure:
                                        Image(systemName: "shoe")
                                            .font(.system(size: 32))
                                            .foregroundColor(.shopTextMuted.opacity(0.4))
                                    case .empty:
                                        ProgressView().scaleEffect(0.8)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                Image(systemName: "shoe")
                                    .font(.system(size: 32))
                                    .foregroundColor(.shopTextMuted.opacity(0.4))
                            }
                        }
                    )

                // Discount Badge in Shop Purple
                if let badge = item.discountBadge {
                    Text(badge)
                        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.shopPurple)
                        .clipShape(Capsule())
                        .padding(8)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                if let brand = item.brand, !brand.isEmpty {
                    Text(brand.uppercased())
                        .font(.system(size: 9.5, weight: .heavy))
                        .foregroundColor(.shopTextMuted)
                        .lineLimit(1)
                }

                Text(item.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.shopDark)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 34, alignment: .topLeading)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.formattedPrice)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(.shopDark)

                    if let orig = item.formattedOriginalPrice {
                        Text(orig)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                            .strikethrough()
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
        .padding(6)
        .background(Color.shopCardBg)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.shopBorder, lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
    }

    // MARK: - Helpers
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
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func brandColor(for name: String) -> Color {
        let s = name.lowercased()
        if s.contains("cisalfa") { return Color(red: 227/255, green: 28/255, blue: 37/255) }
        if s.contains("maxi") { return Color(red: 245/255, green: 130/255, blue: 32/255) }
        if s.contains("mister") { return Color(red: 0/255, green: 114/255, blue: 206/255) }
        if s.contains("nencini") { return Color(red: 0/255, green: 140/255, blue: 70/255) }
        if s.contains("top4") { return Color(red: 0/255, green: 185/255, blue: 241/255) }
        if s.contains("running warehouse") || s.contains("warehouse") { return Color(red: 10/255, green: 55/255, blue: 140/255) }
        return .shopPurple
    }

    private func badgeIcon(for badge: String) -> String {
        let b = badge.lowercased()
        if b.contains("spedizione") || b.contains("consegna") { return "box.truck.fill" }
        if b.contains("reso") { return "arrow.uturn.backward.circle.fill" }
        if b.contains("ufficiale") || b.contains("autorizzato") { return "checkmark.seal.fill" }
        if b.contains("originale") || b.contains("garanzia") { return "shield.lefthalf.filled" }
        if b.contains("sconti") || b.contains("club") || b.contains("outlet") { return "tag.fill" }
        return "star.fill"
    }

    private func sortLabel(for sort: String) -> String {
        switch sort {
        case "discount": return "Sconto %"
        case "price_asc": return "Prezzo: Min"
        case "price_desc": return "Prezzo: Max"
        case "name": return "Nome"
        default: return "Ordina"
        }
    }
}
