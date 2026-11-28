import SwiftUI

// MARK: - Sort & Quick Filter Options

enum WishlistSortOption: String, CaseIterable, Identifiable {
    case recent = "Recenti"
    case priceAsc = "Prezzo crescente"
    case priceDesc = "Prezzo decrescente"
    case biggestDiscount = "Sconto maggiore"
    case biggestDrop = "Calo maggiore"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .recent: return "Recenti"
        case .priceAsc: return "Prezzo ↑"
        case .priceDesc: return "Prezzo ↓"
        case .biggestDiscount: return "Sconto %"
        case .biggestDrop: return "Calo €"
        }
    }
}

enum WishlistQuickFilter: String, CaseIterable, Identifiable {
    case all = "Tutti"
    case priceDrops = "In calo"
    case mySize = "La mia taglia"
    case activeAlerts = "Alert attivi"

    var id: String { rawValue }
}

private struct ComparePairTarget: Identifiable {
    let id = UUID()
    let modelA: String
    let modelB: String?
}

// MARK: - Main Wishlist ("Salvati") View

struct WishlistView: View {
    @Binding var selectedTab: Int
    var embedded: Bool = false
    var onSelectPerTe: (() -> Void)? = nil

    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var notifManager = NotificationManager.shared
    @ObservedObject private var prefsManager = UserPreferencesManager.shared
    @ObservedObject private var supabase = SupabaseManager.shared

    @State private var searchText: String = ""
    @State private var selectedCollectionFilter: String = "Tutti"
    @State private var sortOption: WishlistSortOption = .recent
    @State private var quickFilter: WishlistQuickFilter = .all

    // Sheets & Alerts
    @State private var showingAccountSheet: Bool = false
    @State private var showingNotificationsSheet: Bool = false
    @State private var showingCreateCollectionSheet: Bool = false
    @State private var showingAddToCollectionSheet: Bool = false
    @State private var collectionForAddSheet: String = ""
    @State private var itemToMoveInCollection: WishlistItem? = nil
    @State private var itemForPriceAlert: WishlistItem? = nil
    @State private var comparePair: ComparePairTarget? = nil

    // Collection Rename / Delete Confirmation
    @State private var showingRenameAlert: Bool = false
    @State private var collectionToRename: String = ""
    @State private var newNameForRename: String = ""
    @State private var collectionPendingDelete: String? = nil

    // Compare Mode (select 2 saved models)
    @State private var isCompareMode: Bool = false
    @State private var compareSelection: [String] = []

    // Undo Toast
    @State private var toastMessage: String? = nil
    @State private var undoAction: (() -> Void)? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil

    init(selectedTab: Binding<Int>? = nil, embedded: Bool = false, onSelectPerTe: (() -> Void)? = nil) {
        self.embedded = embedded
        self.onSelectPerTe = onSelectPerTe
        if let tab = selectedTab {
            self._selectedTab = tab
        } else {
            self._selectedTab = .constant(2)
        }
    }

    // MARK: - Derived Data

    private var userInitial: String {
        let trimmed = prefsManager.preferences.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, !trimmed.isEmpty, trimmed.lowercased() != "ospite" {
            return String(first).uppercased()
        }
        if let emailFirst = supabase.currentUserEmail?.first {
            return String(emailFirst).uppercased()
        }
        return "F"
    }

    private var hasPreferredOrMonitoredSize: Bool {
        prefsManager.preferences.hasAnySize || wishlist.items.contains { $0.monitoredSize != nil }
    }

    private var collectionScopedItems: [WishlistItem] {
        guard selectedCollectionFilter != "Tutti" else { return wishlist.items }
        return wishlist.items.filter { $0.belongsToCollection(selectedCollectionFilter) }
    }

    private var priceDropItemsCount: Int {
        collectionScopedItems.filter { $0.hasDroppedSinceSaved || $0.isTargetReachedEffective }.count
    }

    private var activeAlertsCount: Int {
        collectionScopedItems.filter { $0.isAlertEnabled && $0.targetAlertPrice != nil }.count
    }

    private var mySizeAvailableCount: Int {
        collectionScopedItems.filter { $0.isMonitoredSizeAvailable == true }.count
    }

    private var displayItems: [WishlistItem] {
        var list = collectionScopedItems

        switch quickFilter {
        case .all:
            break
        case .priceDrops:
            list = list.filter { $0.hasDroppedSinceSaved || $0.isTargetReachedEffective }
        case .mySize:
            list = list.filter { $0.isMonitoredSizeAvailable == true }
        case .activeAlerts:
            list = list.filter { $0.isAlertEnabled && $0.targetAlertPrice != nil }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter {
                $0.canonical_name.lowercased().contains(query) ||
                $0.effectiveBrand.lowercased().contains(query) ||
                ($0.bestStore?.lowercased().contains(query) ?? false) ||
                $0.collectionNames.contains { $0.lowercased().contains(query) }
            }
        }

        switch sortOption {
        case .recent:
            list.sort { $0.dateAdded > $1.dateAdded }
        case .priceAsc:
            list.sort {
                if $0.isInStock != $1.isInStock { return $0.isInStock }
                return $0.currentBestPrice < $1.currentBestPrice
            }
        case .priceDesc:
            list.sort {
                if $0.isInStock != $1.isInStock { return $0.isInStock }
                return $0.currentBestPrice > $1.currentBestPrice
            }
        case .biggestDiscount:
            list.sort { ($0.effectiveDiscountPct ?? 0) > ($1.effectiveDiscountPct ?? 0) }
        case .biggestDrop:
            list.sort {
                if $0.isTargetReachedEffective != $1.isTargetReachedEffective {
                    return $0.isTargetReachedEffective
                }
                if abs($0.droppedAmountSinceSaved - $1.droppedAmountSinceSaved) > 0.01 {
                    return $0.droppedAmountSinceSaved > $1.droppedAmountSinceSaved
                }
                return ($0.effectiveDiscountPct ?? 0) > ($1.effectiveDiscountPct ?? 0)
            }
        }

        return list
    }

    private var hasActiveSearchOrQuickFilter: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || quickFilter != .all
    }

    // MARK: - Body

    var body: some View {
        Group {
            if embedded {
                contentWithOverlays
            } else {
                NavigationStack {
                    VStack(spacing: 0) {
                        headerBar
                            .shopHeaderBarPadding()

                        contentWithOverlays
                    }
                    .background(Color.shopSurface.ignoresSafeArea())
                    .navigationBarHidden(true)
                }
            }
        }
        .sheet(isPresented: $showingAccountSheet) {
            AccountView()
        }
        .sheet(isPresented: $showingNotificationsSheet) {
            NotificationsView()
        }
        .sheet(item: $itemToMoveInCollection) { item in
            MoveToCollectionSheet(item: item)
        }
        .sheet(item: $itemForPriceAlert) { item in
            PriceAlertSheet(product: item.toMatchedProduct(), existingWishlistItem: item)
        }
        .sheet(item: $comparePair) { pair in
            ModelCompareView(initialModelA: pair.modelA, initialModelB: pair.modelB)
        }
        .sheet(isPresented: $showingCreateCollectionSheet) {
            CreateCollectionSheet(
                isPresented: $showingCreateCollectionSheet,
                existingNames: wishlist.getAvailableCollections().map(\.name),
                onSave: { name in
                    collectionForAddSheet = name
                    wishlist.createCollection(name: name)
                    withAnimation(ShopMotion.pillSlide) {
                        selectedCollectionFilter = name
                        quickFilter = .all
                    }
                    if !wishlist.items.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showingAddToCollectionSheet = true
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $showingAddToCollectionSheet) {
            AddToCollectionSheet(
                collectionName: collectionForAddSheet,
                isPresented: $showingAddToCollectionSheet
            )
        }
        .alert("Rinomina collezione", isPresented: $showingRenameAlert) {
            TextField("Nuovo nome", text: $newNameForRename)
            Button("Annulla", role: .cancel) { }
            Button("Salva") {
                let trimmed = newNameForRename.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !WishlistManager.isReservedCollectionName(trimmed) else { return }
                let old = collectionToRename
                wishlist.renameCollection(oldName: old, newName: trimmed)
                if selectedCollectionFilter.caseInsensitiveCompare(old) == .orderedSame {
                    selectedCollectionFilter = trimmed
                }
            }
        } message: {
            Text("Inserisci il nuovo nome per la collezione «\(collectionToRename)».")
        }
        .alert(
            "Elimina collezione",
            isPresented: Binding(
                get: { collectionPendingDelete != nil },
                set: { if !$0 { collectionPendingDelete = nil } }
            ),
            presenting: collectionPendingDelete
        ) { colName in
            Button("Elimina", role: .destructive) {
                performDeleteCollection(colName)
            }
            Button("Annulla", role: .cancel) { }
        } message: { colName in
            Text("Vuoi eliminare la collezione «\(colName)»? I prodotti salvati resteranno comunque in «Tutti i salvati».")
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == 2 {
                Task { await wishlist.syncWithDatabase() }
            }
        }
    }

    // MARK: - Main Content & Overlays

    private var contentWithOverlays: some View {
        ZStack(alignment: .bottom) {
            mainContent

            if isCompareMode {
                compareFloatingBar
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.bottom, embedded ? 20 : ShopLayout.toastBottomOffset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let msg = toastMessage {
                undoToastBanner(message: msg)
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.bottom, embedded ? 20 : ShopLayout.toastBottomOffset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: isCompareMode)
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: toastMessage)
    }

    private var mainContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ShopLayout.sectionSpacing) {
                    if wishlist.isSyncingDatabase && wishlist.items.isEmpty {
                        ShopWishlistSkeletonView()
                            .transition(.opacity)
                    } else if wishlist.items.isEmpty {
                        emptySavedState
                            .padding(.top, 24)
                    } else {
                        if embedded && wishlist.items.count >= 4 {
                            inlineSearchField
                                .padding(.horizontal, ShopLayout.screenPadding)
                                .padding(.top, 4)
                        }

                        // 1. Collections Section Header & Horizontal Carousel
                        collectionsSection
                            .padding(.top, 2)

                        // 2. Dynamic Savings / Target Reached Insight Banner (only when actionable)
                        if quickFilter == .all && !isCompareMode {
                            liveInsightsBanner
                        }

                        // 3. Active Collection Title + Manage Menu + Filter & Sort Pills
                        VStack(alignment: .leading, spacing: 11) {
                            collectionSectionHeader
                            filterAndSortBar
                        }

                        // 4. Saved Products 2-Column Grid or Smart Empty State
                        if displayItems.isEmpty {
                            emptyFilteredState
                                .padding(.horizontal, ShopLayout.screenPadding)
                                .padding(.top, 6)
                        } else {
                            savedProductsGrid
                                .padding(.horizontal, ShopLayout.screenPadding)
                        }
                    }

                    Spacer(minLength: isCompareMode ? ShopLayout.bottomFilterDockClearance + 20 : ShopLayout.bottomDockClearance)
                }
                .id("wishlist_top")
            }
            .background(Color.shopSurface)
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await wishlist.syncWithDatabase(force: true)
            }
            .onReceive(TabCoordinator.shared.$scrollToTopEvent) { event in
                guard let event, event.tab == 2 else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    scrollProxy.scrollTo("wishlist_top", anchor: .top)
                }
            }
        }
    }

    // MARK: - Empty Saved State

    private var emptySavedState: some View {
        FitMatchEmptyStateView(
            icon: "heart",
            title: "Nessun articolo salvato",
            subtitle: "Salva i prodotti che ti interessano per seguire cali di prezzo, taglie disponibili e minimi storici.",
            primaryTitle: "Esplora prodotti",
            primaryIcon: "sparkles",
            onPrimaryTap: {
                if let onPerTe = onSelectPerTe {
                    onPerTe()
                } else {
                    withAnimation(ShopMotion.tabSwitch) {
                        selectedTab = 0
                    }
                }
            },
            showsCardBackground: false
        )
        .padding(.horizontal, ShopLayout.screenPadding)
        .padding(.top, 20)
    }

    // MARK: - Live Insights Banner

    @ViewBuilder
    private var liveInsightsBanner: some View {
        let targets = wishlist.targetReachedCount
        let drops = wishlist.priceDropsCount
        let totalSavings = wishlist.totalDroppedSavingsEur

        if targets > 0 || drops > 0 {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(ShopMotion.pillSlide) {
                    selectedCollectionFilter = "Tutti"
                    quickFilter = .priceDrops
                    sortOption = .biggestDrop
                }
            }) {
                HStack(spacing: 11) {
                    ZStack {
                        Circle()
                            .fill(Color.shopGreen.opacity(0.14))
                            .frame(width: 36, height: 36)

                        Image(systemName: targets > 0 ? "target" : "arrow.down.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.shopGreen)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        if targets > 0 {
                            Text(targets == 1 ? "1 soglia prezzo raggiunta" : "\(targets) soglie prezzo raggiunte")
                                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                        } else {
                            Text(drops == 1 ? "1 salvato in calo di prezzo" : "\(drops) salvati in calo di prezzo")
                                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                        }

                        Text(
                            totalSavings >= 1.0
                            ? "Risparmi \(Int(totalSavings.rounded())) € rispetto al salvataggio"
                            : "Prezzi live aggiornati sui negozi partner"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 3) {
                        Text("Vedi")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    .foregroundColor(.shopGreen)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                        .stroke(Color.shopGreen.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.985, pressedOpacity: 0.95))
            .padding(.horizontal, ShopLayout.screenPadding)
        }
    }

    // MARK: - Collections Carousel

    private var collectionsSection: some View {
        let availableCollections = wishlist.getAvailableCollections()

        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                HStack(spacing: 6) {
                    Text("Collezioni")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    if !availableCollections.isEmpty {
                        Text("\(availableCollections.count)")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.shopPurple)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.shopPurpleLight)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingCreateCollectionSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11.5, weight: .bold))
                        Text("Nuova")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.shopPurple)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5.5)
                    .background(Color.shopPurpleLight)
                    .clipShape(Capsule())
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.95, pressedOpacity: 0.9))
                .accessibilityLabel("Crea nuova collezione")
            }
            .padding(.horizontal, ShopLayout.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // 1. Always First: "Tutti i salvati"
                    ShopCollectionTileCard(
                        title: "Tutti i salvati",
                        itemCount: wishlist.items.count,
                        isSelected: selectedCollectionFilter == "Tutti",
                        isAllSavedCard: true,
                        thumbnails: wishlist.getThumbnails(for: "Tutti", limit: 4),
                        onTap: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(ShopMotion.pillSlide) {
                                selectedCollectionFilter = "Tutti"
                            }
                        }
                    )
                    .shopCarouselTransition()

                    // 2. User Collections
                    ForEach(availableCollections, id: \.name) { col in
                        let isSelected = selectedCollectionFilter.caseInsensitiveCompare(col.name) == .orderedSame
                        ShopCollectionTileCard(
                            title: col.name,
                            itemCount: col.item_count,
                            isSelected: isSelected,
                            isAllSavedCard: false,
                            thumbnails: wishlist.getThumbnails(for: col.name, limit: 4),
                            onTap: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(ShopMotion.pillSlide) {
                                    selectedCollectionFilter = isSelected ? "Tutti" : col.name
                                }
                            },
                            onManageItems: {
                                collectionForAddSheet = col.name
                                showingAddToCollectionSheet = true
                            },
                            onRename: {
                                collectionToRename = col.name
                                newNameForRename = col.name
                                showingRenameAlert = true
                            },
                            onDelete: {
                                collectionPendingDelete = col.name
                            }
                        )
                        .shopCarouselTransition()
                    }

                    // 3. Create New Collection Card
                    ShopCreateCollectionCard {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingCreateCollectionSheet = true
                    }
                    .shopCarouselTransition()
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Collection Section Header (Clean, Overflow-Safe)

    private var collectionSectionHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            if selectedCollectionFilter == "Tutti" {
                HStack(spacing: 6) {
                    Text("Tutti gli articoli")
                        .font(.system(size: 17.5, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Text("\(displayItems.count)")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(.shopTextMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.shopSurfaceElevated)
                        .clipShape(Capsule())
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.shopPurple)

                    Text(selectedCollectionFilter)
                        .font(.system(size: 17.5, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)
                        .lineLimit(1)

                    Text("\(displayItems.count)")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(.shopTextMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.shopSurfaceElevated)
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 8)

            if selectedCollectionFilter != "Tutti" {
                HStack(spacing: 8) {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        collectionForAddSheet = selectedCollectionFilter
                        showingAddToCollectionSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("Aggiungi")
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.shopPurple)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.95, pressedOpacity: 0.9))

                    Menu {
                        Button(action: {
                            collectionForAddSheet = selectedCollectionFilter
                            showingAddToCollectionSheet = true
                        }) {
                            Label("Gestisci articoli", systemImage: "folder.badge.plus")
                        }

                        Button(action: {
                            collectionToRename = selectedCollectionFilter
                            newNameForRename = selectedCollectionFilter
                            showingRenameAlert = true
                        }) {
                            Label("Rinomina collezione", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive, action: {
                            collectionPendingDelete = selectedCollectionFilter
                        }) {
                            Label("Elimina collezione", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.shopDark)
                            .frame(width: 30, height: 30)
                            .background(Color.white)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.shopBorder, lineWidth: 1)
                            )
                    }
                    .accessibilityLabel("Opzioni collezione")
                }
            }
        }
        .padding(.horizontal, ShopLayout.screenPadding)
    }

    // MARK: - Filter & Sort Bar

    private var filterAndSortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Sort Menu Pill
                Menu {
                    ForEach(WishlistSortOption.allCases) { option in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(ShopMotion.gridReflow) {
                                sortOption = option
                            }
                        }) {
                            if sortOption == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .bold))
                        Text(sortOption.shortLabel)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(sortOption == .recent ? .shopDark : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7.5)
                    .background(sortOption == .recent ? Color.white : Color.shopDark)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(sortOption == .recent ? Color.shopBorder : Color.clear, lineWidth: 1)
                    )
                }

                // Quick Filter: In calo
                quickFilterPill(
                    filter: .priceDrops,
                    icon: "arrow.down.right",
                    label: "In calo",
                    count: priceDropItemsCount > 0 ? priceDropItemsCount : nil,
                    accentColor: .shopGreen
                )

                // Quick Filter: La mia taglia
                if hasPreferredOrMonitoredSize {
                    quickFilterPill(
                        filter: .mySize,
                        icon: "checkmark.circle",
                        label: "La mia taglia",
                        count: mySizeAvailableCount > 0 ? mySizeAvailableCount : nil,
                        accentColor: .shopPurple
                    )
                }

                // Quick Filter: Alert attivi
                quickFilterPill(
                    filter: .activeAlerts,
                    icon: "bell.fill",
                    label: "Alert",
                    count: activeAlertsCount > 0 ? activeAlertsCount : nil,
                    accentColor: .shopPurple
                )

                // Compare Mode Toggle (shown when >= 2 saved items are visible)
                if collectionScopedItems.count >= 2 {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(ShopMotion.pillSlide) {
                            isCompareMode.toggle()
                            if !isCompareMode {
                                compareSelection.removeAll()
                            }
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: isCompareMode ? "xmark" : "arrow.left.arrow.right")
                                .font(.system(size: 11, weight: .bold))
                            Text(isCompareMode ? "Fine confronto" : "Confronta")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(isCompareMode ? .white : .shopPurple)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7.5)
                        .background(isCompareMode ? Color.shopPurple : Color.shopPurpleLight)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ShopLayout.screenPadding)
        }
    }

    private func quickFilterPill(
        filter: WishlistQuickFilter,
        icon: String,
        label: String,
        count: Int?,
        accentColor: Color
    ) -> some View {
        let isSelected = quickFilter == filter
        return Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(ShopMotion.pillSlide) {
                quickFilter = isSelected ? .all : filter
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isSelected ? .white : accentColor)

                Text(label)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? .white : .shopDark)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white : .shopTextMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.white.opacity(0.22) : Color.shopSurfaceElevated)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7.5)
            .background(isSelected ? Color.shopDark : Color.white)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.shopBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Smart Empty Filtered State (Distinguishes Search vs Quick Filter vs Empty Collection)

    @ViewBuilder
    private var emptyFilteredState: some View {
        let cleanQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanQuery.isEmpty {
            FitMatchEmptyStateView(
                icon: "magnifyingglass",
                title: "Nessun risultato per «\(cleanQuery)»",
                subtitle: selectedCollectionFilter == "Tutti"
                    ? "Prova con un altro brand, modello o negozio tra i tuoi salvati."
                    : "Nessun articolo corrisponde nella collezione «\(selectedCollectionFilter)».",
                primaryTitle: "Pulisci ricerca",
                primaryIcon: "xmark",
                onPrimaryTap: {
                    withAnimation(ShopMotion.pillSlide) {
                        searchText = ""
                    }
                },
                secondaryTitle: selectedCollectionFilter == "Tutti" ? nil : "Cerca in tutti i salvati",
                onSecondaryTap: selectedCollectionFilter == "Tutti" ? nil : {
                    withAnimation(ShopMotion.pillSlide) {
                        selectedCollectionFilter = "Tutti"
                    }
                }
            )
            .padding(.vertical, 6)
        } else if quickFilter != .all {
            let subtitle: String = {
                switch quickFilter {
                case .priceDrops:
                    return "Ti avviseremo appena uno dei tuoi articoli salvati scende di prezzo o raggiunge la soglia."
                case .mySize:
                    return "Nessun salvato risulta al momento disponibile nella tua taglia monitorata."
                case .activeAlerts:
                    return "Tocca la campanella su una card per impostare la tua soglia di prezzo personalizzata."
                case .all:
                    return ""
                }
            }()
            FitMatchEmptyStateView(
                icon: quickFilter == .activeAlerts ? "bell" : (quickFilter == .priceDrops ? "arrow.down.right" : "ruler"),
                title: "Nessun salvato in «\(quickFilter.rawValue)»",
                subtitle: subtitle,
                primaryTitle: "Mostra tutti (\(collectionScopedItems.count))",
                onPrimaryTap: {
                    withAnimation(ShopMotion.pillSlide) {
                        quickFilter = .all
                    }
                }
            )
            .padding(.vertical, 6)
        } else {
            FitMatchEmptyStateView(
                icon: "folder",
                title: "Collezione «\(selectedCollectionFilter)» vuota",
                subtitle: "Aggiungi qui i modelli salvati per tenerli ordinati per sport, gara o stagione.",
                primaryTitle: "Aggiungi dai salvati",
                primaryIcon: "plus",
                onPrimaryTap: {
                    collectionForAddSheet = selectedCollectionFilter
                    showingAddToCollectionSheet = true
                },
                secondaryTitle: "Vedi tutti (\(wishlist.items.count))",
                onSecondaryTap: {
                    withAnimation(ShopMotion.pillSlide) {
                        selectedCollectionFilter = "Tutti"
                    }
                }
            )
            .padding(.vertical, 6)
        }
    }

    // MARK: - Saved Products 2-Column Grid

    private var savedProductsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: ShopLayout.gridColumnSpacing, alignment: .top),
                GridItem(.flexible(), spacing: ShopLayout.gridColumnSpacing, alignment: .top)
            ],
            spacing: ShopLayout.gridRowSpacing
        ) {
            ForEach(displayItems) { item in
                let compareIdx = compareSelection.firstIndex(of: item.canonical_name)

                ShopSavedProductCard(
                    item: item,
                    activeCollectionFilter: selectedCollectionFilter,
                    isCompareMode: isCompareMode,
                    compareBadgeNumber: compareIdx.map { $0 + 1 },
                    onCompareToggle: {
                        toggleCompareSelection(item.canonical_name)
                    },
                    onRemove: {
                        performRemoveItem(item)
                    },
                    onOpenPriceAlert: {
                        itemForPriceAlert = item
                    },
                    onManageCollections: {
                        itemToMoveInCollection = item
                    },
                    onRemoveFromCurrentCollection: selectedCollectionFilter == "Tutti" ? nil : {
                        let col = selectedCollectionFilter
                        withAnimation(ShopMotion.gridReflow) {
                            wishlist.removeItem(item.canonical_name, fromCollection: col)
                        }
                        showToast("Rimosso da «\(col)»") {
                            wishlist.toggleCollection(col, for: item.canonical_name)
                        }
                    },
                    onCompareSingle: {
                        comparePair = ComparePairTarget(modelA: item.canonical_name, modelB: nil)
                    }
                )
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(ShopMotion.gridReflow, value: displayItems.map(\.id))
    }

    // MARK: - Compare Floating Bar & Undo Toast

    private var compareFloatingBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(compareSelection.count == 2 ? "Pronto per il confronto IA" : "Seleziona 2 modelli salvati")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("\(compareSelection.count)/2 selezionati")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
            }

            Spacer()

            Button(action: {
                guard compareSelection.count == 2 else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                let a = compareSelection[0]
                let b = compareSelection[1]
                isCompareMode = false
                compareSelection.removeAll()
                comparePair = ComparePairTarget(modelA: a, modelB: b)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                    Text("Confronta")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundColor(compareSelection.count == 2 ? .white : .white.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(compareSelection.count == 2 ? Color.shopPurple : Color.white.opacity(0.14))
                .clipShape(Capsule())
            }
            .disabled(compareSelection.count != 2)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.shopDark)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 5)
    }

    private func undoToastBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)

            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let undo = undoAction {
                Button(action: {
                    undo()
                    toastDismissTask?.cancel()
                    withAnimation {
                        toastMessage = nil
                        undoAction = nil
                    }
                }) {
                    Text("Annulla")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 196/255, green: 181/255, blue: 253/255))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 28/255, green: 28/255, blue: 34/255))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 4)
    }

    // MARK: - Actions Helpers

    private func toggleCompareSelection(_ canonicalName: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let idx = compareSelection.firstIndex(of: canonicalName) {
            compareSelection.remove(at: idx)
        } else {
            if compareSelection.count >= 2 {
                compareSelection.removeFirst()
            }
            compareSelection.append(canonicalName)
        }
    }

    private func performRemoveItem(_ item: WishlistItem) {
        var removedSnapshot: (item: WishlistItem, index: Int)?
        withAnimation(ShopMotion.gridReflow) {
            removedSnapshot = wishlist.removeFromWishlist(item.canonical_name)
        }
        guard let snap = removedSnapshot else { return }
        compareSelection.removeAll { $0 == item.canonical_name }
        showToast("Rimosso dai salvati") {
            withAnimation(ShopMotion.gridReflow) {
                wishlist.restoreItem(snap.item, at: snap.index)
            }
        }
    }

    private func performDeleteCollection(_ colName: String) {
        var affected: [String] = []
        withAnimation(ShopMotion.pillSlide) {
            affected = wishlist.deleteCollection(name: colName)
            if selectedCollectionFilter.caseInsensitiveCompare(colName) == .orderedSame {
                selectedCollectionFilter = "Tutti"
            }
        }
        showToast("Collezione «\(colName)» eliminata") {
            withAnimation(ShopMotion.pillSlide) {
                wishlist.restoreCollection(name: colName, itemCanonicalNames: affected)
                selectedCollectionFilter = colName
            }
        }
    }

    private func showToast(_ message: String, undo: (() -> Void)? = nil) {
        toastDismissTask?.cancel()
        toastMessage = message
        undoAction = undo
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    toastMessage = nil
                    undoAction = nil
                }
            }
        }
    }

    // MARK: - Header Bar (Dynamic Avatar, Context-Aware Search / Title, Bell)

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingAccountSheet = true
            }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 196/255, green: 181/255, blue: 253/255))
                        .frame(width: ShopLayout.headerButtonSize, height: ShopLayout.headerButtonSize)

                    Text(userInitial)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account")

            if wishlist.items.isEmpty {
                Text("Salvati")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                inlineSearchField
            }

            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingNotificationsSheet = true
            }) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: ShopLayout.headerButtonSize, height: ShopLayout.headerButtonSize)
                        .overlay(
                            Circle()
                                .stroke(Color.shopBorder, lineWidth: 1)
                        )

                    Image(systemName: "bell.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.shopDark)
                        .frame(width: ShopLayout.headerButtonSize, height: ShopLayout.headerButtonSize)

                    if notifManager.unreadCount > 0 {
                        Text("\(min(notifManager.unreadCount, 99))")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 2)
                            .background(Color.shopRed)
                            .clipShape(Capsule())
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notifiche")
        }
    }

    private var inlineSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14.5, weight: .medium))
                .foregroundColor(.shopTextMuted)

            TextField("Cerca nei salvati...", text: $searchText)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.shopDark)
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        searchText = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.shopTextMuted.opacity(0.75))
                }
                .accessibilityLabel("Cancella ricerca")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: ShopLayout.searchPillHeight)
        .background(Color.white)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.shopBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Unified Collection Tile Card (2x2 Collage for 3+ Items)

struct ShopCollectionTileCard: View {
    let title: String
    let itemCount: Int
    let isSelected: Bool
    let isAllSavedCard: Bool
    let thumbnails: [String]
    let onTap: () -> Void
    var onManageItems: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.shopSurfaceElevated)
                        .frame(width: 132, height: 88)

                    previewCollage
                        .frame(width: 132, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Text("\(itemCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white : .shopDark)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.shopPurple : Color.white)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                        .padding(6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .shopPurple : .shopDark)
                        .lineLimit(1)

                    Text(itemCount == 1 ? "1 articolo" : "\(itemCount) articoli")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                }
                .padding(.horizontal, 2)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.shopPurpleLight.opacity(0.65) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? Color.shopPurple : Color.shopBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? Color.shopPurple.opacity(0.12) : Color.black.opacity(0.03),
                radius: isSelected ? 6 : 2,
                x: 0,
                y: 2
            )
            .frame(width: 144)
        }
        .buttonStyle(ShopCardPressStyle(scale: 0.96, pressedOpacity: 0.94))
        .accessibilityLabel("\(title), \(itemCount) articoli")
        .contextMenu {
            if !isAllSavedCard {
                if let onManage = onManageItems {
                    Button(action: onManage) {
                        Label("Gestisci articoli", systemImage: "folder.badge.plus")
                    }
                }
                if let onRename = onRename {
                    Button(action: onRename) {
                        Label("Rinomina collezione", systemImage: "pencil")
                    }
                }
                if let onDelete = onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("Elimina collezione", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var previewCollage: some View {
        if thumbnails.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: isAllSavedCard ? "heart.fill" : "folder")
                    .font(.system(size: 22, weight: isAllSavedCard ? .semibold : .regular))
                    .foregroundColor(isAllSavedCard ? .shopPurple : .shopTextMuted.opacity(0.65))

                if !isAllSavedCard {
                    Text("Vuota")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.shopTextMuted.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if thumbnails.count == 1 {
            collageTile(urlString: thumbnails[0], padding: 6, cornerRadius: 12)
                .padding(3)
        } else if thumbnails.count == 2 {
            HStack(spacing: 3) {
                collageTile(urlString: thumbnails[0], padding: 3, cornerRadius: 9)
                collageTile(urlString: thumbnails[1], padding: 3, cornerRadius: 9)
            }
            .padding(4)
        } else {
            // Crisp 2x2 collage for 3 or 4+ items
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    collageTile(urlString: thumbnails[0], padding: 2, cornerRadius: 7)
                    collageTile(urlString: thumbnails[1], padding: 2, cornerRadius: 7)
                }
                HStack(spacing: 3) {
                    collageTile(urlString: thumbnails[2], padding: 2, cornerRadius: 7)
                    if thumbnails.count >= 4 {
                        collageTile(urlString: thumbnails[3], padding: 2, cornerRadius: 7)
                    } else {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.75))
                            .overlay(
                                Image(systemName: isAllSavedCard ? "heart.fill" : "folder.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.shopPurple.opacity(0.4))
                            )
                    }
                }
            }
            .padding(4)
        }
    }

    private func collageTile(urlString: String, padding: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            Color.white
            if let url = URL(string: urlString) {
                ShopCachedAsyncImage(url: url, maxPixelSize: 220) { phase in
                    if let img = phase.image {
                        img.resizable()
                            .scaledToFit()
                            .padding(padding)
                    } else {
                        Color.white
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Create Collection Card

struct ShopCreateCollectionCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.shopSurface)
                        .frame(width: 132, height: 88)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 38, height: 38)
                        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.shopPurple)
                        )
                }

                VStack(spacing: 2) {
                    Text("Crea nuova")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)
                        .lineLimit(1)

                    Text("Collezione")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                }
            }
            .padding(6)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        Color.shopBorder,
                        style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])
                    )
            )
            .frame(width: 144)
        }
        .buttonStyle(ShopCardPressStyle(scale: 0.96, pressedOpacity: 0.94))
        .accessibilityLabel("Crea nuova collezione")
    }
}

// MARK: - Saved Product Card (Cohesive with DealsView / ShopDealGridCard + Live Price Tracker)

struct ShopSavedProductCard: View {
    let item: WishlistItem
    let activeCollectionFilter: String
    var isCompareMode: Bool = false
    var compareBadgeNumber: Int? = nil
    var onCompareToggle: (() -> Void)? = nil
    let onRemove: () -> Void
    let onOpenPriceAlert: () -> Void
    var onManageCollections: (() -> Void)? = nil
    var onRemoveFromCurrentCollection: (() -> Void)? = nil
    var onCompareSingle: (() -> Void)? = nil

    private var eyebrowText: String {
        let brandPart = item.effectiveBrand.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let storePart = item.bestStore?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !brandPart.isEmpty && !storePart.isEmpty {
            if brandPart.caseInsensitiveCompare(storePart) == .orderedSame {
                return "\(brandPart) · Store ufficiale"
            }
            return "\(brandPart) · \(storePart)"
        }
        if !storePart.isEmpty { return storePart }
        if !brandPart.isEmpty { return brandPart }
        return "NEGOZIO PARTNER"
    }

    private var alertChipLabel: String {
        if item.isTargetReachedEffective, let target = item.targetAlertPrice {
            return "≤ \(Int(target.rounded())) €"
        }
        if item.isAlertEnabled, let target = item.targetAlertPrice {
            return "≤ \(Int(target.rounded())) €"
        }
        return item.isAlertEnabled ? "Alert" : "Off"
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 5.5) {
            // 1. Product Image Container
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                    .fill(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)

                if let imgUrl = item.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                    ShopCachedAsyncImage(url: url, maxPixelSize: 520) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(10)
                                .frame(maxWidth: .infinity)
                                .frame(height: 170)
                                .opacity(item.isInStock ? 1.0 : 0.48)
                                .transition(.opacity)
                        case .failure:
                            Image(systemName: "photo")
                                .font(.system(size: 26))
                                .foregroundColor(.shopTextMuted.opacity(0.4))
                                .frame(maxWidth: .infinity)
                                .frame(height: 170)
                        case .empty:
                            ShopSkeletonBlock(cornerRadius: ShopLayout.mediumRadius, height: 170)
                                .frame(maxWidth: .infinity)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous))
                } else {
                    Image(systemName: "shoe.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.shopTextMuted.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .frame(height: 170)
                }

                // Crisp border (highlighted in Compare Mode when selected)
                RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                    .stroke(
                        compareBadgeNumber != nil ? Color.shopPurple : Color.shopBorder,
                        lineWidth: compareBadgeNumber != nil ? 2 : 1
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)

                // Top Row Badges: Primary Status (Left) + All-Time Low (Right)
                HStack(alignment: .top, spacing: 4) {
                    if !item.isInStock {
                        Text("Esaurito")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.shopDark.opacity(0.75))
                            .clipShape(Capsule())
                    } else if item.isTargetReachedEffective {
                        HStack(spacing: 3) {
                            Image(systemName: "target")
                                .font(.system(size: 9, weight: .bold))
                            Text("Soglia")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.shopGreen)
                        .clipShape(Capsule())
                    } else if let dropText = item.formattedPriceDropSinceSaved {
                        HStack(spacing: 2.5) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8.5, weight: .black))
                            Text(dropText)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.shopGreen)
                        .clipShape(Capsule())
                    } else if let discText = item.discountBadgeText {
                        Text(discText)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.shopRed)
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: 2)

                    if item.isAllTimeLow && item.isInStock {
                        Text("Minimo")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(.shopGreen)
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 3)
                            .background(Color.shopGreenLight)
                            .clipShape(Capsule())
                    }
                }
                .padding(8)

                // Bottom Row Inside Image Box: Multi-Store / Collection Pill (Left) + Heart or Compare Badge (Right)
                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 4) {
                        if item.effectiveStoreCount > 1 && item.isInStock {
                            Text("\(item.effectiveStoreCount) negozi")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.shopDark)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.94))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                                )
                        } else if activeCollectionFilter == "Tutti", let firstCol = item.collectionNames.first {
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onManageCollections?()
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 8))
                                    Text(item.collectionNames.count > 1 ? "\(firstCol) +\(item.collectionNames.count - 1)" : firstCol)
                                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.shopPurple)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.95))
                                .clipShape(Capsule())
                                .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 4)

                        if isCompareMode {
                            ZStack {
                                Circle()
                                    .fill(compareBadgeNumber != nil ? Color.shopPurple : Color.black.opacity(0.35))
                                    .frame(width: 30, height: 30)

                                if let num = compareBadgeNumber {
                                    Text("\(num)")
                                        .font(.system(size: 13, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                } else {
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                        } else {
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onRemove()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.94))
                                        .frame(width: 30, height: 30)
                                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)

                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 12.5, weight: .bold))
                                        .foregroundColor(.shopRed)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Rimuovi \(item.canonical_name) dai salvati")
                        }
                    }
                    .padding(8)
                }
                .frame(height: 170)
            }
            .frame(height: 170)

            // 2. Eyebrow: BRAND · Store
            Text(eyebrowText)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(.shopTextMuted)
                .lineLimit(1)
                .padding(.top, 1)

            // 3. Title (up to 2 crisp lines without excess whitespace on 1-line titles)
            Text(item.canonical_name)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(.shopDark)
                .lineLimit(2)
                .lineSpacing(1.5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            // 4. Price Row
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(item.formattedCurrentPrice)
                    .font(.system(size: 15.5, weight: .heavy, design: .rounded))
                    .foregroundColor(item.isInStock ? .shopDark : .shopTextMuted)

                if let orig = item.formattedInitialPrice {
                    Text(orig)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(.shopTextMuted)
                        .strikethrough()
                        .lineLimit(1)
                }
            }

            // 5. Compact Tracker Footer: Size Availability + 1-Tap Price Alert Pill
            HStack(spacing: 5) {
                if let sz = item.monitoredSize, !sz.isEmpty {
                    let isAvail = item.isMonitoredSizeAvailable
                    HStack(spacing: 3) {
                        Image(systemName: isAvail == false ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 9))
                        Text("Tg. \(sz)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundColor(isAvail == false ? .shopTextMuted : .shopPurple)
                }

                Spacer(minLength: 2)

                if !isCompareMode {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onOpenPriceAlert()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: item.isAlertEnabled ? (item.isTargetReachedEffective ? "bell.badge.fill" : "bell.fill") : "bell.slash")
                                .font(.system(size: 9, weight: .bold))
                            Text(alertChipLabel)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundColor(
                            item.isTargetReachedEffective
                            ? .shopGreen
                            : (item.isAlertEnabled && item.targetAlertPrice != nil ? .shopPurple : .shopTextMuted)
                        )
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(
                            item.isTargetReachedEffective
                            ? Color.shopGreenLight
                            : (item.isAlertEnabled && item.targetAlertPrice != nil ? Color.shopPurpleLight : Color.shopSurfaceElevated)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Imposta alert prezzo per \(item.canonical_name)")
                }
            }
            .padding(.top, 1)
        }
    }

    var body: some View {
        Group {
            if isCompareMode {
                Button(action: { onCompareToggle?() }) {
                    cardContent
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.97, pressedOpacity: 0.94))
            } else {
                NavigationLink(destination: ProductDetailView(product: item.toMatchedProduct(), initialSize: item.selectedSize)) {
                    cardContent
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.97, pressedOpacity: 0.94))
            }
        }
        .contextMenu {
            Button(action: onOpenPriceAlert) {
                Label(
                    item.targetAlertPrice != nil ? "Modifica alert prezzo" : "Imposta alert prezzo",
                    systemImage: "bell.badge"
                )
            }

            if let onManage = onManageCollections {
                Button(action: onManage) {
                    Label("Organizza in collezioni", systemImage: "folder.badge.plus")
                }
            }

            if let onRemoveCol = onRemoveFromCurrentCollection {
                Button(action: onRemoveCol) {
                    Label("Rimuovi da «\(activeCollectionFilter)»", systemImage: "folder.badge.minus")
                }
            }

            if let onCompare = onCompareSingle {
                Button(action: onCompare) {
                    Label("Confronta con IA", systemImage: "arrow.left.arrow.right")
                }
            }

            Divider()

            Button(role: .destructive, action: onRemove) {
                Label("Rimuovi dai salvati", systemImage: "trash")
            }
        }
    }
}

// MARK: - Create Collection Sheet (Clean, No Fake Privacy Toggle, Quick Suggestions)

struct CreateCollectionSheet: View {
    @Binding var isPresented: Bool
    var existingNames: [String] = []
    let onSave: (String) -> Void

    @State private var collectionName: String = ""
    @FocusState private var isFieldFocused: Bool

    private let suggestedNames = ["Maratona", "Trail", "Gara", "Allenamento", "Saldi", "Regali"]

    private var availableSuggestions: [String] {
        let existingLow = Set(existingNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return suggestedNames.filter { !existingLow.contains($0.lowercased()) }
    }

    private var trimmedName: String {
        collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationError: String? {
        guard !trimmedName.isEmpty else { return nil }
        if WishlistManager.isReservedCollectionName(trimmedName) {
            return "«Tutti» è riservato alla lista principale."
        }
        if existingNames.contains(where: { $0.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            return "Esiste già una collezione con questo nome."
        }
        return nil
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && validationError == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Top Bar
            HStack {
                Button("Annulla") {
                    isPresented = false
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.shopDark)

                Spacer()

                Text("Nuova collezione")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)

                Spacer()

                Button("Salva") {
                    guard canSave else { return }
                    let finalName = trimmedName
                    isPresented = false
                    onSave(finalName)
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(canSave ? .shopPurple : Color(uiColor: .tertiaryLabel))
                .disabled(!canSave)
            }
            .padding(.top, 8)

            // Large Input
            VStack(alignment: .leading, spacing: 8) {
                TextField("Es. Scarpe Maratona...", text: $collectionName)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($isFieldFocused)
                    .onSubmit {
                        if canSave {
                            let finalName = trimmedName
                            isPresented = false
                            onSave(finalName)
                        }
                    }

                Divider()

                if let err = validationError {
                    Text(err)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.shopRed)
                }
            }

            // Quick Name Suggestions
            if !availableSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("SUGGERIMENTI")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.shopTextMuted)
                        .tracking(0.7)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableSuggestions, id: \.self) { suggestion in
                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    collectionName = suggestion
                                }) {
                                    Text(suggestion)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(.shopDark)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 7)
                                        .background(Color.shopSurfaceElevated)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(ShopLayout.screenPadding)
        .presentationDetents([.height(270)])
        .presentationDragIndicator(.visible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isFieldFocused = true
            }
        }
    }
}

// MARK: - Add To Collection Sheet (Fixed Layout, Centered Images, No Fake Ratings, Multi-Collection Safe)

struct AddToCollectionSheet: View {
    let collectionName: String
    @Binding var isPresented: Bool

    @ObservedObject private var wishlist = WishlistManager.shared
    @State private var selectedItems: Set<String> = []
    @State private var filterText: String = ""

    private var filteredItems: [WishlistItem] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return wishlist.items }
        return wishlist.items.filter {
            $0.canonical_name.lowercased().contains(q) ||
            $0.effectiveBrand.lowercased().contains(q) ||
            ($0.bestStore?.lowercased().contains(q) ?? false)
        }
    }

    private func toggleItem(_ canonicalName: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25)) {
            if selectedItems.contains(canonicalName) {
                selectedItems.remove(canonicalName)
            } else {
                selectedItems.insert(canonicalName)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if wishlist.items.isEmpty {
                    FitMatchEmptyStateView(
                        icon: "heart",
                        title: "Nessun articolo salvato",
                        subtitle: "Salva prima qualche prodotto per aggiungerlo a «\(collectionName)».",
                        showsCardBackground: false
                    )
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            if wishlist.items.count >= 6 {
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 14))
                                        .foregroundColor(.shopTextMuted)
                                    TextField("Filtra salvati...", text: $filterText)
                                        .font(.system(size: 14.5))
                                    if !filterText.isEmpty {
                                        Button(action: { filterText = "" }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(.shopTextMuted)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 40)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.shopBorder, lineWidth: 1))
                                .padding(.horizontal, ShopLayout.screenPadding)
                            }

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: ShopLayout.gridColumnSpacing),
                                    GridItem(.flexible(), spacing: ShopLayout.gridColumnSpacing)
                                ],
                                spacing: ShopLayout.gridRowSpacing
                            ) {
                                ForEach(filteredItems) { item in
                                    let isSelected = selectedItems.contains(item.canonical_name)
                                    let otherCollections = item.collectionNames.filter {
                                        $0.caseInsensitiveCompare(collectionName) != .orderedSame
                                    }

                                    VStack(alignment: .leading, spacing: 5) {
                                        // Centered Product Image + Corner Overlays
                                        ZStack {
                                            RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                                                .fill(isSelected ? Color.shopPurpleLight.opacity(0.45) : Color.white)
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 160)

                                            if let imgUrl = item.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                                                ShopCachedAsyncImage(url: url, maxPixelSize: 320) { phase in
                                                    if let img = phase.image {
                                                        img.resizable()
                                                            .scaledToFit()
                                                            .padding(12)
                                                            .frame(maxWidth: .infinity)
                                                            .frame(height: 160)
                                                    } else {
                                                        ShopSkeletonBlock(cornerRadius: ShopLayout.mediumRadius, height: 160)
                                                    }
                                                }
                                                .clipShape(RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous))
                                            } else {
                                                Image(systemName: "shoe.fill")
                                                    .font(.system(size: 26))
                                                    .foregroundColor(.shopTextMuted.opacity(0.4))
                                            }

                                            RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                                                .stroke(
                                                    isSelected ? Color.shopPurple : Color.shopBorder,
                                                    lineWidth: isSelected ? 2 : 1
                                                )
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 160)

                                            // Top-left indicator if also in another collection (transparent, multi-collection safe)
                                            if let firstOther = otherCollections.first {
                                                VStack {
                                                    HStack {
                                                        HStack(spacing: 3) {
                                                            Image(systemName: "folder.fill")
                                                                .font(.system(size: 7.5))
                                                            Text(otherCollections.count > 1 ? "\(firstOther) +\(otherCollections.count - 1)" : firstOther)
                                                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                                                .lineLimit(1)
                                                        }
                                                        .foregroundColor(.shopTextMuted)
                                                        .padding(.horizontal, 7)
                                                        .padding(.vertical, 3)
                                                        .background(Color.white.opacity(0.95))
                                                        .clipShape(Capsule())
                                                        .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
                                                        Spacer()
                                                    }
                                                    .padding(8)
                                                    Spacer()
                                                }
                                            }

                                            // Bottom-right selection badge
                                            VStack {
                                                Spacer()
                                                HStack {
                                                    Spacer()
                                                    ZStack {
                                                        Circle()
                                                            .fill(isSelected ? Color.shopPurple : Color.black.opacity(0.35))
                                                            .frame(width: 32, height: 32)

                                                        Image(systemName: isSelected ? "checkmark" : "plus")
                                                            .font(.system(size: 13, weight: .bold))
                                                            .foregroundColor(.white)
                                                    }
                                                    .padding(8)
                                                }
                                            }
                                        }
                                        .frame(height: 160)

                                        Text(item.bestStore ?? item.effectiveBrand)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundColor(.shopTextMuted)
                                            .lineLimit(1)
                                            .padding(.top, 1)

                                        Text(item.canonical_name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.shopDark)
                                            .lineLimit(2)
                                            .frame(height: 34, alignment: .topLeading)

                                        HStack(spacing: 5) {
                                            Text(item.formattedCurrentPrice)
                                                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                                .foregroundColor(.shopDark)

                                            if let orig = item.formattedInitialPrice {
                                                Text(orig)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.shopTextMuted)
                                                    .strikethrough()
                                            }
                                        }

                                        if let sz = item.monitoredSize, !sz.isEmpty {
                                            Text("Tg. \(sz)")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.shopTextMuted)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        toggleItem(item.canonical_name)
                                    }
                                }
                            }
                            .padding(.horizontal, ShopLayout.screenPadding)
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
                    .background(Color.shopSurface.ignoresSafeArea())
                }
            }
            .navigationTitle("Aggiungi a «\(collectionName)»")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.shopDark)
                            .frame(width: 32, height: 32)
                            .background(Color.shopSurfaceElevated)
                            .clipShape(Circle())
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        wishlist.setItemsForCollection(collectionName: collectionName, selectedCanonicalNames: selectedItems)
                        isPresented = false
                    }) {
                        Text(selectedItems.isEmpty ? "Fatto" : "Fatto (\(selectedItems.count))")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 7)
                            .background(Color.shopPurple)
                            .clipShape(Capsule())
                    }
                }
            }
            .onAppear {
                let existing = wishlist.items
                    .filter { $0.belongsToCollection(collectionName) }
                    .map { $0.canonical_name }
                selectedItems = Set(existing)
            }
        }
    }
}
