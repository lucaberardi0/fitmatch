import SwiftUI

struct ComparisonPair: Identifiable {
    var id: String { "\(modelA)_\(modelB)" }
    let modelA: String
    let modelB: String
}

struct SearchView: View {
    @StateObject private var api = APIService.shared
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool

    @State private var searchResults: [MatchedProduct] = []
    @State private var topSavingsItems: [MatchedProduct] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var hasSearched: Bool = false

    // Shopify Shop Intelligent Search Mode (AI Deep Dive vs Classic)
    @State private var isDeepDiveMode: Bool = true
    @State private var conversationalHeader: String = "Ho cercato prodotti"
    @State private var conversationalSummary: String = ""
    @State private var curatedSections: [CuratedProductSection] = []
    @State private var comparativeCards: [ComparativeSpecCard] = []
    @State private var spotlight: SpotlightRecommendation? = nil
    @State private var followUpSuggestions: [String] = []
    @State private var followUpInputText: String = ""
    @State private var userFeedback: Int? = nil // 1 for thumbs up, -1 for down

    // Comparison Navigation State
    @State private var comparisonModels: ComparisonPair? = nil
    @State private var showComparisonSheet: Bool = false

    // Filters (Classic Search Mode)
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

    // User Recent Activity & Preferences
    @ObservedObject private var recentManager = RecentActivityManager.shared
    @ObservedObject private var prefs = UserPreferencesManager.shared
    @State private var selectedRecentProduct: MatchedProduct? = nil

    enum SortMode: String, CaseIterable, Identifiable {
        case bestTotalPrice = "Miglior Prezzo"
        case maxSavings = "Massimo Risparmio"
        case lowestPrice = "Prezzo Minimo"
        case maxDiscount = "Maggior Sconto"

        var id: String { rawValue }
    }

    private let availableSizes = ["Tutte", "40", "41", "42", "42.5", "43", "44", "44.5", "45", "46"]

    init(initialSearchQuery: String? = nil) {
        _searchText = State(initialValue: initialSearchQuery ?? "")
        if ProcessInfo.processInfo.arguments.contains("-testClassicMode") {
            _isDeepDiveMode = State(initialValue: false)
        }
    }

    var filteredAndSortedResults: [MatchedProduct] {
        var list = searchResults

        if let country = selectedFilterCountry {
            if country == "IT" {
                let itStores = ["cisalfa", "maxi", "mister", "nencini", "decathlon", "sportler", "nike"]
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
                    // Results View: Dual-Mode (AI Deep Dive vs Classic)
                    resultsContainerView
                } else {
                    // Search Typing / History View
                    searchTypingHistoryView
                }
            }
            .navigationDestination(item: $selectedRecentProduct) { prod in
                ProductDetailView(product: prod)
            }
            .sheet(isPresented: $showComparisonSheet) {
                if let pair = comparisonModels {
                    ModelCompareView(initialModelA: pair.modelA, initialModelB: pair.modelB)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            .task {
                loadInitialTopSavings()
                if !searchText.isEmpty && !hasSearched {
                    executeSearch()
                }
            }
        }
    }

    // MARK: - Search Typing & History View
    private var searchTypingHistoryView: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Header pinned at top: "Continua ad acquistare ›"
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
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.shopPurple)
                            Text("Chiedi al Personal Shopper IA")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.shopPurple)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.shopPurple.opacity(0.6))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.shopPurpleLight)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Section 1: Recent Activity Carousel
                        if !recentManager.activities.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(recentManager.activities) { act in
                                            recentActivityCard(act)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }

                        // Section 2: Quick Search Prompts
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Suggerimenti di Ricerca")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                                .padding(.horizontal, 20)

                            VStack(spacing: 8) {
                                smartPromptRow(
                                    icon: "sparkles",
                                    title: "Scarpe running ammortizzate per ginocchia pesanti",
                                    query: "scarpe running ammortizzate per ginocchia pesanti sotto 150 euro"
                                )
                                smartPromptRow(
                                    icon: "bolt.fill",
                                    title: "Super scarpe veloci con piastra in carbonio",
                                    query: "scarpe running con piastra in carbonio gara"
                                )
                                smartPromptRow(
                                    icon: "figure.run",
                                    title: "Migliori scarpe per iniziare a correre",
                                    query: "scarpe comode per iniziare a correre asfalto"
                                )
                                smartPromptRow(
                                    icon: "applewatch",
                                    title: "Smartwatch GPS Garmin Forerunner",
                                    query: "garmin forerunner 165 orologio corsa"
                                )
                            }
                            .padding(.horizontal, 20)
                        }

                        // Section 3: Trending Deals in Italy
                        if !topSavingsItems.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Offerte Più Convenienti di Oggi")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.shopDark)
                                    Spacer()
                                    Text("Multinegozio")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(.shopPurple)
                                }
                                .padding(.horizontal, 20)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(topSavingsItems.prefix(8)) { prod in
                                            trendingDealCard(prod)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }

                        Spacer(minLength: 140)
                    }
                    .padding(.top, 4)
                }
            }

            // Floating Bottom Search Pill Bar
            floatingSearchInputBar
                .padding(.bottom, 78)
        }
    }

    private func smartPromptRow(icon: String, title: String, query: String) -> some View {
        Button(action: {
            searchText = query
            executeSearch()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.shopPurple)
                    .frame(width: 24, height: 24)
                    .background(Color.shopPurpleLight)
                    .clipShape(Circle())

                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "arrow.up.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 180/255, green: 180/255, blue: 190/255))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(red: 248/255, green: 248/255, blue: 250/255))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
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

    private func recentActivityCard(_ act: RecentActivityItem) -> some View {
        Button(action: {
            handleRecentItemTap(act)
        }) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 245/255, green: 245/255, blue: 247/255))
                        .frame(width: 104, height: 104)

                    if let img = act.imageUrl, let url = URL(string: img) {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 300) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 104, height: 104)
                                    .cornerRadius(14)
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: 14, width: 104, height: 104)
                            default:
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 24))
                                    .foregroundColor(.gray.opacity(0.35))
                                    .frame(width: 104, height: 104)
                            }
                        }
                    } else if let sys = act.systemIcon {
                        Image(systemName: sys)
                            .font(.system(size: 24))
                            .foregroundColor(.gray.opacity(0.4))
                            .frame(width: 104, height: 104)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(.gray.opacity(0.4))
                            .frame(width: 104, height: 104)
                    }
                }

                Text(act.title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)
                    .frame(width: 104, alignment: .leading)

                if let prod = act.productData, let best = prod.best_price {
                    Text(String(format: "%.2f €", best).replacingOccurrences(of: ".", with: ","))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(.shopDark)
                }
            }
            .frame(width: 104)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func trendingDealCard(_ prod: MatchedProduct) -> some View {
        Button(action: {
            selectedRecentProduct = prod
        }) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 245/255, green: 245/255, blue: 247/255))
                        .frame(width: 118, height: 118)

                    if let img = prod.image_url, let url = URL(string: img) {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 300) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 118, height: 118)
                                    .cornerRadius(14)
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: 14, width: 118, height: 118)
                            default:
                                Image(systemName: "photo")
                                    .foregroundColor(.gray.opacity(0.35))
                                    .frame(width: 118, height: 118)
                            }
                        }
                    }

                    if let sav = prod.cross_store_savings, sav > 1.0 {
                        Text("Risparmia \(Int(sav)) €")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2.5)
                            .background(Color(red: 0/255, green: 170/255, blue: 100/255))
                            .cornerRadius(5)
                            .padding(6)
                    }
                }

                Text(prod.displayTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)
                    .frame(width: 118, alignment: .leading)

                if let price = prod.best_price {
                    HStack(spacing: 4) {
                        Text(String(format: "%.2f €", price).replacingOccurrences(of: ".", with: ","))
                            .font(.system(size: 12.5, weight: .heavy))
                            .foregroundColor(.shopDark)
                        if let max = prod.highest_price, max > price {
                            Text(String(format: "%.0f€", max))
                                .font(.system(size: 10))
                                .strikethrough()
                                .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                        }
                    }
                }
            }
            .frame(width: 118)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var floatingSearchInputBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: {}) {
                    Image(systemName: "camera")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
                }
                .padding(.leading, 4)

                TextField("Cerca o chiedi qualsiasi c...", text: $searchText)
                    .font(.system(size: 15.5))
                    .foregroundColor(.shopDark)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        handleSearchOrComparison(query: searchText)
                    }

                Button(action: {
                    handleSearchOrComparison(query: searchText)
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

    // MARK: - Dual-Mode Results Container View
    private var resultsContainerView: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if isDeepDiveMode {
                    // SCREENSHOT 1, 2, 3: AI Deep Dive Results
                    aiDeepDiveHeaderBar
                    aiDeepDiveContentView
                } else {
                    // SCREENSHOT 4: Classic Results with Filters & List
                    classicHeaderBar
                    classicContentView
                }
            }

            // Bottom Sticky Follow-up Input Bar (Screenshots 1, 2, 3, 4)
            stickyFollowUpInputBar
        }
    }

    // MARK: - AI Deep Dive: Pinned Header (Screenshot 1)
    private var aiDeepDiveHeaderBar: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 12) {
                // Back Button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        hasSearched = false
                        searchResults = []
                        curatedSections = []
                        comparativeCards = []
                        spotlight = nil
                        followUpSuggestions = []
                        isSmartSearchActive = false
                        errorMessage = nil
                    }
                }) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 42, height: 42)
                        .overlay(Circle().stroke(Color.black.opacity(0.1), lineWidth: 1))
                        .overlay(
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.shopDark)
                        )
                }

                Spacer()

                // Query Pill Bubble (Screenshot 1: "Maison margiela scarpe nere")
                Button(action: {
                    hasSearched = false
                    isSearchFieldFocused = true
                }) {
                    Text(searchText.isEmpty ? "Cerca prodotto..." : searchText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.shopDark)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color(red: 243/255, green: 243/255, blue: 245/255))
                        .cornerRadius(22)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // "🔍 Cerca invece questo" Button (Exact match to Screenshot 1!)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isDeepDiveMode = false
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .bold))
                    Text("Cerca invece questo")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(Color(red: 80/255, green: 40/255, blue: 220/255))
            }
            .padding(.trailing, 20)
            .padding(.top, 2)
            .padding(.bottom, 6)

            Divider()
        }
        .background(Color.white)
        .zIndex(10)
    }

    // MARK: - AI Deep Dive: Main Content View (Screenshots 1, 2, 3)
    private var aiDeepDiveContentView: some View {
        Group {
            if isLoading {
                ShopSearchDeepDiveSkeletonView()
                    .transition(.opacity)
            } else if let error = errorMessage {
                aiErrorView(error)
            } else if curatedSections.isEmpty && searchResults.isEmpty && spotlight == nil {
                aiEmptyView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            // 1. Header: "Ho cercato prodotti >" (Screenshot 1)
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showAiExplanation.toggle()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(conversationalHeader)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                                        .rotationEffect(.degrees(showAiExplanation ? 90 : 0))
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 18)
                            .padding(.top, 8)

                            if showAiExplanation && !activeChips.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(activeChips) { chip in
                                            ShopSearchChipView(chip: chip) {
                                                removeChip(chip)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 2)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // 2. Conversational Narrative Paragraph (Screenshot 1)
                            if !conversationalSummary.isEmpty {
                                Text(LocalizedStringKey(conversationalSummary))
                                    .font(.system(size: 15.5, weight: .regular))
                                    .foregroundColor(.shopDark)
                                    .lineSpacing(4.5)
                                    .padding(.horizontal, 18)
                            }

                            // 3. Thematic Curated Carousels (Screenshot 1 & 2)
                            if !curatedSections.isEmpty {
                                ForEach(curatedSections) { section in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(section.title)
                                            .font(.system(size: 18.5, weight: .bold))
                                            .foregroundColor(.shopDark)
                                            .padding(.horizontal, 18)

                                        Text(section.subtitle)
                                            .font(.system(size: 12.5, weight: .regular))
                                            .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
                                            .padding(.horizontal, 18)
                                            .padding(.bottom, 4)

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 14) {
                                                ForEach(section.products) { prod in
                                                    ShopThemedCarouselCard(product: prod) {
                                                        selectedRecentProduct = prod
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 4)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                            } else if !searchResults.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("I Modelli Selezionati")
                                        .font(.system(size: 18.5, weight: .bold))
                                        .foregroundColor(.shopDark)
                                        .padding(.horizontal, 18)

                                    Text("Tutti i prodotti trovati per la tua ricerca")
                                        .font(.system(size: 12.5, weight: .regular))
                                        .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
                                        .padding(.horizontal, 18)
                                        .padding(.bottom, 4)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 14) {
                                            ForEach(searchResults) { prod in
                                                ShopThemedCarouselCard(product: prod) {
                                                    selectedRecentProduct = prod
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding(.top, 8)
                            }

                            // 4. Comparative Spec Cards ("Come orientarsi" - Screenshot 3)
                            if !comparativeCards.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Come orientarsi")
                                        .font(.system(size: 18.5, weight: .bold))
                                        .foregroundColor(.shopDark)
                                        .padding(.horizontal, 18)

                                    Text("La scelta dipende soprattutto da esperienza, ritmo e tipo di corsa")
                                        .font(.system(size: 12.5, weight: .regular))
                                        .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
                                        .padding(.horizontal, 18)
                                        .padding(.bottom, 4)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(alignment: .top, spacing: 14) {
                                            ForEach(comparativeCards) { card in
                                                ShopComparativeCard(card: card) {
                                                    selectedRecentProduct = card.product
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding(.top, 10)
                                .id("comparative_section")
                            }

                            // 5. Spotlight / Best Deal Card (Screenshot 3)
                            if let spot = spotlight {
                                VStack(alignment: .leading, spacing: 6) {
                                    ShopSpotlightCardView(spotlight: spot) {
                                        selectedRecentProduct = spot.product
                                    }
                                    .padding(.horizontal, 18)
                                    .padding(.top, 10)
                                }
                                .id("spotlight_section")
                            }

                            // 5. Follow-Up Suggestion Pills (Screenshot 3)
                            if !followUpSuggestions.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(followUpSuggestions, id: \.self) { suggestion in
                                        ShopFollowUpPillButton(title: suggestion) {
                                            handleSearchOrComparison(query: suggestion)
                                        }
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.top, 14)
                                .id("followups_section")
                            }

                            // 6. AI Disclaimer & Thumbs Feedback (Screenshot 3)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("L'IA può commettere errori, ricontrolla le risposte.")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(red: 130/255, green: 130/255, blue: 140/255))
                                    .padding(.horizontal, 18)
                                    .padding(.top, 6)

                                HStack(spacing: 12) {
                                    Text("Cosa ne pensi?")
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundColor(Color(red: 100/255, green: 100/255, blue: 110/255))

                                    Button(action: {
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                        withAnimation { userFeedback = 1 }
                                    }) {
                                        Image(systemName: userFeedback == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                                            .font(.system(size: 13))
                                            .foregroundColor(userFeedback == 1 ? .shopPurple : Color(red: 100/255, green: 100/255, blue: 110/255))
                                    }

                                    Text("|")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(red: 210/255, green: 210/255, blue: 220/255))

                                    Button(action: {
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                        withAnimation { userFeedback = -1 }
                                    }) {
                                        Image(systemName: userFeedback == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                            .font(.system(size: 13))
                                            .foregroundColor(userFeedback == -1 ? .shopPurple : Color(red: 100/255, green: 100/255, blue: 110/255))
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color(red: 245/255, green: 245/255, blue: 247/255))
                                .cornerRadius(12)
                                .padding(.horizontal, 18)
                            }

                            // Spacing at bottom for floating follow-up bar and dock
                            Spacer(minLength: 130)
                        }
                    }
                    .onChange(of: curatedSections) { _ in
                        if ProcessInfo.processInfo.arguments.contains("-testAiSearchScrolled") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                withAnimation {
                                    proxy.scrollTo("spotlight_section", anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - AI Deep Dive Error & Empty Views
    private func aiErrorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.shopPurple)
                .frame(width: 76, height: 76)
                .background(Color.shopPurpleLight)
                .clipShape(Circle())

            Text("Impossibile caricare i risultati")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.shopDark)

            Text(error)
                .font(.system(size: 13.5))
                .foregroundColor(.shopTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            VStack(spacing: 10) {
                Button(action: {
                    executeSearch()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Riprova la ricerca")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: 240)
                    .padding(.vertical, 12)
                    .background(Color.shopDark)
                    .cornerRadius(22)
                }

                Button(action: {
                    withAnimation {
                        isDeepDiveMode = false
                    }
                    executeSearch()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                        Text("Passa alla ricerca classica")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.shopPurple)
                    .padding(.vertical, 8)
                }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }

    private var aiEmptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 38))
                .foregroundColor(.shopPurple)
                .frame(width: 76, height: 76)
                .background(Color.shopPurpleLight)
                .clipShape(Circle())

            Text("Nessun prodotto trovato")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.shopDark)

            Text("L'IA non ha trovato prodotti per \"\(searchText)\". Prova con parole chiave come 'Scarpe running ammortizzate' o cerca per brand.")
                .font(.system(size: 13.5))
                .foregroundColor(.shopTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            VStack(spacing: 10) {
                Button(action: {
                    executeSearch()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Ricarica")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 12)
                    .background(Color.shopDark)
                    .cornerRadius(22)
                }

                Button(action: {
                    withAnimation {
                        isDeepDiveMode = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                        Text("Passa alla ricerca classica")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.shopPurple)
                    .padding(.vertical, 8)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }

    // MARK: - Classic Mode: Pinned Header (Screenshot 4)
    private var classicHeaderBar: some View {
        VStack(spacing: 0) {
            // Top Nav Row
            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        hasSearched = false
                        searchResults = []
                        isSmartSearchActive = false
                        errorMessage = nil
                    }
                }) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 42, height: 42)
                        .overlay(Circle().stroke(Color.black.opacity(0.1), lineWidth: 1))
                        .overlay(
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.shopDark)
                        )
                }

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

                // Switch to AI Deep Dive Mode Button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isDeepDiveMode = true
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                        Text("IA")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.shopPurple)
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                    .background(Color.shopPurpleLight)
                    .cornerRadius(21)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            // Horizontal Filter Strip (Screenshot 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Sliders Filter Icon Button
                    Button(action: {
                        withAnimation { showAiExplanation.toggle() }
                    }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.shopDark)
                            .frame(width: 40, height: 36)
                            .background(Color.white)
                            .cornerRadius(18)
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.12), lineWidth: 1))
                    }

                    // "Vende da 🇪🇺" Filter Pill
                    let isEUSelected = (selectedFilterCountry == "EU")
                    Button(action: {
                        withAnimation { selectedFilterCountry = isEUSelected ? nil : "EU" }
                    }) {
                        Text("Vende da 🇪🇺")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.shopDark)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(isEUSelected ? Color.shopPurpleLight : Color.white)
                            .cornerRadius(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(isEUSelected ? Color.shopPurple : Color.black.opacity(0.12), lineWidth: 1)
                            )
                    }

                    // "Vende da 🇮🇹" Filter Pill
                    let isITSelected = (selectedFilterCountry == "IT")
                    Button(action: {
                        withAnimation { selectedFilterCountry = isITSelected ? nil : "IT" }
                    }) {
                        Text("Vende da 🇮🇹")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.shopDark)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(isITSelected ? Color.shopPurpleLight : Color.white)
                            .cornerRadius(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(isITSelected ? Color.shopPurple : Color.black.opacity(0.12), lineWidth: 1)
                            )
                    }

                    // "Prezzo ▾" Dropdown Menu
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
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.12), lineWidth: 1))
                    }

                    // "Taglia ▾" Dropdown Menu
                    Menu {
                        let prefSize = prefs.preferences.preferredShoeSize
                        if !prefSize.isEmpty {
                            Button(action: {
                                withAnimation {
                                    selectedSize = prefSize
                                    executeSearch()
                                }
                            }) {
                                HStack {
                                    Text("La tua taglia: EU \(prefSize)")
                                    if selectedSize == prefSize {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Divider()
                        }

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
    }

    // MARK: - Classic Mode: Main Content View (Screenshot 4)
    private var classicContentView: some View {
        Group {
            if isLoading {
                ShopSearchGridSkeletonView()
                    .transition(.opacity)
            } else if let error = errorMessage {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundColor(.shopPurple)
                    Text("Impossibile caricare i risultati")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.shopDark)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.shopTextMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button(action: {
                        executeSearch()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Riprova")
                        }
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.shopDark)
                        .cornerRadius(20)
                    }
                    .padding(.top, 8)
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
                    .padding(.bottom, 130)
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.shopTextMuted)
                    Text("Nessun prodotto trovato")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.shopDark)
                    Text("Prova a cercare marchi come 'Nike', 'Hoka', 'Garmin' o 'Asics'.")
                        .font(.system(size: 13))
                        .foregroundColor(.shopTextMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Sticky Bottom Follow-Up Bar (Screenshots 1, 2, 3, 4)
    private var stickyFollowUpInputBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
                .padding(.leading, 2)

            TextField("Fai una domanda di follow-up", text: $followUpInputText)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundColor(.shopDark)
                .onSubmit {
                    sendFollowUp()
                }

            if !followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: {
                    sendFollowUp()
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.shopPurple)
                }
            } else {
                Button(action: {
                    withAnimation {
                        hasSearched = false
                        isSearchFieldFocused = true
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 130/255, green: 130/255, blue: 140/255))
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
        .cornerRadius(26)
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 78) // Floating above bottom bar!
    }

    private func sendFollowUp() {
        let text = followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        followUpInputText = ""
        handleSearchOrComparison(query: text)
    }

    private func handleSearchOrComparison(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let (mA, mB) = parseComparisonQuery(trimmed) {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            comparisonModels = ComparisonPair(modelA: mA, modelB: mB)
            showComparisonSheet = true
            return
        }

        searchText = trimmed
        executeSearch()
    }

    private func parseComparisonQuery(_ text: String) -> (String, String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Pattern 1: "Confronta ModelA e ModelB" / "Compara ModelA con ModelB"
        let pattern1 = #"(?i)^(?:confronta|compara)\s+(.+?)\s+(?:e|ed|con|contro|vs\.?)\s+(.+)$"#
        if let regex1 = try? NSRegularExpression(pattern: pattern1),
           let match = regex1.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           match.numberOfRanges >= 3 {
            if let r1 = Range(match.range(at: 1), in: trimmed),
               let r2 = Range(match.range(at: 2), in: trimmed) {
                let first = String(trimmed[r1]).trimmingCharacters(in: .whitespacesAndNewlines)
                let second = String(trimmed[r2]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !first.isEmpty && !second.isEmpty {
                    return (first, second)
                }
            }
        }

        // Pattern 2: "ModelA vs ModelB" / "ModelA vs. ModelB"
        let pattern2 = #"(?i)^(.+?)\s+vs\.?\s+(.+)$"#
        if let regex2 = try? NSRegularExpression(pattern: pattern2),
           let match = regex2.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           match.numberOfRanges >= 3 {
            if let r1 = Range(match.range(at: 1), in: trimmed),
               let r2 = Range(match.range(at: 2), in: trimmed) {
                let first = String(trimmed[r1]).trimmingCharacters(in: .whitespacesAndNewlines)
                let second = String(trimmed[r2]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !first.isEmpty && !second.isEmpty {
                    return (first, second)
                }
            }
        }

        return nil
    }

    // MARK: - Search Execution
    private func executeSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        recentManager.recordSearch(query)
        isLoading = true
        hasSearched = true
        errorMessage = nil
        conversationalHeader = "Ho cercato \(query)"

        Task {
            do {
                let smartRes = try await api.smartSearch(
                    query: query,
                    maxPrice: overrideMaxPrice,
                    size: selectedSize,
                    store: selectedStore
                )
                await MainActor.run {
                    self.errorMessage = nil
                    self.smartIntent = smartRes.intent
                    self.activeChips = smartRes.chips ?? []
                    self.searchResults = smartRes.results
                    self.curatedSections = smartRes.curated_sections ?? []
                    self.comparativeCards = smartRes.comparative_cards ?? []
                    self.spotlight = smartRes.spotlight
                    self.followUpSuggestions = smartRes.follow_up_suggestions ?? []
                    self.conversationalHeader = smartRes.conversational_header ?? "Ho cercato \(query)"
                    self.conversationalSummary = smartRes.conversational_summary ?? (smartRes.intent?.explanation ?? "")
                    if ProcessInfo.processInfo.arguments.contains("-testClassicMode") {
                        self.isDeepDiveMode = false
                    } else {
                        self.isDeepDiveMode = smartRes.is_deep_dive ?? true
                    }
                    self.isSmartSearchActive = true
                    self.isLoading = false
                }
            } catch {
                if let local = try? await api.searchCatalog(query: query, limit: 30), !local.isEmpty {
                    await MainActor.run {
                        self.errorMessage = nil
                        self.searchResults = local
                        self.isDeepDiveMode = false
                        self.isSmartSearchActive = false
                        self.isLoading = false
                    }
                } else if let live = try? await api.search(query: query, size: selectedSize), !live.isEmpty {
                    await MainActor.run {
                        self.errorMessage = nil
                        self.searchResults = live
                        self.isDeepDiveMode = false
                        self.isSmartSearchActive = false
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.errorMessage = "Impossibile recuperare i risultati in questo momento. Il server potrebbe essere occupato, tocca Riprova per aggiornare."
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

// MARK: - Active Filter Chip View
struct ShopSearchChipView: View {
    let chip: SmartSearchChip
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(chip.label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.shopDark)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(red: 243/255, green: 243/255, blue: 245/255))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Horizontal Themed Carousel Card (Screenshots 1 & 2)
struct ShopThemedCarouselCard: View {
    let product: MatchedProduct
    let onTap: () -> Void

    var bestOffer: Offer? {
        product.offers.min(by: { $0.calculatedTotalPrice < $1.calculatedTotalPrice })
    }

    var maxOffer: Offer? {
        product.offers.max(by: { $0.calculatedTotalPrice < $1.calculatedTotalPrice })
    }

    var referenceOriginalPrice: Double? {
        if let best = bestOffer, let orig = best.original_price, orig > best.calculatedTotalPrice + 1 {
            return orig
        }
        if let max = maxOffer, let best = bestOffer, max.calculatedTotalPrice > best.calculatedTotalPrice + 2 {
            return max.calculatedTotalPrice
        }
        return nil
    }

    var discountBadge: String? {
        if let best = bestOffer {
            if let disc = best.discount_pct, disc >= 5 {
                return "\(disc)% di sconto"
            }
            if let orig = best.original_price, orig > best.calculatedTotalPrice + 1 {
                let pct = Int(round((orig - best.calculatedTotalPrice) / orig * 100))
                if pct >= 5 {
                    return "\(pct)% di sconto"
                }
            }
        }
        if let sav = product.cross_store_savings, sav >= 10 {
            return "Risparmia \(Int(sav)) €"
        }
        return nil
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 245/255, green: 245/255, blue: 247/255))
                        .frame(width: 152, height: 152)

                    if let imgUrl = product.image_url, let url = URL(string: imgUrl) {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 400) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 152, height: 152)
                                    .cornerRadius(16)
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: 16, width: 152, height: 152)
                            default:
                                Image(systemName: "photo")
                                    .foregroundColor(.gray.opacity(0.35))
                                    .frame(width: 152, height: 152)
                            }
                        }
                    }

                    if let badge = discountBadge {
                        Text(badge)
                            .font(.system(size: 9.5, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color(red: 215/255, green: 40/255, blue: 40/255))
                            .cornerRadius(6)
                            .padding(8)
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ShopTranslucentHeartButton(product: product)
                                .padding(8)
                        }
                    }
                    .frame(width: 152, height: 152)
                }

                if let best = bestOffer {
                    Text(best.store_name)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                        .lineLimit(1)
                }

                Text(product.displayTitle)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if let best = bestOffer {
                        Text(String(format: "€ %.2f", best.calculatedTotalPrice))
                            .font(.system(size: 13.5, weight: .heavy))
                            .foregroundColor(.shopDark)

                        if let orig = referenceOriginalPrice {
                            Text(String(format: "€ %.2f", orig))
                                .font(.system(size: 11.5))
                                .strikethrough()
                                .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                        }
                    }
                }
            }
            .frame(width: 152)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Comparative Spec Card ("Come orientarsi" - Screenshot 3)
struct ShopComparativeCard: View {
    let card: ComparativeSpecCard
    let onTap: () -> Void

    var bestOffer: Offer? {
        card.product.offers.min(by: { $0.calculatedTotalPrice < $1.calculatedTotalPrice })
    }

    var maxOffer: Offer? {
        card.product.offers.max(by: { $0.calculatedTotalPrice < $1.calculatedTotalPrice })
    }

    var referenceOriginalPrice: Double? {
        if let best = bestOffer, let orig = best.original_price, orig > best.calculatedTotalPrice + 1 {
            return orig
        }
        if let max = maxOffer, let best = bestOffer, max.calculatedTotalPrice > best.calculatedTotalPrice + 2 {
            return max.calculatedTotalPrice
        }
        return nil
    }

    var discountBadge: String? {
        if let best = bestOffer {
            if let disc = best.discount_pct, disc >= 5 {
                return "\(disc)% di sconto"
            }
            if let orig = best.original_price, orig > best.calculatedTotalPrice + 1 {
                let pct = Int(round((orig - best.calculatedTotalPrice) / orig * 100))
                if pct >= 5 {
                    return "\(pct)% di sconto"
                }
            }
        }
        if let sav = card.product.cross_store_savings, sav >= 10 {
            return "Risparmia \(Int(sav)) €"
        }
        return nil
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // 1. Top Image with Discount Badge & Translucent Heart Button
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 245/255, green: 245/255, blue: 247/255))
                        .frame(width: 200, height: 150)

                    if let imgUrl = card.product.image_url, let url = URL(string: imgUrl) {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 400) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 200, height: 150)
                                    .cornerRadius(16)
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: 16, width: 200, height: 150)
                            default:
                                Image(systemName: "photo")
                                    .foregroundColor(.gray.opacity(0.35))
                                    .frame(width: 200, height: 150)
                            }
                        }
                    }

                    if let badge = discountBadge {
                        Text(badge)
                            .font(.system(size: 9.5, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color(red: 215/255, green: 40/255, blue: 40/255))
                            .cornerRadius(6)
                            .padding(8)
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ShopTranslucentHeartButton(product: card.product)
                                .padding(8)
                        }
                    }
                    .frame(width: 200, height: 150)
                }
                .frame(width: 200, height: 150)

                // 2. Merchant & Title & Price (with Strikethrough & Multi-Store Count)
                VStack(alignment: .leading, spacing: 3) {
                    if let best = bestOffer {
                        HStack(spacing: 4) {
                            Text(best.store_name)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
                                .lineLimit(1)
                            if card.product.offers.count > 1 {
                                Text("• \(card.product.offers.count) negozi")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundColor(.shopPurple)
                            }
                        }
                    }

                    Text(card.product.displayTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.shopDark)
                        .lineLimit(1)

                    if let best = bestOffer {
                        HStack(spacing: 6) {
                            Text(String(format: "€ %.2f", best.calculatedTotalPrice))
                                .font(.system(size: 13.5, weight: .heavy))
                                .foregroundColor(.shopDark)

                            if let orig = referenceOriginalPrice {
                                Text(String(format: "€ %.2f", orig))
                                    .font(.system(size: 11.5))
                                    .strikethrough()
                                    .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                            }
                        }
                    }
                }
                .frame(width: 200, alignment: .leading)

                Divider()
                    .padding(.vertical, 2)

                // 3. Structured Technical Specs (Modello, Ideale Per, Punto Forte - Screenshot 3)
                VStack(alignment: .leading, spacing: 7) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Modello")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                        Text(card.model_name)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.shopDark)
                            .lineLimit(1)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ideale Per")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                        Text(card.ideal_for)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.shopDark)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Punto Forte")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                        Text(card.strengths)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.shopDark)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 200, alignment: .leading)
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Spotlight Card View (Screenshot 3)
struct ShopSpotlightCardView: View {
    let spotlight: SpotlightRecommendation
    let onTap: () -> Void

    var bestOffer: Offer? {
        spotlight.product.offers.min(by: { $0.calculatedTotalPrice < $1.calculatedTotalPrice })
    }

    var maxOffer: Offer? {
        spotlight.product.offers.max(by: { $0.calculatedTotalPrice < $1.calculatedTotalPrice })
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Top Store Header
                HStack(spacing: 8) {
                    if let best = bestOffer {
                        ShopStoreLogo(storeName: best.store_name, showVerified: false, showLabel: false, size: 26)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(best.store_name)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.shopDark)

                            HStack(spacing: 3) {
                                Text("4.8")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.shopDark)
                                Text("(316)")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(Color(red: 130/255, green: 130/255, blue: 140/255))
                            }
                        }
                    }
                    Spacer()
                }

                // Main Content
                HStack(alignment: .top, spacing: 14) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(red: 245/255, green: 245/255, blue: 247/255))
                            .frame(width: 128, height: 128)

                        if let imgUrl = spotlight.product.image_url, let url = URL(string: imgUrl) {
                            ShopCachedAsyncImage(url: url, maxPixelSize: 400) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 128, height: 128)
                                        .cornerRadius(14)
                                case .empty:
                                    ShopSkeletonBlock(cornerRadius: 14, width: 128, height: 128)
                                default:
                                    Image(systemName: "photo")
                                        .foregroundColor(.gray.opacity(0.35))
                                        .frame(width: 128, height: 128)
                                }
                            }
                        }

                        if let badge = spotlight.badge_text {
                            Text(badge)
                                .font(.system(size: 9.5, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(red: 215/255, green: 40/255, blue: 40/255))
                                .cornerRadius(5)
                                .padding(6)
                        }

                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                ShopTranslucentHeartButton(product: spotlight.product)
                                    .padding(6)
                            }
                        }
                        .frame(width: 128, height: 128)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(spotlight.product.displayTitle)
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundColor(.shopDark)
                            .lineLimit(2)

                        if let best = bestOffer {
                            HStack(spacing: 6) {
                                Text(String(format: "€ %.2f", best.calculatedTotalPrice))
                                    .font(.system(size: 14.5, weight: .heavy))
                                    .foregroundColor(.shopDark)

                                if let max = maxOffer, max.calculatedTotalPrice > best.calculatedTotalPrice + 2 {
                                    Text(String(format: "€ %.2f", max.calculatedTotalPrice))
                                        .font(.system(size: 12))
                                        .strikethrough()
                                        .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(spotlight.highlights, id: \.self) { hl in
                                HStack(alignment: .top, spacing: 5) {
                                    Text("•")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.shopDark)
                                    Text(hl)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(Color(red: 80/255, green: 80/255, blue: 90/255))
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Follow-Up Suggestion Purple Pill Button (Screenshot 3)
struct ShopFollowUpPillButton: View {
    let title: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 90/255, green: 50/255, blue: 220/255))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(red: 242/255, green: 238/255, blue: 255/255))
            .cornerRadius(22)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Official Shop Product Card (Screenshot 4)
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
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(red: 243/255, green: 243/255, blue: 245/255))
                        .frame(width: 124, height: 124)

                    if let imgUrl = product.image_url, let url = URL(string: imgUrl) {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 350) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 124, height: 124)
                                    .cornerRadius(18)
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: 18, width: 124, height: 124)
                            default:
                                Image(systemName: "photo")
                                    .foregroundColor(.gray.opacity(0.35))
                                    .frame(width: 124, height: 124)
                            }
                        }
                        .frame(width: 124, height: 124)
                    }

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

                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.shopDark)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

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

// MARK: - Translucent Wishlist Heart Button
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
