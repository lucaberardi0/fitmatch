import SwiftUI

struct WishlistView: View {
    @Binding var selectedTab: Int
    var embedded: Bool = false
    var onSelectPerTe: (() -> Void)? = nil

    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var notifManager = NotificationManager.shared
    @StateObject private var api = APIService.shared

    @State private var searchText: String = ""
    @State private var showingAccountSheet: Bool = false
    @State private var showingNotificationsSheet: Bool = false
    @State private var showingCreateCollectionSheet: Bool = false
    @State private var showingAddToCollectionSheet: Bool = false
    @State private var collectionForAddSheet: String = ""
    @State private var selectedProductForDetail: MatchedProduct? = nil
    @State private var selectedCollectionFilter: String = "Tutti"
    @State private var itemToMoveInCollection: WishlistItem? = nil
    @State private var showingRenameAlert: Bool = false
    @State private var collectionToRename: String = ""
    @State private var newNameForRename: String = ""

    init(selectedTab: Binding<Int>? = nil, embedded: Bool = false, onSelectPerTe: (() -> Void)? = nil) {
        self.embedded = embedded
        self.onSelectPerTe = onSelectPerTe
        if let tab = selectedTab {
            self._selectedTab = tab
        } else {
            self._selectedTab = .constant(2)
        }
    }

    private var displayItems: [WishlistItem] {
        var list = wishlist.items

        // Filter by collection
        if selectedCollectionFilter != "Tutti" {
            list = list.filter {
                $0.collectionName?.caseInsensitiveCompare(selectedCollectionFilter) == .orderedSame
            }
        }

        // Filter by search text
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter {
                $0.canonical_name.lowercased().contains(query) ||
                ($0.brand?.lowercased().contains(query) ?? false) ||
                ($0.bestStore?.lowercased().contains(query) ?? false)
            }
        }
        return list
    }

    var body: some View {
        Group {
            if embedded {
                mainContent
            } else {
                NavigationStack {
                    VStack(spacing: 0) {
                        headerBar
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .padding(.bottom, 10)

                        mainContent
                    }
                    .background(Color(red: 245/255, green: 246/255, blue: 248/255).ignoresSafeArea())
                }
            }
        }
        .sheet(isPresented: $showingAccountSheet) {
            AccountView()
        }
        .sheet(isPresented: $showingNotificationsSheet) {
            NotificationsView()
        }
        .sheet(item: $selectedProductForDetail) { product in
            ProductDetailView(product: product)
        }
        .sheet(item: $itemToMoveInCollection) { item in
            MoveToCollectionSheet(item: item)
        }
        .sheet(isPresented: $showingCreateCollectionSheet) {
            CreateCollectionSheet(
                isPresented: $showingCreateCollectionSheet,
                onSave: { name in
                    collectionForAddSheet = name
                    wishlist.createCollection(name: name)
                    withAnimation(.spring(response: 0.3)) {
                        selectedCollectionFilter = name
                    }
                    if !wishlist.items.isEmpty {
                        // Delay opening AddToCollectionSheet to allow CreateCollectionSheet to finish dismissal
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
                guard !trimmed.isEmpty else { return }
                let old = collectionToRename
                wishlist.renameCollection(oldName: old, newName: trimmed)
                if selectedCollectionFilter.caseInsensitiveCompare(old) == .orderedSame {
                    selectedCollectionFilter = trimmed
                }
            }
        } message: {
            Text("Inserisci il nuovo nome per la collezione '\(collectionToRename)'.")
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if wishlist.items.isEmpty {
                    // Empty Saved State
                    emptySavedState
                        .padding(.top, 40)
                } else {
                    // 1. Collections Section Header & Horizontal Carousel
                    collectionsSection
                        .padding(.top, 4)

                    // 2. Active Filter Banner
                    filterHeaderBanner

                    // 3. Saved Products 2-Column Grid
                    if displayItems.isEmpty {
                        emptyFilteredState
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                    } else {
                        savedProductsGrid
                            .padding(.horizontal, 16)
                    }
                }

                Spacer(minLength: 120)
            }
        }
        .background(Color(red: 245/255, green: 246/255, blue: 248/255))
        .refreshable {
            await wishlist.syncWithDatabase()
        }
    }

    // MARK: - Screen 1: Empty Saved State (Matching Reference Image 1)

    private var emptySavedState: some View {
        VStack(spacing: 22) {
            // Layered card illustration with coffee cup / product and subtle heart
            ZStack {
                // Background shadow tilted card
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 244/255, green: 244/255, blue: 247/255))
                    .frame(width: 175, height: 185)
                    .rotationEffect(.degrees(4))
                    .offset(x: 6, y: -4)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 2, y: 4)

                // Foreground card
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white)
                    .frame(width: 175, height: 185)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)

                // Product photo inside card (mug or sneaker asset)
                VStack {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 54))
                        .foregroundColor(Color(red: 45/255, green: 45/255, blue: 50/255))
                        .padding(.top, 8)
                }
                .frame(width: 175, height: 185)

                // Bottom-right circular heart button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Circle()
                            .fill(Color.black.opacity(0.28))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: "heart")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .padding([.bottom, .trailing], 12)
                    }
                }
                .frame(width: 175, height: 185)
            }
            .padding(.top, 24)

            // Titles
            VStack(spacing: 8) {
                Text("Non hai ancora salvato alcun articolo")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("Tocca l’icona del cuore su un articolo per salvarlo e ricevere una notifica in caso di calo di prezzo")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(red: 120/255, green: 120/255, blue: 125/255))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineSpacing(2)
            }

            // Purple "Fai acquisti" Action Button (Image 1: #633BEE)
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                if let onPerTe = onSelectPerTe {
                    onPerTe()
                } else {
                    withAnimation(.spring(response: 0.25)) {
                        selectedTab = 0
                    }
                }
            }) {
                Text("Fai acquisti")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(red: 99/255, green: 59/255, blue: 238/255))
                    .cornerRadius(26)
                    .shadow(color: Color(red: 99/255, green: 59/255, blue: 238/255).opacity(0.28), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Collections Carousel

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: "Collezioni" + count pill + "Nuova" button
            HStack {
                HStack(spacing: 6) {
                    Text("Collezioni")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    let totalCols = wishlist.getAvailableCollections().count
                    if totalCols > 0 {
                        Text("\(totalCols)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 99/255, green: 59/255, blue: 238/255))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(red: 99/255, green: 59/255, blue: 238/255).opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Button(action: {
                    showingCreateCollectionSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Nuova")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color(red: 99/255, green: 59/255, blue: 238/255))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(red: 99/255, green: 59/255, blue: 238/255).opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            // Horizontal Scroll of Collection Cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // 1. ALWAYS FIRST: "Tutti i salvati" Home Base Card
                    ShopAllSavedCard(
                        totalCount: wishlist.items.count,
                        isSelected: selectedCollectionFilter == "Tutti",
                        thumbnails: wishlist.getThumbnails(for: "Tutti", limit: 2),
                        onTap: {
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selectedCollectionFilter = "Tutti"
                            }
                        }
                    )

                    // 2. User-Created Collections
                    ForEach(wishlist.getAvailableCollections(), id: \.name) { col in
                        let isSelected = selectedCollectionFilter.caseInsensitiveCompare(col.name) == .orderedSame
                        let thumbs = wishlist.getThumbnails(for: col.name, limit: 2)

                        ShopCollectionCard(
                            collection: col,
                            isSelected: isSelected,
                            thumbnails: thumbs,
                            onTap: {
                                let gen = UIImpactFeedbackGenerator(style: .light)
                                gen.impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    if isSelected {
                                        selectedCollectionFilter = "Tutti"
                                    } else {
                                        selectedCollectionFilter = col.name
                                    }
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
                                withAnimation(.spring(response: 0.25)) {
                                    wishlist.deleteCollection(name: col.name)
                                    if selectedCollectionFilter.caseInsensitiveCompare(col.name) == .orderedSame {
                                        selectedCollectionFilter = "Tutti"
                                    }
                                }
                            }
                        )
                    }

                    // 3. "Crea nuova collezione" Card
                    ShopCreateCollectionCard {
                        showingCreateCollectionSheet = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Filter Header Banner (Active Filter Indicator with Instant Reset)

    private var filterHeaderBanner: some View {
        HStack(alignment: .center) {
            if selectedCollectionFilter == "Tutti" {
                HStack(spacing: 6) {
                    Text("Tutti gli articoli")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Text("(\(wishlist.items.count))")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 130/255, green: 130/255, blue: 140/255))
                }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 99/255, green: 59/255, blue: 238/255))

                    Text(selectedCollectionFilter)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Text("(\(displayItems.count))")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 130/255, green: 130/255, blue: 140/255))
                }
            }

            Spacer()

            if selectedCollectionFilter != "Tutti" {
                HStack(spacing: 8) {
                    Button(action: {
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
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(red: 99/255, green: 59/255, blue: 238/255))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        let gen = UIImpactFeedbackGenerator(style: .light)
                        gen.impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            selectedCollectionFilter = "Tutti"
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                            Text("Mostra tutti (\(wishlist.items.count))")
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(red: 99/255, green: 59/255, blue: 238/255))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(red: 99/255, green: 59/255, blue: 238/255).opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    // MARK: - Empty Filtered State

    private var emptyFilteredState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)

                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 26))
                    .foregroundColor(Color(red: 99/255, green: 59/255, blue: 238/255))
            }
            .padding(.top, 12)

            Text("Nessun articolo in '\(selectedCollectionFilter)'")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            Text("Non ci sono articoli in questa collezione. Tutti i tuoi articoli salvati (\(wishlist.items.count)) rimangono comunque visibili in 'Tutti i salvati'.")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.shopTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .lineSpacing(2)

            HStack(spacing: 12) {
                Button(action: {
                    collectionForAddSheet = selectedCollectionFilter
                    showingAddToCollectionSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Aggiungi articoli")
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(red: 99/255, green: 59/255, blue: 238/255))
                    .clipShape(Capsule())
                    .shadow(color: Color(red: 99/255, green: 59/255, blue: 238/255).opacity(0.25), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)

                Button(action: {
                    withAnimation(.spring(response: 0.25)) {
                        selectedCollectionFilter = "Tutti"
                    }
                }) {
                    Text("Mostra tutti (\(wishlist.items.count))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.shopDark)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color(red: 230/255, green: 232/255, blue: 238/255), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Saved Products 2-Column Grid

    private var savedProductsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ],
            spacing: 18
        ) {
            ForEach(displayItems) { item in
                ShopSavedProductCard(
                    item: item,
                    onTap: {
                        selectedProductForDetail = item.toMatchedProduct()
                    },
                    onRemove: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                            wishlist.removeFromWishlist(item.canonical_name)
                        }
                    },
                    onMoveToCollection: {
                        itemToMoveInCollection = item
                    },
                    onRemoveFromCollection: item.collectionName == nil ? nil : {
                        withAnimation(.spring(response: 0.25)) {
                            wishlist.moveItem(canonicalName: item.canonical_name, toCollection: nil)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Header Bar (Avatar "L", Search Bar, Bell)

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button(action: { showingAccountSheet = true }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 196/255, green: 181/255, blue: 253/255))
                        .frame(width: 42, height: 42)

                    Text("L")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))

                TextField("Cerca", text: $searchText)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 170/255, green: 170/255, blue: 180/255))
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.white)
            .cornerRadius(22)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
            )

            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                showingNotificationsSheet = true
            }) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 42, height: 42)
                        .overlay(
                            Circle()
                                .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
                        )

                    Image(systemName: "bell.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                        .frame(width: 42, height: 42)

                    if notifManager.unreadCount > 0 {
                        Text("\(min(notifManager.unreadCount, 99))")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 2)
                            .background(Color(red: 228/255, green: 42/255, blue: 38/255))
                            .clipShape(Capsule())
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - All Saved Items Card (Home Base, Always First)

struct ShopAllSavedCard: View {
    let totalCount: Int
    let isSelected: Bool
    let thumbnails: [String]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 7) {
                // Preview Container (132x88)
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color(red: 244/255, green: 244/255, blue: 248/255))
                        .frame(width: 132, height: 88)

                    if !thumbnails.isEmpty {
                        if thumbnails.count == 1, let url = URL(string: thumbnails[0]) {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable()
                                        .scaledToFit()
                                        .padding(6)
                                } else {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(Color(red: 99/255, green: 59/255, blue: 238/255))
                                }
                            }
                            .frame(width: 132, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                        } else {
                            // 2 items collage side by side
                            HStack(spacing: 3) {
                                ForEach(0..<min(thumbnails.count, 2), id: \.self) { idx in
                                    if let url = URL(string: thumbnails[idx]) {
                                        AsyncImage(url: url) { phase in
                                            if let img = phase.image {
                                                img.resizable()
                                                    .scaledToFit()
                                                    .padding(3)
                                            } else {
                                                Color.white
                                            }
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                    }
                                }
                            }
                            .padding(4)
                            .frame(width: 132, height: 88)
                        }
                    } else {
                        VStack {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 26))
                                .foregroundColor(Color(red: 99/255, green: 59/255, blue: 238/255))
                        }
                        .frame(width: 132, height: 88)
                    }

                    // Count Badge
                    Text("\(totalCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white : Color(red: 40/255, green: 40/255, blue: 45/255))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color(red: 99/255, green: 59/255, blue: 238/255) : Color.white)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                        .padding(6)
                }

                // Titles
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tutti i salvati")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? Color(red: 99/255, green: 59/255, blue: 238/255) : Color.shopDark)
                        .lineLimit(1)

                    Text(totalCount == 1 ? "1 articolo" : "\(totalCount) articoli")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Color(red: 130/255, green: 130/255, blue: 138/255))
                }
                .padding(.horizontal, 2)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? Color(red: 99/255, green: 59/255, blue: 238/255).opacity(0.05) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isSelected ? Color(red: 99/255, green: 59/255, blue: 238/255) : Color(red: 235/255, green: 236/255, blue: 240/255),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: isSelected ? Color(red: 99/255, green: 59/255, blue: 238/255).opacity(0.12) : Color.black.opacity(0.03), radius: isSelected ? 6 : 2, x: 0, y: 2)
            .frame(width: 144)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modern Collection Card

struct ShopCollectionCard: View {
    let collection: WishlistCollection
    let isSelected: Bool
    let thumbnails: [String]
    let onTap: () -> Void
    var onManageItems: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 7) {
                // Preview Container (132x88)
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color(red: 244/255, green: 244/255, blue: 248/255))
                        .frame(width: 132, height: 88)

                    if !thumbnails.isEmpty {
                        if thumbnails.count == 1, let url = URL(string: thumbnails[0]) {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable()
                                        .scaledToFit()
                                        .padding(6)
                                } else {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(Color(red: 170/255, green: 170/255, blue: 180/255))
                                }
                            }
                            .frame(width: 132, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                        } else {
                            // 2 items collage side by side
                            HStack(spacing: 3) {
                                ForEach(0..<min(thumbnails.count, 2), id: \.self) { idx in
                                    if let url = URL(string: thumbnails[idx]) {
                                        AsyncImage(url: url) { phase in
                                            if let img = phase.image {
                                                img.resizable()
                                                    .scaledToFit()
                                                    .padding(3)
                                            } else {
                                                Color.white
                                            }
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                    }
                                }
                            }
                            .padding(4)
                            .frame(width: 132, height: 88)
                        }
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 24, weight: .light))
                                .foregroundColor(Color(red: 160/255, green: 160/255, blue: 170/255))
                            Text("Vuota")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Color(red: 160/255, green: 160/255, blue: 170/255))
                        }
                        .frame(width: 132, height: 88)
                    }

                    // Count Badge
                    Text("\(collection.item_count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white : Color(red: 40/255, green: 40/255, blue: 45/255))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color(red: 99/255, green: 59/255, blue: 238/255) : Color.white)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                        .padding(6)
                }

                // Titles
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.name)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? Color(red: 99/255, green: 59/255, blue: 238/255) : Color.shopDark)
                        .lineLimit(1)

                    Text(collection.item_count == 1 ? "1 articolo" : "\(collection.item_count) articoli")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Color(red: 130/255, green: 130/255, blue: 138/255))
                }
                .padding(.horizontal, 2)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? Color(red: 99/255, green: 59/255, blue: 238/255).opacity(0.05) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isSelected ? Color(red: 99/255, green: 59/255, blue: 238/255) : Color(red: 235/255, green: 236/255, blue: 240/255),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: isSelected ? Color(red: 99/255, green: 59/255, blue: 238/255).opacity(0.12) : Color.black.opacity(0.03), radius: isSelected ? 6 : 2, x: 0, y: 2)
            .frame(width: 144)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onManage = onManageItems {
                Button(action: onManage) {
                    Label("Aggiungi o rimuovi articoli", systemImage: "folder.badge.plus")
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

// MARK: - Modern Create Collection Card

struct ShopCreateCollectionCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color(red: 247/255, green: 247/255, blue: 250/255))
                        .frame(width: 132, height: 88)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 38, height: 38)
                        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color(red: 99/255, green: 59/255, blue: 238/255))
                        )
                }

                VStack(spacing: 2) {
                    Text("Crea nuova")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color.shopDark)
                        .lineLimit(1)

                    Text("Collezione")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Color(red: 130/255, green: 130/255, blue: 138/255))
                }
            }
            .padding(6)
            .background(Color.white)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        Color(red: 228/255, green: 230/255, blue: 236/255),
                        style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])
                    )
            )
            .frame(width: 144)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Saved Product Card with Collection Badge & Full Context Menu

struct ShopSavedProductCard: View {
    let item: WishlistItem
    let onTap: () -> Void
    let onRemove: () -> Void
    var onMoveToCollection: (() -> Void)? = nil
    var onRemoveFromCollection: (() -> Void)? = nil

    private var originalPriceToDisplay: Double? {
        if let h = item.highestPrice, h > item.currentBestPrice {
            return h
        }
        if item.initialPrice > item.currentBestPrice {
            return item.initialPrice
        }
        if let disc = item.discountPct, disc > 0 {
            return item.currentBestPrice / (1.0 - (disc / 100.0))
        }
        return nil
    }

    private var discountPercentText: String? {
        if let disc = item.discountPct, disc > 0 {
            return "\(Int(disc.rounded()))% di sconto"
        }
        if let orig = originalPriceToDisplay, orig > item.currentBestPrice {
            let pct = ((orig - item.currentBestPrice) / orig) * 100.0
            if pct >= 5 {
                return "\(Int(pct.rounded()))% di sconto"
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Product Container with Floating Discount Badge, Collection Pill & Translucent Heart Button
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white)
                    .frame(height: 180)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)

                // Product Image
                Button(action: onTap) {
                    ZStack {
                        if let imgUrl = item.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .padding(12)
                                        .frame(maxWidth: .infinity, maxHeight: 180)
                                case .failure:
                                    Image(systemName: "photo")
                                        .font(.system(size: 30))
                                        .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                        .frame(maxWidth: .infinity, maxHeight: 180)
                                case .empty:
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.shopDark)
                                        .frame(maxWidth: .infinity, maxHeight: 180)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        } else {
                            Image(systemName: "shoe.fill")
                                .font(.system(size: 30))
                                .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                .frame(maxWidth: .infinity, maxHeight: 180)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .contentShape(Rectangle())
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)

                // Subtle border matching DealsView and FollowingView
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    .frame(height: 180)

                // Top-Left Badges: Discount Badge + Collection Pill
                VStack(alignment: .leading, spacing: 4) {
                    if let discText = discountPercentText {
                        Text(discText)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color(red: 228/255, green: 42/255, blue: 38/255))
                            .clipShape(Capsule())
                    }

                    if let col = item.collectionName, !col.isEmpty {
                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.impactOccurred()
                            onMoveToCollection?()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 8.5))
                                Text(col)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                            }
                            .foregroundColor(Color(red: 99/255, green: 59/255, blue: 238/255))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color.white.opacity(0.95))
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding([.top, .leading], 9)

                // Bottom-Right Translucent Heart Button (Matching Image 2 & 3)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .medium)
                            gen.impactOccurred()
                            onRemove()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.35))
                                    .frame(width: 32, height: 32)

                                Image(systemName: "heart.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.red)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding([.bottom, .trailing], 9)
                    }
                }
                .frame(height: 180)
            }
            .frame(height: 180)

            // Store Name (e.g. "Top4Running")
            Text(item.bestStore ?? item.brand ?? "Negozio partner")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(red: 120/255, green: 120/255, blue: 125/255))
                .lineLimit(1)
                .padding(.top, 2)

            // Title (Matching Image 2 & 3: 1 line with clean ellipsis)
            Text(item.canonical_name)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                .lineLimit(1)
                .truncationMode(.tail)

            // Price Row: Bold current price + Strikethrough original price (Matching Image 3)
            HStack(spacing: 5) {
                Text(String(format: "%.2f €", item.currentBestPrice).replacingOccurrences(of: ".", with: ","))
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

                if let orig = originalPriceToDisplay, orig > item.currentBestPrice {
                    Text(String(format: "%.2f €", orig).replacingOccurrences(of: ".", with: ","))
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(.shopTextMuted)
                        .strikethrough()
                }
            }

            // Size / Detail (if present)
            if let size = item.selectedSize, !size.isEmpty, size != "Standard" {
                Text(size)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(Color(red: 120/255, green: 120/255, blue: 125/255))
            }
        }
        .contextMenu {
            if let onMove = onMoveToCollection {
                Button(action: onMove) {
                    Label("Organizza in collezione", systemImage: "folder.badge.plus")
                }
            }
            if let onRemoveCol = onRemoveFromCollection {
                Button(action: onRemoveCol) {
                    Label("Rimuovi dalla collezione", systemImage: "folder.badge.minus")
                }
            }
            Button(role: .destructive, action: onRemove) {
                Label("Rimuovi dai salvati", systemImage: "trash")
            }
        }
    }
}

// MARK: - Screen 2: Create Collection Sheet (Matching Reference Image 2)

struct CreateCollectionSheet: View {
    @Binding var isPresented: Bool
    let onSave: (String) -> Void

    @State private var collectionName: String = ""
    @State private var isPrivate: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Top Navigation Bar
            HStack {
                Button("Annulla") {
                    isPresented = false
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.shopDark)

                Spacer()

                Button("Salva") {
                    let trimmed = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    isPresented = false
                    onSave(trimmed)
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(
                    collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? Color(uiColor: .tertiaryLabel)
                    : Color(red: 99/255, green: 59/255, blue: 238/255)
                )
                .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 10)

            // Large Title Input (Image 2: "Nome della collezione")
            TextField("Nome della collezione", text: $collectionName)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
                .padding(.top, 8)

            // Privacy Capsule Toggle (Image 2)
            HStack(spacing: 14) {
                // Capsule Switch
                Button(action: {
                    withAnimation(.spring(response: 0.25)) {
                        isPrivate.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isPrivate ? .white : Color(uiColor: .secondaryLabel))
                            .frame(width: 28, height: 28)
                            .background(isPrivate ? Color.shopDark : Color.clear)
                            .clipShape(Circle())

                        Image(systemName: "globe")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(!isPrivate ? .white : Color(uiColor: .secondaryLabel))
                            .frame(width: 28, height: 28)
                            .background(!isPrivate ? Color.shopDark : Color.clear)
                            .clipShape(Circle())
                    }
                    .padding(4)
                    .background(Color(red: 238/255, green: 238/255, blue: 242/255))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isPrivate ? "Privata" : "Pubblica")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Text(isPrivate ? "Visibile solo a te e ai collaboratori" : "Visibile a chiunque")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.shopTextMuted)
                }
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(20)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Screens 3 & 4: "Aggiungi dai salvati" Sheet (Matching Reference Images 3 & 4)

struct AddToCollectionSheet: View {
    let collectionName: String
    @Binding var isPresented: Bool

    @ObservedObject private var wishlist = WishlistManager.shared
    @State private var selectedItems: Set<String> = []

    private func toggleItem(_ canonicalName: String) {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
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
                    VStack(spacing: 12) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 40))
                            .foregroundColor(Color(red: 170/255, green: 170/255, blue: 180/255))
                        Text("Nessun articolo salvato")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                        Text("Salva prima qualche prodotto nei tuoi preferiti per poterlo organizzare in questa collezione.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.shopTextMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 14),
                                GridItem(.flexible(), spacing: 14)
                            ],
                            spacing: 18
                        ) {
                            ForEach(wishlist.items) { item in
                                let isSelected = selectedItems.contains(item.canonical_name)

                                VStack(alignment: .leading, spacing: 3) {
                                    // Product Image Box with Selection Button
                                    ZStack(alignment: .bottomTrailing) {
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(isSelected ? Color(red: 99/255, green: 59/255, blue: 238/255).opacity(0.06) : Color(red: 243/255, green: 243/255, blue: 246/255))
                                            .frame(height: 168)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18)
                                                    .stroke(
                                                        isSelected ? Color(red: 99/255, green: 59/255, blue: 238/255) : Color.black.opacity(0.05),
                                                        lineWidth: isSelected ? 2 : 1
                                                    )
                                            )

                                        if let imgUrl = item.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                                            AsyncImage(url: url) { phase in
                                                if let img = phase.image {
                                                    img.resizable().scaledToFit().frame(width: 135, height: 135).clipped()
                                                } else {
                                                    Image(systemName: "shoe.fill")
                                                        .font(.system(size: 28))
                                                        .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                                }
                                            }
                                        }

                                        // Badge if currently in another collection
                                        if let otherCol = item.collectionName,
                                           !otherCol.isEmpty,
                                           otherCol.caseInsensitiveCompare(collectionName) != .orderedSame {
                                            VStack {
                                                HStack {
                                                    HStack(spacing: 3) {
                                                        Image(systemName: "folder.fill")
                                                            .font(.system(size: 7.5))
                                                        Text("In \"\(otherCol)\"")
                                                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                                            .lineLimit(1)
                                                    }
                                                    .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(Color.white.opacity(0.95))
                                                    .clipShape(Capsule())
                                                    .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
                                                    Spacer()
                                                }
                                                .padding([.top, .leading], 8)
                                                Spacer()
                                            }
                                        }

                                        // Selection Circle: Gray "+" or Purple Checkmark
                                        Button(action: {
                                            toggleItem(item.canonical_name)
                                        }) {
                                            ZStack {
                                                Circle()
                                                    .fill(
                                                        isSelected
                                                        ? Color(red: 99/255, green: 59/255, blue: 238/255)
                                                        : Color.black.opacity(0.35)
                                                    )
                                                    .frame(width: 34, height: 34)

                                                Image(systemName: isSelected ? "checkmark" : "plus")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .padding([.bottom, .trailing], 9)
                                    }
                                    .frame(height: 168)

                                    // Metadata
                                    Text(item.bestStore ?? item.brand ?? "Negozio")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(.shopTextMuted)
                                        .lineLimit(1)
                                        .padding(.top, 4)

                                    Text(item.canonical_name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                        .lineLimit(1)

                                    HStack(spacing: 2) {
                                        HStack(spacing: 1) {
                                            ForEach(0..<5) { _ in
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.shopDark)
                                            }
                                        }
                                        Text("(55)")
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundColor(.shopTextMuted)
                                    }

                                    Text(String(format: "%.2f €", item.currentBestPrice).replacingOccurrences(of: ".", with: ", "))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopDark)

                                    Text((item.selectedSize ?? "").isEmpty || item.selectedSize == "Standard" ? "Disponibile" : (item.selectedSize ?? "Disponibile"))
                                        .font(.system(size: 11.5, weight: .regular))
                                        .foregroundColor(.shopTextMuted)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    toggleItem(item.canonical_name)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    }
                }
            }
            .navigationTitle("Aggiungi a \(collectionName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.shopDark)
                            .frame(width: 36, height: 36)
                            .background(Color(red: 242/255, green: 242/255, blue: 246/255))
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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color(red: 99/255, green: 59/255, blue: 238/255))
                            .clipShape(Capsule())
                    }
                }
            }
            .onAppear {
                let existing = wishlist.items
                    .filter { $0.collectionName?.caseInsensitiveCompare(collectionName) == .orderedSame }
                    .map { $0.canonical_name }
                selectedItems = Set(existing)
            }
        }
    }
}
