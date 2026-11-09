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
    @State private var userForcedClassicMode: Bool = false
    @State private var rootQuery: String = ""
    @State private var lastFollowUpQuery: String? = nil
    @State private var conversationalHeader: String = "Ho cercato prodotti"
    @State private var conversationalSummary: String = ""
    @State private var curatedSections: [CuratedProductSection] = []
    @State private var comparativeCards: [ComparativeSpecCard] = []
    @State private var spotlight: SpotlightRecommendation? = nil
    @State private var followUpSuggestions: [String] = []
    @State private var activeQuestionPrompt: FollowUpQuestionPrompt? = nil
    @State private var followUpInputText: String = ""
    @State private var userFeedback: Int? = nil // 1 for thumbs up, -1 for down
    @State private var feedbackConfig: SearchFeedbackSheetConfig? = nil
    @State private var feedbackSubmittedToast: Bool = false
    @State private var lastContextQuery: String? = nil // Multi-turn conversational memory
    @State private var conversationTurns: [SearchConversationTurn] = []
    @State private var isFollowUpLoading: Bool = false
    @State private var pendingFollowUpQuery: String? = nil
    @State private var followUpErrorMessage: String? = nil

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
        let q = initialSearchQuery ?? ""
        _searchText = State(initialValue: q)
        _rootQuery = State(initialValue: q)
        if ProcessInfo.processInfo.arguments.contains("-testClassicMode") {
            _isDeepDiveMode = State(initialValue: false)
            _userForcedClassicMode = State(initialValue: true)
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
                    hideAllKeyboards()
                    searchText = recognizedQuery
                    rootQuery = recognizedQuery
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
            .sheet(item: $activeQuestionPrompt) { prompt in
                FollowUpQuestionSheet(
                    question: prompt.question,
                    baseQuery: rootQuery.isEmpty ? searchText : rootQuery,
                    onAnswerSelected: { answer in
                        handleQuestionAnswered(question: prompt.question, answer: answer)
                    }
                )
                .presentationDetents([.medium, .large])
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
            .onChange(of: isSearchFieldFocused) { _ in
                updateTabBarVisibility()
            }
            .onChange(of: isFollowUpFieldFocused) { _ in
                updateTabBarVisibility()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FitMatchFocusSearch"))) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isSearchFieldFocused = true
                }
            }
            .onDisappear {
                hideAllKeyboards()
            }
            .task {
                loadInitialTopSavings()
                await recentManager.syncFromDatabase()
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
                    // Header Title: Cerca
                    HStack {
                        Text("Cerca")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

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
            .contentShape(Rectangle())
            .onTapGesture {
                hideAllKeyboards()
            }

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
        .contentShape(Rectangle())
        .onTapGesture {
            hideAllKeyboards()
        }
    }

    private var isAnyKeyboardFocused: Bool {
        isSearchFieldFocused || isFollowUpFieldFocused
    }

    private var floatingBarBottomPadding: CGFloat {
        if isAnyKeyboardFocused && (keyboardObserver.isKeyboardVisible || keyboardObserver.effectiveKeyboardOffset > 0) {
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
            NavigationLink(destination: RecentlyViewedView()) {
                HStack(spacing: 5) {
                    Text("Visti di recente")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.shopDark)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 160/255, green: 160/255, blue: 170/255))

                    Spacer()
                }
            }
            .buttonStyle(.plain)
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
            NavigationLink(destination: RecentlyViewedView()) {
                HStack(spacing: 5) {
                    Text("Continua ad acquistare")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.shopDark)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 160/255, green: 160/255, blue: 170/255))

                    Spacer()
                }
            }
            .buttonStyle(.plain)
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
            "Scarpe Hyrox e allenamento ibrido",
            "Puma Deviate Nitro 3 Hyrox",
            "Adidas Adizero Dropset Pro",
            "Long sleeve da corsa",
            "Maglia termica running invernale",
            "Scarpe da gara per la maratona",
            "Scarpe running massimo ammortizzamento",
            "Scarpe running con piastra in carbonio",
            "Scarpe da trail running impermeabili GTX",
            "Nike Pegasus 41",
            "Nike Vomero 18",
            "Nike Vaporfly 3",
            "Nike Alphafly 3",
            "Asics Gel-Nimbus 26",
            "Asics Novablast 4",
            "Asics Superblast 2",
            "Hoka Clifton 9",
            "Hoka Bondi 8",
            "Hoka Speedgoat 6",
            "Saucony Endorphin Speed 4",
            "Saucony Triumph 22",
            "Saucony Ride 18",
            "Brooks Ghost 16",
            "Brooks Glycerin 21",
            "Adidas Adizero Adios Pro 4",
            "Adidas Adizero Boston 12",
            "New Balance Fresh Foam 1080 v14",
            "On Cloudmonster 2",
            "Salomon Speedcross 6",
            "Gilet idratazione Salomon Active Skin",
            "Garmin Forerunner 165",
            "Garmin Forerunner 265",
            "Garmin Fenix 8",
            "Oakley Sutro Prizm",
            "Rullo smart Wahoo Kickr"
        ]

        let queryTokens = q.split(separator: " ").map { String($0) }
        return allPool.filter { candidate in
            let candLow = candidate.lowercased()
            return candLow.contains(q) || queryTokens.allSatisfy { candLow.contains($0) }
        }
    }

    // MARK: - Floating Bottom Search Bar
    private var floatingSearchInputBar: some View {
        HStack(spacing: 10) {
            // Main Pill
            HStack(spacing: 10) {
                Button(action: {
                    hideAllKeyboards()
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
                    hideAllKeyboards()
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
                    resetToSearchTyping(keepText: false)
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
                    resetToSearchTyping(keepText: true)
                }) {
                    Text(rootQuery.isEmpty ? (searchText.isEmpty ? "Cerca prodotto..." : searchText) : rootQuery)
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
                userForcedClassicMode = true
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
            if isLoading && conversationTurns.isEmpty {
                ShopSearchDeepDiveSkeletonView(query: rootQuery.isEmpty ? searchText : rootQuery)
                    .transition(.opacity)
            } else if let error = errorMessage, conversationTurns.isEmpty {
                aiErrorView(error)
            } else if conversationTurns.isEmpty && curatedSections.isEmpty && searchResults.isEmpty && spotlight == nil {
                aiEmptyView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            if !conversationTurns.isEmpty {
                                ForEach(conversationTurns) { turn in
                                    turnContentView(for: turn)
                                        .id(turn.id)
                                }
                            } else {
                                // Fallback if turns haven't initialized yet
                                legacyTurnView
                            }

                            // Follow-up loading state: user bubble + thinking indicator
                            if isFollowUpLoading {
                                followUpLoadingSection
                                    .id("follow_up_loading_section")
                            }

                            // Follow-up error retry banner (if follow-up failed)
                            if let followUpErr = followUpErrorMessage {
                                followUpErrorSection(followUpErr)
                            }

                            // Spacing at bottom for floating follow-up bar and dock
                            Spacer(minLength: 130)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if isFollowUpFieldFocused || isSearchFieldFocused {
                                hideAllKeyboards()
                            }
                        }
                    )
                    .onChange(of: conversationTurns.count) { _ in
                        if let lastTurn = conversationTurns.last, lastTurn.isFollowUp {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    proxy.scrollTo(lastTurn.id, anchor: .top)
                                }
                            }
                        }
                    }
                    .onChange(of: isFollowUpLoading) { loading in
                        if loading {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation {
                                    proxy.scrollTo("follow_up_loading_section", anchor: .bottom)
                                }
                            }
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

    // MARK: - Conversational Turn Content View
    @ViewBuilder
    private func turnContentView(for turn: SearchConversationTurn) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // User Follow-up Query Bubble (when this turn is a follow-up)
            if turn.isFollowUp {
                HStack {
                    Spacer()
                    Text(turn.query)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color.shopPurple, Color(red: 100/255, green: 55/255, blue: 235/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(20)
                        .shadow(color: Color.shopPurple.opacity(0.18), radius: 6, y: 3)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 2)
            }

            // 1. Header: "Ho cercato ... >" (or Shield / Alert for Off-topic/Security)
            if turn.isOffTopic || turn.isUnsafe || turn.conversationalHeader.contains("non pertinente") || turn.conversationalHeader.contains("non consentita") {
                HStack(spacing: 6) {
                    Image(systemName: turn.isUnsafe ? "shield.slash.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(turn.isUnsafe ? Color(red: 220/255, green: 38/255, blue: 38/255) : Color.shopPurple)
                    Text(turn.conversationalHeader)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.shopDark)
                }
                .padding(.horizontal, 18)
                .padding(.top, turn.isFollowUp ? 4 : 8)
            } else {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if let idx = conversationTurns.firstIndex(where: { $0.id == turn.id }) {
                            conversationTurns[idx].showAiExplanation.toggle()
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(turn.conversationalHeader)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                            .rotationEffect(.degrees(turn.showAiExplanation ? 90 : 0))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 18)
                .padding(.top, turn.isFollowUp ? 4 : 8)
            }

            // Chips (collapsible)
            if turn.showAiExplanation && !turn.activeChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(turn.activeChips) { chip in
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

            // 2. Conversational Narrative Paragraph
            if !turn.conversationalSummary.isEmpty {
                if turn.isOffTopic || turn.isUnsafe || turn.conversationalHeader.contains("non pertinente") || turn.conversationalHeader.contains("non consentita") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedStringKey(turn.conversationalSummary))
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundColor(.shopDark)
                            .lineSpacing(4.5)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(red: 248/255, green: 248/255, blue: 251/255))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .padding(.horizontal, 18)
                } else {
                    Text(LocalizedStringKey(turn.conversationalSummary))
                        .font(.system(size: 15.5, weight: .regular))
                        .foregroundColor(.shopDark)
                        .lineSpacing(4.5)
                        .padding(.horizontal, 18)
                }
            }

            // 3. Thematic Curated Carousels
            if !turn.curatedSections.isEmpty {
                ForEach(turn.curatedSections) { section in
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
            } else if !turn.searchResults.isEmpty {
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
                            ForEach(turn.searchResults) { prod in
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

            // 4. Comparative Spec Cards
            if !turn.comparativeCards.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(turn.comparativeCards.first?.section_title ?? "Confronto rapido")
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
                            ForEach(turn.comparativeCards) { card in
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
                .id(turn.id == conversationTurns.first?.id ? "comparative_section" : "comparative_section_\(turn.id)")
            }

            // 5. Spotlight / Best Deal Card
            if let spot = turn.spotlight {
                VStack(alignment: .leading, spacing: 6) {
                    ShopSpotlightCardView(spotlight: spot) {
                        selectedRecentProduct = spot.product
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                }
                .id(turn.id == conversationTurns.first?.id ? "spotlight_section" : "spotlight_section_\(turn.id)")
            }

            // 6. Follow-Up Suggestion Pills (Shown for the latest turn when not loading)
            if turn.id == conversationTurns.last?.id && !isFollowUpLoading && !turn.followUpSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(turn.followUpSuggestions, id: \.self) { suggestion in
                        ShopFollowUpPillButton(title: suggestion) {
                            handleFollowUpTap(suggestion)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .id("followups_section")
            }

            // 7. AI Disclaimer & Thumbs Feedback
            turnFeedbackBar(for: turn)

            // Divider between conversation turns
            if turn.id != conversationTurns.last?.id {
                Divider()
                    .background(Color.black.opacity(0.08))
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
            }
        }
    }

    // MARK: - Follow-Up Loading Section
    private var followUpLoadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let pending = pendingFollowUpQuery {
                HStack {
                    Spacer()
                    Text(pending)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color.shopPurple, Color(red: 100/255, green: 55/255, blue: 235/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(20)
                        .shadow(color: Color.shopPurple.opacity(0.18), radius: 6, y: 3)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }

            // Upgraded Agent Thinking HUD for Follow-Up
            ShopAgentThinkingCardView(
                query: pendingFollowUpQuery ?? lastFollowUpQuery ?? "",
                isFollowUp: true
            )
            .padding(.horizontal, 18)
        }
    }

    // MARK: - Follow-Up Error Section
    private func followUpErrorSection(_ errorText: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(Color(red: 220/255, green: 38/255, blue: 38/255))
            Text(errorText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.shopDark)
            Spacer()
            if let lastQ = lastFollowUpQuery {
                Button("Riprova") {
                    executeSearch(isFollowUp: true, rawFollowUpText: lastQ)
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.shopPurple)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 254/255, green: 242/255, blue: 242/255))
        .cornerRadius(14)
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    // MARK: - Turn Feedback Bar
    private func turnFeedbackBar(for turn: SearchConversationTurn) -> some View {
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
                    if let idx = conversationTurns.firstIndex(where: { $0.id == turn.id }) {
                        withAnimation { conversationTurns[idx].userFeedback = 1 }
                    }
                    userFeedback = 1
                    feedbackConfig = SearchFeedbackSheetConfig(
                        query: turn.query.isEmpty ? (searchText.isEmpty ? "Ricerca" : searchText) : turn.query,
                        feedbackType: "positive",
                        products: turn.productsForFeedback
                    )
                }) {
                    Image(systemName: turn.userFeedback == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(turn.userFeedback == 1 ? Color(red: 22/255, green: 163/255, blue: 74/255) : Color(red: 110/255, green: 110/255, blue: 120/255))
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
                    if let idx = conversationTurns.firstIndex(where: { $0.id == turn.id }) {
                        withAnimation { conversationTurns[idx].userFeedback = -1 }
                    }
                    userFeedback = -1
                    feedbackConfig = SearchFeedbackSheetConfig(
                        query: turn.query.isEmpty ? (searchText.isEmpty ? "Ricerca" : searchText) : turn.query,
                        feedbackType: "negative",
                        products: turn.productsForFeedback
                    )
                }) {
                    Image(systemName: turn.userFeedback == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(turn.userFeedback == -1 ? Color(red: 220/255, green: 38/255, blue: 38/255) : Color(red: 110/255, green: 110/255, blue: 120/255))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .background(Color(red: 242/255, green: 243/255, blue: 246/255))
            .cornerRadius(12)
            .padding(.horizontal, 18)
        }
    }

    // MARK: - Legacy Single Turn View (Fallback)
    private var legacyTurnView: some View {
        VStack(alignment: .leading, spacing: 18) {
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

            if !conversationalSummary.isEmpty {
                Text(LocalizedStringKey(conversationalSummary))
                    .font(.system(size: 15.5, weight: .regular))
                    .foregroundColor(.shopDark)
                    .lineSpacing(4.5)
                    .padding(.horizontal, 18)
            }

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
                    userForcedClassicMode = true
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
                    userForcedClassicMode = true
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
                    resetToSearchTyping(keepText: false)
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
                    resetToSearchTyping(keepText: true)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Color(red: 80/255, green: 80/255, blue: 90/255))

                        Text(rootQuery.isEmpty ? (searchText.isEmpty ? "Cerca prodotto..." : searchText) : rootQuery)
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
                    userForcedClassicMode = false
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
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if isFollowUpFieldFocused || isSearchFieldFocused {
                            hideAllKeyboards()
                        }
                    }
                )
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
            // Main Pill Capsule
            HStack(spacing: 10) {
                Button(action: {
                    hideAllKeyboards()
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
                    .submitLabel(.send)
                    .onSubmit {
                        sendFollowUp()
                    }
                    .disabled(isLoading || isFollowUpLoading)

                if !followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Quick clear button for what the user typed
                    Button(action: {
                        followUpInputText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 170/255, green: 170/255, blue: 180/255))
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Send Button
                    Button(action: {
                        sendFollowUp()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor((isLoading || isFollowUpLoading) ? Color.shopPurple.opacity(0.4) : .shopPurple)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isLoading || isFollowUpLoading)
                } else {
                    // When text is empty:
                    // If focused (keyboard is open): tapping this dismisses the keyboard!
                    // If NOT focused (normal browsing): tapping this returns to search typing view!
                    Button(action: {
                        if isFollowUpFieldFocused || keyboardObserver.isKeyboardVisible {
                            hideAllKeyboards()
                        } else {
                            resetToSearchTyping(keepText: true)
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(red: 130/255, green: 130/255, blue: 140/255))
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
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

            // External dismiss button (Matches Image 1 style) when keyboard is open
            if isFollowUpFieldFocused || keyboardObserver.isKeyboardVisible {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    hideAllKeyboards()
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
        .padding(.bottom, floatingBarBottomPadding)
    }

    private func hideAllKeyboards() {
        isSearchFieldFocused = false
        isFollowUpFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        tabVisibility.setHidden(false, for: "search_input")
    }

    private func updateTabBarVisibility() {
        let isFocused = isSearchFieldFocused || isFollowUpFieldFocused
        tabVisibility.setHidden(isFocused, for: "search_input")
    }

    private func resetToSearchTyping(keepText: Bool = false) {
        hideAllKeyboards()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            hasSearched = false
            searchResults = []
            curatedSections = []
            comparativeCards = []
            spotlight = nil
            followUpSuggestions = []
            isSmartSearchActive = false
            errorMessage = nil
            followUpInputText = ""
            selectedFilterCountry = nil
            selectedSize = nil
            selectedStore = nil
            overrideMaxPrice = nil
            userFeedback = nil
            userForcedClassicMode = false
            lastFollowUpQuery = nil
            conversationTurns = []
            isFollowUpLoading = false
            pendingFollowUpQuery = nil
            followUpErrorMessage = nil
            if !keepText {
                searchText = ""
                rootQuery = ""
                lastContextQuery = nil
            } else if !rootQuery.isEmpty {
                searchText = rootQuery
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isSearchFieldFocused = true
        }
    }

    private func sendFollowUp() {
        guard !isLoading && !isFollowUpLoading else { return }
        let text = followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        followUpInputText = ""
        hideAllKeyboards()

        // Smart User Preference Auto-Fill: "Cercale nella mia taglia"
        if text.lowercased().contains("nella mia taglia") || text.lowercased().contains("mia taglia") {
            let prefSize = UserPreferencesManager.shared.preferences.preferredShoeSize
            if !prefSize.isEmpty {
                selectedSize = prefSize
            }
        }

        // When the user directly types into the follow-up bar, ALWAYS execute the follow-up query.
        // Never intercept user-typed questions with the prompt/clarification sheet.
        handleSearchOrComparison(query: text, isFollowUp: true)
    }

    private func handleFollowUpTap(_ suggestion: String) {
        guard !isLoading && !isFollowUpLoading else { return }
        hideAllKeyboards()
        let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // If suggestion is a question, present the quick-answer sheet so user can answer
        if SearchView.isQuestionSuggestion(trimmed) {
            activeQuestionPrompt = FollowUpQuestionPrompt(question: trimmed)
            return
        }

        // Smart User Preference Auto-Fill: "Cercale nella mia taglia"
        if trimmed.lowercased().contains("nella mia taglia") || trimmed.lowercased().contains("mia taglia") {
            let prefSize = UserPreferencesManager.shared.preferences.preferredShoeSize
            if !prefSize.isEmpty {
                selectedSize = prefSize
            }
        }

        handleSearchOrComparison(query: trimmed, isFollowUp: true)
    }

    private func handleQuestionAnswered(question: String, answer: String) {
        let clean = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        // Simplify parenthesized descriptions, e.g. "Principiante (Prime corse / Camminata)" -> "Principiante"
        let simplified = clean.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? clean

        // If user preference applies
        if simplified.lowercased().contains("nella mia taglia") || simplified.lowercased().contains("mia taglia") {
            let prefSize = UserPreferencesManager.shared.preferences.preferredShoeSize
            if !prefSize.isEmpty {
                selectedSize = prefSize
            }
        }

        handleSearchOrComparison(query: simplified, isFollowUp: true)
    }

    static func isQuestionSuggestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("?") || trimmed.contains("¿") { return true }
        let lower = trimmed.lowercased()
        let questionStarters = [
            "qual è", "quale", "quali", "cosa", "come", "dove", "quando", "quanto", "quanti", "quante", "perché", "perchè", "chi",
            "stai cercando", "cerchi", "preferisci", "hai una preferenza", "hai preferenze", "ti alleni", "vorresti", "vuoi",
            "meglio per", "su che", "in che"
        ]
        return questionStarters.contains { lower.hasPrefix($0) }
    }

    static func extractQuickOptions(for question: String) -> [String] {
        let lower = question.lowercased()

        // 1. Level / experience / training
        if lower.contains("livello") || lower.contains("allenament") || lower.contains("esperienza") || lower.contains("esperto") || lower.contains("ritmo") {
            return [
                "Principiante (Prime corse / Camminata)",
                "Intermedio (Allenamenti regolari)",
                "Avanzato (Maratona & Ritmi veloci)"
            ]
        }

        // 2. Terrain / Surface
        if lower.contains("strada") || lower.contains("sentier") || lower.contains("trail") || lower.contains("terreno") || lower.contains("asfalto") || lower.contains("superficie") {
            return [
                "Corsa su strada e asfalto",
                "Sentieri e trail running",
                "Misto (Parchi, sterrato e asfalto)",
                "Tapis roulant o pista indoor"
            ]
        }

        // 3. Cushioning / Comfort / Support
        if lower.contains("cushioning") || lower.contains("ammortizz") || lower.contains("reattiv") || lower.contains("schiuma") || lower.contains("morbide") {
            return [
                "Ammortizzazione massima (Max Cushioning)",
                "Reattivo ed elastico per ritmi veloci",
                "Equilibrato per tutti i giorni",
                "Leggero da gara con piastra in carbonio"
            ]
        }

        // 4. Budget / Price
        if lower.contains("prezzo") || lower.contains("budget") || lower.contains("costo") || lower.contains("spendere") || lower.contains("euro") || lower.contains("sconto") {
            return [
                "Sotto i 100€ (Economiche)",
                "Tra 100€ e 150€ (Miglior rapporto qualità/prezzo)",
                "Top di gamma senza limiti di budget"
            ]
        }

        // 5. Distance / Mileage
        if lower.contains("distanza") || lower.contains("km") || lower.contains("chilometri") || lower.contains("maratona") || lower.contains("lungo") {
            return [
                "Corse brevi (5-10 km)",
                "Mezza maratona (10-21 km)",
                "Maratona e lunghissimi (oltre 30 km)",
                "Uso versatile quotidiano"
            ]
        }

        // 6. Pronation / Support
        if lower.contains("pronazion") || lower.contains("appoggio") || lower.contains("piatto") || lower.contains("stabilit") {
            return [
                "Appoggio neutro",
                "Supporto per iperpronazione",
                "Supinazione / Arco alto"
            ]
        }

        // 7. Binary/disjunctive " o " question (e.g. "scarpe A o scarpe B", "leggere o protettive")
        if lower.contains(" o ") {
            let parts = question
                .replacingOccurrences(of: "?", with: "")
                .replacingOccurrences(of: "¿", with: "")
                .components(separatedBy: " o ")
            if parts.count >= 2 {
                let p1 = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let p2 = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanP1 = p1
                    .replacingOccurrences(of: "Stai cercando ", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "Preferisci ", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "Cerchi ", with: "", options: .caseInsensitive)
                    .capitalized
                let cleanP2 = p2.capitalized
                if cleanP1.count > 2 && cleanP2.count > 2 {
                    return [cleanP1, cleanP2, "Entrambi / Misto"]
                }
            }
        }

        // Default universal options
        return [
            "Miglior modello per iniziare",
            "Opzione più versatile e comoda",
            "Miglior rapporto qualità / prezzo"
        ]
    }

    private func handleSearchOrComparison(query: String, isFollowUp: Bool = false) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        hideAllKeyboards()

        if let (mA, mB) = parseComparisonQuery(trimmed) {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            comparisonModels = ComparisonPair(modelA: mA, modelB: mB)
            showComparisonSheet = true
            return
        }

        if !isFollowUp {
            rootQuery = trimmed
            searchText = trimmed
            userForcedClassicMode = false
        }
        executeSearch(isFollowUp: isFollowUp, rawFollowUpText: isFollowUp ? trimmed : nil)
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
    private func executeSearch(isFollowUp: Bool = false, rawFollowUpText: String? = nil) {
        let activeQuery = isFollowUp ? (rawFollowUpText ?? searchText) : searchText
        let query = activeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        hideAllKeyboards()

        if !isFollowUp {
            rootQuery = query
            conversationalHeader = "Ho cercato \(query)"
            conversationTurns = []
            isLoading = true
            isFollowUpLoading = false
            pendingFollowUpQuery = nil
            followUpErrorMessage = nil
        } else {
            lastFollowUpQuery = query
            pendingFollowUpQuery = query
            isFollowUpLoading = true
            // Do NOT wipe out existing turns with full-screen skeleton
            isLoading = false
            followUpErrorMessage = nil
            userForcedClassicMode = false
            isDeepDiveMode = true
        }

        hasSearched = true
        errorMessage = nil

        let activeContext: String?
        if isFollowUp {
            let turnQueries = conversationTurns.map { $0.query }.filter { !$0.isEmpty }
            if !turnQueries.isEmpty {
                activeContext = turnQueries.joined(separator: " >> ")
            } else if let last = lastContextQuery, !last.isEmpty, last != rootQuery {
                activeContext = "\(rootQuery) >> \(last)"
            } else if !rootQuery.isEmpty {
                activeContext = rootQuery
            } else {
                activeContext = lastContextQuery
            }
        } else {
            activeContext = nil
        }

        let requestedMode = userForcedClassicMode ? "classic" : nil

        Task {
            do {
                let smartRes = try await api.smartSearch(
                    query: query,
                    mode: requestedMode,
                    maxPrice: overrideMaxPrice,
                    size: selectedSize,
                    store: selectedStore,
                    contextQuery: activeContext
                )
                await MainActor.run {
                    self.errorMessage = nil
                    self.followUpErrorMessage = nil
                    self.smartIntent = smartRes.intent
                    self.activeChips = smartRes.chips ?? []
                    self.searchResults = smartRes.results
                    self.curatedSections = smartRes.curated_sections ?? []
                    self.comparativeCards = smartRes.comparative_cards ?? []
                    self.spotlight = smartRes.spotlight
                    self.followUpSuggestions = smartRes.follow_up_suggestions ?? []
                    self.conversationalHeader = smartRes.conversational_header ?? (isFollowUp ? "Ho cercato \(query)" : "Ho cercato \(self.rootQuery.isEmpty ? query : self.rootQuery)")
                    self.conversationalSummary = smartRes.conversational_summary ?? (smartRes.intent?.explanation ?? "")

                    let isOff = smartRes.is_off_topic ?? (smartRes.intent?.is_off_topic ?? false)
                    let isUnsafe = smartRes.is_unsafe ?? (smartRes.intent?.is_unsafe ?? false)

                    let newTurn = SearchConversationTurn(
                        id: UUID().uuidString,
                        query: query,
                        isFollowUp: isFollowUp,
                        conversationalHeader: self.conversationalHeader,
                        conversationalSummary: self.conversationalSummary,
                        smartIntent: smartRes.intent,
                        activeChips: smartRes.chips ?? [],
                        searchResults: smartRes.results,
                        curatedSections: smartRes.curated_sections ?? [],
                        comparativeCards: smartRes.comparative_cards ?? [],
                        spotlight: smartRes.spotlight,
                        followUpSuggestions: smartRes.follow_up_suggestions ?? [],
                        userFeedback: nil,
                        showAiExplanation: false,
                        error: nil,
                        isOffTopic: isOff,
                        isUnsafe: isUnsafe,
                        timestamp: Date()
                    )

                    if !isFollowUp {
                        self.rootQuery = query
                        self.lastContextQuery = query
                        self.conversationTurns = [newTurn]
                        // Record only genuine shopping searches with products (never conversational follow-ups, off-topic, or empty)
                        if !isOff && !isUnsafe && !smartRes.results.isEmpty {
                            self.recentManager.recordSearch(query)
                        }
                    } else {
                        self.lastContextQuery = query
                        self.conversationTurns.append(newTurn)
                    }

                    self.pendingFollowUpQuery = nil
                    self.isFollowUpLoading = false

                    if ProcessInfo.processInfo.arguments.contains("-testClassicMode") {
                        self.isDeepDiveMode = false
                    } else if self.userForcedClassicMode {
                        self.isDeepDiveMode = false
                    } else {
                        self.isDeepDiveMode = smartRes.is_deep_dive ?? true
                    }
                    self.isSmartSearchActive = true
                    self.isLoading = false
                }
            } catch {
                if !isFollowUp {
                    // 1. Direct Supabase Cloud instant fallback for high availability
                    let directProds = await SupabaseManager.shared.fetchSmartProductsDirect(
                        category: nil,
                        keywords: [query],
                        maxPrice: overrideMaxPrice,
                        size: selectedSize,
                        store: selectedStore,
                        limit: 30
                    )
                    if !directProds.isEmpty {
                        await MainActor.run {
                            self.errorMessage = nil
                            self.searchResults = directProds
                            self.curatedSections = [
                                CuratedProductSection(
                                    id: "sec_cloud",
                                    title: "Migliori Risultati Trovati",
                                    subtitle: "Offerte verificate nel catalogo FitMatch Cloud",
                                    products: directProds
                                )
                            ]
                            self.conversationalHeader = "Ho cercato \(query)"
                            self.conversationalSummary = "Ecco i modelli trovati per la tua ricerca:"
                            self.isDeepDiveMode = true
                            self.isSmartSearchActive = true
                            self.isLoading = false
                            self.recentManager.recordSearch(query)
                        }
                    } else if let local = try? await api.searchCatalog(query: query, limit: 30), !local.isEmpty {
                        await MainActor.run {
                            self.errorMessage = nil
                            self.searchResults = local
                            self.isDeepDiveMode = false
                            self.isSmartSearchActive = false
                            self.isLoading = false
                            self.recentManager.recordSearch(query)
                        }
                    } else if let live = try? await api.search(query: query, size: selectedSize), !live.isEmpty {
                        await MainActor.run {
                            self.errorMessage = nil
                            self.searchResults = live
                            self.isDeepDiveMode = false
                            self.isSmartSearchActive = false
                            self.isLoading = false
                            self.recentManager.recordSearch(query)
                        }
                    } else {
                        await MainActor.run {
                            self.errorMessage = "Impossibile recuperare i risultati in questo momento. Il server potrebbe essere occupato, tocca Riprova per aggiornare."
                            self.isLoading = false
                        }
                    }
                } else {
                    // Follow-up failed: preserve all existing turns and show retry notification
                    await MainActor.run {
                        self.isFollowUpLoading = false
                        self.pendingFollowUpQuery = nil
                        self.followUpErrorMessage = "Impossibile completare il follow-up in questo momento."
                    }
                }
            }
        }
    }

    private func removeChip(_ chip: SmartSearchChip) {
        withAnimation {
            activeChips.removeAll { $0.id == chip.id }
            if let lastIdx = conversationTurns.indices.last {
                conversationTurns[lastIdx].activeChips.removeAll { $0.id == chip.id }
            }
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
                        Text(card.model_name.replacingOccurrences(of: "**", with: ""))
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.shopDark)
                            .lineLimit(1)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Uso")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                        Text(LocalizedStringKey(card.ideal_for))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.shopDark)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Punto Forte")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                        Text(LocalizedStringKey(card.strengths))
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

    var referenceOriginalPrice: Double? {
        if let best = bestOffer, let orig = best.original_price, orig > best.calculatedTotalPrice + 1 {
            return orig
        }
        if let max = maxOffer, let best = bestOffer, max.calculatedTotalPrice > best.calculatedTotalPrice + 2 {
            return max.calculatedTotalPrice
        }
        return nil
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

                                if let orig = referenceOriginalPrice {
                                    Text(String(format: "€ %.2f", orig))
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
                                    Text(LocalizedStringKey(hl))
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

// MARK: - Follow-Up Question Prompt & Sheet

struct FollowUpQuestionPrompt: Identifiable {
    let id = UUID()
    let question: String
}

struct FollowUpQuestionSheet: View {
    let question: String
    let baseQuery: String
    let onAnswerSelected: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var customAnswerText: String = ""
    @FocusState private var isCustomFieldFocused: Bool

    private var options: [String] {
        SearchView.extractQuickOptions(for: question)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                // Header badge & title
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.shopPurple)
                        Text("ASSISTENTE FITMATCH")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.shopPurple)
                            .tracking(0.5)
                    }

                    Text(question)
                        .font(.system(size: 17.5, weight: .bold))
                        .foregroundColor(.shopDark)
                        .fixedSize(horizontal: false, vertical: true)

                    if !baseQuery.isEmpty {
                        Text("Scegli o scrivi una risposta per affinare «\(baseQuery)»:")
                            .font(.system(size: 12.5))
                            .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // Quick Answer Options
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(options, id: \.self) { opt in
                            Button(action: {
                                dismiss()
                                onAnswerSelected(opt)
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6.5))
                                        .foregroundColor(.shopPurple)

                                    Text(opt)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                        .multilineTextAlignment(.leading)

                                    Spacer()

                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(.shopPurple)
                                }
                                .padding(.horizontal, 15)
                                .padding(.vertical, 11)
                                .background(Color(red: 247/255, green: 246/255, blue: 252/255))
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.shopPurple.opacity(0.12), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }

                // Bottom Custom Answer Field
                VStack(spacing: 8) {
                    Divider()

                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil.line")
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 150/255, green: 150/255, blue: 160/255))

                            TextField("Oppure digita qui la tua risposta...", text: $customAnswerText)
                                .font(.system(size: 14))
                                .focused($isCustomFieldFocused)
                                .submitLabel(.send)
                                .onSubmit {
                                    submitCustom()
                                }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(red: 245/255, green: 245/255, blue: 248/255))
                        .cornerRadius(20)

                        if !customAnswerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button(action: submitCustom) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Color.shopPurple)
                                    .clipShape(Circle())
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(red: 190/255, green: 190/255, blue: 200/255))
                    }
                }
            }
        }
    }

    private func submitCustom() {
        let clean = customAnswerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        dismiss()
        onAnswerSelected(clean)
    }
}

// MARK: - Follow-Up Suggestion Purple Pill Button
struct ShopFollowUpPillButton: View {
    let title: String
    let onTap: () -> Void

    private var isQuestion: Bool {
        SearchView.isQuestionSuggestion(title)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Left Icon
                ZStack {
                    Circle()
                        .fill(isQuestion ? Color.shopPurple.opacity(0.12) : Color.white.opacity(0.8))
                        .frame(width: 28, height: 28)

                    Image(systemName: isQuestion ? "questionmark.bubble.fill" : "sparkle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.shopPurple)
                }

                // Text
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(red: 70/255, green: 40/255, blue: 180/255))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                // Right action hint
                if isQuestion {
                    HStack(spacing: 4) {
                        Text("Rispondi")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(Color.shopPurple)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.shopPurple)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(12)
                } else {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.shopPurple.opacity(0.75))
                        .padding(6)
                        .background(Color.white.opacity(0.8))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 243/255, green: 239/255, blue: 255/255),
                        Color(red: 248/255, green: 245/255, blue: 255/255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.shopPurple.opacity(0.16), lineWidth: 1)
            )
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
