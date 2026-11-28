import SwiftUI
import PhotosUI
import AVFoundation

struct SearchView: View {
    @StateObject private var api = APIService.shared
    @StateObject private var keyboardObserver = KeyboardObserver.shared
    @ObservedObject private var tabVisibility = TabBarVisibilityManager.shared
    @ObservedObject private var tabCoordinator = TabCoordinator.shared
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool
    @FocusState private var isFollowUpFieldFocused: Bool
    @State private var wasSearchKeyboardActive: Bool = false
    @State private var hasAutoFocused: Bool = false
    @State private var showVisualSearch: Bool = false

    @State private var searchResults: [MatchedProduct] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var hasSearched: Bool = false
    @State private var activeSearchTask: Task<Void, Never>? = nil
    @State private var activeVisualSearchTask: Task<Void, Never>? = nil

    // Shopify Shop Intelligent Search Mode (AI Deep Dive vs Classic)
    @State private var isDeepDiveMode: Bool = true
    @State private var userForcedClassicMode: Bool = false
    @State private var rootQuery: String = ""
    @State private var lastFollowUpQuery: String? = nil
    @State private var conversationalHeader: String = "Ho cercato prodotti"
    @State private var conversationalSummary: String = ""
    @State private var searchedQueries: [String] = []
    @State private var curatedSections: [CuratedProductSection] = []
    @State private var comparativeCards: [ComparativeSpecCard] = []
    @State private var featuredCards: [SpotlightRecommendation] = []
    @State private var spotlight: SpotlightRecommendation? = nil
    @State private var followUpSuggestions: [String] = []
    @State private var activeQuestionPrompt: FollowUpQuestionPrompt? = nil
    @State private var followUpInputText: String = ""
    @State private var userFeedback: Int? = nil // 1 for thumbs up, -1 for down
    @State private var feedbackConfig: SearchFeedbackSheetConfig? = nil
    @State private var feedbackSubmittedToast: Bool = false
    @State private var lastContextQuery: String? = nil // Multi-turn conversational memory
    @State private var conversationTurns: [SearchConversationTurn] = []
    @State private var currentSessionId: String? = nil
    @State private var savedChatSessions: [ChatSessionSummary] = []
    @State private var isLoadingChatSessions: Bool = true
    @State private var isFollowUpLoading: Bool = false
    @State private var pendingFollowUpQuery: String? = nil
    @State private var pendingVisualImageURL: String? = nil
    @State private var pendingVisualImagePreview: UIImage? = nil
    @State private var pendingVisualDescription: String? = nil
    @State private var followUpErrorMessage: String? = nil
    @State private var thinkingSteps: [SearchThinkingStep] = []
    @State private var thinkingStartedAt: Date = Date()
    @State private var partialStreamResults: [MatchedProduct] = []
    @State private var partialStreamChips: [SmartSearchChip] = []

    // Filters (Classic Search Mode)
    @State private var selectedFilterCountry: String? = nil // nil, "EU", "IT"
    @State private var selectedSize: String? = nil
    @State private var selectedStore: String? = nil
    @State private var sortMode: SortMode = .relevance
    @State private var showClassicFiltersSheet: Bool = false
    @State private var classicFreeShippingOnly: Bool = false
    @State private var classicOnSaleOnly: Bool = false

    // Classic Mode Pagination ("Carica altri")
    @State private var hasMoreClassicResults: Bool = false
    @State private var isLoadingMoreClassic: Bool = false
    @State private var activeContextState: ChatSessionContextState? = nil
    @State private var loadMoreErrorMessage: String? = nil

    // Live Catalog Autocomplete
    @State private var liveAutocompleteSuggestions: [String] = []
    @State private var autocompleteTask: Task<Void, Never>? = nil

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
        case relevance = "Rilevanza"
        case bestTotalPrice = "Miglior Prezzo"
        case maxSavings = "Massimo Risparmio"
        case lowestPrice = "Prezzo Minimo"
        case maxDiscount = "Maggior Sconto"

        var id: String { rawValue }
    }

    private let shoeSizesList = ["Tutte", "36", "37", "37.5", "38", "38.5", "39", "40", "40.5", "41", "42", "42.5", "43", "44", "44.5", "45", "46", "47"]
    private let apparelSizesList = ["Tutte", "XS", "S", "M", "L", "XL", "XXL"]

    private var isCurrentSearchApparel: Bool {
        let probe = "\(rootQuery) \(searchText) \(smartIntent?.category ?? "")".lowercased()
        return probe.range(
            of: #"\b(top|pants|jacket|apparel|long\s*sleeve|short\s*sleeve|manica|magli[ae]|t[\s-]*shirt|felp[ae]|fleece|pile|pantalon|shorts|leggings|tights|giacc[ae]|canott[ae]|reggisen)\b"#,
            options: .regularExpression
        ) != nil
    }

    private var isCurrentSearchNonWearable: Bool {
        let probe = "\(rootQuery) \(searchText) \(smartIntent?.category ?? "")".lowercased()
        return probe.range(
            of: #"\b(sensor|fasc(?:ia|e|ie)\s*card(?:io|o)|\bhrm\b|gps_watch|orologi[o]?|smartwatch|cycling|ciclocomputer|eyewear|occhial[ie]|hydration|zain[oi]|borracc(?:ia|e)|padel|racchett[ae]|nutrition|gel\s*energetic|barrett[ae]|occhialin[oi]|cuffi[ae]|rull[oi]|smart\s*trainer)\b"#,
            options: .regularExpression
        ) != nil && probe.range(
            of: #"\b(scarp[ae]|shoes?|magli[ae]|pantalon|shorts?|leggings?|tights?|giacc[ae])\b"#,
            options: .regularExpression
        ) == nil
    }

    private var contextualAvailableSizes: [String] {
        isCurrentSearchApparel ? apparelSizesList : shoeSizesList
    }

    private var activeClassicFilterCount: Int {
        var count = 0
        if overrideMaxPrice != nil { count += 1 }
        if selectedStore != nil { count += 1 }
        if classicFreeShippingOnly { count += 1 }
        if classicOnSaleOnly { count += 1 }
        return count
    }

    private var availableStoresInResults: [String] {
        let names = Set(searchResults.flatMap { $0.offers.map(\.store_name) })
        return names.sorted()
    }

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
            let target = country.uppercased()
            list = list.filter { prod in
                prod.offers.contains { off in
                    DynamicCatalogRegistry.shared.storeCountry(for: off.store_id, storeName: off.store_name) == target
                }
            }
        }

        if let st = selectedStore, st != "Tutti" {
            list = list.filter { prod in
                prod.offers.contains { $0.store_name.lowercased().contains(st.lowercased()) }
            }
        }

        if let maxP = overrideMaxPrice, maxP > 0 {
            list = list.filter { prod in
                (prod.best_price ?? Double.infinity) <= maxP + 0.01
            }
        }

        if classicFreeShippingOnly {
            list = list.filter { prod in
                prod.offers.contains { ($0.shipping_cost ?? 99) <= 0.01 }
            }
        }

        if classicOnSaleOnly {
            list = list.filter { prod in
                prod.offers.contains { o in
                    (o.discount_pct ?? 0) >= 5 || ((o.original_price ?? 0) > o.price + 1)
                }
            }
        }

        switch sortMode {
        case .relevance:
            break // Preserve the hybrid search engine's relevance ranking
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
                        .shopFadeScaleTransition()
                } else {
                    // Search Typing / History View
                    searchTypingHistoryView
                        .transition(.opacity)
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
                        .padding(.horizontal, ShopLayout.screenPadding)
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
            .animation(ShopMotion.tabSwitch, value: hasSearched || !searchResults.isEmpty)
            .navigationDestination(item: $selectedRecentProduct) { prod in
                ProductDetailView(product: prod, openedFromSearch: true)
            }
            .sheet(isPresented: $showVisualSearch) {
                ShopVisualSearchSheet(
                    onSelectModel: { recognizedQuery, uploadedImageURL in
                        hideAllKeyboards()
                        let runAsFollowUp = hasSearched && isDeepDiveMode && !conversationTurns.isEmpty
                        if !runAsFollowUp {
                            searchText = recognizedQuery
                            rootQuery = recognizedQuery
                        }
                        handleSearchOrComparison(query: recognizedQuery, isFollowUp: runAsFollowUp, userImageURL: uploadedImageURL)
                    },
                    onStartVisualSearch: { capturedImage, optionalDescription in
                        hideAllKeyboards()
                        let runAsFollowUp = hasSearched && isDeepDiveMode && !conversationTurns.isEmpty
                        executeVisualSearch(image: capturedImage, description: optionalDescription, isFollowUp: runAsFollowUp)
                    }
                )
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $feedbackConfig) { config in
                ShopSearchFeedbackSheet(
                    query: config.query,
                    products: config.products,
                    initialFeedbackType: config.feedbackType,
                    sessionId: config.sessionId,
                    turnId: config.turnId,
                    onSubmitted: { finalType in
                        let fbVal = finalType == "positive" ? 1 : -1
                        if let tid = config.turnId,
                           let idx = conversationTurns.firstIndex(where: { $0.id == tid }) {
                            conversationTurns[idx].userFeedback = fbVal
                        }
                        userFeedback = fbVal
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
                let hasOptions = !SearchView.extractQuickOptions(for: prompt.question).isEmpty
                FollowUpQuestionSheet(
                    question: prompt.question,
                    baseQuery: rootQuery.isEmpty ? searchText : rootQuery,
                    onAnswerSelected: { answer in
                        handleQuestionAnswered(question: prompt.question, answer: answer)
                    }
                )
                .presentationDetents(hasOptions ? [.medium, .large] : [.height(250), .medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showClassicFiltersSheet) {
                ShopClassicFiltersSheet(
                    maxPrice: $overrideMaxPrice,
                    selectedStore: $selectedStore,
                    freeShippingOnly: $classicFreeShippingOnly,
                    onSaleOnly: $classicOnSaleOnly,
                    sortMode: $sortMode,
                    availableStores: availableStoresInResults,
                    onApplyServerRefresh: { prompt in
                        applyClassicFilterRefinement(followUpPrompt: prompt)
                    },
                    onResetAll: {
                        overrideMaxPrice = nil
                        selectedStore = nil
                        selectedSize = nil
                        selectedFilterCountry = nil
                        classicFreeShippingOnly = false
                        classicOnSaleOnly = false
                        sortMode = .relevance
                        applyClassicFilterRefinement(followUpPrompt: "Rimuovi tutti i filtri")
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: searchText) { _, newValue in
                autocompleteTask?.cancel()
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 2, !hasSearched else {
                    liveAutocompleteSuggestions = []
                    return
                }
                autocompleteTask = Task {
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    guard !Task.isCancelled else { return }
                    let live = await SupabaseManager.shared.fetchCatalogSuggestions(prefix: trimmed, limit: 4)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self.liveAutocompleteSuggestions = live
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            .onAppear {
                if tabCoordinator.selectedTab == 1 && !hasAutoFocused && !hasSearched {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        isSearchFieldFocused = true
                        hasAutoFocused = true
                    }
                }
            }
            .onChange(of: tabCoordinator.selectedTab) { newTab in
                if newTab == 1 {
                    Task {
                        await recentManager.syncFromDatabase()
                    }
                } else {
                    wasSearchKeyboardActive = false
                    hideAllKeyboards()
                    tabVisibility.setHidden(false, for: "search_input")
                }
            }
            .onChange(of: isSearchFieldFocused) { focused in
                if focused {
                    wasSearchKeyboardActive = true
                } else if !isFollowUpFieldFocused && !keyboardObserver.isKeyboardVisible {
                    wasSearchKeyboardActive = false
                }
                updateTabBarVisibility()
            }
            .onChange(of: isFollowUpFieldFocused) { focused in
                if focused {
                    wasSearchKeyboardActive = true
                } else if !isSearchFieldFocused && !keyboardObserver.isKeyboardVisible {
                    wasSearchKeyboardActive = false
                }
                updateTabBarVisibility()
            }
            .onChange(of: keyboardObserver.isKeyboardVisible) { visible in
                if !visible {
                    wasSearchKeyboardActive = false
                }
                updateTabBarVisibility()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FitMatchFocusSearch"))) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isSearchFieldFocused = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FitMatchOpenVisualSearch"))) { _ in
                hideAllKeyboards()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    showVisualSearch = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FitMatchRunQuickSearch"))) { notif in
                guard let query = notif.userInfo?["query"] as? String,
                      !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                hideAllKeyboards()
                searchText = query
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    executeSearch(isFollowUp: false, ignorePriorContext: true)
                }
            }
            .onDisappear {
                hideAllKeyboards()
            }
            .task {
                async let syncRecent: Void = recentManager.syncFromDatabase()
                async let loadChats: Void = loadSavedChatSessions()
                _ = await (syncRecent, loadChats)
                if !searchText.isEmpty && !hasSearched {
                    executeSearch()
                }
            }
        }
    }

    // MARK: - Search Typing & History View
    private var searchTypingHistoryView: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        // Header Title: Cerca (with back button if navigated from Home/Product)
                    HStack(spacing: 12) {
                        if tabCoordinator.previousTab != nil {
                            Button(action: {
                                tabCoordinator.returnToPreviousTab()
                            }) {
                                Circle()
                                    .fill(Color(red: 246/255, green: 247/255, blue: 249/255))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle().stroke(Color(red: 232/255, green: 233/255, blue: 237/255), lineWidth: 0.8)
                                    )
                                    .overlay(
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.shopDark)
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Cerca")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Spacer()
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.top, 4)

                    // Section 1: "Visti di recente >" (Screenshot 1 & 2 top)
                    if !recentManager.recentlyViewedProducts.isEmpty {
                        recentlyViewedSection
                            .transition(.opacity)
                    } else if recentManager.isSyncingDatabase {
                        ShopSearchRecentlyViewedSkeletonSection()
                            .transition(.opacity)
                    }

                    // Section 2: "Conversazioni recenti" (Saved multi-turn chats from DB)
                    if !savedChatSessions.isEmpty {
                        savedChatSessionsSection
                            .transition(.opacity)
                    } else if isLoadingChatSessions {
                        ShopSearchRecentChatsSkeletonSection(rowCount: 3)
                            .transition(.opacity)
                    } else if recentManager.recentlyViewedProducts.isEmpty && !recentManager.isSyncingDatabase {
                        emptyHistoryPlaceholder
                            .transition(.opacity)
                    }

                    Spacer(minLength: 150)
                }
                .padding(.top, 10)
                .animation(.easeOut(duration: 0.24), value: recentManager.isSyncingDatabase)
                .animation(.easeOut(duration: 0.24), value: isLoadingChatSessions)
                .id("search_home_top")
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture {
                hideAllKeyboards()
            }
            .onReceive(tabCoordinator.$scrollToTopEvent) { event in
                guard let event, event.tab == 1, !hasSearched else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    scrollProxy.scrollTo("search_home_top", anchor: .top)
                }
            }
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
        FitMatchEmptyStateView(
            icon: "magnifyingglass",
            title: "Cerca un prodotto",
            subtitle: "Digita un modello, un brand o uno sport per confrontare i prezzi.",
            showsCardBackground: false
        )
        .padding(.horizontal, ShopLayout.screenPadding)
        .padding(.top, 36)
        .contentShape(Rectangle())
        .onTapGesture {
            hideAllKeyboards()
        }
    }

    private var isAnyKeyboardFocused: Bool {
        isSearchFieldFocused || isFollowUpFieldFocused
    }

    private var floatingBarBottomPadding: CGFloat {
        guard tabCoordinator.selectedTab == 1 else { return 90 }
        if (wasSearchKeyboardActive || isAnyKeyboardFocused) && keyboardObserver.effectiveKeyboardOffset > 0 {
            return keyboardObserver.effectiveKeyboardOffset + 8
        } else {
            return 90
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
            .padding(.horizontal, ShopLayout.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ShopLayout.compactSpacing) {
                    ForEach(recentManager.recentlyViewedProducts) { prod in
                        RecentlyViewedCard(product: prod) {
                            selectedRecentProduct = prod
                        }
                        .shopCarouselTransition()
                    }
                }
                .padding(.horizontal, ShopLayout.screenPadding)
            }
        }
    }

    // MARK: - Section 2: Conversazioni recenti (Persistent DB Chats)
    private var savedChatSessionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Conversazioni recenti")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.shopDark)

                Text("\(min(savedChatSessions.count, 5))")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.shopPurple)
                    .padding(.horizontal, 7.5)
                    .padding(.vertical, 2.5)
                    .background(Color.shopPurple.opacity(0.10))
                    .clipShape(Capsule())

                Spacer()
            }
            .padding(.horizontal, ShopLayout.screenPadding)

            VStack(spacing: 10) {
                ForEach(savedChatSessions.prefix(5)) { session in
                    savedChatSessionRow(session)
                }
            }
            .padding(.horizontal, ShopLayout.screenPadding)
        }
    }

    private func savedChatSessionRow(_ session: ChatSessionSummary) -> some View {
        let turnsCount = max(1, session.turn_count ?? 1)
        let rawSubtitle = (session.subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSubtitle: String? = {
            let genericSubtitles: Set<String> = [
                "ho cercato prodotti",
                "ho cercato",
                "ricerca prodotti",
                "ricerca",
                "offerte verificate nel catalogo fitmatch cloud"
            ]
            if !rawSubtitle.isEmpty,
               !genericSubtitles.contains(rawSubtitle.lowercased()),
               rawSubtitle.caseInsensitiveCompare(session.title) != .orderedSame,
               rawSubtitle.range(of: #"\b(ai|ia)\b"#, options: [.regularExpression, .caseInsensitive]) == nil {
                return rawSubtitle
            }
            if let ctx = session.context_state {
                if turnsCount > 1,
                   let lastQ = ctx.last_query?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !lastQ.isEmpty,
                   lastQ.caseInsensitiveCompare(session.title) != .orderedSame {
                    return lastQ
                }
                let titleLower = session.title.lowercased()
                var parts: [String] = []
                if let g = ctx.gender?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !g.isEmpty, g.lowercased() != "unisex",
                   !titleLower.contains(g.lowercased()) {
                    parts.append(g.capitalized)
                }
                if let sz = ctx.size?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !sz.isEmpty,
                   !titleLower.contains(sz.lowercased()) {
                    parts.append("Tg. \(sz)")
                }
                if let mp = ctx.max_price, mp > 0 {
                    parts.append("fino a \(Int(mp)) €")
                }
                if !parts.isEmpty {
                    return parts.joined(separator: " · ")
                }
            }
            return nil
        }()

        return Button(action: {
            restoreChatSession(session)
        }) {
            HStack(spacing: 13) {
                if let imgUrl = session.preview_image_url, !imgUrl.isEmpty {
                    ShopProductThumbnail(
                        imageUrl: imgUrl,
                        systemIcon: "bubble.left.and.bubble.right.fill",
                        cornerRadius: 13,
                        size: CGSize(width: 48, height: 48)
                    )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.shopPurple.opacity(0.12), Color.shopPurple.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)

                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.shopPurple)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.shopDark)
                        .lineLimit(1)

                    if let sub = cleanSubtitle {
                        Text(sub)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(Color(red: 110/255, green: 110/255, blue: 124/255))
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        if turnsCount > 1 {
                            Text("\(turnsCount) messaggi")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.shopPurple)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.shopPurple.opacity(0.08))
                                .clipShape(Capsule())
                        }

                        Text(session.formattedUpdatedDate)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color(red: 145/255, green: 145/255, blue: 158/255))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 175/255, green: 175/255, blue: 185/255))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 8, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(role: .destructive) {
                deleteSavedChatSession(session)
            } label: {
                Label("Elimina conversazione", systemImage: "trash")
            }
        }
    }

    private func loadSavedChatSessions() async {
        await MainActor.run {
            if self.savedChatSessions.isEmpty {
                self.isLoadingChatSessions = true
            }
        }
        let sessions = await api.fetchChatSessions(deviceId: SupabaseManager.shared.deviceId, limit: 15)
        await MainActor.run {
            self.savedChatSessions = sessions.filter { ($0.chat_type ?? "smart_search") == "smart_search" }
            self.isLoadingChatSessions = false
        }
    }

    private func deleteSavedChatSession(_ session: ChatSessionSummary) {
        withAnimation {
            savedChatSessions.removeAll { $0.id == session.id }
        }
        Task {
            _ = await api.deleteChatSession(sessionId: session.id, deviceId: SupabaseManager.shared.deviceId)
        }
    }

    private func restoreChatSession(_ session: ChatSessionSummary) {
        hideAllKeyboards()
        isLoading = true
        hasSearched = true
        currentSessionId = session.id
        rootQuery = session.title
        searchText = session.title

        Task {
            if let detail = await api.fetchChatSessionDetail(sessionId: session.id),
               let msgs = detail.messages, !msgs.isEmpty {
                let restoredTurns: [SearchConversationTurn] = msgs.map { m in
                    let snap = m.results_snapshot_json
                    return SearchConversationTurn(
                        id: m.id,
                        query: m.query,
                        isFollowUp: m.is_follow_up ?? (m.turn_index > 0),
                        isConversationalAdvice: m.is_conversational_advice ?? false,
                        conversationalHeader: m.conversational_header ?? "Ho cercato prodotti",
                        conversationalSummary: m.conversational_summary ?? "",
                        searchedQueries: snap?.searched_queries ?? [],
                        smartIntent: m.intent_json,
                        activeChips: m.chips_json ?? [],
                        searchResults: snap?.results ?? [],
                        curatedSections: snap?.curated_sections ?? [],
                        comparativeCards: snap?.comparative_cards ?? [],
                        featuredCards: snap?.featured_cards ?? [],
                        spotlight: snap?.spotlight,
                        followUpSuggestions: m.follow_up_suggestions_json ?? [],
                        userFeedback: m.user_feedback,
                        showAiExplanation: false,
                        error: nil,
                        isOffTopic: m.is_off_topic ?? false,
                        isUnsafe: m.is_unsafe ?? false,
                        userImageURL: m.user_image_url,
                        timestamp: Date()
                    )
                }
                await MainActor.run {
                    if let last = restoredTurns.last {
                        self.selectedSize = nil
                        self.overrideMaxPrice = nil
                        self.selectedStore = nil
                        self.selectedFilterCountry = nil
                        self.classicFreeShippingOnly = false
                        self.classicOnSaleOnly = false
                        self.hasMoreClassicResults = last.searchResults.count >= 28
                        self.isLoadingMoreClassic = false
                        self.activeContextState = detail.context_state
                        self.loadMoreErrorMessage = nil
                        self.conversationTurns = restoredTurns
                        self.lastContextQuery = restoredTurns.map(\.query).filter { !$0.isEmpty }.joined(separator: " >> ")
                        self.smartIntent = last.smartIntent
                        self.activeChips = last.activeChips
                        self.searchResults = last.searchResults
                        self.searchedQueries = last.searchedQueries
                        self.curatedSections = last.curatedSections
                        self.comparativeCards = last.comparativeCards
                        self.featuredCards = last.featuredCards
                        self.spotlight = last.spotlight
                        self.followUpSuggestions = last.followUpSuggestions
                        self.conversationalHeader = last.conversationalHeader
                        self.conversationalSummary = last.conversationalSummary
                        self.isDeepDiveMode = true
                        self.isSmartSearchActive = true
                        self.errorMessage = nil
                    }
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                    self.executeSearch(isFollowUp: false)
                }
            }
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
            "Scarpe running sotto i 150 euro",
            "Scarpe running più economiche",
            "Nike long sleeve ACG",
            "Long sleeve da corsa",
            "Maglia termica running invernale",
            "Pantaloncini running con tasche",
            "Scarpe Hyrox e allenamento ibrido",
            "Puma Deviate Nitro 3 Hyrox",
            "Adidas Adizero Dropset Pro",
            "Scarpe da gara per la maratona",
            "Scarpe running massimo ammortizzamento",
            "Scarpe running senza piastra in carbonio",
            "Scarpe da trail running impermeabili GTX",
            "Nike Pegasus 41",
            "Nike Pegasus Plus",
            "Nike Vomero 18",
            "Nike Vaporfly 4",
            "Nike Alphafly 3",
            "Asics Gel-Nimbus 27",
            "Asics Novablast 5",
            "Asics Superblast 2",
            "Hoka Clifton 10",
            "Hoka Bondi 9",
            "Hoka Speedgoat 6",
            "Saucony Endorphin Speed 4",
            "Saucony Triumph 22",
            "Saucony Ride 18",
            "Brooks Ghost 17",
            "Brooks Glycerin 22",
            "Adidas Adizero Adios Pro 4",
            "Adidas Adizero Boston 13",
            "Adidas Adizero EVO SL",
            "New Balance Fresh Foam 1080 v15",
            "On Cloudmonster 2",
            "Salomon Speedcross 6 GTX",
            "Gilet idratazione Salomon Active Skin",
            "Garmin Forerunner 165",
            "Garmin Forerunner 265",
            "Garmin Fenix 8",
            "Fascia cardio Garmin HRM",
            "Oakley Sutro Prizm",
            "Rullo smart Wahoo Kickr"
        ]

        let queryTokens = q.split(separator: " ").map { String($0) }
        let localMatches = allPool.filter { candidate in
            let candLow = candidate.lowercased()
            return candLow.contains(q) || queryTokens.allSatisfy { candLow.contains($0) }
        }

        // Merge live catalog matches FIRST (real products in DB) + curated local intent suggestions
        var merged: [String] = []
        var seen = Set<String>()
        for item in liveAutocompleteSuggestions + localMatches {
            let key = item.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                merged.append(item)
            }
        }
        return merged
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

                TextField("Cerca o chiedi qualsiasi cosa...", text: $searchText)
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
            if isSearchFieldFocused || (wasSearchKeyboardActive && keyboardObserver.isKeyboardVisible) {
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
        .animation(.easeOut(duration: 0.22), value: isSearchFieldFocused || (wasSearchKeyboardActive && keyboardObserver.isKeyboardVisible))
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

    // MARK: - AI Deep Dive: Minimal Shop-Style Header Chrome (Screenshots 1–4)
    private var aiDeepDiveHeaderBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                resetToSearchTyping(keepText: false)
            }) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                    .overlay(
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundColor(.shopDark)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
            }
            .buttonStyle(.plain)

            Spacer()

            // New search / compose button (matches Shop top-right circular button)
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                resetToSearchTyping(keepText: false)
            }) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                    .overlay(
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.shopDark)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, ShopLayout.screenPadding)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(Color.white.opacity(0.96))
        .zIndex(10)
    }

    // MARK: - AI Deep Dive: Main Content View (Screenshots 1, 2, 3)
    private var aiDeepDiveContentView: some View {
        Group {
            if isLoading && conversationTurns.isEmpty {
                let activeQueryText = (rootQuery.isEmpty ? searchText : rootQuery)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let initialPromptBubbleText: String = {
                    if pendingVisualImagePreview != nil {
                        if let desc = pendingVisualDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                            return desc
                        }
                        if activeQueryText != "Ricerca dalla foto" {
                            return activeQueryText
                        }
                        return ""
                    }
                    return activeQueryText
                }()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        if pendingVisualImagePreview != nil || pendingVisualImageURL != nil || !initialPromptBubbleText.isEmpty {
                            VStack(alignment: .trailing, spacing: 8) {
                                if let localPreview = pendingVisualImagePreview {
                                    HStack {
                                        Spacer()
                                        Image(uiImage: localPreview)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 112, height: 112)
                                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                            )
                                            .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                                    }
                                } else if let imgStr = pendingVisualImageURL, let imgURL = URL(string: imgStr) {
                                    HStack {
                                        Spacer()
                                        ShopCachedAsyncImage(url: imgURL, maxPixelSize: 320) { phase in
                                            if let image = phase.image {
                                                image.resizable().scaledToFill()
                                            } else {
                                                ShopSkeletonBlock(cornerRadius: 16)
                                            }
                                        }
                                        .frame(width: 112, height: 112)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                                    }
                                }

                                if !initialPromptBubbleText.isEmpty {
                                    HStack {
                                        Spacer(minLength: 48)
                                        Text(initialPromptBubbleText)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.shopDark)
                                            .multilineTextAlignment(.trailing)
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 11)
                                            .background(Color(red: 243/255, green: 243/255, blue: 245/255))
                                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    }
                                }
                            }
                            .padding(.horizontal, ShopLayout.screenPadding)
                            .padding(.top, 2)
                        }

                        if !partialStreamResults.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                ShopAgentThinkingCardView(
                                    query: activeQueryText,
                                    isFollowUp: false,
                                    steps: thinkingSteps,
                                    startedAt: thinkingStartedAt
                                )
                                .padding(.horizontal, ShopLayout.screenPadding)

                                partialStreamPreviewSection

                                VStack(alignment: .leading, spacing: 7) {
                                    ShopSkeletonTextLine(height: 12, cornerRadius: 5)
                                        .frame(maxWidth: .infinity)
                                    ShopSkeletonTextLine(width: 220, height: 12, cornerRadius: 5)
                                }
                                .padding(.horizontal, ShopLayout.screenPadding)
                                .opacity(0.55)

                                Spacer(minLength: ShopLayout.bottomFilterDockClearance)
                            }
                            .transition(.opacity)
                        } else {
                            ShopSearchDeepDiveSkeletonView(
                                query: activeQueryText,
                                thinkingSteps: thinkingSteps,
                                thinkingStartedAt: thinkingStartedAt
                            )
                        }
                    }
                }
                .transition(.opacity)
            } else if let error = errorMessage, conversationTurns.isEmpty {
                aiErrorView(error)
            } else if conversationTurns.isEmpty && curatedSections.isEmpty && searchResults.isEmpty && spotlight == nil {
                aiEmptyView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 0).id("search_ai_top")

                            VStack(alignment: .leading, spacing: 18) {
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
                                        .transition(.opacity)
                                }

                                // Follow-up error retry banner (if follow-up failed)
                                if let followUpErr = followUpErrorMessage {
                                    followUpErrorSection(followUpErr)
                                        .transition(.opacity)
                                }

                                // Spacing at bottom for floating follow-up bar and dock
                                Spacer(minLength: 130)
                            }
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
                            DispatchQueue.main.async {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                    proxy.scrollTo(lastTurn.id, anchor: .top)
                                }
                            }
                        }
                    }
                    .onChange(of: isFollowUpLoading) { loading in
                        if loading {
                            DispatchQueue.main.async {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                    proxy.scrollTo("follow_up_loading_section", anchor: .top)
                                }
                            }
                        }
                    }
                    .onAppear {
                        if ProcessInfo.processInfo.arguments.contains("-testAiSearchScrolled") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                withAnimation {
                                    proxy.scrollTo("spotlight_section", anchor: .top)
                                }
                            }
                        }
                    }
                    .onChange(of: curatedSections) { _ in
                        if ProcessInfo.processInfo.arguments.contains("-testAiSearchScrolled") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                withAnimation {
                                    proxy.scrollTo("spotlight_section", anchor: .top)
                                }
                            }
                        }
                    }
                    .onReceive(tabCoordinator.$scrollToTopEvent) { event in
                        guard let event, event.tab == 1, hasSearched, isDeepDiveMode else { return }
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            proxy.scrollTo("search_ai_top", anchor: .top)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.22), value: isLoading)
    }

    // MARK: - Conversational Turn Content View (Shop-Exact Layout)
    @ViewBuilder
    private func turnContentView(for turn: SearchConversationTurn) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. User Photo + Query Pill Bubble (right-aligned, clean light-gray Shop capsule)
            VStack(alignment: .trailing, spacing: 8) {
                if let imgStr = turn.userImageURL, let imgURL = URL(string: imgStr) {
                    HStack {
                        Spacer()
                        ShopCachedAsyncImage(url: imgURL, maxPixelSize: 320) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                ShopSkeletonBlock(cornerRadius: 16)
                            }
                        }
                        .frame(width: 112, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                    }
                }

                if !turn.query.isEmpty {
                    HStack {
                        Spacer(minLength: 48)
                        Button(action: {
                            if !turn.isFollowUp {
                                resetToSearchTyping(keepText: true)
                            }
                        }) {
                            Text(turn.query)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.shopDark)
                                .multilineTextAlignment(.trailing)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                                .background(Color(red: 243/255, green: 243/255, blue: 245/255))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Subtle purple "Cerca invece questo" link (Screenshot 3) to switch to Classic filterable list
                if !turn.isOffTopic && !turn.isUnsafe && !turn.searchResults.isEmpty && turn.id == conversationTurns.last?.id {
                    HStack {
                        Spacer()
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            self.searchResults = turn.searchResults
                            self.userForcedClassicMode = true
                            withAnimation(.easeInOut(duration: 0.22)) {
                                self.isDeepDiveMode = false
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Cerca invece questo")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.shopPurple)
                            .padding(.top, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, ShopLayout.screenPadding)
            .padding(.top, turn.isFollowUp ? 6 : 2)

            if turn.isConversationalAdvice && turn.searchResults.isEmpty {
                // MARK: - Dedicated Q&A AI Advice Card (only for pure questions without products)
                conversationalAdviceCard(for: turn)
            } else {
                // 2. Expandable "Ho cercato prodotti ⌄" (Screenshots 1 & 3)
                if turn.isOffTopic || turn.isUnsafe || turn.conversationalHeader.contains("non pertinente") || turn.conversationalHeader.contains("non consentita") {
                    HStack(spacing: 6) {
                        Image(systemName: turn.isUnsafe ? "shield.slash.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(turn.isUnsafe ? Color(red: 220/255, green: 38/255, blue: 38/255) : Color.shopPurple)
                        Text(turn.conversationalHeader)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.shopDark)
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
                } else {
                    let hasExpandableDetails = !turn.searchedQueries.isEmpty
                    Button(action: {
                        guard hasExpandableDetails else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            if let idx = conversationTurns.firstIndex(where: { $0.id == turn.id }) {
                                conversationTurns[idx].showAiExplanation.toggle()
                            }
                        }
                    }) {
                        HStack(spacing: 5) {
                            Text(turn.conversationalHeader.isEmpty ? "Ho cercato prodotti" : turn.conversationalHeader)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Color(red: 118/255, green: 118/255, blue: 128/255))
                            if hasExpandableDetails {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(red: 135/255, green: 135/255, blue: 145/255))
                                    .rotationEffect(.degrees(turn.showAiExplanation ? 0 : -90))
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, ShopLayout.screenPadding)
                }

                // Active filter pills (always visible; interactive ✕ on latest turn to remove any single filter!)
                if !turn.activeChips.isEmpty {
                    let isLatestTurn = (turn.id == conversationTurns.last?.id)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(turn.activeChips) { chip in
                                ShopSearchChipView(
                                    chip: chip,
                                    onRemove: isLatestTurn ? {
                                        removeFilterChip(chip)
                                    } : nil
                                )
                            }
                        }
                        .padding(.horizontal, ShopLayout.screenPadding)
                        .padding(.vertical, 2)
                    }
                }

                // Expandable Sub-Query Pills (Screenshot 1: stacked soft-gray pills with magnifying glass!)
                if turn.showAiExplanation && !turn.searchedQueries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(turn.searchedQueries, id: \.self) { subQuery in
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                handleSearchOrComparison(query: subQuery, isFollowUp: false)
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                    Text(subQuery)
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundColor(.shopDark)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(Color(red: 243/255, green: 243/255, blue: 245/255))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // 3. Conversational Editorial Narrative Paragraph (Screenshots 1 & 3)
                if !turn.conversationalSummary.isEmpty {
                    if turn.isOffTopic || turn.isUnsafe || turn.conversationalHeader.contains("non pertinente") || turn.conversationalHeader.contains("non consentita") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(LocalizedStringKey(turn.conversationalSummary))
                                .font(.system(size: 15, weight: .regular))
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
                        .padding(.horizontal, ShopLayout.screenPadding)
                    } else {
                        Text(LocalizedStringKey(turn.conversationalSummary))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.shopDark)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, ShopLayout.screenPadding)
                    }
                }
            }

            // 4. Thematic Curated Carousels (Screenshots 1, 3, 4)
            if !turn.curatedSections.isEmpty {
                ForEach(turn.curatedSections) { section in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(section.title)
                            .font(.system(size: 19.5, weight: .bold))
                            .foregroundColor(.shopDark)
                            .tracking(-0.25)
                            .padding(.horizontal, ShopLayout.screenPadding)

                        Text(section.subtitle)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundColor(Color(red: 115/255, green: 115/255, blue: 125/255))
                            .padding(.horizontal, ShopLayout.screenPadding)
                            .padding(.bottom, 6)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(section.products) { prod in
                                    ShopThemedCarouselCard(product: prod) {
                                        selectedRecentProduct = prod
                                    }
                                }
                            }
                            .padding(.horizontal, ShopLayout.screenPadding)
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.top, 10)
                }
            } else if !turn.searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("I modelli selezionati")
                        .font(.system(size: 19.5, weight: .bold))
                        .foregroundColor(.shopDark)
                        .tracking(-0.25)
                        .padding(.horizontal, ShopLayout.screenPadding)

                    Text("Le opzioni più vicine alla tua ricerca")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundColor(Color(red: 115/255, green: 115/255, blue: 125/255))
                        .padding(.horizontal, ShopLayout.screenPadding)
                        .padding(.bottom, 6)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(turn.searchResults) { prod in
                                ShopThemedCarouselCard(product: prod) {
                                    selectedRecentProduct = prod
                                }
                            }
                        }
                        .padding(.horizontal, ShopLayout.screenPadding)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.top, 10)
            }

            // 5. Stacked Horizontal Featured Product Cards (Screenshot 2!)
            let highlightsList = turn.effectiveFeaturedCards
            if !turn.isConversationalAdvice && !highlightsList.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(highlightsList.prefix(2)) { card in
                        ShopFeaturedProductCard(spotlight: card) {
                            selectedRecentProduct = card.product
                        }
                    }
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 10)
                .id(turn.id == conversationTurns.first?.id ? "spotlight_section" : "spotlight_section_\(turn.id)")
            } else if !turn.isConversationalAdvice && !turn.comparativeCards.isEmpty {
                // Legacy fallback for explicit comparison turns without featured cards
                VStack(alignment: .leading, spacing: 6) {
                    Text(turn.comparativeCards.first?.section_title ?? "Confronto rapido")
                        .font(.system(size: 19.5, weight: .bold))
                        .foregroundColor(.shopDark)
                        .padding(.horizontal, ShopLayout.screenPadding)

                    Text("Scegli in base all'uso principale")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundColor(Color(red: 115/255, green: 115/255, blue: 125/255))
                        .padding(.horizontal, ShopLayout.screenPadding)
                        .padding(.bottom, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(turn.comparativeCards) { card in
                                ShopComparativeCard(card: card) {
                                    selectedRecentProduct = card.product
                                }
                            }
                        }
                        .padding(.horizontal, ShopLayout.screenPadding)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.top, 10)
                .id(turn.id == conversationTurns.first?.id ? "comparative_section" : "comparative_section_\(turn.id)")
            }

            // 6. Follow-Up Suggestion Pills (Screenshots 2 & 4: hug-content lavender capsules)
            if turn.id == conversationTurns.last?.id && !isFollowUpLoading && !turn.followUpSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(turn.followUpSuggestions, id: \.self) { suggestion in
                        ShopFollowUpPillButton(title: suggestion) {
                            handleFollowUpTap(suggestion)
                        }
                    }
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 12)
                .id("followups_section")
                .transition(.opacity)
            }

            // 7. AI Disclaimer & Thumbs Feedback
            turnFeedbackBar(for: turn)

            // Divider between conversation turns
            if turn.id != conversationTurns.last?.id {
                Divider()
                    .background(Color.black.opacity(0.08))
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.top, 12)
            }
        }
    }

    // MARK: - Conversational Advice Card (ChatGPT-style advice in search)
    @ViewBuilder
    private func conversationalAdviceCard(for turn: SearchConversationTurn) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with AI sparkle icon + Title + Category/Subject context
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.shopPurple, Color(red: 110/255, green: 65/255, blue: 240/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Consulente Tecnico FitMatch")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(.shopDark)
                    Text(turn.conversationalHeader)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 110/255, green: 110/255, blue: 125/255))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Narrative Body: Rich ChatGPT-style Markdown answer
            Text(LocalizedStringKey(turn.conversationalSummary))
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.shopDark)
                .lineSpacing(4.5)
                .padding(.horizontal, 16)
                .padding(.bottom, (turn.searchResults.first != nil || turn.spotlight != nil) ? 4 : 14)

            // Reference Subject Product Preview Pill / Card
            if let refProd = turn.searchResults.first ?? turn.spotlight?.product {
                Button(action: {
                    selectedRecentProduct = refProd
                }) {
                    HStack(spacing: 12) {
                        if let imgUrl = refProd.image_url, let url = URL(string: imgUrl) {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFit()
                                } else {
                                    Color(red: 242/255, green: 242/255, blue: 245/255)
                                }
                            }
                            .frame(width: 46, height: 46)
                            .cornerRadius(10)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(refProd.canonical_name)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(.shopDark)
                                .lineLimit(1)
                            if let p = refProd.best_price {
                                Text(String(format: "Miglior offerta da € %.2f", p))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.shopPurple)
                            }
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Text("Vedi offerte")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.shopPurple)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.shopPurple)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(Color(red: 250/255, green: 250/255, blue: 253/255))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
        .padding(.horizontal, ShopLayout.screenPadding)
        .padding(.top, 4)
    }

    // MARK: - Follow-Up Loading Section
    private var followUpLoadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if pendingFollowUpQuery != nil || pendingVisualImageURL != nil || pendingVisualImagePreview != nil {
                VStack(alignment: .trailing, spacing: 8) {
                    if let imgStr = pendingVisualImageURL, let imgURL = URL(string: imgStr) {
                        HStack {
                            Spacer()
                            ShopCachedAsyncImage(url: imgURL, maxPixelSize: 320) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else if let localPreview = pendingVisualImagePreview {
                                    Image(uiImage: localPreview).resizable().scaledToFill()
                                } else {
                                    ShopSkeletonBlock(cornerRadius: 16)
                                }
                            }
                            .frame(width: 112, height: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.shopPurple.opacity(0.22), lineWidth: 1)
                            )
                        }
                    } else if let localPreview = pendingVisualImagePreview {
                        HStack {
                            Spacer()
                            Image(uiImage: localPreview)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 112, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.shopPurple.opacity(0.22), lineWidth: 1)
                                )
                        }
                    }

                    if let pending = pendingFollowUpQuery {
                        HStack {
                            Spacer(minLength: 48)
                            Text(pending)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.shopDark)
                                .multilineTextAlignment(.trailing)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                                .background(Color(red: 243/255, green: 243/255, blue: 245/255))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 8)
            }

            // ChatGPT-style Minimal Thinking Indicator for Follow-Up
            ShopAgentThinkingCardView(
                query: pendingFollowUpQuery ?? lastFollowUpQuery ?? "",
                isFollowUp: true,
                steps: thinkingSteps,
                startedAt: thinkingStartedAt
            )
            .padding(.horizontal, ShopLayout.screenPadding)

            if !partialStreamResults.isEmpty {
                partialStreamPreviewSection
                    .transition(.opacity)
            } else {
                // Quiet Narrative Placeholder Lines
                VStack(alignment: .leading, spacing: 7) {
                    ShopSkeletonTextLine(height: 12, cornerRadius: 5)
                        .frame(maxWidth: .infinity)
                    ShopSkeletonTextLine(width: 210, height: 12, cornerRadius: 5)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .opacity(0.60)
            }
        }
    }

    // MARK: - Progressive SSE Product Preview (renders real verified cards while Stage-2 AI curates)
    private var partialStreamPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !partialStreamChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(partialStreamChips) { chip in
                            ShopSearchChipView(chip: chip)
                        }
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text("\(partialStreamResults.count) \(partialStreamResults.count == 1 ? "modello trovato" : "modelli trovati")")
                        .font(.system(size: 18.5, weight: .bold))
                        .foregroundColor(.shopDark)
                        .tracking(-0.2)
                    ProgressView()
                        .scaleEffect(0.72)
                        .tint(.shopPurple)
                }
                .padding(.horizontal, ShopLayout.screenPadding)

                Text("Anteprima verificata — organizzo sezioni e confronto AI…")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(red: 115/255, green: 115/255, blue: 125/255))
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.bottom, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(partialStreamResults.prefix(12)) { prod in
                            ShopThemedCarouselCard(product: prod) {
                                selectedRecentProduct = prod
                            }
                        }
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.vertical, 2)
                }
            }
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
        .padding(.horizontal, ShopLayout.screenPadding)
        .padding(.top, 4)
    }

    // MARK: - Turn Feedback Bar
    private func turnFeedbackBar(for turn: SearchConversationTurn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("L'IA può commettere errori, ricontrolla le risposte.")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color(red: 130/255, green: 130/255, blue: 140/255))
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 6)

            HStack(spacing: 0) {
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    if let idx = conversationTurns.firstIndex(where: { $0.id == turn.id }) {
                        withAnimation { conversationTurns[idx].userFeedback = 1 }
                    }
                    userFeedback = 1
                    let qStr = turn.query.isEmpty ? (searchText.isEmpty ? "Ricerca" : searchText) : turn.query
                    let sid = currentSessionId
                    let tid = turn.id
                    Task {
                        if let sid, !sid.isEmpty {
                            await api.submitChatTurnFeedback(sessionId: sid, turnId: tid, feedback: 1)
                        }
                        await api.submitSearchFeedback(query: qStr, feedbackType: "positive")
                    }
                    withAnimation { feedbackSubmittedToast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation { feedbackSubmittedToast = false }
                    }
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
                    if let sid = currentSessionId, !sid.isEmpty {
                        let tid = turn.id
                        Task {
                            await api.submitChatTurnFeedback(sessionId: sid, turnId: tid, feedback: -1)
                        }
                    }
                    feedbackConfig = SearchFeedbackSheetConfig(
                        query: turn.query.isEmpty ? (searchText.isEmpty ? "Ricerca" : searchText) : turn.query,
                        feedbackType: "negative",
                        products: turn.productsForFeedback,
                        sessionId: currentSessionId,
                        turnId: turn.id
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
            .padding(.horizontal, ShopLayout.screenPadding)
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
            .padding(.horizontal, ShopLayout.screenPadding)
            .padding(.top, 8)

            if !activeChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeChips) { chip in
                            ShopSearchChipView(chip: chip)
                        }
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.vertical, 2)
                }
            }

            if !conversationalSummary.isEmpty {
                Text(LocalizedStringKey(conversationalSummary))
                    .font(.system(size: 15.5, weight: .regular))
                    .foregroundColor(.shopDark)
                    .lineSpacing(4.5)
                    .padding(.horizontal, ShopLayout.screenPadding)
            }

            if !curatedSections.isEmpty {
                ForEach(curatedSections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.system(size: 18.5, weight: .bold))
                            .foregroundColor(.shopDark)
                            .padding(.horizontal, ShopLayout.screenPadding)

                        Text(section.subtitle)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
                            .padding(.horizontal, ShopLayout.screenPadding)
                            .padding(.bottom, 4)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(section.products) { prod in
                                    ShopThemedCarouselCard(product: prod) {
                                        selectedRecentProduct = prod
                                    }
                                }
                            }
                            .padding(.horizontal, ShopLayout.screenPadding)
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
                        .padding(.horizontal, ShopLayout.screenPadding)

                    Text("Tutti i prodotti trovati per la tua ricerca")
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
                        .padding(.horizontal, ShopLayout.screenPadding)
                        .padding(.bottom, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(searchResults) { prod in
                                ShopThemedCarouselCard(product: prod) {
                                    selectedRecentProduct = prod
                                }
                            }
                        }
                        .padding(.horizontal, ShopLayout.screenPadding)
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
                        .padding(.horizontal, ShopLayout.screenPadding)

                    Text("Scegli in base all'uso principale")
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
                        .padding(.horizontal, ShopLayout.screenPadding)
                        .padding(.bottom, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(comparativeCards) { card in
                                ShopComparativeCard(card: card) {
                                    selectedRecentProduct = card.product
                                }
                            }
                        }
                        .padding(.horizontal, ShopLayout.screenPadding)
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
                    .padding(.horizontal, ShopLayout.screenPadding)
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
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 14)
                .id("followups_section")
                .transition(.opacity)
            }
        }
    }

    // MARK: - AI Deep Dive Error & Empty Views
    private func aiErrorView(_ error: String) -> some View {
        VStack {
            Spacer()
            FitMatchEmptyStateView(
                icon: "wifi.exclamationmark",
                accentColor: .shopRed,
                title: "Ricerca non disponibile",
                subtitle: error,
                primaryTitle: "Riprova",
                primaryIcon: "arrow.clockwise",
                onPrimaryTap: {
                    executeSearch()
                }
            )
            .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }

    private var aiEmptyView: some View {
        let hasActiveFilters = overrideMaxPrice != nil || selectedSize != nil || selectedStore != nil || classicFreeShippingOnly || classicOnSaleOnly || !activeChips.isEmpty
        let displayQuery = rootQuery.isEmpty ? searchText : rootQuery
        let emptySuggestions: [String] = hasActiveFilters
            ? ["Rimuovi limite di prezzo", "Tutte le taglie", "Tutti i negozi"]
            : ["Scarpe maratona", "Garmin Forerunner", "Racchetta padel"]
        return VStack {
            Spacer()
            FitMatchEmptyStateView(
                icon: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "magnifyingglass",
                title: hasActiveFilters ? "Nessun risultato con questi filtri" : "Nessun risultato trovato",
                subtitle: hasActiveFilters
                    ? "Nessuna offerta per «\(displayQuery)» con i filtri selezionati."
                    : "Nessun articolo trovato per «\(displayQuery)». Prova uno dei suggerimenti qui sotto.",
                suggestions: emptySuggestions,
                onSuggestionTap: { term in
                    if hasActiveFilters {
                        if term == "Rimuovi limite di prezzo" { overrideMaxPrice = nil }
                        else if term == "Tutte le taglie" { selectedSize = nil }
                        else if term == "Tutti i negozi" { selectedStore = nil }
                        executeSearch(isFollowUp: !conversationTurns.isEmpty, rawFollowUpText: term)
                    } else {
                        searchText = term
                        executeSearch()
                    }
                },
                primaryTitle: hasActiveFilters ? "Rimuovi filtri" : "Riprova",
                primaryIcon: hasActiveFilters ? "arrow.uturn.backward" : "arrow.clockwise",
                onPrimaryTap: {
                    if hasActiveFilters {
                        overrideMaxPrice = nil
                        selectedSize = nil
                        selectedStore = nil
                        classicFreeShippingOnly = false
                        classicOnSaleOnly = false
                        activeChips = []
                        searchText = displayQuery
                        executeSearch(isFollowUp: false, ignorePriorContext: true)
                    } else {
                        executeSearch()
                    }
                }
            )
            .padding(.horizontal, 16)
            Spacer()
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
                    // Sliders Filter Icon Button -> Opens real Classic Filters Sheet
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showClassicFiltersSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(activeClassicFilterCount > 0 ? .shopPurple : .shopDark)
                            if activeClassicFilterCount > 0 {
                                Text("\(activeClassicFilterCount)")
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundColor(.shopPurple)
                            }
                        }
                        .padding(.horizontal, activeClassicFilterCount > 0 ? 11 : 0)
                        .frame(minWidth: 40, minHeight: 36, maxHeight: 36)
                        .background(activeClassicFilterCount > 0 ? Color.shopPurpleLight : Color.white)
                        .cornerRadius(18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(activeClassicFilterCount > 0 ? Color.shopPurple : Color.black.opacity(0.12), lineWidth: 1)
                        )
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

                    // "Ordina ▾" Dropdown Menu (shows active sort mode clearly & syncs sort with server!)
                    Menu {
                        ForEach(SortMode.allCases) { mode in
                            Button(action: {
                                let changed = (sortMode != mode)
                                withAnimation { sortMode = mode }
                                if changed {
                                    let sortPrompt: String?
                                    switch mode {
                                    case .lowestPrice, .bestTotalPrice:
                                        sortPrompt = "Prezzo più basso"
                                    case .maxDiscount:
                                        sortPrompt = "Sconti più alti"
                                    case .relevance:
                                        sortPrompt = "Ordine consigliato"
                                    case .maxSavings:
                                        sortPrompt = nil
                                    }
                                    if let sortPrompt {
                                        applyClassicFilterRefinement(followUpPrompt: sortPrompt)
                                    }
                                }
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
                        let isCustomSort = sortMode != .relevance
                        HStack(spacing: 5) {
                            Text(isCustomSort ? sortMode.rawValue : "Ordina")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.shopDark)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.shopDark)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(isCustomSort ? Color.shopPurpleLight : Color.white)
                        .cornerRadius(18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(isCustomSort ? Color.shopPurple : Color.black.opacity(0.12), lineWidth: 1)
                        )
                    }

                    // "Taglia ▾" Contextual Dropdown Menu (hidden for non-wearable searches like watches, HRM, rackets)
                    if !isCurrentSearchNonWearable {
                    Menu {
                        let prefSize = isCurrentSearchApparel
                            ? prefs.preferences.preferredApparelSize.trimmingCharacters(in: .whitespacesAndNewlines)
                            : prefs.preferences.preferredShoeSize.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !prefSize.isEmpty {
                            Button(action: {
                                withAnimation {
                                    selectedSize = prefSize
                                    applyClassicFilterRefinement(followUpPrompt: "Taglia \(prefSize)")
                                }
                            }) {
                                HStack {
                                    Text(isCurrentSearchApparel ? "La tua taglia: \(prefSize)" : "La tua taglia: EU \(prefSize)")
                                    if selectedSize == prefSize {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Divider()
                        }

                        ForEach(contextualAvailableSizes, id: \.self) { sz in
                            Button(action: {
                                withAnimation {
                                    selectedSize = (sz == "Tutte") ? nil : sz
                                    applyClassicFilterRefinement(followUpPrompt: sz == "Tutte" ? "Tutte le taglie" : "Taglia \(sz)")
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
                VStack {
                    Spacer()
                    FitMatchEmptyStateView(
                        icon: "wifi.exclamationmark",
                        accentColor: .shopRed,
                        title: "Impossibile caricare i risultati",
                        subtitle: error,
                        primaryTitle: "Riprova",
                        primaryIcon: "arrow.clockwise",
                        onPrimaryTap: {
                            executeSearch()
                        }
                    )
                    .padding(.horizontal, 16)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !filteredAndSortedResults.isEmpty {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Color.clear.frame(height: 0).id("search_classic_top")

                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(filteredAndSortedResults.enumerated()), id: \.element.id) { idx, item in
                                    ShopOfficialProductCard(product: item)
                                        .padding(.vertical, 8)

                                    if idx < filteredAndSortedResults.count - 1 {
                                        Divider()
                                            .opacity(0.45)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                            // Classic Mode Footer & "Carica altri" Pagination
                            VStack(spacing: 10) {
                                Text("Mostrati \(filteredAndSortedResults.count) prodotti")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.shopTextMuted)

                                if let lmErr = loadMoreErrorMessage {
                                    Text(lmErr)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.red.opacity(0.85))
                                        .multilineTextAlignment(.center)
                                }

                                if hasMoreClassicResults {
                                    Button(action: {
                                        loadMoreClassicResults()
                                    }) {
                                        HStack(spacing: 8) {
                                            if isLoadingMoreClassic {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                    .scaleEffect(0.85)
                                                Text("Caricamento...")
                                            } else {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.system(size: 14, weight: .semibold))
                                                Text("Carica altri prodotti")
                                            }
                                        }
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 22)
                                        .frame(height: 44)
                                        .background(Color.shopDark)
                                        .clipShape(Capsule())
                                    }
                                    .disabled(isLoadingMoreClassic)
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 16)
                            .padding(.bottom, 130)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if isFollowUpFieldFocused || isSearchFieldFocused {
                                hideAllKeyboards()
                            }
                        }
                    )
                    .onReceive(tabCoordinator.$scrollToTopEvent) { event in
                        guard let event, event.tab == 1, hasSearched, !isDeepDiveMode else { return }
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            scrollProxy.scrollTo("search_classic_top", anchor: .top)
                        }
                    }
                }
            } else {
                VStack {
                    Spacer()
                    FitMatchEmptyStateView(
                        icon: "magnifyingglass",
                        title: "Nessun prodotto trovato",
                        subtitle: "Nessun articolo corrisponde a «\(searchText)».",
                        suggestions: ["Hoka Clifton", "Garmin 265", "Asics Novablast"],
                        onSuggestionTap: { term in
                            searchText = term
                            executeSearch()
                        }
                    )
                    .padding(.horizontal, 16)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Sticky Bottom Follow-Up Bar (Shop Frosted Glass Capsule + Circle X, Screenshots 1–4)
    private var stickyFollowUpInputBar: some View {
        HStack(spacing: 10) {
            // Main Frosted Glass Pill Capsule
            HStack(spacing: 10) {
                Button(action: {
                    hideAllKeyboards()
                    showVisualSearch = true
                }) {
                    Image(systemName: "camera")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(Color(red: 110/255, green: 110/255, blue: 120/255))
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.04))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())

                TextField("Fai una domanda di follow-up", text: $followUpInputText)
                    .font(.system(size: 15.5, weight: .regular))
                    .foregroundColor(.shopDark)
                    .focused($isFollowUpFieldFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        sendFollowUp()
                    }
                    .disabled(isLoading || isFollowUpLoading)

                if !followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: {
                        followUpInputText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 170/255, green: 170/255, blue: 180/255))
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        sendFollowUp()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor((isLoading || isFollowUpLoading) ? Color.shopPurple.opacity(0.4) : .shopPurple)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isLoading || isFollowUpLoading)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.68)))
            )
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.09), radius: 14, x: 0, y: 4)

            // Separate Circular X Button (matches Shop Screenshots 1–4)
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if isFollowUpFieldFocused || keyboardObserver.isKeyboardVisible {
                    hideAllKeyboards()
                } else {
                    resetToSearchTyping(keepText: false)
                }
            }) {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.75)))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundColor(.shopDark)
                    )
                    .shadow(color: Color.black.opacity(0.09), radius: 14, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, floatingBarBottomPadding)
        .animation(.easeOut(duration: 0.22), value: isFollowUpFieldFocused || (wasSearchKeyboardActive && keyboardObserver.isKeyboardVisible))
    }

    private func hideAllKeyboards() {
        isSearchFieldFocused = false
        isFollowUpFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if !keyboardObserver.isKeyboardVisible {
            wasSearchKeyboardActive = false
            tabVisibility.setHidden(false, for: "search_input")
        }
    }

    private func updateTabBarVisibility() {
        guard tabCoordinator.selectedTab == 1 else {
            tabVisibility.setHidden(false, for: "search_input")
            return
        }
        let shouldHide = isSearchFieldFocused || isFollowUpFieldFocused || (wasSearchKeyboardActive && keyboardObserver.isKeyboardVisible)
        tabVisibility.setHidden(shouldHide, for: "search_input")
    }

    private func preferredSizeForCurrentSearch(query: String, context: String? = nil) -> String {
        let probe = "\(query) \(context ?? "") \(smartIntent?.category ?? "")".lowercased()
        let isNonWearable = probe.range(
            of: #"\b(sensor|fasc(?:ia|e|ie)\s*card(?:io|o)|\bhrm\b|gps_watch|orologi[o]?|smartwatch|cycling|ciclocomputer|eyewear|occhial[ie]|hydration|zain[oi]|borracc(?:ia|e)|padel|racchett[ae]|nutrition|gel\s*energetic|barrett[ae]|occhialin[oi]|cuffi[ae]|rull[oi])\b"#,
            options: .regularExpression
        ) != nil && probe.range(of: #"\b(scarp[ae]|shoes?|magli[ae]|pantalon|shorts?|leggings?|tights?|giacc[ae])\b"#, options: .regularExpression) == nil
        if isNonWearable {
            return ""
        }
        let isApparel = probe.range(
            of: #"\b(top|pants|jacket|long\s*sleeve|manica|magli[ae]|t[\s-]*shirt|felp[ae]|fleece|pile|pantalon|shorts|leggings|tights|giacc[ae]|canott[ae])\b"#,
            options: .regularExpression
        ) != nil
        if isApparel {
            return prefs.preferences.preferredApparelSize.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return prefs.preferences.preferredShoeSize.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetToSearchTyping(keepText: Bool = false) {
        activeSearchTask?.cancel()
        activeSearchTask = nil
        activeVisualSearchTask?.cancel()
        activeVisualSearchTask = nil
        hideAllKeyboards()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            hasSearched = false
            isLoading = false
            searchResults = []
            searchedQueries = []
            curatedSections = []
            comparativeCards = []
            featuredCards = []
            spotlight = nil
            followUpSuggestions = []
            isSmartSearchActive = false
            errorMessage = nil
            followUpInputText = ""
            selectedFilterCountry = nil
            selectedSize = nil
            selectedStore = nil
            overrideMaxPrice = nil
            sortMode = .relevance
            classicFreeShippingOnly = false
            classicOnSaleOnly = false
            hasMoreClassicResults = false
            isLoadingMoreClassic = false
            activeContextState = nil
            loadMoreErrorMessage = nil
            liveAutocompleteSuggestions = []
            autocompleteTask?.cancel()
            userFeedback = nil
            userForcedClassicMode = false
            lastFollowUpQuery = nil
            conversationTurns = []
            currentSessionId = nil
            isFollowUpLoading = false
            pendingFollowUpQuery = nil
            pendingVisualImageURL = nil
            pendingVisualImagePreview = nil
            pendingVisualDescription = nil
            followUpErrorMessage = nil
            partialStreamResults = []
            partialStreamChips = []
            if !keepText {
                searchText = ""
                rootQuery = ""
                lastContextQuery = nil
            } else if !rootQuery.isEmpty {
                searchText = rootQuery
            }
        }
        Task {
            await loadSavedChatSessions()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isSearchFieldFocused = true
        }
    }

    private func clearLocalOverridesIfReset(in text: String) {
        let low = text.lowercased()
        let resetAll = low.contains("rimuovi tutti i filtri") || low.contains("azzera filtri") || low.contains("azzera tutti i filtri") || low.contains("senza filtri")
        if resetAll || low.contains("tutte le taglie") || low.contains("qualsiasi taglia") || low.contains("rimuovi taglia") || low.contains("togli taglia") {
            selectedSize = nil
        }
        if resetAll || low.contains("rimuovi limite di prezzo") || low.contains("senza limite di prezzo") || low.contains("senza limiti di prezzo") || low.contains("tutti i prezzi") || low.contains("qualsiasi prezzo") || low.contains("senza budget") {
            overrideMaxPrice = nil
        }
        if resetAll || low.contains("tutti gli store") || low.contains("tutti i negozi") || low.contains("ovunque") {
            selectedStore = nil
        }
    }

    private func sendFollowUp() {
        guard !isLoading && !isFollowUpLoading else { return }
        let text = followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        followUpInputText = ""
        hideAllKeyboards()
        clearLocalOverridesIfReset(in: text)

        // Note: preferredSize is always sent to the Edge Function, which resolves "mia taglia" cleanly in session context_state
        // without permanently pinning selectedSize across later turns!
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

        clearLocalOverridesIfReset(in: trimmed)
        handleSearchOrComparison(query: trimmed, isFollowUp: true)
    }

    private func handleQuestionAnswered(question: String, answer: String) {
        let clean = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        let simplified = clean.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? clean
        clearLocalOverridesIfReset(in: simplified)
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
            if parts.count == 2 {
                let p1 = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let p2 = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanP1 = p1
                    .replacingOccurrences(of: "Stai cercando ", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "Preferisci ", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "Cerchi ", with: "", options: .caseInsensitive)
                    .capitalized
                let cleanP2 = p2.capitalized
                if cleanP1.count > 2 && cleanP2.count > 2 && cleanP1.count <= 40 && cleanP2.count <= 40 {
                    return [cleanP1, cleanP2, "Entrambi / Misto"]
                }
            }
        }

        // No generic fallback pills when they aren't directly relevant to the question
        return []
    }

    private func handleSearchOrComparison(query: String, isFollowUp: Bool = false, userImageURL: String? = nil) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        hideAllKeyboards()

        if !isFollowUp {
            rootQuery = trimmed
            searchText = trimmed
            selectedSize = nil
            overrideMaxPrice = nil
            selectedStore = nil
            selectedFilterCountry = nil
            sortMode = .relevance
            classicFreeShippingOnly = false
            classicOnSaleOnly = false
            userForcedClassicMode = false
            hasMoreClassicResults = false
            isLoadingMoreClassic = false
            activeContextState = nil
            loadMoreErrorMessage = nil
        }
        executeSearch(isFollowUp: isFollowUp, rawFollowUpText: isFollowUp ? trimmed : nil, userImageURL: userImageURL)
    }

    private func loadMoreClassicResults() {
        guard !isLoadingMoreClassic, hasMoreClassicResults else { return }
        let baseQuery = rootQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            : rootQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseQuery.isEmpty else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isLoadingMoreClassic = true
        loadMoreErrorMessage = nil

        let currentIds = searchResults.compactMap { $0.id_val ?? $0.id }
        let existingKeys = Set(searchResults.map { $0.id_val ?? $0.id })
        let sid = currentSessionId
        let ctx = activeContextState
        let mp = overrideMaxPrice
        let sz = selectedSize
        let st = selectedStore
        let prefSz = preferredSizeForCurrentSearch(query: baseQuery, context: lastContextQuery)

        Task {
            do {
                let pageRes = try await APIService.shared.loadMoreSmartSearch(
                    query: baseQuery,
                    excludeIds: currentIds,
                    sessionId: sid,
                    contextState: ctx,
                    maxPrice: mp,
                    size: sz,
                    store: st,
                    preferredSize: prefSz.isEmpty ? nil : prefSz,
                    limit: 30
                )
                await MainActor.run {
                    let uniqueNew = pageRes.results.filter { item in
                        let k = item.id_val ?? item.id
                        return !existingKeys.contains(k)
                    }
                    withAnimation(.easeOut(duration: 0.22)) {
                        self.searchResults.append(contentsOf: uniqueNew)
                    }
                    self.hasMoreClassicResults = !uniqueNew.isEmpty && (pageRes.has_more ?? false)
                    self.isLoadingMoreClassic = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingMoreClassic = false
                    self.loadMoreErrorMessage = "Impossibile caricare altri prodotti. Riprova."
                }
            }
        }
    }

    private func removeFilterChip(_ chip: SmartSearchChip) {
        guard !isLoading && !isFollowUpLoading else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let resetQuery: String
        switch chip.param_key {
        case "max_price", "min_price":
            overrideMaxPrice = nil
            resetQuery = "Rimuovi limite di prezzo"
        case "size":
            selectedSize = nil
            resetQuery = "Tutte le taglie"
        case "gender":
            resetQuery = "Tutti i generi"
        case "color":
            resetQuery = "Tutti i colori"
        case "store":
            selectedStore = nil
            resetQuery = "Tutti i negozi"
        case "brand":
            resetQuery = "Tutti i brand"
        case "free_shipping":
            classicFreeShippingOnly = false
            resetQuery = "Rimuovi filtro spedizione"
        case "on_sale", "min_discount":
            classicOnSaleOnly = false
            resetQuery = "Rimuovi filtro sconti"
        case "excluded_brand", "excluded_store", "excluded_feature":
            resetQuery = "Rimuovi esclusioni"
        case "sort_by":
            resetQuery = "Ordine consigliato"
        default:
            resetQuery = "Rimuovi tutti i filtri"
        }
        handleSearchOrComparison(query: resetQuery, isFollowUp: true)
    }

    private func applyClassicFilterRefinement(followUpPrompt: String?) {
        userForcedClassicMode = true
        if !conversationTurns.isEmpty {
            let prompt: String
            if let explicit = followUpPrompt, !explicit.isEmpty {
                prompt = explicit
            } else if let maxP = overrideMaxPrice {
                prompt = "Sotto \(Int(maxP)) euro"
            } else if let st = selectedStore {
                prompt = "Su \(st)"
            } else if classicFreeShippingOnly {
                prompt = "Con spedizione gratuita"
            } else if classicOnSaleOnly {
                prompt = "In sconto"
            } else {
                prompt = rootQuery.isEmpty ? searchText : rootQuery
            }
            executeSearch(
                isFollowUp: true,
                rawFollowUpText: prompt,
                keepClassicMode: true
            )
        } else {
            executeSearch(isFollowUp: false, keepClassicMode: true)
        }
    }

    private func executeVisualSearch(image: UIImage, description: String?, isFollowUp: Bool) {
        guard let jpegData = ShopVisualSearchSheet.compressedJPEGData(from: image) else {
            if isFollowUp {
                followUpErrorMessage = "Impossibile preparare l'immagine per l'invio."
            } else {
                errorMessage = "Impossibile preparare l'immagine per l'invio."
                hasSearched = true
                isDeepDiveMode = true
            }
            return
        }

        hideAllKeyboards()

        let trimmedDesc = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDesc = (trimmedDesc?.isEmpty == false) ? trimmedDesc : nil

        let initialStep = SearchThinkingStep(
            id: "visual_analyze",
            status: .running,
            title: "Analisi foto con IA",
            detail: cleanDesc
        )

        if !isFollowUp {
            let labelQuery = cleanDesc ?? "Ricerca dalla foto"
            rootQuery = labelQuery
            searchText = labelQuery
            conversationalHeader = "Analisi immagine in corso"
            conversationTurns = []
            currentSessionId = UUID().uuidString.lowercased()
            isLoading = true
            isFollowUpLoading = false
            pendingFollowUpQuery = nil
            pendingVisualImageURL = nil
            pendingVisualImagePreview = image
            pendingVisualDescription = cleanDesc
            followUpErrorMessage = nil
        } else {
            if currentSessionId == nil {
                currentSessionId = UUID().uuidString.lowercased()
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                lastFollowUpQuery = cleanDesc ?? "Ricerca dalla foto"
                pendingFollowUpQuery = cleanDesc
                pendingVisualImageURL = nil
                pendingVisualImagePreview = image
                pendingVisualDescription = cleanDesc
                isFollowUpLoading = true
                isLoading = false
                followUpErrorMessage = nil
                userForcedClassicMode = false
                isDeepDiveMode = true
            }
        }

        hasSearched = true
        isDeepDiveMode = true
        errorMessage = nil
        thinkingSteps = [initialStep]
        thinkingStartedAt = Date()

        activeSearchTask?.cancel()
        activeSearchTask = nil
        activeVisualSearchTask?.cancel()
        activeVisualSearchTask = Task {
            do {
                let res = try await api.analyzeVisualSearchImage(
                    imageData: jpegData,
                    mimeType: "image/jpeg",
                    description: cleanDesc
                )
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        if let idx = self.thinkingSteps.firstIndex(where: { $0.id == "visual_analyze" }) {
                            self.thinkingSteps[idx].status = .done
                            self.thinkingSteps[idx].detail = res.is_sport_product
                                ? res.recognized_model
                                : "Articolo sportivo non rilevato"
                        }
                    }
                }

                if !res.is_sport_product {
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        let turnQuery = cleanDesc ?? "Foto caricata"
                        let nonSportTurn = SearchConversationTurn(
                            id: UUID().uuidString,
                            query: turnQuery,
                            isFollowUp: isFollowUp,
                            conversationalHeader: "Articolo sportivo non rilevato",
                            conversationalSummary: res.note ?? "La foto non sembra mostrare scarpe, smartwatch o abbigliamento sportivo. Prova con un'altra immagine o aggiungi una descrizione più precisa.",
                            userFeedback: nil,
                            showAiExplanation: false,
                            isOffTopic: true,
                            isUnsafe: false,
                            userImageURL: res.uploaded_image_url
                        )
                        withAnimation(.easeOut(duration: 0.24)) {
                            if !isFollowUp {
                                self.rootQuery = turnQuery
                                self.searchText = turnQuery
                                self.conversationTurns = [nonSportTurn]
                            } else {
                                self.conversationTurns.append(nonSportTurn)
                            }
                            self.isLoading = false
                            self.isFollowUpLoading = false
                            self.pendingFollowUpQuery = nil
                            self.pendingVisualImageURL = nil
                            self.pendingVisualImagePreview = nil
                            self.pendingVisualDescription = nil
                        }
                    }
                    return
                }

                let rawBase = res.search_query.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalQuery = rawBase.isEmpty ? res.recognized_model : rawBase
                let preservedSteps = await MainActor.run { self.thinkingSteps }

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    if !isFollowUp {
                        self.rootQuery = finalQuery
                        self.searchText = finalQuery
                    }
                    // When uploading a fresh photo inside an existing chat WITHOUT a refining caption,
                    // isolate prior text context so an unrelated brand/filter never leaks onto the photographed item!
                    let shouldIgnorePrior = isFollowUp && (cleanDesc == nil)
                    self.executeSearch(
                        isFollowUp: isFollowUp,
                        rawFollowUpText: isFollowUp ? finalQuery : nil,
                        userImageURL: res.uploaded_image_url,
                        initialThinkingSteps: preservedSteps,
                        ignorePriorContext: shouldIgnorePrior
                    )
                }
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.22)) {
                        self.pendingVisualImagePreview = nil
                        self.pendingVisualDescription = nil
                        self.pendingVisualImageURL = nil
                        self.pendingFollowUpQuery = nil
                        self.isLoading = false
                        self.isFollowUpLoading = false
                        if isFollowUp {
                            self.followUpErrorMessage = error.localizedDescription
                        } else {
                            self.errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    // MARK: - Search Execution
    private func executeSearch(
        isFollowUp: Bool = false,
        rawFollowUpText: String? = nil,
        userImageURL: String? = nil,
        initialThinkingSteps: [SearchThinkingStep] = [],
        keepClassicMode: Bool = false,
        ignorePriorContext: Bool = false
    ) {
        let activeQuery = isFollowUp ? (rawFollowUpText ?? searchText) : searchText
        let query = activeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        hideAllKeyboards()

        let cleanVisualImg = userImageURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeImageURL = (cleanVisualImg?.isEmpty == false) ? cleanVisualImg : nil

        if !isFollowUp {
            rootQuery = query
            conversationalHeader = "Ho cercato \(query)"
            conversationTurns = []
            if currentSessionId == nil || initialThinkingSteps.isEmpty {
                currentSessionId = UUID().uuidString.lowercased()
            }
            if !keepClassicMode && !userForcedClassicMode {
                isDeepDiveMode = true
            }
            isLoading = true
            isFollowUpLoading = false
            pendingFollowUpQuery = nil
            pendingVisualImageURL = activeImageURL
            followUpErrorMessage = nil
        } else {
            if currentSessionId == nil {
                currentSessionId = UUID().uuidString.lowercased()
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                lastFollowUpQuery = query
                pendingFollowUpQuery = query
                pendingVisualImageURL = activeImageURL
                isFollowUpLoading = !keepClassicMode
                isLoading = keepClassicMode
                followUpErrorMessage = nil
                if !keepClassicMode {
                    userForcedClassicMode = false
                    isDeepDiveMode = true
                }
            }
        }

        hasSearched = true
        errorMessage = nil
        partialStreamResults = []
        partialStreamChips = []
        thinkingSteps = initialThinkingSteps
        if initialThinkingSteps.isEmpty {
            thinkingStartedAt = Date()
        }

        let activeContext: String?
        if isFollowUp && !ignorePriorContext {
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

        let requestedMode = (userForcedClassicMode || keepClassicMode) ? "classic" : nil
        let activeSid = ignorePriorContext ? nil : currentSessionId
        let prefSize = preferredSizeForCurrentSearch(query: query, context: activeContext)

        activeSearchTask?.cancel()
        activeSearchTask = Task {
            do {
                let smartRes = try await api.smartSearchStream(
                    query: query,
                    mode: requestedMode,
                    maxPrice: overrideMaxPrice,
                    size: selectedSize,
                    store: selectedStore,
                    contextQuery: activeContext,
                    sessionId: activeSid,
                    deviceId: SupabaseManager.shared.deviceId,
                    preferredSize: prefSize.isEmpty ? nil : prefSize,
                    userImageURL: activeImageURL,
                    onStep: { step in
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            if let idx = self.thinkingSteps.firstIndex(where: { $0.id == step.id }) {
                                self.thinkingSteps[idx] = step
                            } else {
                                self.thinkingSteps.append(step)
                            }
                        }
                    },
                    onPartialResults: { partial in
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.24)) {
                            self.partialStreamResults = partial.results
                            self.partialStreamChips = partial.chips ?? []
                            if self.userForcedClassicMode || keepClassicMode {
                                self.searchResults = partial.results
                                self.activeChips = partial.chips ?? []
                            }
                        }
                    }
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.partialStreamResults = []
                    self.partialStreamChips = []
                    if let returnedSid = smartRes.session_id, !returnedSid.isEmpty {
                        self.currentSessionId = returnedSid
                    }
                    self.errorMessage = nil
                    self.followUpErrorMessage = nil
                    self.smartIntent = smartRes.intent
                    self.activeChips = smartRes.chips ?? []
                    self.searchResults = smartRes.results
                    self.activeContextState = smartRes.context_state
                    self.hasMoreClassicResults = smartRes.has_more ?? (smartRes.results.count >= 30)
                    self.isLoadingMoreClassic = false
                    self.loadMoreErrorMessage = nil
                    self.searchedQueries = smartRes.searched_queries ?? []
                    self.curatedSections = smartRes.curated_sections ?? []
                    self.comparativeCards = smartRes.comparative_cards ?? []
                    self.featuredCards = smartRes.featured_cards ?? []
                    self.spotlight = smartRes.spotlight
                    self.followUpSuggestions = smartRes.follow_up_suggestions ?? []
                    self.conversationalHeader = smartRes.conversational_header ?? "Ho cercato prodotti"
                    self.conversationalSummary = smartRes.conversational_summary ?? (smartRes.intent?.explanation ?? "")

                    let isOff = smartRes.is_off_topic ?? (smartRes.intent?.is_off_topic ?? false)
                    let isUnsafe = smartRes.is_unsafe ?? (smartRes.intent?.is_unsafe ?? false)
                    let isAdvice = smartRes.is_conversational_advice ?? (smartRes.intent?.is_conversational_advice ?? false)

                    let newTurn = SearchConversationTurn(
                        id: smartRes.turn_id ?? UUID().uuidString,
                        query: query,
                        isFollowUp: isFollowUp,
                        isConversationalAdvice: isAdvice,
                        conversationalHeader: self.conversationalHeader,
                        conversationalSummary: self.conversationalSummary,
                        searchedQueries: smartRes.searched_queries ?? [],
                        smartIntent: smartRes.intent,
                        activeChips: smartRes.chips ?? [],
                        searchResults: smartRes.results,
                        curatedSections: smartRes.curated_sections ?? [],
                        comparativeCards: smartRes.comparative_cards ?? [],
                        featuredCards: smartRes.featured_cards ?? [],
                        spotlight: smartRes.spotlight,
                        followUpSuggestions: smartRes.follow_up_suggestions ?? [],
                        userFeedback: nil,
                        showAiExplanation: false,
                        error: nil,
                        isOffTopic: isOff,
                        isUnsafe: isUnsafe,
                        userImageURL: smartRes.user_image_url ?? activeImageURL,
                        timestamp: Date()
                    )

                    withAnimation(.easeOut(duration: 0.24)) {
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
                        self.pendingVisualImageURL = nil
                        self.pendingVisualImagePreview = nil
                        self.pendingVisualDescription = nil
                        self.isFollowUpLoading = false
                    }

                    if ProcessInfo.processInfo.arguments.contains("-testClassicMode") || self.userForcedClassicMode {
                        self.isDeepDiveMode = false
                    } else {
                        self.isDeepDiveMode = true
                    }
                    self.isSmartSearchActive = true
                    self.isLoading = false
                    Task {
                        await self.loadSavedChatSessions()
                    }
                }
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                await MainActor.run {
                    self.partialStreamResults = []
                    self.partialStreamChips = []
                }
                if !isFollowUp {
                    // 1. Direct Supabase Cloud instant fallback with full in-query filter parsing (price, size, category)
                    if let directFallback = await api.buildDirectSmartSearchFallback(
                        query: query,
                        category: nil,
                        maxPrice: overrideMaxPrice,
                        size: selectedSize,
                        store: selectedStore,
                        contextQuery: nil,
                        sessionId: activeSid
                    ), !directFallback.results.isEmpty {
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            self.errorMessage = nil
                            self.pendingVisualImagePreview = nil
                            self.pendingVisualDescription = nil
                            self.smartIntent = directFallback.intent
                            self.activeChips = directFallback.chips ?? []
                            self.searchResults = directFallback.results
                            self.curatedSections = directFallback.curated_sections ?? [
                                CuratedProductSection(
                                    id: "sec_cloud",
                                    title: "Migliori Risultati Trovati",
                                    subtitle: "Offerte verificate nel catalogo FitMatch Cloud",
                                    products: directFallback.results
                                )
                            ]
                            self.conversationalHeader = directFallback.conversational_header ?? "Ho cercato \(query)"
                            self.conversationalSummary = directFallback.conversational_summary ?? "Ecco i modelli trovati per la tua ricerca:"
                            self.followUpSuggestions = directFallback.follow_up_suggestions ?? []
                            let fallbackTurn = SearchConversationTurn(
                                id: UUID().uuidString,
                                query: query,
                                isFollowUp: false,
                                conversationalHeader: self.conversationalHeader,
                                conversationalSummary: self.conversationalSummary,
                                smartIntent: directFallback.intent,
                                activeChips: directFallback.chips ?? [],
                                searchResults: directFallback.results,
                                curatedSections: self.curatedSections,
                                comparativeCards: directFallback.comparative_cards ?? [],
                                featuredCards: directFallback.featured_cards ?? [],
                                spotlight: directFallback.spotlight,
                                followUpSuggestions: self.followUpSuggestions,
                                userFeedback: nil,
                                showAiExplanation: false,
                                error: nil,
                                timestamp: Date()
                            )
                            self.conversationTurns = [fallbackTurn]
                            self.lastContextQuery = query
                            self.isDeepDiveMode = !self.userForcedClassicMode
                            self.isSmartSearchActive = true
                            self.isLoading = false
                            self.recentManager.recordSearch(query)
                        }
                    } else if let local = try? await api.searchCatalog(query: query, limit: 30), !local.isEmpty {
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            self.errorMessage = nil
                            self.pendingVisualImagePreview = nil
                            self.pendingVisualDescription = nil
                            self.searchResults = local
                            self.conversationalHeader = "Ho cercato \(query)"
                            self.conversationalSummary = "Ecco i modelli trovati per la tua ricerca:"
                            self.isDeepDiveMode = true
                            self.isSmartSearchActive = true
                            self.isLoading = false
                            self.recentManager.recordSearch(query)
                        }
                    } else if let live = try? await api.search(query: query, size: selectedSize), !live.isEmpty {
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            self.errorMessage = nil
                            self.pendingVisualImagePreview = nil
                            self.pendingVisualDescription = nil
                            self.searchResults = live
                            self.conversationalHeader = "Ho cercato \(query)"
                            self.conversationalSummary = "Ecco i modelli trovati per la tua ricerca:"
                            self.isDeepDiveMode = true
                            self.isSmartSearchActive = true
                            self.isLoading = false
                            self.recentManager.recordSearch(query)
                        }
                    } else {
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            self.pendingVisualImagePreview = nil
                            self.pendingVisualDescription = nil
                            self.errorMessage = "Impossibile recuperare i risultati in questo momento. Il server potrebbe essere occupato, tocca Riprova per aggiornare."
                            self.isLoading = false
                        }
                    }
                } else {
                    guard !Task.isCancelled else { return }
                    // Follow-up failed or timed out: attempt direct Supabase fallback before failing!
                    if let directFallback = await api.buildDirectSmartSearchFallback(
                        query: query,
                        category: smartIntent?.category,
                        maxPrice: overrideMaxPrice,
                        size: selectedSize,
                        store: selectedStore,
                        contextQuery: activeContext,
                        sessionId: activeSid
                    ) {
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            withAnimation(.easeOut(duration: 0.24)) {
                                self.isFollowUpLoading = false
                                self.pendingFollowUpQuery = nil
                                self.pendingVisualImageURL = nil
                                self.pendingVisualImagePreview = nil
                                self.pendingVisualDescription = nil
                                self.followUpErrorMessage = nil
                                let newTurn = SearchConversationTurn(
                                    id: UUID().uuidString,
                                    query: query,
                                    isFollowUp: true,
                                    conversationalHeader: directFallback.conversational_header ?? "Ho cercato \(query)",
                                    conversationalSummary: directFallback.conversational_summary ?? "Risultati verificati sul catalogo FitMatch Cloud.",
                                    smartIntent: directFallback.intent,
                                    activeChips: directFallback.chips ?? [],
                                    searchResults: directFallback.results,
                                    curatedSections: directFallback.curated_sections ?? [],
                                    comparativeCards: directFallback.comparative_cards ?? [],
                                    spotlight: directFallback.spotlight,
                                    followUpSuggestions: directFallback.follow_up_suggestions ?? [],
                                    userFeedback: nil,
                                    showAiExplanation: false,
                                    error: nil,
                                    isOffTopic: false,
                                    isUnsafe: false,
                                    userImageURL: activeImageURL,
                                    timestamp: Date()
                                )
                                self.conversationTurns.append(newTurn)
                                self.lastContextQuery = query
                            }
                        }
                    } else {
                        guard !Task.isCancelled else { return }
                        // Follow-up failed: preserve all existing turns and show retry notification
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            withAnimation(.easeOut(duration: 0.22)) {
                                self.isFollowUpLoading = false
                                self.pendingFollowUpQuery = nil
                                self.pendingVisualImageURL = nil
                                self.pendingVisualImagePreview = nil
                                self.pendingVisualDescription = nil
                                self.followUpErrorMessage = "Impossibile completare il follow-up in questo momento."
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Active Filter Chip View
struct ShopSearchChipView: View {
    let chip: SmartSearchChip
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 5) {
            Text(chip.label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.shopDark)
            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(Color(red: 110/255, green: 110/255, blue: 122/255))
                        .frame(width: 16, height: 16)
                        .background(Color.black.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, onRemove != nil ? 7 : 10)
        .padding(.vertical, 6)
        .background(Color(red: 243/255, green: 243/255, blue: 245/255))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Classic Search Filters Sheet
struct ShopClassicFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var maxPrice: Double?
    @Binding var selectedStore: String?
    @Binding var freeShippingOnly: Bool
    @Binding var onSaleOnly: Bool
    @Binding var sortMode: SearchView.SortMode
    let availableStores: [String]
    let onApplyServerRefresh: (String?) -> Void
    let onResetAll: () -> Void

    @State private var draftMaxPrice: Double? = nil
    @State private var draftStore: String? = nil
    @State private var draftFreeShipping: Bool = false
    @State private var draftOnSale: Bool = false
    @State private var draftSort: SearchView.SortMode = .relevance

    private let pricePresets: [Double] = [50, 100, 150, 200, 300]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // 1. Budget Massimo
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Budget massimo")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.shopDark)
                            Spacer()
                            Text(draftMaxPrice == nil ? "Qualsiasi" : "Fino a €\(Int(draftMaxPrice!))")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(.shopPurple)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button(action: { draftMaxPrice = nil }) {
                                    Text("Qualsiasi")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(draftMaxPrice == nil ? .white : .shopDark)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 8)
                                        .background(draftMaxPrice == nil ? Color.shopDark : Color(red: 243/255, green: 243/255, blue: 245/255))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                ForEach(pricePresets, id: \.self) { p in
                                    let sel = draftMaxPrice == p
                                    Button(action: { draftMaxPrice = sel ? nil : p }) {
                                        Text("≤ €\(Int(p))")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(sel ? .white : .shopDark)
                                            .padding(.horizontal, 13)
                                            .padding(.vertical, 8)
                                            .background(sel ? Color.shopPurple : Color(red: 243/255, green: 243/255, blue: 245/255))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // 2. Spedizione & Sconti
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Offerte e spedizione")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.shopDark)

                        Toggle("Solo spedizione gratuita", isOn: $draftFreeShipping)
                            .tint(.shopPurple)
                            .font(.system(size: 14.5, weight: .medium))

                        Toggle("Solo articoli in sconto", isOn: $draftOnSale)
                            .tint(.shopPurple)
                            .font(.system(size: 14.5, weight: .medium))
                    }

                    // 3. Negozio
                    if !availableStores.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Negozio")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.shopDark)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    Button(action: { draftStore = nil }) {
                                        Text("Tutti")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(draftStore == nil ? .white : .shopDark)
                                            .padding(.horizontal, 13)
                                            .padding(.vertical, 8)
                                            .background(draftStore == nil ? Color.shopDark : Color(red: 243/255, green: 243/255, blue: 245/255))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)

                                    ForEach(availableStores, id: \.self) { st in
                                        let sel = draftStore?.lowercased() == st.lowercased()
                                        Button(action: { draftStore = sel ? nil : st }) {
                                            Text(st)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(sel ? .white : .shopDark)
                                                .padding(.horizontal, 13)
                                                .padding(.vertical, 8)
                                                .background(sel ? Color.shopPurple : Color(red: 243/255, green: 243/255, blue: 245/255))
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // 4. Ordinamento
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ordina per")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.shopDark)

                        ForEach(SearchView.SortMode.allCases) { m in
                            Button(action: { draftSort = m }) {
                                HStack {
                                    Text(m.rawValue)
                                        .font(.system(size: 14.5, weight: draftSort == m ? .semibold : .regular))
                                        .foregroundColor(.shopDark)
                                    Spacer()
                                    if draftSort == m {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.shopPurple)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Filtri ricerca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Azzera") {
                        onResetAll()
                        dismiss()
                    }
                    .foregroundColor(.shopPurple)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Applica") {
                        var deltaClauses: [String] = []
                        if draftMaxPrice != maxPrice {
                            if let p = draftMaxPrice {
                                deltaClauses.append("Sotto \(Int(p)) euro")
                            } else {
                                deltaClauses.append("Rimuovi limite di prezzo")
                            }
                        }
                        if draftStore != selectedStore {
                            if let st = draftStore {
                                deltaClauses.append("Su \(st)")
                            } else {
                                deltaClauses.append("Tutti i negozi")
                            }
                        }
                        if draftFreeShipping != freeShippingOnly {
                            deltaClauses.append(draftFreeShipping ? "Con spedizione gratuita" : "Rimuovi filtro spedizione")
                        }
                        if draftOnSale != onSaleOnly {
                            deltaClauses.append(draftOnSale ? "In sconto" : "Rimuovi filtro sconti")
                        }
                        if draftSort != sortMode {
                            switch draftSort {
                            case .lowestPrice, .bestTotalPrice:
                                deltaClauses.append("Prezzo più basso")
                            case .maxDiscount:
                                deltaClauses.append("Sconti più alti")
                            case .relevance:
                                deltaClauses.append("Ordine consigliato")
                            case .maxSavings:
                                break
                            }
                        }
                        maxPrice = draftMaxPrice
                        selectedStore = draftStore
                        freeShippingOnly = draftFreeShipping
                        onSaleOnly = draftOnSale
                        sortMode = draftSort
                        dismiss()
                        if !deltaClauses.isEmpty {
                            onApplyServerRefresh(deltaClauses.joined(separator: ", "))
                        }
                    }
                    .fontWeight(.bold)
                    .foregroundColor(.shopDark)
                }
            }
            .onAppear {
                draftMaxPrice = maxPrice
                draftStore = selectedStore
                draftFreeShipping = freeShippingOnly
                draftOnSale = onSaleOnly
                draftSort = sortMode
            }
        }
    }
}

// MARK: - Horizontal Themed Carousel Card (Shop Screenshots 1, 3 & 4)
struct ShopThemedCarouselCard: View {
    let product: MatchedProduct
    let onTap: () -> Void

    var bestOffer: Offer? {
        product.offers.min(by: { $0.price < $1.price })
    }

    var maxOffer: Offer? {
        product.offers.max(by: { $0.price < $1.price })
    }

    var storeMeta: ActiveStoreItem? {
        guard let best = bestOffer else { return nil }
        return DynamicCatalogRegistry.shared.storeItem(for: best.store_id)
            ?? DynamicCatalogRegistry.shared.storeItem(for: best.store_name)
    }

    var referenceOriginalPrice: Double? {
        if let best = bestOffer, let orig = best.original_price, orig > best.price + 1 {
            return orig
        }
        if let max = maxOffer, let best = bestOffer, max.price > best.price + 2 {
            return max.price
        }
        return nil
    }

    var discountBadge: String? {
        if let best = bestOffer {
            if let disc = best.discount_pct, disc >= 5 {
                return "\(Int(round(disc)))% di sconto"
            }
            if let orig = best.original_price, orig > best.price + 1 {
                let pct = Int(round((orig - best.price) / orig * 100))
                if pct >= 5 {
                    return "\(pct)% di sconto"
                }
            }
        }
        if let sav = product.cross_store_savings, sav >= 10 {
            return "Risparmia \(Int(round(sav))) €"
        }
        return nil
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 246/255, green: 246/255, blue: 248/255))
                        .frame(width: 156, height: 156)

                    if let imgUrl = product.image_url, let url = URL(string: imgUrl) {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 420) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 156, height: 156)
                                    .blendMode(.multiply)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: 18, width: 156, height: 156)
                            default:
                                Image(systemName: "photo")
                                    .foregroundColor(.gray.opacity(0.35))
                                    .frame(width: 156, height: 156)
                            }
                        }
                    }

                    if let badge = discountBadge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(red: 217/255, green: 45/255, blue: 32/255))
                            .clipShape(Capsule())
                            .padding(9)
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ShopTranslucentHeartButton(product: product)
                                .padding(8)
                        }
                    }
                    .frame(width: 156, height: 156)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                )
                .padding(.bottom, 2)

                if let best = bestOffer {
                    HStack(spacing: 4) {
                        Text(best.store_name)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color(red: 98/255, green: 98/255, blue: 110/255))
                            .lineLimit(1)
                        if product.offers.count > 1 {
                            Text("· +\(product.offers.count - 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.shopPurple)
                        }
                    }
                }

                Text(product.displayTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)

                if let meta = storeMeta, let rating = meta.rating, rating >= 3.5 {
                    let fullStars = min(5, max(1, Int(round(rating))))
                    HStack(spacing: 2) {
                        ForEach(0..<fullStars, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 8.5))
                                .foregroundColor(.shopDark)
                        }
                        if let revLabel = meta.formatted_review_count, !revLabel.isEmpty {
                            Text("(\(revLabel))")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Color(red: 115/255, green: 115/255, blue: 125/255))
                                .padding(.leading, 2)
                        }
                    }
                }

                HStack(spacing: 5) {
                    if let best = bestOffer {
                        Text(String(format: "€ %.2f", best.price))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.shopDark)

                        if let orig = referenceOriginalPrice {
                            Text(String(format: "€ %.2f", orig))
                                .font(.system(size: 12))
                                .strikethrough()
                                .foregroundColor(Color(red: 145/255, green: 145/255, blue: 155/255))
                        }
                    }
                }
            }
            .frame(width: 156)
        }
        .buttonStyle(ShopCardPressStyle(scale: 0.98))
    }
}

// MARK: - Comparative Spec Card ("Come orientarsi" - Screenshot 3)
struct ShopComparativeCard: View {
    let card: ComparativeSpecCard
    let onTap: () -> Void

    var bestOffer: Offer? {
        card.product.offers.min(by: { $0.price < $1.price })
    }

    var maxOffer: Offer? {
        card.product.offers.max(by: { $0.price < $1.price })
    }

    var referenceOriginalPrice: Double? {
        if let best = bestOffer, let orig = best.original_price, orig > best.price + 1 {
            return orig
        }
        if let max = maxOffer, let best = bestOffer, max.price > best.price + 2 {
            return max.price
        }
        return nil
    }

    var discountBadge: String? {
        if let best = bestOffer {
            if let disc = best.discount_pct, disc >= 5 {
                return "\(disc)% di sconto"
            }
            if let orig = best.original_price, orig > best.price + 1 {
                let pct = Int(round((orig - best.price) / orig * 100))
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
                            Text(String(format: "€ %.2f", best.price))
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

// MARK: - Stacked Horizontal Featured Product Card (Shop Screenshot 2)
struct ShopFeaturedProductCard: View {
    let spotlight: SpotlightRecommendation
    let onTap: () -> Void

    @State private var currentImageIndex: Int = 0

    var bestOffer: Offer? {
        spotlight.product.offers.min(by: { $0.price < $1.price })
    }

    var maxOffer: Offer? {
        spotlight.product.offers.max(by: { $0.price < $1.price })
    }

    var storeMeta: ActiveStoreItem? {
        guard let best = bestOffer else { return nil }
        return DynamicCatalogRegistry.shared.storeItem(for: best.store_id)
            ?? DynamicCatalogRegistry.shared.storeItem(for: best.store_name)
    }

    var galleryImages: [String] {
        Array(spotlight.product.allImages.prefix(5))
    }

    var referenceOriginalPrice: Double? {
        if let best = bestOffer, let orig = best.original_price, orig > best.price + 1 {
            return orig
        }
        if let max = maxOffer, let best = bestOffer, max.price > best.price + 2 {
            return max.price
        }
        return nil
    }

    var discountBadge: String? {
        if let badge = spotlight.badge_text, !badge.isEmpty, badge.lowercased().contains("sconto") || badge.lowercased().contains("risparmia") {
            return badge
        }
        if let best = bestOffer {
            if let disc = best.discount_pct, disc >= 5 {
                return "\(Int(round(disc)))% di sconto"
            }
            if let orig = best.original_price, orig > best.price + 1 {
                let pct = Int(round((orig - best.price) / orig * 100))
                if pct >= 5 {
                    return "\(pct)% di sconto"
                }
            }
        }
        if let sav = spotlight.product.cross_store_savings, sav >= 10 {
            return "Risparmia \(Int(round(sav))) €"
        }
        return nil
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                // Left Image Box with optional swipe dots, red discount capsule, and translucent heart
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 246/255, green: 246/255, blue: 248/255))
                        .frame(width: 146, height: 154)

                    if galleryImages.count > 1 {
                        TabView(selection: $currentImageIndex) {
                            ForEach(Array(galleryImages.enumerated()), id: \.offset) { idx, imgStr in
                                if let url = URL(string: imgStr) {
                                    ShopCachedAsyncImage(url: url, maxPixelSize: 420) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .blendMode(.multiply)
                                        case .empty:
                                            ShopSkeletonBlock(cornerRadius: 18)
                                        default:
                                            Image(systemName: "photo")
                                                .foregroundColor(.gray.opacity(0.35))
                                        }
                                    }
                                    .tag(idx)
                                }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(width: 146, height: 154)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else if let imgUrl = spotlight.product.image_url, let url = URL(string: imgUrl) {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 420) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 146, height: 154)
                                    .blendMode(.multiply)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: 18, width: 146, height: 154)
                            default:
                                Image(systemName: "photo")
                                    .foregroundColor(.gray.opacity(0.35))
                                    .frame(width: 146, height: 154)
                            }
                        }
                    }

                    if let badge = discountBadge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(red: 217/255, green: 45/255, blue: 32/255))
                            .clipShape(Capsule())
                            .padding(8)
                    }

                    // Bottom Overlay: centered pagination dots + bottom-right heart
                    VStack {
                        Spacer()
                        ZStack {
                            if galleryImages.count > 1 {
                                HStack(spacing: 4) {
                                    ForEach(0..<galleryImages.count, id: \.self) { idx in
                                        Circle()
                                            .fill(idx == currentImageIndex ? Color.shopDark.opacity(0.75) : Color.black.opacity(0.22))
                                            .frame(width: idx == currentImageIndex ? 5.5 : 4.5, height: idx == currentImageIndex ? 5.5 : 4.5)
                                    }
                                }
                            }
                            HStack {
                                Spacer()
                                ShopTranslucentHeartButton(product: spotlight.product)
                            }
                        }
                        .padding(8)
                    }
                    .frame(width: 146, height: 154)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                )

                // Right Column: Store Avatar + Rating, Product Title, Price, and 3 AI Technical Bullets
                VStack(alignment: .leading, spacing: 7) {
                    if let best = bestOffer {
                        HStack(spacing: 8) {
                            ShopStoreLogo(
                                storeName: best.store_name,
                                showVerified: false,
                                showLabel: false,
                                size: 28,
                                logoURL: storeMeta?.logo_url
                            )

                            VStack(alignment: .leading, spacing: 1) {
                                Text(best.store_name)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                    .lineLimit(1)

                                if let meta = storeMeta, let rating = meta.rating {
                                    HStack(spacing: 3) {
                                        Text(String(format: "%.1f", rating))
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundColor(.shopDark)
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 9))
                                            .foregroundColor(.shopDark)
                                        if let rev = meta.formatted_review_count, !rev.isEmpty {
                                            Text("(\(rev))")
                                                .font(.system(size: 11.5))
                                                .foregroundColor(Color(red: 125/255, green: 125/255, blue: 136/255))
                                        }
                                    }
                                } else if spotlight.product.offers.count > 1 {
                                    Text("\(spotlight.product.offers.count) negozi a confronto")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.shopPurple)
                                }
                            }
                        }
                    }

                    Text(spotlight.product.displayTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.shopDark)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let best = bestOffer {
                        HStack(spacing: 6) {
                            Text(String(format: "€ %.2f", best.price))
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundColor(.shopDark)

                            if let orig = referenceOriginalPrice {
                                Text(String(format: "€ %.2f", orig))
                                    .font(.system(size: 12.5))
                                    .strikethrough()
                                    .foregroundColor(Color(red: 145/255, green: 145/255, blue: 155/255))
                            }
                        }
                    }

                    if !spotlight.highlights.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(spotlight.highlights.prefix(3), id: \.self) { hl in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .font(.system(size: 12.5, weight: .bold))
                                        .foregroundColor(Color(red: 95/255, green: 95/255, blue: 108/255))
                                    Text(LocalizedStringKey(hl))
                                        .font(.system(size: 12.5, weight: .regular))
                                        .foregroundColor(Color(red: 95/255, green: 95/255, blue: 108/255))
                                        .lineSpacing(1.5)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.07), radius: 14, x: 0, y: 4)
        }
        .buttonStyle(ShopCardPressStyle(scale: 0.985))
    }
}

// MARK: - Spotlight Card View (Legacy Alias)
struct ShopSpotlightCardView: View {
    let spotlight: SpotlightRecommendation
    let onTap: () -> Void

    var body: some View {
        ShopFeaturedProductCard(spotlight: spotlight, onTap: onTap)
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
                        Text(
                            options.isEmpty
                            ? "Scrivi una risposta per affinare «\(baseQuery)»:"
                            : "Scegli o scrivi una risposta per affinare «\(baseQuery)»:"
                        )
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                    }
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 12)

                // Quick Answer Options (only shown when relevant to the question)
                if !options.isEmpty {
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
                        .padding(.horizontal, ShopLayout.screenPadding)
                        .padding(.vertical, 2)
                    }
                } else {
                    Spacer(minLength: 0)
                }

                // Bottom Custom Answer Field
                VStack(spacing: 8) {
                    Divider()

                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil.line")
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 150/255, green: 150/255, blue: 160/255))

                            TextField(
                                options.isEmpty ? "Digita qui la tua risposta..." : "Oppure digita qui la tua risposta...",
                                text: $customAnswerText
                            )
                            .font(.system(size: 14))
                            .focused($isCustomFieldFocused)
                            .submitLabel(.send)
                            .onSubmit {
                                submitCustom()
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.shopSurface)
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
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.bottom, 10)
                }
            }
            .onAppear {
                if options.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        isCustomFieldFocused = true
                    }
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

// MARK: - Follow-Up Suggestion Lavender Capsule Pill (Shop Screenshots 2 & 4)
struct ShopFollowUpPillButton: View {
    let title: String
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            Text(title)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundColor(Color(red: 78/255, green: 46/255, blue: 207/255))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color(red: 239/255, green: 236/255, blue: 254/255))
                .clipShape(Capsule())
        }
        .buttonStyle(ShopCardPressStyle(scale: 0.97))
    }
}

// MARK: - Official Shop Product Card (Screenshot 4)
struct ShopOfficialProductCard: View {
    let product: MatchedProduct

    var sortedOffers: [Offer] {
        product.offers.sorted { $0.price < $1.price }
    }

    var bestOffer: Offer? { sortedOffers.first }
    var maxOffer: Offer? { sortedOffers.last }

    private var storeMeta: ActiveStoreItem? {
        guard let best = bestOffer else { return nil }
        return DynamicCatalogRegistry.shared.storeItem(for: best.store_id)
            ?? DynamicCatalogRegistry.shared.storeItem(for: best.store_name)
    }

    var savingsAmount: Double {
        guard let best = bestOffer, let max = maxOffer, max.price > best.price else {
            return product.cross_store_savings ?? 0.0
        }
        return max.price - best.price
    }

    private var hasFreeShipping: Bool {
        guard let ship = bestOffer?.shipping_cost else { return false }
        return ship <= 0.01
    }

    var body: some View {
        NavigationLink(destination: ProductDetailView(product: product, openedFromSearch: true)) {
            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 243/255, green: 243/255, blue: 245/255))

                    if let imgUrl = product.image_url, let url = URL(string: imgUrl) {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 350) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding(6)
                                    .frame(width: 124, height: 124)
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: 18, width: 124, height: 124)
                            default:
                                Image(systemName: "photo")
                                    .foregroundColor(.gray.opacity(0.35))
                                    .frame(width: 124, height: 124)
                            }
                        }
                        .frame(width: 124, height: 124)
                    } else {
                        Image(systemName: "photo")
                            .foregroundColor(.gray.opacity(0.35))
                            .frame(width: 124, height: 124)
                    }

                    if savingsAmount > 1.0 {
                        Text("-\(String(format: "%.0f", savingsAmount)) €")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color(red: 0/255, green: 170/255, blue: 100/255))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                .frame(width: 124, height: 124)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayTitle)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(.shopDark)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 5) {
                        if let meta = storeMeta, let rating = meta.rating, rating >= 3.5 {
                            HStack(spacing: 2.5) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.shopDark)
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.shopDark)
                            }
                            Text("·")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(red: 165/255, green: 165/255, blue: 175/255))
                        }

                        Text(
                            product.offers.count > 1
                            ? "\(product.offers.count) negozi a confronto"
                            : "1 offerta verificata"
                        )
                        .font(.system(size: 11, weight: product.offers.count > 1 ? .semibold : .medium))
                        .foregroundColor(product.offers.count > 1 ? .shopPurple : Color(red: 120/255, green: 120/255, blue: 130/255))
                        .lineLimit(1)
                    }
                    .padding(.top, 1)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let best = bestOffer {
                            Text(String(format: "%.2f €", best.price).replacingOccurrences(of: ".", with: ","))
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundColor(.shopDark)
                                .lineLimit(1)

                            if let max = maxOffer, max.price > best.price + 0.5 {
                                Text(String(format: "%.2f €", max.price).replacingOccurrences(of: ".", with: ","))
                                    .font(.system(size: 12))
                                    .strikethrough()
                                    .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 2)

                    Spacer(minLength: 4)

                    let targetSize = product.isComparable ? UserPreferencesManager.shared.preferences.preferredShoeSize : UserPreferencesManager.shared.preferences.preferredApparelSize
                    let hasPref = !targetSize.isEmpty && product.allAvailableSizes.contains(where: {
                        $0.replacingOccurrences(of: ",", with: ".") == targetSize.replacingOccurrences(of: ",", with: ".")
                    })

                    if hasPref || hasFreeShipping {
                        HStack(spacing: 6) {
                            if hasPref {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(.shopPurple)
                                    Text("Tg. \(targetSize)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.shopPurple)
                                }
                                .lineLimit(1)
                            }
                            if hasFreeShipping {
                                Text("Sped. gratis")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(Color(red: 0/255, green: 140/255, blue: 82/255))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 0/255, green: 170/255, blue: 100/255).opacity(0.12))
                                    .clipShape(Capsule())
                                    .lineLimit(1)
                            }
                        }
                    }

                    if let best = bestOffer {
                        HStack(spacing: 6) {
                            ShopStoreLogo(storeName: best.store_name, showVerified: false, showLabel: false, size: 18)

                            Text(best.store_name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.shopDark)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.top, 1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
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
                                .transition(.opacity)
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
                        } else if let img = product.image_url, let url = URL(string: img), !img.isEmpty {
                            ShopCachedAsyncImage(url: url, maxPixelSize: 320) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 104, height: 94)
                                        .transition(.opacity)
                                case .empty:
                                    ShopSkeletonBlock(cornerRadius: 12, width: 88, height: 80)
                                default:
                                    Image(systemName: "photo")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray.opacity(0.35))
                                        .frame(width: 104, height: 94)
                                }
                            }
                        } else {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.gray.opacity(0.35))
                                .frame(width: 104, height: 94)
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .frame(width: 136, height: 140)

                // Top-Left Price Badge Pill (Screenshots: "80,00 €" / "160,00 € 230,00 €")
                let bestPrice = product.best_price ?? product.bestOffer?.price
                let origPrice = product.highest_price ?? product.bestOffer?.original_price
                if let best = bestPrice {
                    HStack(spacing: 4) {
                        Text(formatEuro(best))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)

                        if let orig = origPrice, orig > best {
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
        .buttonStyle(ShopCardPressStyle())
    }

    private func formatEuro(_ price: Double) -> String {
        return String(format: "%.2f €", price).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Visual Search Modal (Camera + Gallery + Vision AI)
struct ShopVisualSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelectModel: (String, String?) -> Void
    var onStartVisualSearch: ((UIImage, String?) -> Void)? = nil

    @ObservedObject private var prefsManager = UserPreferencesManager.shared
    @State private var selectedImage: UIImage? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showCameraPicker: Bool = false
    @State private var showCameraPermissionAlert: Bool = false
    @State private var cameraAlertMessage: String = ""
    @State private var userDescription: String = ""
    @State private var selectedQuickHints: [String] = []
    @FocusState private var isDescriptionFocused: Bool
    @State private var sheetDetent: PresentationDetent = .medium

    @State private var isAnalyzing: Bool = false
    @State private var analysisResult: VisualSearchResponse? = nil
    @State private var analysisError: String? = nil

    private struct VisualQuickHint: Identifiable {
        let id: String
        let label: String
    }

    private var availableQuickHints: [VisualQuickHint] {
        var hints: [VisualQuickHint] = []
        let prefSize = prefsManager.preferences.preferredShoeSize.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prefSize.isEmpty {
            hints.append(VisualQuickHint(id: "size", label: "Taglia EU \(prefSize)"))
        }
        hints.append(contentsOf: [
            VisualQuickHint(id: "men", label: "Uomo"),
            VisualQuickHint(id: "women", label: "Donna"),
            VisualQuickHint(id: "budget", label: "Sotto 150€"),
            VisualQuickHint(id: "alt", label: "Alternative economiche")
        ])
        return hints
    }

    private var combinedUserDescription: String? {
        let typed = userDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !typed.isEmpty {
            parts.append(typed)
        }
        for hint in selectedQuickHints where !typed.lowercased().contains(hint.lowercased()) {
            parts.append(hint)
        }
        let joined = parts.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: ShopLayout.cardSpacing) {
                    visualStageCard
                        .padding(.horizontal, ShopLayout.screenPadding)

                    if selectedImage == nil {
                        sourceControlsSection
                            .padding(.horizontal, ShopLayout.screenPadding)
                    } else if let image = selectedImage, analysisResult == nil && !isAnalyzing {
                        descriptionComposerSection(for: image)
                            .padding(.horizontal, ShopLayout.screenPadding)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if let error = analysisError, !isAnalyzing {
                        visualErrorCard(error)
                            .padding(.horizontal, ShopLayout.screenPadding)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else if let result = analysisResult, !isAnalyzing {
                        visualResultSection(result)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Ricerca visiva")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(red: 190/255, green: 190/255, blue: 200/255))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let image = selectedImage, analysisResult == nil && !isAnalyzing {
                    stickySearchActionDock(for: image)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .fullScreenCover(isPresented: $showCameraPicker) {
                CameraImagePicker { capturedImage in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        selectedImage = capturedImage
                        analysisResult = nil
                        analysisError = nil
                        sheetDetent = .large
                    }
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhotoItem) { newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let uiImg = UIImage(data: data) {
                        await MainActor.run {
                            selectedPhotoItem = nil
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                selectedImage = uiImg
                                analysisResult = nil
                                analysisError = nil
                                sheetDetent = .large
                            }
                        }
                    } else {
                        await MainActor.run {
                            selectedPhotoItem = nil
                            analysisError = "Impossibile caricare l'immagine dalla galleria."
                        }
                    }
                }
            }
            .alert("Fotocamera non disponibile", isPresented: $showCameraPermissionAlert) {
                Button("Impostazioni") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(cameraAlertMessage)
            }
        }
        .presentationDetents([.medium, .large], selection: $sheetDetent)
    }

    @ViewBuilder
    private func stickySearchActionDock(for image: UIImage) -> some View {
        VStack(spacing: 0) {
            Divider()

            Button(action: {
                triggerVisualSearch(with: image)
            }) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                    Text(combinedUserDescription == nil ? "Cerca prodotto" : "Cerca con nota")
                        .font(.system(size: 15.5, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.shopPurple)
                .clipShape(Capsule())
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.98))
            .padding(.horizontal, ShopLayout.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func descriptionComposerSection(for image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 14))
                    .foregroundColor(.shopTextMuted)
                    .padding(.top, 2)

                TextField(
                    "Aggiungi una nota facoltativa (taglia, budget…)",
                    text: $userDescription,
                    axis: .vertical
                )
                .font(.system(size: 14.5))
                .foregroundColor(.shopDark)
                .lineLimit(1...3)
                .focused($isDescriptionFocused)
                .submitLabel(.search)
                .onSubmit {
                    triggerVisualSearch(with: image)
                }

                if !userDescription.isEmpty {
                    Button(action: { userDescription = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 170/255, green: 170/255, blue: 180/255))
                    }
                    .padding(.top, 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.shopSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isDescriptionFocused ? Color.shopPurple.opacity(0.45) : Color.shopBorder, lineWidth: 1)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableQuickHints) { hint in
                        let isSelected = selectedQuickHints.contains(hint.label)
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                if let idx = selectedQuickHints.firstIndex(of: hint.label) {
                                    selectedQuickHints.remove(at: idx)
                                } else {
                                    selectedQuickHints.append(hint.label)
                                }
                            }
                        }) {
                            Text(hint.label)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(isSelected ? .white : .shopDark)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isSelected ? Color.shopDark : Color.shopSurface)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? Color.clear : Color.shopBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func triggerVisualSearch(with image: UIImage) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isDescriptionFocused = false
        let desc = combinedUserDescription
        if let onStart = onStartVisualSearch {
            dismiss()
            onStart(image, desc)
        } else {
            analyzePickedImage(image, description: desc)
        }
    }

    @ViewBuilder
    private var visualStageCard: some View {
        if let image = selectedImage {
            ZStack {
                RoundedRectangle(cornerRadius: ShopLayout.cardRadius, style: .continuous)
                    .fill(Color.shopSurface)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 204)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(12)

                if isAnalyzing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                        Text("Analisi in corso…")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.shopDark.opacity(0.82))
                    .clipShape(Capsule())
                } else {
                    VStack {
                        HStack {
                            PhotosPicker(
                                selection: $selectedPhotoItem,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                HStack(spacing: 5) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Cambia")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.shopDark)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.95))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.shopBorder, lineWidth: 1)
                                )
                            }

                            Spacer()

                            Button(action: resetSelectedPhoto) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.black.opacity(0.45))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(ShopCardPressStyle(scale: 0.92))
                        }
                        .padding(12)
                        Spacer()
                    }
                }
            }
            .frame(height: 228)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: ShopLayout.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ShopLayout.cardRadius, style: .continuous)
                    .stroke(Color.shopBorder, lineWidth: 1)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.shopPurpleLight)
                        .frame(width: 56, height: 56)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.shopPurple)
                }

                VStack(spacing: 4) {
                    Text("Cerca da una foto")
                        .font(.system(size: 16.5, weight: .bold))
                        .foregroundColor(.shopDark)
                    Text("Scatta una foto o carica uno screenshot di scarpe, orologi o capi sportivi.")
                        .font(.system(size: 13))
                        .foregroundColor(.shopTextMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .background(Color.shopSurface)
            .clipShape(RoundedRectangle(cornerRadius: ShopLayout.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ShopLayout.cardRadius, style: .continuous)
                    .stroke(Color.shopBorder, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var sourceControlsSection: some View {
        HStack(spacing: 10) {
            Button(action: handleCameraButtonTap) {
                HStack(spacing: 7) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Fotocamera")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.shopDark)
                .clipShape(Capsule())
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.97))
            .disabled(isAnalyzing)

            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack(spacing: 7) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Galleria")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.shopDark)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.shopSurface)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.shopBorder, lineWidth: 1)
                )
            }
            .disabled(isAnalyzing)
        }
    }

    @ViewBuilder
    private func visualErrorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.shopRed)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Analisi non riuscita")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(.shopDark)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.shopTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let image = selectedImage {
                Button(action: {
                    analyzePickedImage(image, description: combinedUserDescription)
                }) {
                    Text("Riprova")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.shopPurple)
                        .clipShape(Capsule())
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.98))
            }
        }
        .shopCard(shadowOpacity: 0)
    }

    @ViewBuilder
    private func visualResultSection(_ result: VisualSearchResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !result.is_sport_product {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.shopPurple)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Articolo sportivo non rilevato")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.shopDark)
                        Text(result.note ?? "Prova a fotografare meglio scarpe, smartwatch, abbigliamento o attrezzatura sportiva.")
                            .font(.system(size: 13))
                            .foregroundColor(.shopTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .shopCard(shadowOpacity: 0)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if let brand = result.brand, !brand.isEmpty {
                        Text(brand.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(.shopTextMuted)
                    }

                    Text(result.recognized_model)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.shopDark)

                    if let note = result.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 13.5))
                            .foregroundColor(.shopTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: {
                        let query = result.search_query.isEmpty ? result.recognized_model : result.search_query
                        let imgUrl = result.uploaded_image_url
                        dismiss()
                        onSelectModel(query, imgUrl)
                    }) {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .bold))
                            Text("Cerca e confronta prezzi")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.shopPurple)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.98))
                    .padding(.top, 4)
                }
                .shopCard(shadowOpacity: 0)

                if !result.alternatives.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Varianti simili")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.shopTextMuted)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(result.alternatives, id: \.self) { alt in
                                    Button(action: {
                                        let imgUrl = result.uploaded_image_url
                                        dismiss()
                                        onSelectModel(alt, imgUrl)
                                    }) {
                                        Text(alt)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundColor(.shopDark)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color.shopSurface)
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .stroke(Color.shopBorder, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(ShopCardPressStyle(scale: 0.96))
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, ShopLayout.screenPadding)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func resetSelectedPhoto() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            selectedImage = nil
            userDescription = ""
            selectedQuickHints = []
            analysisResult = nil
            analysisError = nil
            isAnalyzing = false
            sheetDetent = .medium
        }
    }

    private func handleCameraButtonTap() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraAlertMessage = "La fotocamera non è disponibile su questo dispositivo. Usa la Galleria per scegliere una foto."
            showCameraPermissionAlert = true
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            showCameraPicker = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCameraPicker = true
                    } else {
                        cameraAlertMessage = "Consenti l'accesso alla fotocamera nelle Impostazioni per scattare foto ai prodotti."
                        showCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            cameraAlertMessage = "L'accesso alla fotocamera è disattivato. Abilitalo nelle Impostazioni per scattare foto."
            showCameraPermissionAlert = true
        @unknown default:
            showCameraPicker = true
        }
    }

    private func analyzePickedImage(_ image: UIImage, description: String? = nil) {
        guard let jpegData = Self.compressedJPEGData(from: image) else {
            analysisError = "Impossibile preparare l'immagine per l'invio."
            return
        }

        isAnalyzing = true
        analysisResult = nil
        analysisError = nil

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                let res = try await APIService.shared.analyzeVisualSearchImage(
                    imageData: jpegData,
                    mimeType: "image/jpeg",
                    description: description
                )
                await MainActor.run {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
                        self.isAnalyzing = false
                        self.analysisResult = res
                    }
                    if res.is_sport_product {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.isAnalyzing = false
                        self.analysisError = error.localizedDescription
                    }
                }
            }
        }
    }

    static func compressedJPEGData(from image: UIImage, maxDimension: CGFloat = 1024, quality: CGFloat = 0.76) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image.jpegData(compressionQuality: quality) }
        let scale = min(1.0, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImageCaptured: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker
        init(parent: CameraImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Search Feedback Bottom Sheet (Matches Reference Images 1 & 2)

struct SearchFeedbackSheetConfig: Identifiable {
    let id = UUID()
    let query: String
    let feedbackType: String // "positive" or "negative"
    let products: [MatchedProduct]
    let sessionId: String?
    let turnId: String?
}

struct ShopSearchFeedbackSheet: View {
    let query: String
    let products: [MatchedProduct]
    let initialFeedbackType: String
    let sessionId: String?
    let turnId: String?
    let onSubmitted: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentFeedbackType: String
    @State private var commentText: String = ""
    @State private var productRatings: [String: String] = [:] // productId -> "up" | "down"
    @State private var isSubmitting: Bool = false

    init(
        query: String,
        products: [MatchedProduct],
        initialFeedbackType: String,
        sessionId: String? = nil,
        turnId: String? = nil,
        onSubmitted: @escaping (String) -> Void
    ) {
        self.query = query
        self.products = products
        self.initialFeedbackType = initialFeedbackType
        self.sessionId = sessionId
        self.turnId = turnId
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
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, ShopLayout.cardPadding)

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
                        .background(currentFeedbackType == "positive" ? Color.green.opacity(0.15) : Color.shopSurfaceElevated)
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
                        .background(currentFeedbackType == "negative" ? Color.red.opacity(0.15) : Color.shopSurfaceElevated)
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
                .padding(.horizontal, ShopLayout.screenPadding)

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
                        .padding(.horizontal, ShopLayout.screenPadding)
                    }
                }

                // Comment Text Field (Screenshot 2: "Dicci come stiamo andando")
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.shopBorder, lineWidth: 1)
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
                .padding(.horizontal, ShopLayout.screenPadding)

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
                .padding(.horizontal, ShopLayout.screenPadding)
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

        let submittedType = currentFeedbackType
        let sid = sessionId
        let tid = turnId

        Task {
            if let sid, !sid.isEmpty, let tid, !tid.isEmpty {
                await APIService.shared.submitChatTurnFeedback(
                    sessionId: sid,
                    turnId: tid,
                    feedback: submittedType == "positive" ? 1 : -1
                )
            }
            await APIService.shared.submitSearchFeedback(
                query: query,
                feedbackType: submittedType,
                comment: commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : commentText,
                productEvaluations: evaluations.isEmpty ? nil : evaluations
            )
            await MainActor.run {
                isSubmitting = false
                dismiss()
                onSubmitted(submittedType)
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
