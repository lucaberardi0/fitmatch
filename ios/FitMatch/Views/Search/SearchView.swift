import SwiftUI

struct SearchView: View {
    @StateObject private var api = APIService.shared
    @State private var searchText: String = ""
    @State private var selectedSize: String? = nil
    @State private var selectedCategory: String = "all"
    @State private var selectedStore: String? = nil
    @State private var sortMode: SortMode = .bestTotalPrice

    @State private var searchResults: [MatchedProduct] = []
    @State private var topSavingsItems: [MatchedProduct] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var hasSearched: Bool = false

    enum SortMode: String, CaseIterable, Identifiable {
        case bestTotalPrice = "Miglior Prezzo Totale"
        case maxSavings = "Massimo Risparmio"
        case lowestPrice = "Prezzo Minimo"
        case maxDiscount = "Maggior Sconto"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .bestTotalPrice: return "sparkles"
            case .maxSavings: return "arrow.down.right"
            case .lowestPrice: return "tag.fill"
            case .maxDiscount: return "percent"
            }
        }
    }

    struct CategoryFilter: Identifiable {
        let id: String
        let name: String
        let icon: String
        let query: String
    }

    private let categories: [CategoryFilter] = [
        CategoryFilter(id: "all", name: "Tutto", icon: "sparkles", query: ""),
        CategoryFilter(id: "running_shoes", name: "Scarpe", icon: "shoeprints.fill", query: "Nike Pegasus"),
        CategoryFilter(id: "gps_watch", name: "GPS & Orologi", icon: "applewatch", query: "Garmin"),
        CategoryFilter(id: "hydration", name: "Zaini & Trail", icon: "backpack.fill", query: "Salomon Active Skin"),
        CategoryFilter(id: "eyewear", name: "Occhiali", icon: "eyeglasses", query: "Oakley"),
        CategoryFilter(id: "fitness", name: "Fitness & Recupero", icon: "dumbbell.fill", query: "Theragun"),
        CategoryFilter(id: "nutrition", name: "Nutrizione", icon: "bolt.fill", query: "Enervit"),
        CategoryFilter(id: "gear", name: "Ciclismo & Padel", icon: "bicycle", query: "Casco")
    ]

    private let availableSizes = ["Tutte", "40", "41", "42", "42.5", "43", "44", "44.5", "45", "46"]
    private let popularSearches = [
        "Garmin Edge", "Nike Pegasus 41", "Oakley Radar EV", "Salomon Active Skin",
        "Theragun Mini", "Asics Nimbus 26", "Polar Grit X", "Enervit Gel"
    ]

    private let partnerStores = [
        "Tutti", "Decathlon", "Cisalfa Sport", "Maxi Sport", "Mister Running", "Nencini Sport",
        "Top4Running", "Running Warehouse", "Deporvillage", "Alltricks"
    ]

    var filteredAndSortedResults: [MatchedProduct] {
        var list = searchResults

        // Filter by store
        if let st = selectedStore, st != "Tutti" {
            list = list.filter { prod in
                prod.offers.contains { $0.store_name.lowercased().contains(st.lowercased()) }
            }
        }

        // Sort results
        switch sortMode {
        case .bestTotalPrice:
            list.sort { (p1, p2) in
                let cost1 = p1.offers.map { $0.calculatedTotalPrice }.min() ?? Double.infinity
                let cost2 = p2.offers.map { $0.calculatedTotalPrice }.min() ?? Double.infinity
                return cost1 < cost2
            }
        case .maxSavings:
            list.sort { ($0.cross_store_savings ?? 0) > ($1.cross_store_savings ?? 0) }
        case .lowestPrice:
            list.sort { ($0.best_price ?? 9999) < ($1.best_price ?? 9999) }
        case .maxDiscount:
            list.sort { (p1, p2) in
                let d1 = p1.offers.compactMap { $0.discount_pct }.max() ?? 0
                let d2 = p2.offers.compactMap { $0.discount_pct }.max() ?? 0
                return d1 > d2
            }
        }

        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // 1. Header & Title
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Trova Miglior Prezzo")
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundColor(.shopDark)
                            Spacer()
                            Text("8 STORE")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(.shopPurple)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.shopPurpleLight)
                                .cornerRadius(8)
                        }

                        Text("Confronta offerte in tempo reale con calcolo effettivo delle spese di spedizione")
                            .font(.system(size: 12.5))
                            .foregroundColor(.shopTextMuted)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    // 2. Search Input Box
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.shopPurple)

                        TextField("Cerca prodotto, marca o accessorio...", text: $searchText)
                            .font(.system(size: 15))
                            .foregroundColor(.shopDark)
                            .submitLabel(.search)
                            .onSubmit {
                                executeSearch()
                            }

                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                searchResults = []
                                hasSearched = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.shopTextMuted)
                            }
                        }

                        Button(action: {
                            executeSearch()
                        }) {
                            Text("Cerca")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.shopPurple)
                                .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.shopSurface)
                    .cornerRadius(24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.shopBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)

                    // 3. Category Filter Carousel
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories) { cat in
                                let isSelected = (selectedCategory == cat.id)
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedCategory = cat.id
                                        if !cat.query.isEmpty {
                                            searchText = cat.query
                                            executeSearch()
                                        } else {
                                            loadCategoryCatalog(cat.id)
                                        }
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: cat.icon)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(cat.name)
                                            .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                                    }
                                    .foregroundColor(isSelected ? .white : .shopDark)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? Color.shopDark : Color.shopSurface)
                                    .cornerRadius(18)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .stroke(isSelected ? Color.shopDark : Color.shopBorder, lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // 4. Secondary Filters: Taglia & Ordinamento
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            // Sort Selector Menu
                            Menu {
                                ForEach(SortMode.allCases) { mode in
                                    Button(action: {
                                        withAnimation { sortMode = mode }
                                    }) {
                                        HStack {
                                            Text(mode.rawValue)
                                            if sortMode == mode {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: sortMode.icon)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.shopPurple)
                                    Text(sortMode.rawValue)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.shopDark)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.shopTextMuted)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.shopSurface)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.shopBorder, lineWidth: 1)
                                )
                            }

                            Spacer()

                            // Store Filter Menu
                            Menu {
                                ForEach(partnerStores, id: \.self) { st in
                                    Button(action: {
                                        withAnimation { selectedStore = (st == "Tutti") ? nil : st }
                                    }) {
                                        HStack {
                                            Text(st)
                                            if (selectedStore == st) || (selectedStore == nil && st == "Tutti") {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "building.2.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.shopPurple)
                                    Text(selectedStore ?? "Tutti gli Store")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9))
                                        .foregroundColor(.shopTextMuted)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.shopSurface)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.shopBorder, lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, 16)

                        // Size Pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(availableSizes, id: \.self) { sz in
                                    let isSel = (sz == "Tutte" && selectedSize == nil) || (selectedSize == sz)
                                    Button(action: {
                                        selectedSize = (sz == "Tutte") ? nil : sz
                                        executeSearch()
                                    }) {
                                        Text(sz)
                                            .font(.system(size: 11.5, weight: isSel ? .bold : .medium))
                                            .foregroundColor(isSel ? .white : .shopDark)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 5)
                                            .background(isSel ? Color.shopPurple : Color.shopSurface)
                                            .cornerRadius(12)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // 5. Content Area
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(.shopPurple)
                            Text("Confronto prezzi in tempo reale su 8 store...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else if !filteredAndSortedResults.isEmpty {
                        // Results List with Best Price Spotlight Cards
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("\(filteredAndSortedResults.count) PRODOTTI A CONFRONTO")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(.shopTextMuted)
                                    .tracking(0.6)
                                Spacer()
                                Text("Ordinato per: \(sortMode.rawValue)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.shopPurple)
                            }
                            .padding(.horizontal, 16)

                            LazyVStack(spacing: 16) {
                                ForEach(filteredAndSortedResults) { item in
                                    BestPriceProductCard(product: item)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    } else if hasSearched {
                        // Empty Search State
                        VStack(spacing: 14) {
                            Image(systemName: "magnifyingglass.circle")
                                .font(.system(size: 48))
                                .foregroundColor(.shopTextMuted)
                            Text("Nessun prodotto trovato")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.shopDark)
                            Text("Prova a cercare con un altro termine come 'Garmin', 'Nike', 'Oakley' o 'Salomon'.")
                                .font(.system(size: 13))
                                .foregroundColor(.shopTextMuted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .padding(.vertical, 50)
                    } else {
                        // Initial Default Landing State: Trending & Top Savings
                        initialLandingSection
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationBarHidden(true)
            .task {
                loadInitialTopSavings()
            }
        }
    }

    // MARK: - Initial Landing State
    private var initialLandingSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            // 1. Trending Searches
            VStack(alignment: .leading, spacing: 10) {
                Text("RICERCHE DI TENDENZA")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.shopTextMuted)
                    .tracking(0.6)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(popularSearches, id: \.self) { term in
                            Button(action: {
                                searchText = term
                                executeSearch()
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10, weight: .bold))
                                    Text(term)
                                        .font(.system(size: 12.5, weight: .semibold))
                                }
                                .foregroundColor(.shopDark)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.shopSurface)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.shopBorder, lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            // 2. Top Savings Highlight Cards
            if !topSavingsItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.orange)
                        Text("MASSIMO RISPARMIO TROVATO NEL CATALOGO")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.shopTextMuted)
                            .tracking(0.6)
                    }
                    .padding(.horizontal, 16)

                    LazyVStack(spacing: 14) {
                        ForEach(topSavingsItems.prefix(6)) { item in
                            BestPriceProductCard(product: item)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Actions
    private func executeSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isLoading = true
        hasSearched = true

        Task {
            // First load sub-millisecond local catalog
            if let local = try? await api.searchCatalog(query: query, limit: 30), !local.isEmpty {
                self.searchResults = local
                self.isLoading = false
            }

            // In background or live, query live multi-store comparison
            do {
                let live = try await api.search(query: query, size: selectedSize)
                if !live.isEmpty {
                    self.searchResults = live
                }
            } catch {
                // If live search fails, keep local results
            }
            self.isLoading = false
        }
    }

    private func loadCategoryCatalog(_ categoryId: String) {
        isLoading = true
        hasSearched = true
        Task {
            do {
                let prods = try await api.searchCatalog(query: "", category: categoryId, limit: 40)
                self.searchResults = prods
            } catch {
                self.searchResults = []
            }
            self.isLoading = false
        }
    }

    private func loadInitialTopSavings() {
        Task {
            do {
                let prods = try await api.searchCatalog(query: "", limit: 30)
                let sorted = prods.filter { ($0.cross_store_savings ?? 0) > 1.0 }
                    .sorted { ($0.cross_store_savings ?? 0) > ($1.cross_store_savings ?? 0) }
                await MainActor.run {
                    self.topSavingsItems = sorted
                }
            } catch {
                print("Error loading initial top savings: \(error)")
            }
        }
    }
}

// MARK: - Best Price Product Spotlight Card
struct BestPriceProductCard: View {
    let product: MatchedProduct

    // Order offers by total price (price + real shipping)
    var sortedOffers: [Offer] {
        product.offers.sorted { $0.calculatedTotalPrice < $1.calculatedTotalPrice }
    }

    var bestOffer: Offer? {
        sortedOffers.first
    }

    var maxOffer: Offer? {
        sortedOffers.last
    }

    var realSavings: Double {
        guard let best = bestOffer, let max = maxOffer, max.calculatedTotalPrice > best.calculatedTotalPrice else {
            return product.cross_store_savings ?? 0.0
        }
        return max.calculatedTotalPrice - best.calculatedTotalPrice
    }

    var body: some View {
        NavigationLink(destination: ProductDetailView(product: product)) {
            VStack(alignment: .leading, spacing: 0) {
                // 1. Top Section: Image + Title + Wishlist
                HStack(alignment: .top, spacing: 14) {
                    // Image Box
                    ZStack {
                        Color.shopSurface

                        if let imgUrl = product.image_url, let url = URL(string: imgUrl) {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img
                                        .resizable()
                                        .scaledToFit()
                                        .padding(6)
                                } else {
                                    Color.shopSurface
                                }
                            }
                        }
                    }
                    .frame(width: 96, height: 96)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.shopBorder, lineWidth: 0.8)
                    )

                    // Title & Store Count
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if let brand = product.brand {
                                Text(brand.uppercased())
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundColor(.shopPurple)
                            }
                            Spacer()
                            Text("\(product.offers.count) \(product.offers.count == 1 ? "STORE" : "STORE A CONFRONTO")")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.shopTextMuted)
                        }

                        Text(product.canonical_name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.shopDark)
                            .lineLimit(2)

                        Spacer()

                        // Best Price Tag
                        if let best = bestOffer {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("Miglior Prezzo Totale:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.shopTextMuted)

                                Text(best.formattedTotalPrice)
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .foregroundColor(.shopDark)
                            }
                        }
                    }
                    .frame(height: 96)
                }
                .padding(12)

                Divider()
                    .background(Color.shopBorder.opacity(0.8))

                // 2. Best Offer Spotlight Banner (Winning Store)
                if let best = bestOffer {
                    VStack(spacing: 8) {
                        HStack {
                            HStack(spacing: 6) {
                                ShopStoreLogo(storeName: best.store_name, showVerified: true, showLabel: true, size: 20)

                                Text("✓ Più conveniente")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.shopGreen)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.shopGreenLight)
                                    .cornerRadius(6)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(best.formattedPrice)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.shopDark)

                                Text(best.formattedShipping)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(best.isFreeShipping ? .shopGreen : .shopTextMuted)
                            }
                        }

                        // Savings Callout if available
                        if realSavings > 2.0 {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.right.circle.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.shopGreen)

                                Text("Risparmi fino a €\(String(format: "%.2f", realSavings)) rispetto agli altri store")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.shopGreen)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.shopGreenLight.opacity(0.6))
                            .cornerRadius(6)
                        }

                        // 3. Mini Store Comparison Rows
                        if sortedOffers.count > 1 {
                            VStack(spacing: 4) {
                                ForEach(sortedOffers.dropFirst().prefix(2)) { off in
                                    HStack {
                                        Text(off.store_name)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.shopTextMuted)
                                        Spacer()
                                        Text("\(off.formattedPrice) (\(off.formattedShipping))")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.shopDark)
                                        let diff = off.calculatedTotalPrice - best.calculatedTotalPrice
                                        if diff > 0.5 {
                                            Text("+€\(String(format: "%.0f", diff))")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.shopSurface.opacity(0.7))
                }

                // 4. Bottom Action Bar
                HStack {
                    Text("Vedi tutte le \(product.offers.count) offerte disponibili")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.shopPurple)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.shopPurple)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white)
            }
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.shopBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 5, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
