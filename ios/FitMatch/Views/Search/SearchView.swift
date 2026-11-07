import SwiftUI

struct ComparisonPair: Identifiable {
    var id: String { "\(modelA)_\(modelB)" }
    let modelA: String
    let modelB: String
}

struct SearchView: View {
    @StateObject private var api = APIService.shared
    @StateObject private var keyboardObserver = KeyboardObserver.shared
    @ObservedObject private var tabVisibility = TabBarVisibilityManager.shared
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool
    @FocusState private var isFollowUpFieldFocused: Bool
    @State private var hasAutoFocused: Bool = false
    @State private var showVisualSearch: Bool = false

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
    @State private var feedbackConfig: SearchFeedbackSheetConfig? = nil
    @State private var feedbackSubmittedToast: Bool = false
    @State private var lastContextQuery: String? = nil // Multi-turn conversational memory

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
        if ProcessInfo.processInfo.arguments.contains("-testSearchClosed") {
            _hasAutoFocused = State(initialValue: true)
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

                if feedbackSubmittedToast {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Grazie per il tuo feedback!")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.shopDark.opacity(0.92))
                        .cornerRadius(22)
                        .shadow(color: Color.black.opacity(0.16), radius: 8, y: 3)
                        .padding(.top, 16)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
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
            .sheet(isPresented: $showVisualSearch) {
                ShopVisualSearchSheet { recognizedQuery in
                    searchText = recognizedQuery
                    isSearchFieldFocused = false
                    handleSearchOrComparison(query: recognizedQuery)
                }
            }
            .sheet(item: $feedbackConfig) { config in
                ShopSearchFeedbackSheet(
                    query: config.query,
                    products: config.products,
                    initialFeedbackType: config.feedbackType,
                    onSubmitted: {
                        withAnimation {
                            feedbackSubmittedToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            withAnimation { feedbackSubmittedToast = false }
                        }
                    }
                )
                .presentationDetents([.fraction(0.64), .large])
                .presentationDragIndicator(.visible)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            .onAppear {
                if !hasAutoFocused && !hasSearched {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        isSearchFieldFocused = true
                        hasAutoFocused = true
                    }
                }
            }
            .onChange(of: isSearchFieldFocused) { focused in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    if focused || isFollowUpFieldFocused {
                        tabVisibility.hide()
                    } else {
                        tabVisibility.show()
                    }
                }
            }
            .onChange(of: isFollowUpFieldFocused) { focused in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    if focused || isSearchFieldFocused {
                        tabVisibility.hide()
                    } else {
                        tabVisibility.show()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FitMatchFocusSearch"))) { _ in
                isSearchFieldFocused = true
            }
            .onDisappear {
                tabVisibility.reset()
            }
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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    // Section 1: "Visti di recente >" (Screenshot 1 & 2 top)
                    if !recentManager.recentlyViewedProducts.isEmpty {
                        recentlyViewedSection
                    }

                    // Section 2: "Continua ad acquistare >" (Screenshot 1 & 2 list)
                    if !recentManager.continueShoppingItems.isEmpty {
                        continueShoppingSection
                    } else if recentManager.recentlyViewedProducts.isEmpty {
                        emptyHistoryPlaceholder
                    }

                    Spacer(minLength: 160)
                }
                .padding(.top, 10)
            }
            .scrollDismissesKeyboard(.interactively)

            // Autocomplete live suggestions overlay when typing
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasSearched {
                liveSearchSuggestionsCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, floatingBarBottomPadding + 62)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Floating Bottom Search Pill Bar
            floatingSearchInputBar
                .padding(.bottom, floatingBarBottomPadding)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var emptyHistoryPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 38))
                .foregroundColor(Color(red: 170/255, green: 170/255, blue: 180/255))
                .padding(.top, 40)
            Text("Cosa vorresti cercare?")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.shopDark)
            Text("Digita un prodotto, una marca o una categoria per confrontare i prezzi dei migliori negozi di sport.")
                .font(.system(size: 13.5))
                .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var floatingBarBottomPadding: CGFloat {
        if keyboardObserver.isKeyboardVisible || keyboardObserver.effectiveKeyboardOffset > 0 {
            return keyboardObserver.effectiveKeyboardOffset + 8
        } else {
            return 98
        }
    }

    private var curatedProductsForFeedback: [MatchedProduct] {
        var prods: [MatchedProduct] = []
        for sec in curatedSections {
            for p in sec.products {
                if !prods.contains(where: { $0.id == p.id }) {
                    prods.append(p)
                }
            }
        }
        for res in searchResults {
            if !prods.contains(where: { $0.id == res.id }) {
                prods.append(res)
            }
        }
        if prods.isEmpty {
            prods = Array(recentManager.recentlyViewedProducts.prefix(6))
        }
        return Array(prods.prefix(8))
    }

    // MARK: - Section 1: Visti di recente >
    private var recentlyViewedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 5) {
                Text("Visti di recente")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.shopDark)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(red: 160/255, green: 160/255, blue: 170/255))

                Spacer()
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(recentManager.recentlyViewedProducts) { prod in
                        RecentlyViewedCard(product: prod) {
                            selectedRecentProduct = prod
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Section 2: Continua ad acquistare >
    private var continueShoppingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 5) {
                Text("Continua ad acquistare")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.shopDark)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(red: 160/255, green: 160/255, blue: 170/255))

                Spacer()
            }
            .padding(.horizontal, 20)

            VStack(spacing: 12) {
                ForEach(recentManager.continueShoppingItems) { item in
                    continueShoppingRow(item)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func continueShoppingRow(_ item: RecentActivityItem) -> some View {
        Button(action: {
            handleRecentItemTap(item)
        }) {
            HStack(spacing: 14) {
                ShopProductThumbnail(
                    imageUrl: item.imageUrl,
                    systemIcon: item.systemIcon,
                    cornerRadius: 15,
                    size: CGSize(width: 52, height: 52)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.shopDark)
                        .lineLimit(1)

                    Text(item.formattedDate)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(role: .destructive, action: {
                withAnimation {
                    recentManager.removeActivity(item)
                }
            }) {
                Label("Rimuovi dalla cronologia", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation {
                    recentManager.removeActivity(item)
                }
            } label: {
                Label("Elimina", systemImage: "trash")
            }
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

    // MARK: - Autocomplete Live Suggestions Overlay
    private var liveSearchSuggestionsCard: some View {
        let suggestions = filteredSuggestions(for: searchText)
        return Group {
            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.prefix(4).enumerated()), id: \.offset) { idx, suggestion in
                        Button(action: {
                            searchText = suggestion
                            isSearchFieldFocused = false
                            handleSearchOrComparison(query: suggestion)
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))

                                Text(suggestion)
                                    .font(.system(size: 14.5, weight: .medium))
                                    .foregroundColor(.shopDark)
                                    .lineLimit(1)

                                Spacer()

                                Button(action: {
                                    searchText = suggestion
                                }) {
                                    Image(systemName: "arrow.up.left")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Color(red: 170/255, green: 170/255, blue: 180/255))
                                        .frame(width: 28, height: 28)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(PlainButtonStyle())

                        if idx < min(3, suggestions.count - 1) {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                )
            }
        }
    }

    private func filteredSuggestions(for query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        let allPool: [String] = [
            "Adidas Adizero Dropset Pro",
            "Scarpe da gara per la maratona",
            "Adidas da corsa per maratona",
            "Scelte di scarpa per mezza maratona",
            "Scelte Nike per running e training",
            "Esplorare le opzioni Nike",
            "Nike running e sneaker lifestyle",
            "Nike Air Force 1 '07",
            "Nike Pegasus 41",
            "Nike Vaporfly 3",
            "Adidas Ultraboost Light",
            "Adidas Samba OG",
            "New Balance 9060",
            "Asics Novablast 4",
            "Hoka Clifton 9",
            "Garmin Forerunner 265",
            "Camicia a quadri Stüssy",
            "Scarpe running ammortizzate",
            "Scarpe running con piastra in carbonio"
        ]

        return allPool.filter { $0.lowercased().contains(q) }
    }

    // MARK: - Floating Bottom Search Bar
    private var floatingSearchInputBar: some View {
        HStack(spacing: 10) {
            // Main Pill
            HStack(spacing: 10) {
                Button(action: {
                    showVisualSearch = true
                }) {
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

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 170/255, green: 170/255, blue: 180/255))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Button(action: {
                    handleSearchOrComparison(query: searchText)
                }) {
                    Circle()
                        .fill(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(red: 235/255, green: 235/255, blue: 238/255) : Color.shopDark)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(red: 140/255, green: 140/255, blue: 150/255) : .white)
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
            .contentShape(Rectangle())
            .onTapGesture {
                if !isSearchFieldFocused {
                    isSearchFieldFocused = true
                }
            }

            // Dismiss Button (Image 1: circular button with 'X' right next to capsule when typing/focused)
            if isSearchFieldFocused || keyboardObserver.isKeyboardVisible {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        isSearchFieldFocused = false
                    }
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
                .transition(.scale.combined(with: .opacity))
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
        .ignoresSafeArea(.keyboard, edges: .bottom)
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

                            // 4. Comparative Spec Cards ("Confronto rapido" - Screenshot 4 style)
                            if !comparativeCards.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(comparativeCards.first?.section_title ?? "Confronto rapido")
                                        .font(.system(size: 18.5, weight: .bold))
                                        .foregroundColor(.shopDark)
                                        .padding(.horizontal, 18)

                                    Text("Scegli in base all'uso principale")
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

                            // 5. Follow-Up Suggestion Pills (Screenshot 4 style)
                            if !followUpSuggestions.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(followUpSuggestions, id: \.self) { suggestion in
                                        ShopFollowUpPillButton(title: suggestion) {
                                            handleFollowUpTap(suggestion)
                                        }
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.top, 14)
                                .id("followups_section")
                            }

                            // 6. AI Disclaimer & Thumbs Feedback (Matches Screenshot 1)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("L'IA può commettere errori, ricontrolla le risposte.")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Color(red: 130/255, green: 130/255, blue: 140/255))
                                    .padding(.horizontal, 18)
                                    .padding(.top, 6)

                                HStack(spacing: 0) {
                                    Button(action: {
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                        withAnimation { userFeedback = 1 }
                                        feedbackConfig = SearchFeedbackSheetConfig(
                                            query: searchText.isEmpty ? "Ricerca" : searchText,
                                            feedbackType: "positive",
                                            products: curatedProductsForFeedback
                                        )
                                    }) {
                                        Image(systemName: userFeedback == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(userFeedback == 1 ? Color(red: 22/255, green: 163/255, blue: 74/255) : Color(red: 110/255, green: 110/255, blue: 120/255))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    Divider()
                                        .frame(height: 16)
                                        .background(Color.black.opacity(0.12))

                                    Button(action: {
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                        withAnimation { userFeedback = -1 }
                                        feedbackConfig = SearchFeedbackSheetConfig(
                                            query: searchText.isEmpty ? "Ricerca" : searchText,
                                            feedbackType: "negative",
                                            products: curatedProductsForFeedback
                                        )
                                    }) {
                                        Image(systemName: userFeedback == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(userFeedback == -1 ? Color(red: 220/255, green: 38/255, blue: 38/255) : Color(red: 110/255, green: 110/255, blue: 120/255))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .background(Color(red: 242/255, green: 243/255, blue: 246/255))
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
            Button(action: {
                showVisualSearch = true
            }) {
                Image(systemName: "camera")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
                    .padding(.leading, 2)
            }
            .buttonStyle(PlainButtonStyle())

            TextField("Fai una domanda di follow-up", text: $followUpInputText)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundColor(.shopDark)
                .focused($isFollowUpFieldFocused)
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
        .padding(.bottom, floatingBarBottomPadding)
    }

    private func sendFollowUp() {
        let text = followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        followUpInputText = ""
        handleFollowUpTap(text)
    }

    private func handleFollowUpTap(_ suggestion: String) {
        let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Smart User Preference Auto-Fill: "Cercale nella mia taglia"
        if trimmed.lowercased().contains("nella mia taglia") || trimmed.lowercased().contains("mia taglia") {
            let prefSize = UserPreferencesManager.shared.preferences.preferredShoeSize
            if !prefSize.isEmpty {
                selectedSize = prefSize
            }
        }

        handleSearchOrComparison(query: trimmed, isFollowUp: true)
    }

    private func handleSearchOrComparison(query: String, isFollowUp: Bool = false) {
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
        executeSearch(isFollowUp: isFollowUp)
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
    private func executeSearch(isFollowUp: Bool = false) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        recentManager.recordSearch(query)
        isLoading = true
        hasSearched = true
        errorMessage = nil
        conversationalHeader = "Ho cercato \(query)"

        let activeContext = isFollowUp ? lastContextQuery : nil

        Task {
            do {
                let smartRes = try await api.smartSearch(
                    query: query,
                    maxPrice: overrideMaxPrice,
                    size: selectedSize,
                    store: selectedStore,
                    contextQuery: activeContext
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
                    self.lastContextQuery = query
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
                        Text("Uso")
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

                    let targetSize = product.isComparable ? UserPreferencesManager.shared.preferences.preferredShoeSize : UserPreferencesManager.shared.preferences.preferredApparelSize
                    let hasPref = !targetSize.isEmpty && product.allAvailableSizes.contains(where: {
                        $0.replacingOccurrences(of: ",", with: ".") == targetSize.replacingOccurrences(of: ",", with: ".")
                    })

                    if hasPref {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.shopPurple)
                            Text("Tg. \(targetSize) disp.")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.shopPurple)
                        }
                    }

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

// MARK: - Squircle Thumbnail for Continue Shopping Rows (Screenshots 1 & 2)
struct ShopProductThumbnail: View {
    let imageUrl: String?
    let systemIcon: String?
    var cornerRadius: CGFloat = 15
    var size: CGSize = CGSize(width: 52, height: 52)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 247/255, green: 247/255, blue: 249/255))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )

            if let img = imageUrl, !img.isEmpty {
                if let local = UIImage(named: img) {
                    Image(uiImage: local)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(5)
                } else if let url = URL(string: img) {
                    ShopCachedAsyncImage(url: url, maxPixelSize: 200) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(5)
                        case .empty:
                            ShopSkeletonBlock(cornerRadius: cornerRadius, width: size.width, height: size.height)
                        default:
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundColor(.gray.opacity(0.35))
                        }
                    }
                }
            } else if let sys = systemIcon {
                Image(systemName: sys)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Recently Viewed Product Card (Screenshots 1 & 2 Top Carousel)
struct RecentlyViewedCard: View {
    let product: MatchedProduct
    @ObservedObject private var wishlist = WishlistManager.shared
    let onTap: () -> Void

    var isFavorite: Bool {
        wishlist.isFavorite(product.canonical_name)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                // Card background
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 243/255, green: 244/255, blue: 246/255))
                    .frame(width: 136, height: 140)

                // Product image centered
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        if let img = product.image_url, let local = UIImage(named: img) {
                            Image(uiImage: local)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 104, height: 94)
                        } else if let img = product.image_url, let url = URL(string: img) {
                            ShopCachedAsyncImage(url: url, maxPixelSize: 320) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 104, height: 94)
                                case .empty:
                                    ShopSkeletonBlock(cornerRadius: 12, width: 88, height: 80)
                                default:
                                    Image(systemName: "photo")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray.opacity(0.35))
                                        .frame(width: 104, height: 94)
                                }
                            }
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .frame(width: 136, height: 140)

                // Top-Left Price Badge Pill (Screenshots: "80,00 €" / "160,00 € 230,00 €")
                if let best = product.best_price {
                    HStack(spacing: 4) {
                        Text(formatEuro(best))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)

                        if let orig = product.highest_price, orig > best {
                            Text(formatEuro(orig))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(.white.opacity(0.72))
                                .strikethrough(true, color: .white.opacity(0.72))
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.26))
                    )
                    .padding(.top, 10)
                    .padding(.leading, 10)
                }

                // Bottom-Right Heart Button (Purple filled when active, translucent dark when inactive)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) {
                                wishlist.toggleFavorite(product: product)
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(isFavorite ? Color(red: 95/255, green: 45/255, blue: 237/255) : Color.black.opacity(0.26))
                                    .frame(width: 32, height: 32)

                                Image(systemName: isFavorite ? "heart.fill" : "heart")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.trailing, 10)
                        .padding(.bottom, 10)
                    }
                }
                .frame(width: 136, height: 140)
            }
            .frame(width: 136, height: 140)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formatEuro(_ price: Double) -> String {
        return String(format: "%.2f €", price).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Visual Search Modal with AI Scanner Viewfinder
struct ShopVisualSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelectModel: (String) -> Void

    @State private var isScanning: Bool = false
    @State private var scanOffset: CGFloat = -100
    @State private var recognizedModel: String? = nil

    private let sampleModels = [
        ("Nike Air Force 1 '07", "prod_nike1"),
        ("Adidas Adizero Dropset Pro", "prod_samba"),
        ("New Balance 9060", "prod_nike2"),
        ("Puma Velocity Nitro", "prod_puma")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 6) {
                    Text("Ricerca Visiva con IA")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.shopDark)
                    Text("Inquadra una scarpa o capo per trovare le migliori offerte multinegozio")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 130/255, green: 130/255, blue: 140/255))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 20)

                // Viewfinder Frame
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(red: 245/255, green: 245/255, blue: 248/255))
                        .frame(height: 250)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )

                    if let model = recognizedModel, let sample = sampleModels.first(where: { $0.0 == model }) {
                        if let img = UIImage(named: sample.1) {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 180, height: 140)
                                .transition(.scale.combined(with: .opacity))
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 60, weight: .ultraLight))
                                .foregroundColor(.shopPurple.opacity(0.8))

                            Text("Posiziona la scarpa o prodotto al centro")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                        }
                    }

                    if isScanning {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, Color.shopPurple.opacity(0.8), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 3)
                            .offset(y: scanOffset)
                            .shadow(color: .shopPurple, radius: 8)
                    }
                }
                .padding(.horizontal, 24)

                if let model = recognizedModel {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(Color(red: 0/255, green: 170/255, blue: 100/255))
                            Text("Modello Identificato")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(red: 0/255, green: 170/255, blue: 100/255))
                        }

                        Text(model)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.shopDark)

                        Button(action: {
                            dismiss()
                            onSelectModel(model)
                        }) {
                            Text("Cerca offerte per questo modello")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.shopPurple)
                                .cornerRadius(14)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                    }
                    .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Oppure prova con questi modelli popolari:")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(red: 130/255, green: 130/255, blue: 140/255))
                            .padding(.horizontal, 24)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(sampleModels, id: \.0) { item in
                                    Button(action: {
                                        startScan(for: item.0)
                                    }) {
                                        HStack(spacing: 8) {
                                            if let img = UIImage(named: item.1) {
                                                Image(uiImage: img)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fit)
                                                    .frame(width: 24, height: 24)
                                            }
                                            Text(item.0)
                                                .font(.system(size: 12.5, weight: .medium))
                                                .foregroundColor(.shopDark)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(red: 244/255, green: 244/255, blue: 247/255))
                                        .cornerRadius(10)
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                }

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") {
                        dismiss()
                    }
                    .foregroundColor(.shopDark)
                }
            }
        }
    }

    private func startScan(for model: String) {
        isScanning = true
        recognizedModel = nil
        scanOffset = -90

        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
            scanOffset = 90
        }

        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.spring()) {
                self.isScanning = false
                self.recognizedModel = model
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - Search Feedback Bottom Sheet (Matches Reference Images 1 & 2)

struct SearchFeedbackSheetConfig: Identifiable {
    let id = UUID()
    let query: String
    let feedbackType: String // "positive" or "negative"
    let products: [MatchedProduct]
}

struct ShopSearchFeedbackSheet: View {
    let query: String
    let products: [MatchedProduct]
    let initialFeedbackType: String
    let onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentFeedbackType: String
    @State private var commentText: String = ""
    @State private var productRatings: [String: String] = [:] // productId -> "up" | "down"
    @State private var isSubmitting: Bool = false

    init(query: String, products: [MatchedProduct], initialFeedbackType: String, onSubmitted: @escaping () -> Void) {
        self.query = query
        self.products = products
        self.initialFeedbackType = initialFeedbackType
        self.onSubmitted = onSubmitted
        self._currentFeedbackType = State(initialValue: initialFeedbackType)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                // Header Titles (Screenshot 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Condividi feedback")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.shopDark)

                    Text("Questi prodotti erano adatti a te?")
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(.shopDark)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Overall Feedback Type Indicator & Toggle
                HStack(spacing: 8) {
                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            currentFeedbackType = "positive"
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.thumbsup.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Risultati Positivi")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(currentFeedbackType == "positive" ? Color.green.opacity(0.15) : Color(red: 242/255, green: 243/255, blue: 246/255))
                        .foregroundColor(currentFeedbackType == "positive" ? Color.green : Color(red: 120/255, green: 120/255, blue: 130/255))
                        .cornerRadius(18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(currentFeedbackType == "positive" ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            currentFeedbackType = "negative"
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.thumbsdown.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Da Migliorare")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(currentFeedbackType == "negative" ? Color.red.opacity(0.15) : Color(red: 242/255, green: 243/255, blue: 246/255))
                        .foregroundColor(currentFeedbackType == "negative" ? Color.red : Color(red: 120/255, green: 120/255, blue: 130/255))
                        .cornerRadius(18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(currentFeedbackType == "negative" ? Color.red.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()
                }
                .padding(.horizontal, 20)

                // Horizontal Product Carousel (Screenshot 2)
                if !products.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(products) { prod in
                                FeedbackProductCard(
                                    product: prod,
                                    rating: productRatings[prod.id],
                                    onRate: { rating in
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                        if productRatings[prod.id] == rating {
                                            productRatings.removeValue(forKey: prod.id)
                                        } else {
                                            productRatings[prod.id] = rating
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                // Comment Text Field (Screenshot 2: "Dicci come stiamo andando")
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(red: 220/255, green: 220/255, blue: 226/255), lineWidth: 1)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))

                    if commentText.isEmpty {
                        Text("Dicci come stiamo andando")
                            .font(.system(size: 15))
                            .foregroundColor(Color(red: 170/255, green: 170/255, blue: 180/255))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }

                    TextEditor(text: $commentText)
                        .font(.system(size: 15))
                        .foregroundColor(.shopDark)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .scrollContentBackground(.hidden)
                }
                .frame(height: 94)
                .padding(.horizontal, 20)

                // Invia Button (Screenshot 2: Full-width black button)
                Button(action: {
                    submit()
                }) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Invia")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.shopDark)
                    .cornerRadius(26)
                }
                .disabled(isSubmitting)
                .padding(.horizontal, 20)
                .padding(.top, 4)

                Spacer(minLength: 12)
            }
            .background(Color.white)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        let impact = UINotificationFeedbackGenerator()
        impact.notificationOccurred(.success)

        let evaluations: [[String: Any]] = productRatings.map { prodId, thumb in
            let prod = products.first(where: { $0.id == prodId })
            return [
                "product_id": prodId,
                "product_name": prod?.canonical_name ?? prodId,
                "thumb": thumb
            ]
        }

        Task {
            await APIService.shared.submitSearchFeedback(
                query: query,
                feedbackType: currentFeedbackType,
                comment: commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : commentText,
                productEvaluations: evaluations.isEmpty ? nil : evaluations
            )
            await MainActor.run {
                isSubmitting = false
                dismiss()
                onSubmitted()
            }
        }
    }
}

// MARK: - Feedback Product Card (Screenshot 2 item)

struct FeedbackProductCard: View {
    let product: MatchedProduct
    let rating: String? // "up" or "down" or nil
    let onRate: (String) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background squircle
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 246/255, green: 247/255, blue: 249/255))
                .frame(width: 124, height: 128)

            // Centered Product Image
            VStack {
                Spacer()
                if let img = product.image_url, let local = UIImage(named: img) {
                    Image(uiImage: local)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 74)
                } else if let img = product.image_url, let url = URL(string: img) {
                    ShopCachedAsyncImage(url: url, maxPixelSize: 320) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 96, height: 74)
                        case .empty:
                            ShopSkeletonBlock(cornerRadius: 8, width: 80, height: 60)
                        default:
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundColor(.gray.opacity(0.35))
                                .frame(width: 96, height: 74)
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundColor(.gray.opacity(0.35))
                        .frame(width: 96, height: 74)
                }
                Spacer()
            }
            .frame(width: 124, height: 128)

            // Bottom Two Circular Thumbs Buttons (Screenshot 2)
            HStack(spacing: 12) {
                // Thumbs Down Button
                Button(action: {
                    onRate("down")
                }) {
                    Circle()
                        .fill(rating == "down" ? Color.shopDark : Color.black.opacity(0.38))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: rating == "down" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .buttonStyle(PlainButtonStyle())

                // Thumbs Up Button
                Button(action: {
                    onRate("up")
                }) {
                    Circle()
                        .fill(rating == "up" ? Color(red: 22/255, green: 163/255, blue: 74/255) : Color.black.opacity(0.38))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: rating == "up" ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 10)
        }
        .frame(width: 124, height: 128)
    }
}
