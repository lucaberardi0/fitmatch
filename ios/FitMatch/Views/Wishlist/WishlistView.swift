import SwiftUI

struct WishlistView: View {
    @Binding var selectedTab: Int
    var embedded: Bool = false
    var onSelectPerTe: (() -> Void)? = nil

    @ObservedObject private var wishlist = WishlistManager.shared
    @StateObject private var api = APIService.shared

    @State private var searchText: String = ""
    @State private var showingAccountSheet: Bool = false
    @State private var showingNotificationsAlert: Bool = false
    @State private var showingCreateCollectionSheet: Bool = false
    @State private var showingAddToCollectionSheet: Bool = false
    @State private var newlyCreatedCollectionName: String = ""
    @State private var selectedProductForDetail: MatchedProduct? = nil
    @State private var selectedCollectionFilter: String = "Tutti"

    init(selectedTab: Binding<Int>? = nil, embedded: Bool = false, onSelectPerTe: (() -> Void)? = nil) {
        self.embedded = embedded
        self.onSelectPerTe = onSelectPerTe
        if let tab = selectedTab {
            self._selectedTab = tab
        } else {
            self._selectedTab = .constant(3)
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

                        navigationPills
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                        mainContent
                    }
                    .background(Color(red: 250/255, green: 250/255, blue: 252/255).ignoresSafeArea())
                }
            }
        }
        .sheet(isPresented: $showingAccountSheet) {
            AccountView()
        }
        .sheet(item: $selectedProductForDetail) { product in
            ProductDetailView(product: product)
        }
        .sheet(isPresented: $showingCreateCollectionSheet) {
            CreateCollectionSheet(
                isPresented: $showingCreateCollectionSheet,
                onSave: { name in
                    newlyCreatedCollectionName = name
                    wishlist.createCollection(name: name)
                    withAnimation(.spring(response: 0.3)) {
                        selectedCollectionFilter = name
                    }
                    if !wishlist.items.isEmpty {
                        showingAddToCollectionSheet = true
                    }
                }
            )
        }
        .sheet(isPresented: $showingAddToCollectionSheet) {
            AddToCollectionSheet(
                collectionName: newlyCreatedCollectionName,
                isPresented: $showingAddToCollectionSheet
            )
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if wishlist.items.isEmpty {
                    // MARK: - Screen 1: Empty State (Matching reference Image 1)
                    emptySavedState
                        .padding(.top, 40)
                } else {
                    // MARK: - Screen 5: Active Collections & Saved Items (Matching reference Image 5)
                    // 1. Collections Section Header & Horizontal Carousel
                    collectionsSection
                        .padding(.top, 4)

                    // 2. Active Collection Filter Tag (if filtered)
                    if selectedCollectionFilter != "Tutti" {
                        activeCollectionFilterPill
                            .padding(.horizontal, 16)
                    }

                    // 3. Saved Products 2-Column Grid
                    if displayItems.isEmpty {
                        emptyFilteredState
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                    } else {
                        savedProductsGrid
                            .padding(.horizontal, 16)
                    }
                }

                Spacer(minLength: 120)
            }
        }
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

    // MARK: - Screen 5: Collections Carousel (Matching Reference Image 5)

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: "Collezioni >" on left, "+" on right
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.25)) {
                        selectedCollectionFilter = "Tutti"
                    }
                }) {
                    HStack(spacing: 6) {
                        Text("Collezioni")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 120/255, green: 120/255, blue: 125/255))
                            .frame(width: 22, height: 22)
                            .background(Color(red: 240/255, green: 240/255, blue: 244/255))
                            .clipShape(Circle())
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    showingCreateCollectionSheet = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundColor(.shopDark)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            // Horizontal Scroll of Collection Cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(wishlist.getAvailableCollections()) { col in
                        let isSelected = selectedCollectionFilter.caseInsensitiveCompare(col.name) == .orderedSame
                        let thumb = wishlist.getThumbnails(for: col.name, limit: 1).first

                        ShopCollectionCard(
                            collection: col,
                            isSelected: isSelected,
                            thumbnailUrl: thumb,
                            onTap: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    if isSelected {
                                        selectedCollectionFilter = "Tutti"
                                    } else {
                                        selectedCollectionFilter = col.name
                                    }
                                }
                            }
                        )
                    }

                    // "Crea collezione" Card
                    ShopCreateCollectionCard {
                        showingCreateCollectionSheet = true
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // Active collection filter pill
    private var activeCollectionFilterPill: some View {
        HStack(spacing: 8) {
            Text("Filtro: \(selectedCollectionFilter)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            Spacer()

            Button("Mostra tutti") {
                withAnimation(.spring(response: 0.25)) {
                    selectedCollectionFilter = "Tutti"
                }
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(Color(red: 99/255, green: 59/255, blue: 238/255))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    // Empty filtered state
    private var emptyFilteredState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 36))
                .foregroundColor(.shopTextMuted)
            Text("Nessun articolo salvato in '\(selectedCollectionFilter)'")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.shopDark)
            Button("Aggiungi articoli") {
                newlyCreatedCollectionName = selectedCollectionFilter
                showingAddToCollectionSheet = true
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(Color(red: 99/255, green: 59/255, blue: 238/255))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Saved Products 2-Column Grid (Matching Reference Image 5)

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

                TextField("Cerca nei salvati", text: $searchText)
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

            Button(action: { showingNotificationsAlert = true }) {
                ZStack {
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
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Navigation Pills

    private var navigationPills: some View {
        HStack(spacing: 4) {
            Button(action: {
                withAnimation(.spring(response: 0.25)) { selectedTab = 0 }
            }) {
                Text("Per te")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 50/255, green: 50/255, blue: 55/255))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.25)) { selectedTab = 2 }
            }) {
                Text("Saldi per le feste")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 50/255, green: 50/255, blue: 55/255))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.25)) { selectedTab = 0 }
            }) {
                Text("Segui già")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 50/255, green: 50/255, blue: 55/255))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Spacer()

            // Active Pill
            ZStack {
                Capsule()
                    .fill(Color.white)
                    .overlay(
                        Capsule()
                            .stroke(Color(red: 230/255, green: 230/255, blue: 235/255), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)

                Text("Salvati")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 20/255, green: 20/255, blue: 25/255))
            }
            .frame(width: 86, height: 38)
        }
    }
}

// MARK: - Collection Card (Matching Reference Image 5)

struct ShopCollectionCard: View {
    let collection: WishlistCollection
    let isSelected: Bool
    let thumbnailUrl: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 243/255, green: 243/255, blue: 246/255))
                    .frame(width: 165, height: 170)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(
                                isSelected ? Color(red: 99/255, green: 59/255, blue: 238/255) : Color.black.opacity(0.04),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )

                // Centered white tilted card with item preview
                VStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white)
                            .frame(width: 88, height: 88)
                            .shadow(color: Color.black.opacity(0.06), radius: 5, x: 0, y: 2)

                        if let thumb = thumbnailUrl, let url = URL(string: thumb), !thumb.isEmpty {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFit().padding(6)
                                } else {
                                    Image(systemName: "shoe.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(Color(red: 190/255, green: 190/255, blue: 200/255))
                                }
                            }
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 26))
                                .foregroundColor(Color(red: 190/255, green: 190/255, blue: 200/255))
                        }
                    }
                    .padding(.top, 16)

                    Spacer()
                }
                .frame(width: 165, height: 170)

                // Collection Name in Bottom-Left
                Text(collection.name)
                    .font(.system(size: 16.5, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)
                    .padding(14)
            }
            .frame(width: 165, height: 170)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Create Collection Card (Matching Reference Image 5)

struct ShopCreateCollectionCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 243/255, green: 243/255, blue: 246/255))
                    .frame(width: 165, height: 170)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                    )

                // Centered plus icon and title
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.shopDark)

                    Text("Crea collezione")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.shopDark)
                    Spacer()
                }
                .frame(width: 165, height: 170)

                // Faint thumbnail in corner
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 26, height: 26)
                        .shadow(color: Color.black.opacity(0.05), radius: 2)
                }
                .padding([.bottom, .leading], 12)
            }
            .frame(width: 165, height: 170)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Saved Product Card (Matching Reference Image 5)

struct ShopSavedProductCard: View {
    let item: WishlistItem
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Product Container with Purple Heart Badge
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 243/255, green: 243/255, blue: 246/255))
                    .frame(height: 168)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                    )

                // Product Image
                Button(action: onTap) {
                    VStack {
                        Spacer()
                        if let imgUrl = item.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFit().frame(width: 140, height: 140).clipped()
                                } else {
                                    Image(systemName: "shoe.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                }
                            }
                        } else {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 28))
                                .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)

                // Purple Heart Badge (Matching Reference Image 5)
                Button(action: onRemove) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 99/255, green: 59/255, blue: 238/255))
                            .frame(width: 34, height: 34)
                            .shadow(color: Color(red: 99/255, green: 59/255, blue: 238/255).opacity(0.3), radius: 3, x: 0, y: 1)

                        Image(systemName: "heart.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding([.bottom, .trailing], 9)
            }
            .frame(height: 168)

            // Store Name (Image 5: "The Closet Inc.")
            Text(item.bestStore ?? item.brand ?? "Negozio partner")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(red: 120/255, green: 120/255, blue: 125/255))
                .lineLimit(1)
                .padding(.top, 4)

            // Title (Image 5: 1 line truncated)
            Text(item.canonical_name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                .lineLimit(1)
                .truncationMode(.tail)

            // Price (Image 5: Bold)
            Text(String(format: "%.2f €", item.currentBestPrice).replacingOccurrences(of: ".", with: ","))
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

            // Size / Detail (Image 5: "8")
            Text((item.selectedSize ?? "").isEmpty || item.selectedSize == "Standard" ? "Disponibile" : (item.selectedSize ?? "Disponibile"))
                .font(.system(size: 11.5, weight: .regular))
                .foregroundColor(Color(red: 130/255, green: 130/255, blue: 135/255))
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

    var body: some View {
        NavigationStack {
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
                                    .fill(Color(red: 243/255, green: 243/255, blue: 246/255))
                                    .frame(height: 168)

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

                                // Selection Circle: Gray "+" (Image 3) or Purple Checkmark (Image 4)
                                Button(action: {
                                    let gen = UIImpactFeedbackGenerator(style: .light)
                                    gen.impactOccurred()
                                    withAnimation(.spring(response: 0.25)) {
                                        if isSelected {
                                            selectedItems.remove(item.canonical_name)
                                        } else {
                                            selectedItems.insert(item.canonical_name)
                                        }
                                    }
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

                            // Metadata matching Images 3 & 4
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
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
            .navigationTitle("Aggiungi dai salvati")
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
                        // Assign selected items to collection in Supabase & locally
                        for canonical in selectedItems {
                            wishlist.moveItem(canonicalName: canonical, toCollection: collectionName)
                        }
                        isPresented = false
                    }) {
                        Text("Fatto")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color(red: 242/255, green: 242/255, blue: 246/255))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}
