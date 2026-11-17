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
            .onDisappear {
                hideAllKeyboards()
            }
            .task {
                loadInitialTopSavings()
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
            icon: "sparkle.magnifyingglass",
            illustrationName: "empty_search",
            accentColor: .shopPurple,
            badgeText: "CERCA & CONFRONTA",
            title: "Cosa vorresti cercare?",
            subtitle: "Digita un prodotto, una marca o una categoria per confrontare i prezzi dei migliori negozi di sport."
        )
        .padding(.horizontal, ShopLayout.screenPadding)
        .padding(.top, 16)
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
            guard !rawSubtitle.isEmpty,
                  rawSubtitle.caseInsensitiveCompare(session.title) != .orderedSame,
                  rawSubtitle.range(of: #"\b(ai|ia)\b"#, options: [.regularExpression, .caseInsensitive]) == nil
            else { return nil }
            return rawSubtitle
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
                        conversationalHeader: m.conversational_header ?? "Ho cercato \(m.query)",
                        conversationalSummary: m.conversational_summary ?? "",
                        smartIntent: m.intent_json,
                        activeChips: m.chips_json ?? [],
                        searchResults: snap?.results ?? [],
                        curatedSections: snap?.curated_sections ?? [],
                        comparativeCards: snap?.comparative_cards ?? [],
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
                        self.conversationTurns = restoredTurns
                        self.lastContextQuery = last.query
                        self.smartIntent = last.smartIntent
                        self.activeChips = last.activeChips
                        self.searchResults = last.searchResults
                        self.curatedSections = last.curatedSections
                        self.comparativeCards = last.comparativeCards
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
                        .padding(.horizontal, ShopLayout.screenPadding)
                        .padding(.vertical, 10)
                        .background(Color(red: 243/255, green: 243/255, blue: 245/255))
                        .cornerRadius(22)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            Divider()
        }
        .background(Color.white)
        .zIndex(10)
    }

    // MARK: - AI Deep Dive: Main Content View (Screenshots 1, 2, 3)
    private var aiDeepDiveContentView: some View {
        Group {
            if isLoading && conversationTurns.isEmpty {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .trailing, spacing: 10) {
                        if let localPreview = pendingVisualImagePreview {
                            VStack(alignment: .trailing, spacing: 8) {
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
                                        .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
                                }

                                if let desc = pendingVisualDescription, !desc.isEmpty {
                                    HStack {
                                        Spacer()
                                        Text(desc)
                                            .font(.system(size: 14.5, weight: .semibold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 15)
                                            .padding(.vertical, 9)
                                            .background(
                                                LinearGradient(
                                                    colors: [Color.shopPurple, Color(red: 100/255, green: 55/255, blue: 235/255)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .cornerRadius(18)
                                    }
                                }
                            }
                            .padding(.horizontal, ShopLayout.screenPadding)
                            .padding(.top, 10)
                        }

                        ShopSearchDeepDiveSkeletonView(
                            query: rootQuery.isEmpty ? searchText : rootQuery,
                            thinkingSteps: thinkingSteps,
                            thinkingStartedAt: thinkingStartedAt
                        )
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
                    .onChange(of: curatedSections) { _ in
                        if ProcessInfo.processInfo.arguments.contains("-testAiSearchScrolled") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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

    // MARK: - Conversational Turn Content View
    @ViewBuilder
    private func turnContentView(for turn: SearchConversationTurn) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // User Photo + Query Bubble (saved in DB and associated with this turn)
            if turn.isFollowUp || turn.userImageURL != nil {
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
                                    .stroke(Color.shopPurple.opacity(0.22), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
                        }
                    }

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
                    }
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 8)
            }

            if turn.isConversationalAdvice {
                // MARK: - Dedicated ChatGPT-style AI Advice Card
                conversationalAdviceCard(for: turn)
            } else {
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
                .padding(.horizontal, ShopLayout.screenPadding)
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
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, turn.isFollowUp ? 4 : 8)
            }

            // Chips (collapsible)
            if turn.showAiExplanation && !turn.activeChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(turn.activeChips) { chip in
                            ShopSearchChipView(chip: chip)
                        }
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
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
                    .padding(.horizontal, ShopLayout.screenPadding)
                } else {
                    Text(LocalizedStringKey(turn.conversationalSummary))
                        .font(.system(size: 15.5, weight: .regular))
                        .foregroundColor(.shopDark)
                        .lineSpacing(4.5)
                        .padding(.horizontal, ShopLayout.screenPadding)
                }
            }
            }

            // 3. Thematic Curated Carousels (shown both on standard search turns and below Q&A advice cards)
            if !turn.curatedSections.isEmpty {
                ForEach(turn.curatedSections) { section in
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
            } else if !turn.searchResults.isEmpty {
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
                            ForEach(turn.searchResults) { prod in
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

            // 4. Comparative Spec Cards
            if !turn.isConversationalAdvice && !turn.comparativeCards.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(turn.comparativeCards.first?.section_title ?? "Confronto rapido")
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

            // 5. Spotlight / Best Deal Card
            if !turn.isConversationalAdvice, let spot = turn.spotlight {
                VStack(alignment: .leading, spacing: 6) {
                    ShopSpotlightCardView(spotlight: spot) {
                        selectedRecentProduct = spot.product
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
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
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 14)
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

            if showAiExplanation && !activeChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeChips) { chip in
                            ShopSearchChipView(chip: chip)
                        }
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.vertical, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
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
                accentColor: .shopPurple,
                badgeText: "RICERCA IA FITMATCH",
                title: "Analisi momentaneamente non disponibile",
                subtitle: error,
                primaryTitle: "Riprova analisi IA",
                primaryIcon: "arrow.clockwise",
                primaryColor: .shopDark,
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
        VStack {
            Spacer()
            FitMatchEmptyStateView(
                icon: "sparkles",
                illustrationName: "empty_search",
                accentColor: .shopPurple,
                badgeText: "MOTORE SPORTIVO IA",
                title: "Nessuna corrispondenza per questa ricerca",
                subtitle: "L'assistente FitMatch non ha trovato attrezzatura per «\(searchText)» tra i negozi partner. Prova uno dei suggerimenti qui sotto.",
                suggestions: ["Scarpe maratona", "Garmin Forerunner", "Racchetta padel"],
                onSuggestionTap: { term in
                    searchText = term
                    executeSearch()
                },
                primaryTitle: "Ricarica ricerca IA",
                primaryIcon: "arrow.clockwise",
                primaryColor: .shopDark,
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
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 0).id("search_classic_top")

                            LazyVStack(spacing: 14) {
                                ForEach(filteredAndSortedResults) { item in
                                    ShopOfficialProductCard(product: item)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 130)
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
                        illustrationName: "empty_search",
                        accentColor: .shopPurple,
                        badgeText: "CATALOGO FITMATCH",
                        title: "Nessun prodotto trovato",
                        subtitle: "Nessun articolo corrisponde a «\(searchText)». Prova a cercare per modello o disciplina sportiva tra i nostri negozi partner.",
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
            if isFollowUpFieldFocused || (wasSearchKeyboardActive && keyboardObserver.isKeyboardVisible) {
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
            currentSessionId = nil
            isFollowUpLoading = false
            pendingFollowUpQuery = nil
            pendingVisualImageURL = nil
            pendingVisualImagePreview = nil
            pendingVisualDescription = nil
            followUpErrorMessage = nil
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
            userForcedClassicMode = false
        }
        executeSearch(isFollowUp: isFollowUp, rawFollowUpText: isFollowUp ? trimmed : nil, userImageURL: userImageURL)
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

        Task {
            do {
                let res = try await api.analyzeVisualSearchImage(
                    imageData: jpegData,
                    mimeType: "image/jpeg",
                    description: cleanDesc
                )

                await MainActor.run {
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
                    if !isFollowUp {
                        self.rootQuery = finalQuery
                        self.searchText = finalQuery
                    }
                    self.executeSearch(
                        isFollowUp: isFollowUp,
                        rawFollowUpText: isFollowUp ? finalQuery : nil,
                        userImageURL: res.uploaded_image_url,
                        initialThinkingSteps: preservedSteps
                    )
                }
            } catch {
                await MainActor.run {
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
        initialThinkingSteps: [SearchThinkingStep] = []
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
                isFollowUpLoading = true
                // Do NOT wipe out existing turns with full-screen skeleton
                isLoading = false
                followUpErrorMessage = nil
                userForcedClassicMode = false
                isDeepDiveMode = true
            }
        }

        hasSearched = true
        errorMessage = nil
        thinkingSteps = initialThinkingSteps
        if initialThinkingSteps.isEmpty {
            thinkingStartedAt = Date()
        }

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
        let activeSid = currentSessionId
        let prefSize = prefs.preferences.preferredShoeSize.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
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
                        withAnimation(.easeOut(duration: 0.2)) {
                            if let idx = self.thinkingSteps.firstIndex(where: { $0.id == step.id }) {
                                self.thinkingSteps[idx] = step
                            } else {
                                self.thinkingSteps.append(step)
                            }
                        }
                    }
                )
                await MainActor.run {
                    if let returnedSid = smartRes.session_id, !returnedSid.isEmpty {
                        self.currentSessionId = returnedSid
                    }
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
                    let isAdvice = smartRes.is_conversational_advice ?? (smartRes.intent?.is_conversational_advice ?? false)

                    let newTurn = SearchConversationTurn(
                        id: smartRes.turn_id ?? UUID().uuidString,
                        query: query,
                        isFollowUp: isFollowUp,
                        isConversationalAdvice: isAdvice,
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

                    if ProcessInfo.processInfo.arguments.contains("-testClassicMode") {
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
                            self.pendingVisualImagePreview = nil
                            self.pendingVisualDescription = nil
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
                        await MainActor.run {
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
                        await MainActor.run {
                            self.pendingVisualImagePreview = nil
                            self.pendingVisualDescription = nil
                            self.errorMessage = "Impossibile recuperare i risultati in questo momento. Il server potrebbe essere occupato, tocca Riprova per aggiornare."
                            self.isLoading = false
                        }
                    }
                } else {
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
                        await MainActor.run {
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
                        // Follow-up failed: preserve all existing turns and show retry notification
                        await MainActor.run {
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

    var body: some View {
        Text(chip.label)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(.shopDark)
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
        product.offers.min(by: { $0.price < $1.price })
    }

    var maxOffer: Offer? {
        product.offers.max(by: { $0.price < $1.price })
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

// MARK: - Spotlight Card View (Screenshot 3)
struct ShopSpotlightCardView: View {
    let spotlight: SpotlightRecommendation
    let onTap: () -> Void

    var bestOffer: Offer? {
        spotlight.product.offers.min(by: { $0.price < $1.price })
    }

    var maxOffer: Offer? {
        spotlight.product.offers.max(by: { $0.price < $1.price })
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
                                Text(String(format: "€ %.2f", best.price))
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
        product.offers.sorted { $0.price < $1.price }
    }

    var bestOffer: Offer? { sortedOffers.first }
    var maxOffer: Offer? { sortedOffers.last }

    var savingsAmount: Double {
        guard let best = bestOffer, let max = maxOffer, max.price > best.price else {
            return product.cross_store_savings ?? 0.0
        }
        return max.price - best.price
    }

    var body: some View {
        NavigationLink(destination: ProductDetailView(product: product, openedFromSearch: true)) {
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
                            Text(String(format: "%.2f €", best.price).replacingOccurrences(of: ".", with: ","))
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundColor(.shopDark)

                            if let max = maxOffer, max.price > best.price {
                                Text(String(format: "%.2f €", max.price).replacingOccurrences(of: ".", with: ","))
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

    @State private var isAnalyzing: Bool = false
    @State private var scanOffset: CGFloat = -110
    @State private var pulseViewfinder: Bool = false
    @State private var analysisResult: VisualSearchResponse? = nil
    @State private var analysisError: String? = nil

    private struct VisualQuickHint: Identifiable {
        let id: String
        let label: String
        let icon: String
    }

    private var availableQuickHints: [VisualQuickHint] {
        var hints: [VisualQuickHint] = []
        let prefSize = prefsManager.preferences.preferredShoeSize.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prefSize.isEmpty {
            hints.append(VisualQuickHint(id: "size", label: "Taglia EU \(prefSize)", icon: "ruler"))
        }
        hints.append(contentsOf: [
            VisualQuickHint(id: "men", label: "Uomo", icon: "figure.stand"),
            VisualQuickHint(id: "women", label: "Donna", icon: "figure.stand.dress"),
            VisualQuickHint(id: "budget", label: "Sotto 150€", icon: "eurosign.circle"),
            VisualQuickHint(id: "alt", label: "Alternative economiche", icon: "sparkles")
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
                VStack(spacing: 16) {
                    // Custom Header Bar (Consistent with FitMatch Shop Design)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10.5, weight: .bold))
                                Text("RICERCA VISIVA IA")
                                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                                    .tracking(0.6)
                            }
                            .foregroundColor(.shopPurple)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.shopPurpleLight)
                            .clipShape(Capsule())

                            Text(selectedImage == nil ? "Trova dalla foto" : "Pronta per l'analisi")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            Text(
                                selectedImage == nil
                                ? "Scatta o carica un articolo sportivo per trovare subito il prezzo migliore."
                                : "Aggiungi una nota facoltativa per affinare modello, taglia o budget."
                            )
                            .font(.system(size: 13.5))
                            .foregroundColor(.shopTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.shopDark)
                                .shopNavCircle(size: 38)
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.92))
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.top, 16)

                    // Studio Viewfinder / Selected Photo Stage
                    visualStageCard
                        .padding(.horizontal, ShopLayout.screenPadding)

                    // Source Controls (Prominent cards before photo; overlay controls handle photo swap after selection)
                    if selectedImage == nil {
                        sourceControlsSection
                            .padding(.horizontal, ShopLayout.screenPadding)

                        visualUsageTipsBar
                            .padding(.horizontal, ShopLayout.screenPadding)
                    }

                    // Optional Description Composer (after photo is selected)
                    if let image = selectedImage, analysisResult == nil && !isAnalyzing {
                        descriptionComposerSection(for: image)
                            .padding(.horizontal, ShopLayout.screenPadding)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Results or Error
                    if let error = analysisError, !isAnalyzing {
                        visualErrorCard(error)
                            .padding(.horizontal, ShopLayout.screenPadding)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else if let result = analysisResult, !isAnalyzing {
                        visualResultSection(result)
                    }

                    Spacer(minLength: selectedImage != nil ? 28 : 24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.shopSurface.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if let image = selectedImage, analysisResult == nil && !isAnalyzing {
                    stickySearchActionDock(for: image)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    pulseViewfinder = true
                }
            }
            .fullScreenCover(isPresented: $showCameraPicker) {
                CameraImagePicker { capturedImage in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        selectedImage = capturedImage
                        analysisResult = nil
                        analysisError = nil
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
    }

    @ViewBuilder
    private func stickySearchActionDock(for image: UIImage) -> some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.6)

            Button(action: {
                triggerVisualSearch(with: image)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                    Text(combinedUserDescription == nil ? "Cerca con IA" : "Cerca con IA e nota")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    LinearGradient(
                        colors: [Color.shopPurple, Color(red: 112/255, green: 62/255, blue: 248/255)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color.shopPurple.opacity(0.32), radius: 12, x: 0, y: 5)
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.98))
            .padding(.horizontal, ShopLayout.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var visualUsageTipsBar: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.shopPurpleLight)
                    .frame(width: 32, height: 32)
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 13.5))
                    .foregroundColor(.shopPurple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Consiglio rapido")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                Text("Funziona benissimo anche con screenshot da Instagram, TikTok o Strava.")
                    .font(.system(size: 12))
                    .foregroundColor(.shopTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.shopBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func descriptionComposerSection(for image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 12.5))
                    .foregroundColor(.shopPurple)

                Text("Aiuta l'IA a cercare meglio")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)

                Spacer()

                Text("Facoltativo")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(.shopPurple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color.shopPurpleLight)
                    .clipShape(Capsule())
            }

            HStack(alignment: .top, spacing: 8) {
                TextField(
                    "Es. modello donna, taglia 42.5, sotto 130€, solo l'orologio…",
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
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.shopSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isDescriptionFocused ? Color.shopPurple.opacity(0.5) : Color.shopBorder, lineWidth: isDescriptionFocused ? 1.5 : 1)
            )

            // Quick-intent hint pills
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
                            HStack(spacing: 5) {
                                Image(systemName: isSelected ? "checkmark" : hint.icon)
                                    .font(.system(size: 10.5, weight: .bold))
                                Text(hint.label)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(isSelected ? .shopPurple : .shopDark)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(isSelected ? Color.shopPurpleLight : Color.shopSurface)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.shopPurple.opacity(0.45) : Color.shopBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .shopCard(padding: 15, cornerRadius: 20)
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
        ZStack {
            if let image = selectedImage {
                ZStack {
                    // Ambient blurred backdrop eliminates awkward sidebars while keeping full product visible
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 248)
                        .frame(maxWidth: .infinity)
                        .blur(radius: 26)
                        .overlay(Color.black.opacity(0.30))
                        .clipped()

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 222)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 6)
                        .padding(12)

                    VisualScannerReticle(color: .white.opacity(0.75))
                        .padding(18)

                    if isAnalyzing {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, Color.shopPurple.opacity(0.92), Color.white.opacity(0.9), Color.shopPurple.opacity(0.92), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 3)
                            .offset(y: scanOffset)
                            .shadow(color: .shopPurple, radius: 10)

                        VStack {
                            Spacer()
                            HStack(spacing: 9) {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.88)
                                Text("Analisi modello con IA…")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial.opacity(0.92))
                            .background(Color.black.opacity(0.45))
                            .clipShape(Capsule())
                            .padding(.bottom, 14)
                        }
                    } else {
                        VStack {
                            HStack(spacing: 8) {
                                // Quick camera retake button
                                Button(action: handleCameraButtonTap) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 30, height: 30)
                                        .background(.ultraThinMaterial)
                                        .background(Color.black.opacity(0.36))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(ShopCardPressStyle(scale: 0.94))

                                // Quick gallery swap button
                                PhotosPicker(
                                    selection: $selectedPhotoItem,
                                    matching: .images,
                                    photoLibrary: .shared()
                                ) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "photo.on.rectangle")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Cambia")
                                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .background(Color.black.opacity(0.36))
                                    .clipShape(Capsule())
                                }

                                Spacer()

                                Button(action: resetSelectedPhoto) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10.5, weight: .bold))
                                        Text("Rimuovi")
                                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .background(Color.black.opacity(0.36))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(ShopCardPressStyle(scale: 0.94))
                            }
                            .padding(12)
                            Spacer()
                        }
                    }
                }
                .frame(height: 248)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 6)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white, Color.shopPurpleLight.opacity(0.38)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.shopPurple.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 5)

                    VisualScannerReticle(color: .shopPurple.opacity(0.32))
                        .padding(20)

                    VStack(spacing: 15) {
                        ZStack {
                            Circle()
                                .fill(Color.shopPurpleLight.opacity(pulseViewfinder ? 0.72 : 0.42))
                                .frame(width: 90, height: 90)
                                .scaleEffect(pulseViewfinder ? 1.05 : 0.96)

                            Circle()
                                .fill(Color.shopPurpleLight)
                                .frame(width: 64, height: 64)

                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.shopPurple)
                        }

                        VStack(spacing: 4) {
                            Text("Inquadra il prodotto")
                                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                            Text("Foto nitide di scarpe, smartwatch, capi o accessori sportivi")
                                .font(.system(size: 12.5))
                                .foregroundColor(.shopTextMuted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }

                        HStack(spacing: 6) {
                            ForEach([
                                ("Scarpe", "shoe.fill"),
                                ("Orologi", "applewatch"),
                                ("Capi", "tshirt.fill"),
                                ("Zaini", "backpack.fill")
                            ], id: \.0) { label, icon in
                                HStack(spacing: 4) {
                                    Image(systemName: icon)
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundColor(.shopPurple)
                                    Text(label)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(.shopDark.opacity(0.78))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.9))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.shopBorder.opacity(0.8), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
                .frame(height: 256)
            }
        }
    }

    @ViewBuilder
    private var sourceControlsSection: some View {
        if selectedImage == nil {
            HStack(spacing: 12) {
                Button(action: handleCameraButtonTap) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 36, height: 36)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Fotocamera")
                                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Scatta ora")
                                .font(.system(size: 11.5))
                                .foregroundColor(.white.opacity(0.72))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(Color.shopDark)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.97))
                .disabled(isAnalyzing)

                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.shopPurpleLight)
                                .frame(width: 36, height: 36)
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.shopPurple)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Galleria")
                                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                            Text("Scegli foto")
                                .font(.system(size: 11.5))
                                .foregroundColor(.shopTextMuted)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.shopBorder, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 3)
                }
                .disabled(isAnalyzing)
            }
        } else {
            HStack(spacing: 10) {
                Button(action: handleCameraButtonTap) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Nuova foto")
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.shopDark)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.shopBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.97))
                .disabled(isAnalyzing)

                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Cambia da Galleria")
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.shopPurple)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(Color.shopPurpleLight)
                    .clipShape(Capsule())
                }
                .disabled(isAnalyzing)
            }
        }
    }

    @ViewBuilder
    private func visualErrorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 254/255, green: 226/255, blue: 226/255))
                        .frame(width: 36, height: 36)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.shopRed)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Analisi non riuscita")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
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
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                        Text("Riprova analisi")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.shopPurple)
                    .clipShape(Capsule())
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.98))
            }
        }
        .shopCard()
    }

    @ViewBuilder
    private func visualResultSection(_ result: VisualSearchResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !result.is_sport_product {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.shopPurpleLight)
                            .frame(width: 36, height: 36)
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.shopPurple)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Articolo sportivo non rilevato")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                        Text(result.note ?? "Prova a fotografare meglio scarpe, smartwatch, abbigliamento o attrezzatura sportiva.")
                            .font(.system(size: 13))
                            .foregroundColor(.shopTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .shopCard()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11.5))
                            Text(result.confidence == "high" ? "Modello identificato" : "Possibile corrispondenza")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.shopGreen)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.shopGreenLight)
                        .clipShape(Capsule())

                        Spacer()

                        if let cat = result.category, !cat.isEmpty {
                            Text(cat)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.shopPurple)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.shopPurpleLight)
                                .clipShape(Capsule())
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if let brand = result.brand, !brand.isEmpty {
                            Text(brand.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(0.6)
                                .foregroundColor(.shopTextMuted)
                        }

                        Text(result.recognized_model)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                    }

                    if let note = result.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 13.5))
                            .foregroundColor(.shopTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if result.catalog_matches_count > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 11))
                            Text("\(result.catalog_matches_count) corrispondenze trovate su FitMatch")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.shopPurple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.shopPurpleLight.opacity(0.65))
                        .clipShape(Capsule())
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
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.shopPurple)
                        .clipShape(Capsule())
                        .shadow(color: Color.shopPurple.opacity(0.28), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.98))
                    .padding(.top, 2)
                }
                .shopCard()

                if !result.alternatives.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Oppure cerca una variante simile")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.shopTextMuted)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(result.alternatives, id: \.self) { alt in
                                    Button(action: {
                                        let imgUrl = result.uploaded_image_url
                                        dismiss()
                                        onSelectModel(alt, imgUrl)
                                    }) {
                                        HStack(spacing: 5) {
                                            Image(systemName: "arrow.up.right")
                                                .font(.system(size: 10.5, weight: .bold))
                                                .foregroundColor(.shopPurple)
                                            Text(alt)
                                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                                .foregroundColor(.shopDark)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.white)
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
        scanOffset = -110

        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
            scanOffset = 110
        }

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

private struct VisualScannerReticle: View {
    let color: Color
    private let length: CGFloat = 20
    private let lineWidth: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                // Top-left
                path.move(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: 0, y: 4))
                path.addQuadCurve(to: CGPoint(x: 4, y: 0), control: .zero)
                path.addLine(to: CGPoint(x: length, y: 0))

                // Top-right
                path.move(to: CGPoint(x: w - length, y: 0))
                path.addLine(to: CGPoint(x: w - 4, y: 0))
                path.addQuadCurve(to: CGPoint(x: w, y: 4), control: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: length))

                // Bottom-left
                path.move(to: CGPoint(x: 0, y: h - length))
                path.addLine(to: CGPoint(x: 0, y: h - 4))
                path.addQuadCurve(to: CGPoint(x: 4, y: h), control: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: length, y: h))

                // Bottom-right
                path.move(to: CGPoint(x: w - length, y: h))
                path.addLine(to: CGPoint(x: w - 4, y: h))
                path.addQuadCurve(to: CGPoint(x: w, y: h - 4), control: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w, y: h - length))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
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
