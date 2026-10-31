import SwiftUI

struct HomeView: View {
    @StateObject private var api = APIService.shared
    @State private var searchText = "Nike Pegasus"
    @State private var selectedCategoryId: String = "all"
    @State private var selectedSize: String? = nil
    @State private var selectedStoreFilter: String? = nil
    @State private var products: [MatchedProduct] = []
    @State private var showcases: [StoreShowcase] = []
    @State private var isLoading = false
    @State private var isShowcasesLoading = false
    @State private var errorMessage: String? = nil

    private let availableSizes = ["Tutte", "40", "41", "42", "42.5", "43", "44", "44.5", "45", "46"]
    private let quickSearches = ["Tutti", "Garmin", "Oakley", "Salomon Gilet", "Theragun", "Enervit", "Nike Pegasus", "Asics Nimbus"]

    struct GearCategory: Identifiable {
        let id: String
        let name: String
        let icon: String
        let query: String
    }

    private let categories: [GearCategory] = [
        GearCategory(id: "all", name: "Tutto", icon: "sparkles", query: "Nike"),
        GearCategory(id: "shoes", name: "Scarpe", icon: "shoeprints.fill", query: "Nike Pegasus"),
        GearCategory(id: "gps", name: "GPS & Orologi", icon: "applewatch", query: "Garmin"),
        GearCategory(id: "trail", name: "Zaini & Trail", icon: "backpack.fill", query: "Salomon Active Skin"),
        GearCategory(id: "eyewear", name: "Occhiali", icon: "eyeglasses", query: "Oakley"),
        GearCategory(id: "fitness", name: "Fitness & Recupero", icon: "dumbbell.fill", query: "Theragun"),
        GearCategory(id: "nutrition", name: "Nutrizione", icon: "bolt.fill", query: "Enervit"),
        GearCategory(id: "gear", name: "Ciclismo & Padel", icon: "bicycle", query: "Casco")
    ]

    // The 8 verified partner stores
    private let partnerStores: [(name: String, color: Color, initials: String, rating: String)] = [
        ("Cisalfa Sport", Color(red: 227/255, green: 28/255, blue: 37/255), "CS", "4.8"),
        ("Maxi Sport", Color(red: 245/255, green: 130/255, blue: 32/255), "MS", "4.9"),
        ("Mister Running", Color(red: 0/255, green: 114/255, blue: 206/255), "MR", "4.9"),
        ("Nencini Sport", Color(red: 0/255, green: 140/255, blue: 70/255), "NS", "4.7"),
        ("Top4Running", Color(red: 0/255, green: 185/255, blue: 241/255), "T4", "4.8"),
        ("Running Warehouse", Color(red: 10/255, green: 55/255, blue: 140/255), "RW", "4.9"),
        ("Deporvillage", Color(red: 232/255, green: 67/255, blue: 17/255), "DV", "4.3"),
        ("Alltricks", Color(red: 0/255, green: 163/255, blue: 224/255), "AT", "4.4")
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var filteredProducts: [MatchedProduct] {
        if let store = selectedStoreFilter {
            return products.filter { p in
                p.offers.contains { $0.store_name.lowercased().contains(store.lowercased()) }
            }
        }
        return products
    }

    var filteredShowcases: [StoreShowcase] {
        if let store = selectedStoreFilter {
            return showcases.filter { $0.store_name.lowercased().contains(store.lowercased()) }
        }
        return showcases
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 1. Top Shop-style Header & Wordmark
                    HStack {
                        HStack(spacing: 6) {
                            Text("Shop")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundColor(.shopDark)

                            Text("COMPARATORE")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundColor(.shopPurple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.shopPurpleLight)
                                .cornerRadius(6)
                        }

                        Spacer()

                        NavigationLink(destination: DealsView()) {
                            Circle()
                                .fill(Color.shopSurface)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(Color.orange)
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    // 2. Shop Signature Search Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.shopTextMuted)

                        TextField("Cerca scarpe, GPS, occhiali, accessori...", text: $searchText)
                            .font(.system(size: 15))
                            .foregroundColor(.shopDark)
                            .onSubmit {
                                performSearch()
                            }

                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.shopTextMuted)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.shopSurface)
                    .cornerRadius(24) // Shop capsule
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.shopBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)

                    // 2.1 Sports Gear Categories Carousel
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories) { cat in
                                let isSelected = (selectedCategoryId == cat.id)
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedCategoryId = cat.id
                                        searchText = cat.query
                                        performSearch()
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

                    // 3. Verified Partner Retailers Carousel (8 Stores)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("NEGOZI VERIFICATI (\(partnerStores.count))")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.shopTextMuted)
                                .tracking(0.6)
                            Spacer()
                            if selectedStoreFilter != nil {
                                Button("Tutti i negozi") {
                                    withAnimation { selectedStoreFilter = nil }
                                }
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.shopPurple)
                            }
                        }
                        .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(partnerStores, id: \.name) { store in
                                    let isSelected = selectedStoreFilter?.lowercased() == store.name.lowercased()

                                    Button(action: {
                                        withAnimation {
                                            selectedStoreFilter = isSelected ? nil : store.name
                                        }
                                    }) {
                                        HStack(spacing: 8) {
                                            ShopStoreLogo(storeName: store.name, showVerified: false, showLabel: false, size: 28)

                                            VStack(alignment: .leading, spacing: 1) {
                                                HStack(spacing: 3) {
                                                    Text(store.name)
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundColor(isSelected ? .white : .shopDark)
                                                    Image(systemName: "checkmark.seal.fill")
                                                        .font(.system(size: 9))
                                                        .foregroundColor(isSelected ? .white : .shopPurple)
                                                }

                                                Text("★ \(store.rating)")
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(isSelected ? .white.opacity(0.8) : .shopTextMuted)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(isSelected ? Color.shopPurple : Color.white)
                                        .cornerRadius(20)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1)
                                        )
                                        .shadow(color: isSelected ? Color.shopPurple.opacity(0.2) : Color.black.opacity(0.02), radius: 3, y: 1)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // 4. Taglie in Stock (Size Chips)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("TAGLIE IN STOCK")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.shopTextMuted)
                                .tracking(0.6)
                            Spacer()
                            if selectedSize != nil {
                                Button("Azzera") {
                                    selectedSize = nil
                                    performSearch()
                                }
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.shopPurple)
                            }
                        }
                        .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(availableSizes, id: \.self) { sz in
                                    let isSelected = (sz == "Tutte" && selectedSize == nil) || (selectedSize == sz)
                                    Button(action: {
                                        selectedSize = (sz == "Tutte") ? nil : sz
                                        performSearch()
                                    }) {
                                        SizeChip(size: sz, isSelected: isSelected)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // 5. Category Quick Filter Pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickSearches, id: \.self) { term in
                                let isSelected = (term == "Tutti" && searchText.isEmpty) || (searchText == term)
                                Button(action: {
                                    searchText = (term == "Tutti") ? "running" : term
                                    performSearch()
                                }) {
                                    Text(term)
                                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                        .foregroundColor(isSelected ? .white : .shopDark)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
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

                    // 6. Shopify Shop-Style Store Showcase Cards (Card per ciascun negozio con prodotti)
                    if !filteredShowcases.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("NEGOZI IN EVIDENZA")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(.shopTextMuted)
                                    .tracking(0.6)

                                Spacer()

                                Text("\(filteredShowcases.count) Store attivi")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.shopPurple)
                            }
                            .padding(.horizontal, 16)

                            VStack(spacing: 16) {
                                ForEach(filteredShowcases) { showcase in
                                    StoreShowcaseCard(
                                        showcase: showcase,
                                        onSelectStore: { storeName in
                                            withAnimation {
                                                selectedStoreFilter = storeName
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // 7. Multi-Store Matched Products Feed
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.shopPurple)
                                .scaleEffect(1.2)
                            Text("Scansione simultanea sugli 8 store partner...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if let error = errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 36))
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(.shopTextMuted)
                                .multilineTextAlignment(.center)
                            Button("Riprova") {
                                performSearch()
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.shopPurple)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else if !filteredProducts.isEmpty {
                        // 2-Column Product Grid
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("TUTTI I MODELLI A CONFRONTO (\(filteredProducts.count))")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(.shopTextMuted)
                                    .tracking(0.6)
                                Spacer()
                                Text("Comparati su 6 Negozi")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.shopPurple)
                            }
                            .padding(.horizontal, 16)

                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(filteredProducts) { product in
                                    NavigationLink(destination: ProductDetailView(product: product)) {
                                        ProductCardView(product: product)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Color.shopSurface.ignoresSafeArea())
            .refreshable {
                fetchShowcases()
                performSearch()
            }
            .onAppear {
                if showcases.isEmpty {
                    fetchShowcases()
                }
                if products.isEmpty {
                    performSearch()
                }
            }
        }
    }

    private func fetchShowcases() {
        isShowcasesLoading = true
        Task {
            do {
                let sc = try await api.getStoreShowcases()
                await MainActor.run {
                    self.showcases = sc
                    self.isShowcasesLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isShowcasesLoading = false
                }
            }
        }
    }

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let res = try await api.search(query: searchText, size: selectedSize)
                await MainActor.run {
                    self.products = res
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Impossibile collegarsi al server FitMatch. Verifica che il backend sia attivo su http://localhost:8000."
                    self.isLoading = false
                }
            }
        }
    }
}
