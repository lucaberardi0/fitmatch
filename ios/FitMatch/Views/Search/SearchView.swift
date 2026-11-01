import SwiftUI

struct SearchView: View {
    @StateObject private var api = APIService.shared
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool

    @State private var searchResults: [MatchedProduct] = []
    @State private var topSavingsItems: [MatchedProduct] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var hasSearched: Bool = false

    // Filters (Matching Shop App Screenshot 2)
    @State private var selectedFilterCountry: String? = nil // nil, "EU", "IT"
    @State private var selectedSize: String? = nil
    @State private var selectedStore: String? = nil
    @State private var sortMode: SortMode = .bestTotalPrice

    // Smart Search AI State
    @State private var smartIntent: SmartSearchIntent? = nil
    @State private var activeChips: [SmartSearchChip] = []
    @State private var isSmartSearchActive: Bool = false
    @State private var showAiExplanation: Bool = false
    @State private var overrideMaxPrice: Double? = nil

    // User Recent Activity (Shopify "Continua ad acquistare" real user history)
    @ObservedObject private var recentManager = RecentActivityManager.shared
    @State private var selectedRecentProduct: MatchedProduct? = nil

    enum SortMode: String, CaseIterable, Identifiable {
        case bestTotalPrice = "Miglior Prezzo"
        case maxSavings = "Massimo Risparmio"
        case lowestPrice = "Prezzo Minimo"
        case maxDiscount = "Maggior Sconto"

        var id: String { rawValue }
    }

    private let availableSizes = ["Tutte", "40", "41", "42", "42.5", "43", "44", "44.5", "45", "46"]

    var filteredAndSortedResults: [MatchedProduct] {
        var list = searchResults

        // Country / Store filters (Shop Screenshot 2: "Vende da 🇪🇺", "Vende da 🇮🇹")
        if let country = selectedFilterCountry {
            if country == "IT" {
                let itStores = ["cisalfa", "maxi", "mister", "nencini", "decathlon", "sportler"]
                list = list.filter { prod in
                    prod.offers.contains { off in
                        itStores.contains(where: { off.store_id.lowercased().contains($0) })
                    }
                }
            } else if country == "EU" {
                let euStores = ["top4", "depor", "alltricks", "warehouse"]
                list = list.filter { prod in
                    prod.offers.contains { off in
                        euStores.contains(where: { off.store_id.lowercased().contains($0) })
                    }
                }
            }
        }

        if let st = selectedStore, st != "Tutti" {
            list = list.filter { prod in
                prod.offers.contains { $0.store_name.lowercased().contains(st.lowercased()) }
            }
        }

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
            ZStack(alignment: .bottom) {
                Color.white.ignoresSafeArea()

                if hasSearched || !searchResults.isEmpty {
                    // SCREENSHOT 2: Results View with Top Nav, Filter Strip & Shop Cards
                    resultsView
                } else {
                    // SCREENSHOT 1: Search Typing / History View
                    searchTypingHistoryView
                }
            }
            .navigationDestination(item: $selectedRecentProduct) { prod in
                ProductDetailView(product: prod)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            .task {
                loadInitialTopSavings()
            }
        }
    }

    // MARK: - SCREENSHOT 1: Search Typing & History View
    private var searchTypingHistoryView: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Header pinned at top: "Continua ad acquistare ›" (Exact match to Screenshot 1)
                HStack(spacing: 6) {
                    Text("Continua ad acquistare")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(red: 100/255, green: 100/255, blue: 110/255))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                    Spacer()

                    if !recentManager.activities.isEmpty {
                        Button(action: {
                            withAnimation {
                                recentManager.clearAll()
                            }
                        }) {
                            Text("Cancella")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(red: 160/255, green: 160/255, blue: 170/255))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Color.white)

                // AI Quick Access Strip
                HStack(spacing: 10) {
                    NavigationLink(destination: AIAdvisorView()) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.shopPurple)
                            Text("Coach IA")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.shopPurpleLight.opacity(0.6))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.shopPurple.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: ModelCompareView()) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.blue)
                            Text("Confronta 2 Modelli")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                // Real User Recent Activity List (Searches & Viewed Products)
                ScrollView(showsIndicators: false) {
                    if recentManager.activities.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 32))
                                .foregroundColor(Color(red: 180/255, green: 180/255, blue: 190/255))
                            Text("Nessuna attività recente")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.shopDark)
                            Text("Le tue ricerche e i prodotti visualizzati appariranno qui.")
                                .font(.system(size: 12))
                                .foregroundColor(.shopTextMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(recentManager.activities) { item in
                                Button(action: {
                                    handleRecentItemTap(item)
                                }) {
                                    HStack(spacing: 16) {
                                        // Left Thumbnail / Icon Card
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 14)
                                                .fill(Color(red: 245/255, green: 245/255, blue: 247/255))
                                                .frame(width: 52, height: 52)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 14)
                                                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                                                )

                                            if let imgUrl = item.imageUrl, let url = URL(string: imgUrl) {
                                                AsyncImage(url: url) { phase in
                                                    if let img = phase.image {
                                                        img
                                                            .resizable()
                                                            .scaledToFit()
                                                            .frame(width: 42, height: 42)
                                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    } else {
                                                        Image(systemName: "shoe.fill")
                                                            .font(.system(size: 18))
                                                            .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                                                    }
                                                }
                                            } else if let sys = item.systemIcon {
                                                Image(systemName: sys)
                                                    .font(.system(size: 20, weight: .semibold))
                                                    .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                                            } else {
                                                Image(systemName: "text.bubble.fill")
                                                    .font(.system(size: 20, weight: .semibold))
                                                    .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                                            }
                                        }

                                        // Title & Date/Subtext
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.title)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.shopDark)
                                                .lineLimit(1)
                                            Text(item.formattedDate)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .contextMenu {
                                    Button(role: .destructive, action: {
                                        withAnimation {
                                            recentManager.removeActivity(item)
                                        }
                                    }) {
                                        Label("Rimuovi", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 150) // Space for bottom floating search bar and island dock
                    }
                }
            }

            // Floating Bottom Search Bar (Exact match to Screenshot 1)
            bottomSearchInputBar
                .padding(.bottom, 84)
        }
    }

    private func handleRecentItemTap(_ item: RecentActivityItem) {
        if let prod = item.productData {
            selectedRecentProduct = prod
        } else {
            searchText = item.title
            isSearchFieldFocused = false
            executeSearch()
        }
    }

    // MARK: - Floating Bottom Search Input Bar (Screenshot 1)
    private var bottomSearchInputBar: some View {
        HStack(spacing: 10) {
            // Main Search Capsule
            HStack(spacing: 10) {
                // Camera Icon (Visual search scanner)
                Button(action: {
                    // Visual search camera trigger
                }) {
                    Image(systemName: "camera")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
                }
                .padding(.leading, 4)

                // Input Field
                TextField("Cerca o chiedi qualsiasi c...", text: $searchText)
                    .font(.system(size: 15.5))
                    .foregroundColor(.shopDark)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        executeSearch()
                    }

                // Circular Submit Arrow Button
                Button(action: {
                    executeSearch()
                }) {
                    Circle()
                        .fill(searchText.isEmpty ? Color(red: 235/255, green: 235/255, blue: 238/255) : Color.shopDark)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(searchText.isEmpty ? Color(red: 140/255, green: 140/255, blue: 150/255) : .white)
                        )
                }
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white)
            .cornerRadius(28)
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 3)

            // Separate Circular Dismiss Button (✕)
            Button(action: {
                isSearchFieldFocused = false
                searchText = ""
            }) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.shopDark)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 10, y: 3)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - SCREENSHOT 2: Search Results View
    private var resultsView: some View {
        VStack(spacing: 0) {
            // Pinned Top Header (Back + Search + Filter Pills) with solid opaque background
            VStack(spacing: 0) {
                // 1. Top Nav Bar (Exact match to Screenshot 2: Back Button + Wide Search Pill)
                HStack(spacing: 12) {
                    // Circular Back Button (<)
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            hasSearched = false
                            searchResults = []
                            smartIntent = nil
                            activeChips = []
                            isSmartSearchActive = false
                        }
                    }) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 42, height: 42)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                            )
                            .overlay(
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.shopDark)
                            )
                    }

                    // Wide Search Capsule Pill (Tap to re-edit)
                    Button(action: {
                        hasSearched = false
                        isSearchFieldFocused = true
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Color(red: 80/255, green: 80/255, blue: 90/255))

                            Text(searchText.isEmpty ? "Cerca prodotto..." : searchText)
                                .font(.system(size: 15.5, weight: .medium))
                                .foregroundColor(.shopDark)
                                .lineLimit(1)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10.5)
                        .background(Color(red: 243/255, green: 243/255, blue: 245/255))
                        .cornerRadius(24)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

                // 2. Horizontal Filter Strip (Exact match to Screenshot 2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // A. Sliders Filter Icon Button
                        Button(action: {
                            withAnimation { showAiExplanation.toggle() }
                        }) {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.shopDark)
                            }
                            .frame(width: 40, height: 36)
                            .background(Color.white)
                            .cornerRadius(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
                            )
                        }

                        // B. "Vende da 🇪🇺" Filter Pill
                        let isEUSelected = (selectedFilterCountry == "EU")
                        Button(action: {
                            withAnimation {
                                selectedFilterCountry = isEUSelected ? nil : "EU"
                            }
                        }) {
                            HStack(spacing: 5) {
                                Text("Vende da 🇪🇺")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.shopDark)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(isEUSelected ? Color.shopPurpleLight : Color.white)
                            .cornerRadius(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(isEUSelected ? Color.shopPurple : Color.black.opacity(0.12), lineWidth: 1)
                            )
                        }

                        // C. "Vende da 🇮🇹" Filter Pill
                        let isITSelected = (selectedFilterCountry == "IT")
                        Button(action: {
                            withAnimation {
                                selectedFilterCountry = isITSelected ? nil : "IT"
                            }
                        }) {
                            HStack(spacing: 5) {
                                Text("Vende da 🇮🇹")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.shopDark)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(isITSelected ? Color.shopPurpleLight : Color.white)
                            .cornerRadius(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(isITSelected ? Color.shopPurple : Color.black.opacity(0.12), lineWidth: 1)
                            )
                        }

                        // D. "Prezzo ▾" Dropdown Menu
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
                            HStack(spacing: 5) {
                                Text("Prezzo")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.shopDark)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Color.white)
                            .cornerRadius(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
                            )
                        }

                        // E. "Taglia ▾" Dropdown Menu
                        Menu {
                            ForEach(availableSizes, id: \.self) { sz in
                                Button(action: {
                                    withAnimation {
                                        selectedSize = (sz == "Tutte") ? nil : sz
                                        executeSearch()
                                    }
                                }) {
                                    HStack {
                                        Text(sz)
                                        if (sz == "Tutte" && selectedSize == nil) || (selectedSize == sz) {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(selectedSize == nil ? "Taglia" : "Tg. \(selectedSize!)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.shopDark)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(selectedSize != nil ? Color.shopPurpleLight : Color.white)
                            .cornerRadius(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(selectedSize != nil ? Color.shopPurple : Color.black.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }

                Divider()
                    .padding(.top, 4)
            }
            .background(Color.white)
            .zIndex(10)

            // 3. Product Results List (Matching Screenshot 2 Cards)
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.shopDark)
                    Text("Ricerca tra 8 negozi partner in corso...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !filteredAndSortedResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(filteredAndSortedResults) { item in
                            ShopOfficialProductCard(product: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 120) // Leave space for bottom AI assistant bar and floating dock
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.shopTextMuted)
                    Text("Nessun prodotto trovato")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.shopDark)
                    Text("Prova a cercare marchi come 'Nike', 'Hoka', 'Garmin' o 'Oakley'.")
                        .font(.system(size: 13))
                        .foregroundColor(.shopTextMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 4. Bottom AI Assistant Strip (Exact match to Screenshot 2)
            bottomAiAssistantStrip
                .padding(.bottom, 78)
        }
    }

    // MARK: - Bottom AI Assistant Strip (Screenshot 2)
    private var bottomAiAssistantStrip: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                Text(assistantSummaryText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)

                Button(action: {
                    withAnimation { showAiExplanation.toggle() }
                }) {
                    Text("Visualizza altro ›")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.shopPurple)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.white)

            // Expandable AI Explanation & Chips
            if showAiExplanation, let intent = smartIntent {
                VStack(alignment: .leading, spacing: 8) {
                    if let exp = intent.explanation, !exp.isEmpty {
                        Text(exp.replacingOccurrences(of: "**", with: ""))
                            .font(.system(size: 12.5))
                            .foregroundColor(.shopDark)
                    }

                    if !activeChips.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(activeChips) { chip in
                                    HStack(spacing: 4) {
                                        Text(chip.label)
                                            .font(.system(size: 11.5, weight: .bold))
                                            .foregroundColor(.shopDark)
                                        Button(action: {
                                            removeChip(chip)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(.shopTextMuted)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.shopBorder, lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.shopPurpleLight.opacity(0.45))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
        }
        .padding(.bottom, 6)
    }

    private var assistantSummaryText: String {
        if let intent = smartIntent, let cat = intent.category {
            return "Posso restringere \(searchText) al mondo che ti interessa: \(cat)..."
        }
        return "Posso restringere \(searchText) al mondo che ti interessa di più: running..."
    }

    // MARK: - Actions
    private func executeSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        // Record real user search to recent activity
        recentManager.recordSearch(query)

        isLoading = true
        hasSearched = true

        Task {
            do {
                let smartRes = try await api.smartSearch(
                    query: query,
                    maxPrice: overrideMaxPrice,
                    size: selectedSize,
                    store: selectedStore
                )
                await MainActor.run {
                    self.smartIntent = smartRes.intent
                    self.activeChips = smartRes.chips
                    self.searchResults = smartRes.results
                    self.isSmartSearchActive = true
                    self.isLoading = false
                }
            } catch {
                if let local = try? await api.searchCatalog(query: query, limit: 30), !local.isEmpty {
                    await MainActor.run {
                        self.searchResults = local
                        self.isSmartSearchActive = false
                        self.isLoading = false
                    }
                } else if let live = try? await api.search(query: query, size: selectedSize), !live.isEmpty {
                    await MainActor.run {
                        self.searchResults = live
                        self.isSmartSearchActive = false
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.isLoading = false
                    }
                }
            }
        }
    }

    private func removeChip(_ chip: SmartSearchChip) {
        withAnimation {
            activeChips.removeAll { $0.id == chip.id }
            if chip.param_key == "max_price" {
                overrideMaxPrice = 9999.0
            } else if chip.param_key == "size" {
                selectedSize = nil
            }
            executeSearch()
        }
    }

    private func loadInitialTopSavings() {
        Task {
            if let prods = try? await api.searchCatalog(query: "", limit: 30) {
                let sorted = prods.filter { ($0.cross_store_savings ?? 0) > 1.0 }
                    .sorted { ($0.cross_store_savings ?? 0) > ($1.cross_store_savings ?? 0) }
                await MainActor.run {
                    self.topSavingsItems = sorted
                }
            }
        }
    }
}

// MARK: - Official Shop Product Card (Exact match to Screenshot 2)
struct ShopOfficialProductCard: View {
    let product: MatchedProduct

    var sortedOffers: [Offer] {
        product.offers.sorted { $0.calculatedTotalPrice < $1.calculatedTotalPrice }
    }

    var bestOffer: Offer? { sortedOffers.first }
    var maxOffer: Offer? { sortedOffers.last }

    var savingsAmount: Double {
        guard let best = bestOffer, let max = maxOffer, max.calculatedTotalPrice > best.calculatedTotalPrice else {
            return product.cross_store_savings ?? 0.0
        }
        return max.calculatedTotalPrice - best.calculatedTotalPrice
    }

    var body: some View {
        NavigationLink(destination: ProductDetailView(product: product)) {
            HStack(alignment: .top, spacing: 14) {
                // 1. Left Image Container (Rounded 20pt, Gray Fill, with Green Badge & Heart)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(red: 243/255, green: 243/255, blue: 245/255))
                        .frame(width: 124, height: 124)

                    // Product Image
                    if let imgUrl = product.image_url, let url = URL(string: imgUrl) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img
                                    .resizable()
                                    .scaledToFit()
                                    .padding(8)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 124, height: 124)
                    }

                    // Top-Left Green Savings Pill (Exact match to Screenshot 2: "Risparmia 10 €")
                    if savingsAmount > 1.0 {
                        Text("Risparmia \(String(format: "%.0f", savingsAmount)) €")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color(red: 0/255, green: 170/255, blue: 100/255))
                            .cornerRadius(6)
                            .padding(8)
                    }

                    // Bottom-Right Translucent Heart Wishlist Button (Exact match to Screenshot 2)
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ShopTranslucentHeartButton(product: product)
                                .padding(8)
                        }
                    }
                    .frame(width: 124, height: 124)
                }

                // 2. Right Product Info Column
                VStack(alignment: .leading, spacing: 4) {
                    // Title with Gender distinction
                    Text(product.displayTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.shopDark)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Star Rating: ★★★★★ (X store)
                    HStack(spacing: 2) {
                        ForEach(0..<5) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.shopDark)
                        }
                        Text("(\(product.offers.count))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                    }
                    .padding(.top, 1)

                    // Price Row: Best Price + Strikethrough Original
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let best = bestOffer {
                            Text(String(format: "%.2f €", best.calculatedTotalPrice).replacingOccurrences(of: ".", with: ","))
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundColor(.shopDark)

                            if let max = maxOffer, max.calculatedTotalPrice > best.calculatedTotalPrice {
                                Text(String(format: "%.2f €", max.calculatedTotalPrice).replacingOccurrences(of: ".", with: ","))
                                    .font(.system(size: 12))
                                    .strikethrough()
                                    .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                            }
                        }
                    }
                    .padding(.top, 2)

                    Spacer(minLength: 4)

                    // Merchant Row: Circular Avatar + Name + Rating or Green Saving Pill
                    if let best = bestOffer {
                        HStack(spacing: 6) {
                            ShopStoreLogo(storeName: best.store_name, showVerified: false, showLabel: false, size: 18)

                            Text(best.store_name)
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.shopDark)
                                .lineLimit(1)

                            if savingsAmount > 1.0 {
                                Text("Risparmia \(String(format: "%.0f", savingsAmount)) €")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 0/255, green: 170/255, blue: 100/255))
                                    .cornerRadius(5)
                            }
                        }
                    }
                }
                .frame(height: 124)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Translucent Wishlist Heart Button (Screenshot 2)
struct ShopTranslucentHeartButton: View {
    let product: MatchedProduct
    @ObservedObject private var wishlist = WishlistManager.shared

    private var isFavorite: Bool {
        wishlist.isFavorite(product.canonical_name)
    }

    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                wishlist.toggleFavorite(product: product)
            }
        }) {
            Circle()
                .fill(Color.black.opacity(0.32))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isFavorite ? Color(red: 235/255, green: 40/255, blue: 60/255) : .white)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
