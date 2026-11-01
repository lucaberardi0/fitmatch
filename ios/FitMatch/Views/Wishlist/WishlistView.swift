import SwiftUI

struct WishlistView: View {
    @Binding var selectedTab: Int
    var embedded: Bool = false
    @ObservedObject private var wishlist = WishlistManager.shared
    @StateObject private var api = APIService.shared

    @State private var searchText: String = ""
    @State private var showingAccountSheet: Bool = false
    @State private var showingNotificationsAlert: Bool = false
    @State private var showingFollowedStoresSheet: Bool = false
    @State private var showingCreateCollectionAlert: Bool = false
    @State private var showingDeleteCollectionConfirm: Bool = false
    @State private var newCollectionName: String = ""
    @State private var selectedProductForDetail: MatchedProduct? = nil
    @State private var itemToMove: WishlistItem? = nil
    @State private var selectedCollectionFilter: String = "Tutti"

    init(selectedTab: Binding<Int>? = nil, embedded: Bool = false) {
        self.embedded = embedded
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
                        // MARK: - 1. Pinned Header: Avatar 'L', Search Bar, Bell
                        headerBar
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .padding(.bottom, 10)

                        // MARK: - 2. Nav Pills: Per te, Offerte, Segui già, Salvati
                        navigationPills
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                        mainContent
                    }
                    .background(Color(red: 245/255, green: 246/255, blue: 248/255).ignoresSafeArea())
                }
            }
        }
    }

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        // MARK: - 3. Collections Visual Carousel
                        collectionsCarousel

                        // MARK: - 4. Quick Filter Chips Bar
                        collectionFilterChips

                        // MARK: - 5. Active Filter Banner (when filtered)
                        if selectedCollectionFilter != "Tutti" {
                            activeFilterBanner
                        }

                        // MARK: - 6. Saved Items Grid or Empty State
                        if displayItems.isEmpty {
                            if selectedCollectionFilter != "Tutti" {
                                emptyCollectionState
                                    .padding(.horizontal, 16)
                                    .padding(.top, 10)
                            } else {
                                emptySavedState
                                    .padding(.horizontal, 16)
                                    .padding(.top, 30)
                            }
                        } else {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 14),
                                    GridItem(.flexible(), spacing: 14)
                                ],
                                spacing: 20
                            ) {
                                ForEach(displayItems) { item in
                                    SavedProductCard(
                                        item: item,
                                        onTap: {
                                            selectedProductForDetail = item.toMatchedProduct()
                                        },
                                        onToggleFavorite: {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                                                wishlist.removeFromWishlist(item.canonical_name)
                                            }
                                        },
                                        onMoveCollection: {
                                            itemToMove = item
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        // Space for floating island dock
                        Spacer(minLength: 120)
                    }
                    .padding(.top, 4)
                }
                .refreshable {
                    await wishlist.syncWithDatabase()
                }
                .background(Color(red: 250/255, green: 250/255, blue: 252/255).ignoresSafeArea())
                .navigationBarHidden(true)
                .sheet(isPresented: $showingAccountSheet) {
                    AccountView()
                }
                .sheet(isPresented: $showingFollowedStoresSheet) {
                    NavigationStack {
                        FollowingView()
                            .navigationTitle("Negozi Seguiti")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .sheet(item: $selectedProductForDetail) { product in
                    ProductDetailView(product: product)
                }
                .sheet(item: $itemToMove) { item in
                    MoveToCollectionSheet(item: item)
                }
                .alert("Nuova Collezione", isPresented: $showingCreateCollectionAlert) {
                    TextField("Es. Sneakers, Running, Estate...", text: $newCollectionName)
                    Button("Annulla", role: .cancel) { newCollectionName = "" }
                    Button("Crea") {
                        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            wishlist.createCollection(name: trimmed)
                            withAnimation(.spring(response: 0.3)) {
                                selectedCollectionFilter = trimmed
                            }
                            newCollectionName = ""
                        }
                    }
                } message: {
                    Text("Crea una raccolta per organizzare i tuoi articoli salvati.")
                }
                .alert("Elimina Collezione", isPresented: $showingDeleteCollectionConfirm) {
                    Button("Annulla", role: .cancel) { }
                    Button("Elimina", role: .destructive) {
                        let name = selectedCollectionFilter
                        wishlist.deleteCollection(name: name)
                        withAnimation(.spring(response: 0.3)) {
                            selectedCollectionFilter = "Tutti"
                        }
                    }
                } message: {
                    Text("Vuoi eliminare '\(selectedCollectionFilter)'? Gli articoli rimarranno comunque tra i salvati.")
                }
                .alert("Notifiche Attive", isPresented: $showingNotificationsAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Riceverai avvisi e notifiche push appena i prezzi dei tuoi articoli preferiti scendono.")
                }
    }

    // MARK: - Header Bar (Avatar "L", Search Bar, Bell)

    private var headerBar: some View {
        HStack(spacing: 12) {
            // User Avatar (Purple circle with 'L')
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

            // Search Bar ("Cerca")
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

            // Bell Button
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

    // MARK: - Navigation Pills (Per te, Offerte, Segui già, Salvati)

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
                Text("Offerte")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 50/255, green: 50/255, blue: 55/255))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: {
                showingFollowedStoresSheet = true
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
            .frame(width: 90, height: 38)
        }
    }

    // MARK: - Collections Visual Carousel

    private var collectionsCarousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Text("Collezioni")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 20/255, green: 20/255, blue: 25/255))

                    Text("\(wishlist.getAvailableCollections().count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 92/255, green: 60/255, blue: 245/255))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Color(red: 242/255, green: 240/255, blue: 254/255))
                        .clipShape(Capsule())
                }

                Spacer()

                Button(action: { showingCreateCollectionAlert = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Nuova")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Color(red: 92/255, green: 60/255, blue: 245/255))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 245/255, green: 243/255, blue: 255/255))
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(wishlist.getAvailableCollections()) { col in
                        CollectionCard(
                            collection: col,
                            isSelected: selectedCollectionFilter.caseInsensitiveCompare(col.name) == .orderedSame,
                            thumbnails: wishlist.getThumbnails(for: col.name, limit: 3),
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    selectedCollectionFilter = col.name
                                }
                            }
                        )
                    }

                    CreateCollectionCard {
                        showingCreateCollectionAlert = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Quick Filter Chips Bar

    private var collectionFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(wishlist.getAvailableCollections()) { col in
                    let isSelected = selectedCollectionFilter.caseInsensitiveCompare(col.name) == .orderedSame

                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedCollectionFilter = col.name
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: iconName(for: col.name))
                                .font(.system(size: 11, weight: .bold))

                            Text(col.name)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))

                            Text("\(col.item_count)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isSelected ? Color.white.opacity(0.25) : Color(red: 235/255, green: 235/255, blue: 240/255))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isSelected ? Color(red: 92/255, green: 60/255, blue: 245/255) : Color.white)
                        .foregroundColor(isSelected ? .white : Color(red: 40/255, green: 40/255, blue: 50/255))
                        .cornerRadius(18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(isSelected ? Color.clear : Color(red: 230/255, green: 230/255, blue: 235/255), lineWidth: 1)
                        )
                        .shadow(color: isSelected ? Color(red: 92/255, green: 60/255, blue: 245/255).opacity(0.22) : Color.black.opacity(0.02), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Active Filter Banner

    private var activeFilterBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName(for: selectedCollectionFilter))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(red: 92/255, green: 60/255, blue: 245/255))

            Text(selectedCollectionFilter)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

            Text("(\(displayItems.count) \(displayItems.count == 1 ? "prodotto" : "prodotti"))")
                .font(.system(size: 12))
                .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))

            Spacer()

            // Trash icon if not a system default collection
            if !WishlistManager.defaultCollectionNames.contains(where: { $0.caseInsensitiveCompare(selectedCollectionFilter) == .orderedSame }) {
                Button(action: {
                    showingDeleteCollectionConfirm = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 220/255, green: 50/255, blue: 60/255))
                        .padding(6)
                        .background(Color(red: 255/255, green: 240/255, blue: 240/255))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Show all button
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    selectedCollectionFilter = "Tutti"
                }
            }) {
                HStack(spacing: 4) {
                    Text("Mostra tutti")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(Color(red: 92/255, green: 60/255, blue: 245/255))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(red: 242/255, green: 240/255, blue: 254/255))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.white)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Empty States

    private var emptyCollectionState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(red: 245/255, green: 243/255, blue: 255/255))
                    .frame(width: 80, height: 80)

                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 32))
                    .foregroundColor(Color(red: 92/255, green: 60/255, blue: 245/255))
            }

            VStack(spacing: 6) {
                Text("Nessun articolo in '\(selectedCollectionFilter)'")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

                Text("Puoi spostare i tuoi articoli salvati in questa raccolta toccando l'etichetta della cartella su ciascun prodotto.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        selectedCollectionFilter = "Tutti"
                    }
                }) {
                    Text("Mostra tutti i salvati")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color(red: 92/255, green: 60/255, blue: 245/255))
                        .cornerRadius(20)
                }

                if !WishlistManager.defaultCollectionNames.contains(where: { $0.caseInsensitiveCompare(selectedCollectionFilter) == .orderedSame }) {
                    Button(action: {
                        showingDeleteCollectionConfirm = true
                    }) {
                        Text("Elimina")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(red: 220/255, green: 50/255, blue: 60/255))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(red: 255/255, green: 240/255, blue: 240/255))
                            .cornerRadius(20)
                    }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var emptySavedState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(red: 237/255, green: 233/255, blue: 254/255))
                    .frame(width: 80, height: 80)

                Image(systemName: "heart.slash")
                    .font(.system(size: 34))
                    .foregroundColor(Color(red: 109/255, green: 40/255, blue: 217/255))
            }

            VStack(spacing: 6) {
                Text("Nessun articolo salvato")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

                Text("Tocca l'icona del cuore sui prodotti per monitorare prezzi e offerte in tempo reale dal database.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button(action: {
                Task {
                    await wishlist.syncWithDatabase()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Carica dal Database")
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color(red: 92/255, green: 60/255, blue: 245/255))
                .cornerRadius(20)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func iconName(for name: String) -> String {
        switch name.lowercased() {
        case "tutti": return "star.fill"
        case "scarpe da corsa": return "figure.run"
        case "smartwatch & gps": return "applewatch"
        case "trail & outdoor": return "mountain.2.fill"
        case "offerte speciali": return "tag.fill"
        default: return "folder.fill"
        }
    }
}

// MARK: - Collection Carousel Card

struct CollectionCard: View {
    let collection: WishlistCollection
    let isSelected: Bool
    let thumbnails: [String]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Top Row: Icon + Count Pill
                HStack {
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(isSelected ? 0.22 : 0.12))
                            .frame(width: 32, height: 32)

                        Image(systemName: iconName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(iconColor)
                    }

                    Spacer()

                    Text("\(collection.item_count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white : Color(red: 90/255, green: 90/255, blue: 100/255))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(isSelected ? Color(red: 92/255, green: 60/255, blue: 245/255) : Color(red: 236/255, green: 237/255, blue: 242/255))
                        .clipShape(Capsule())
                }

                // Middle: Visual Collage of Saved Items
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 248/255, green: 249/255, blue: 251/255))
                        .frame(height: 62)

                    if thumbnails.isEmpty {
                        VStack(spacing: 2) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 15))
                                .foregroundColor(Color(red: 185/255, green: 185/255, blue: 198/255))
                            Text("Vuota")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundColor(Color(red: 160/255, green: 160/255, blue: 175/255))
                        }
                    } else {
                        HStack(spacing: -12) {
                            ForEach(Array(thumbnails.prefix(3).enumerated()), id: \.offset) { index, urlStr in
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 42, height: 42)
                                        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)

                                    if let url = URL(string: urlStr) {
                                        AsyncImage(url: url) { phase in
                                            if let img = phase.image {
                                                img.resizable().scaledToFit().padding(4)
                                            } else {
                                                Image(systemName: "shoe.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(Color(red: 200/255, green: 200/255, blue: 210/255))
                                            }
                                        }
                                    } else {
                                        Image(systemName: "shoe.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(red: 200/255, green: 200/255, blue: 210/255))
                                    }
                                }
                                .zIndex(Double(3 - index))
                            }
                        }
                    }
                }

                // Bottom: Collection Name
                Text(collection.name)
                    .font(.system(size: 13, weight: isSelected ? .bold : .semibold, design: .rounded))
                    .foregroundColor(Color(red: 20/255, green: 20/255, blue: 25/255))
                    .lineLimit(1)
            }
            .padding(12)
            .frame(width: 154, height: 146)
            .background(Color.white)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isSelected ? Color(red: 92/255, green: 60/255, blue: 245/255) : Color(red: 232/255, green: 233/255, blue: 238/255),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? Color(red: 92/255, green: 60/255, blue: 245/255).opacity(0.16) : Color.black.opacity(0.03),
                radius: isSelected ? 8 : 4,
                y: 2
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch collection.name.lowercased() {
        case "tutti": return "star.fill"
        case "scarpe da corsa": return "figure.run"
        case "smartwatch & gps": return "applewatch"
        case "trail & outdoor": return "mountain.2.fill"
        case "offerte speciali": return "tag.fill"
        default: return "folder.fill"
        }
    }

    private var iconColor: Color {
        switch collection.name.lowercased() {
        case "tutti": return Color(red: 92/255, green: 60/255, blue: 245/255)
        case "scarpe da corsa": return Color(red: 245/255, green: 110/255, blue: 40/255)
        case "smartwatch & gps": return Color(red: 40/255, green: 130/255, blue: 245/255)
        case "trail & outdoor": return Color(red: 34/255, green: 160/255, blue: 95/255)
        case "offerte speciali": return Color(red: 230/255, green: 50/255, blue: 80/255)
        default: return Color(red: 120/255, green: 70/255, blue: 240/255)
        }
    }
}

// MARK: - Create Collection Card (in Carousel)

struct CreateCollectionCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color(red: 245/255, green: 243/255, blue: 255/255))
                        .frame(width: 44, height: 44)

                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(red: 92/255, green: 60/255, blue: 245/255))
                }

                Text("Nuova Raccolta")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 92/255, green: 60/255, blue: 245/255))

                Spacer()
            }
            .frame(width: 140, height: 146)
            .background(Color(red: 252/255, green: 251/255, blue: 255/255))
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        Color(red: 92/255, green: 60/255, blue: 245/255).opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Saved Product Card (Exact Match to Reference Screenshot + Collection Tag)

struct SavedProductCard: View {
    let item: WishlistItem
    let onTap: () -> Void
    let onToggleFavorite: () -> Void
    let onMoveCollection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: Image Box Container
            ZStack {
                // Background Rounded Card
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(red: 243/255, green: 244/255, blue: 247/255))
                    .frame(height: 195)

                // Product Image
                Group {
                    if let urlStr = item.image_url, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .padding(14)
                            case .failure:
                                Image(systemName: "shoe.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(Color(red: 200/255, green: 200/255, blue: 210/255))
                            case .empty:
                                ProgressView()
                                    .tint(Color(red: 92/255, green: 60/255, blue: 245/255))
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "shoe.fill")
                            .font(.system(size: 40))
                            .foregroundColor(Color(red: 200/255, green: 200/255, blue: 210/255))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: 195)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            .overlay(alignment: .topLeading) {
                // Top-Left Discount Badge ("23% di sconto")
                if let discountText = item.discountBadgeText {
                    Text(discountText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(Capsule().fill(Color.black))
                        .padding(.top, 10)
                        .padding(.leading, 10)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Bottom-Right Purple Heart Button
                Button(action: {
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    onToggleFavorite()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 92/255, green: 60/255, blue: 245/255))
                            .frame(width: 34, height: 34)
                            .shadow(color: Color(red: 92/255, green: 60/255, blue: 245/255).opacity(0.35), radius: 5, y: 2)

                        Image(systemName: "heart.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                .padding(.bottom, 10)
            }

            // MARK: Text Information Below Image
            VStack(alignment: .leading, spacing: 3) {
                // Store / Brand Name (e.g. SneakerAsk, Kith, Maxi Sport)
                Text(item.bestStore ?? item.brand ?? "Partner Store")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(red: 115/255, green: 115/255, blue: 125/255))
                    .lineLimit(1)

                // Product Title (e.g. Maison Mihara Yasuhiro Hank, Nuovo Balance 740)
                Text(item.canonical_name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 20/255, green: 20/255, blue: 25/255))
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Price Row: Bold current price + Strikethrough original price
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.formattedCurrentPrice)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(Color(red: 20/255, green: 20/255, blue: 25/255))

                    if let originalPriceText = item.formattedInitialPrice {
                        Text(originalPriceText)
                            .font(.system(size: 12.5, weight: .regular))
                            .strikethrough(true, color: Color(red: 140/255, green: 140/255, blue: 150/255))
                            .foregroundColor(Color(red: 140/255, green: 140/255, blue: 150/255))
                    }
                }

                // Size Tag (e.g. 36 EU, 7.5, 42 EU)
                if let size = item.selectedSize, !size.isEmpty {
                    Text(size)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }

            // Collection Tag Capsule (Tappable to change/move collection)
            Button(action: {
                onMoveCollection()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(item.collectionName ?? "Tutti")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(Color(red: 92/255, green: 60/255, blue: 245/255))
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color(red: 245/255, green: 243/255, blue: 255/255))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
        }
        .contextMenu {
            Button {
                onMoveCollection()
            } label: {
                Label("Organizza in collezione...", systemImage: "folder.badge.gearshape")
            }
            Button(role: .destructive) {
                onToggleFavorite()
            } label: {
                Label("Rimuovi dai Salvati", systemImage: "heart.slash")
            }
        }
    }
}

// MARK: - Extension to Convert WishlistItem to MatchedProduct

extension WishlistItem {
    func toMatchedProduct() -> MatchedProduct {
        let dummyOffer = Offer(
            store_id: bestStore?.lowercased().replacingOccurrences(of: " ", with: "") ?? "store",
            store_name: bestStore ?? "Store Partner",
            product_id: nil,
            title: canonical_name,
            brand: brand,
            price: currentBestPrice,
            original_price: initialPrice,
            discount_pct: discountPct,
            savings: (initialPrice > currentBestPrice) ? (initialPrice - currentBestPrice) : nil,
            url: bestStoreUrl ?? "https://fitmatch.it",
            image_url: image_url,
            available_sizes: selectedSize != nil ? [selectedSize!] : nil,
            in_stock: true,
            shipping_cost: 0.0,
            total_price: currentBestPrice,
            is_free_shipping: true,
            shipping_label: "Spedizione Gratuita",
            free_shipping_threshold: 50.0,
            courier: "Corriere Espresso"
        )
        return MatchedProduct(
            canonical_name: canonical_name,
            brand: brand,
            image_url: image_url,
            offers: [dummyOffer],
            best_price: currentBestPrice,
            highest_price: highestPrice ?? initialPrice,
            cross_store_savings: (initialPrice > currentBestPrice) ? (initialPrice - currentBestPrice) : nil
        )
    }
}
