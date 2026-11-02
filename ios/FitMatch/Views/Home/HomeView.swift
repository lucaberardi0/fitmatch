import SwiftUI

enum HomeSubTab: Int, CaseIterable {
    case perTe = 0
    case offerte = 1
    case seguiGia = 2
    case salvati = 3

    var title: String {
        switch self {
        case .perTe: return "Per te"
        case .offerte: return "Offerte"
        case .seguiGia: return "Segui già"
        case .salvati: return "Salvati"
        }
    }
}

struct HomeView: View {
    @Binding var selectedTab: Int
    var initialSubTab: HomeSubTab = .perTe
    @State private var activeSubTab: HomeSubTab

    init(selectedTab: Binding<Int>, initialSubTab: HomeSubTab = .perTe) {
        self._selectedTab = selectedTab
        self.initialSubTab = initialSubTab
        self._activeSubTab = State(initialValue: initialSubTab)
    }

    @StateObject private var api = APIService.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var recentManager = RecentActivityManager.shared

    @State private var showcases: [StoreShowcase] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var showingAccountSheet = false
    @State private var showingNotificationsAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - 1. Pinned Top Header: Avatar "L" | Search Bar "Cerca" | Bell
                topHeaderBar
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                // MARK: - 2. Sub-Navigation Pills: Per te | Offerte | Segui già | Salvati
                subNavigationPills
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // MARK: - 3. Content Area based on Active Sub-Tab
                Group {
                    switch activeSubTab {
                    case .perTe:
                        perTeContent
                    case .offerte:
                        DealsView(embedded: true, onSelectPerTe: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                activeSubTab = .perTe
                            }
                        })
                    case .seguiGia:
                        FollowingView(onGoShopping: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                activeSubTab = .perTe
                            }
                        })
                    case .salvati:
                        WishlistView(selectedTab: $selectedTab, embedded: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(red: 245/255, green: 246/255, blue: 248/255).ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAccountSheet) {
                AccountView()
            }
            .alert("Notifiche Attive", isPresented: $showingNotificationsAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Riceverai avvisi e notifiche push appena i prezzi dei tuoi articoli e brand seguiti scendono.")
            }
            .task {
                if showcases.isEmpty {
                    await fetchShowcases()
                }
            }
        }
    }

    // MARK: - Top Header Bar (Screenshot 1: Avatar "L" | Search "Cerca" | Bell)

    private var topHeaderBar: some View {
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

            // Search Bar Capsule ("Cerca")
            NavigationLink(destination: SearchView()) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(red: 135/255, green: 135/255, blue: 145/255))

                    Text("Cerca")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(Color(red: 135/255, green: 135/255, blue: 145/255))

                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white)
                .cornerRadius(22)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Bell Notifications Button
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

    // MARK: - Sub-Navigation Pills (Screenshot 1: Per te | Offerte | Segui già | Salvati)

    private var subNavigationPills: some View {
        HStack(spacing: 6) {
            ForEach(HomeSubTab.allCases, id: \.self) { tab in
                Button(action: {
                    let gen = UIImpactFeedbackGenerator(style: .light)
                    gen.impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        activeSubTab = tab
                    }
                }) {
                    Text(tab.title)
                        .font(.system(size: 14, weight: activeSubTab == tab ? .bold : .medium, design: .rounded))
                        .foregroundColor(activeSubTab == tab ? Color(red: 20/255, green: 20/255, blue: 25/255) : Color(red: 90/255, green: 90/255, blue: 100/255))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(activeSubTab == tab ? Color.white : Color.clear)
                                .shadow(color: activeSubTab == tab ? Color.black.opacity(0.04) : Color.clear, radius: 4, x: 0, y: 1)
                        )
                        .overlay(
                            activeSubTab == tab ?
                                Capsule()
                                    .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
                                : nil
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if tab != .salvati {
                    Spacer()
                }
            }
        }
    }

    // MARK: - "Per te" Feed Content (100% Real Database Stores & Products)

    private var perTeContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // 1. "Elementi salvati" Preview Card (Real saved items or real top database picks)
                savedItemsPreviewCard
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                // 2. "Visti di recente" Preview Card
                recentlyViewedPreviewCard
                    .padding(.horizontal, 16)

                // 3. Real Database Partner Stores from Supabase & API
                if isLoading && showcases.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.shopDark)
                        Text("Caricamento negozi e offerte dal database...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(Array(showcases.filter { !$0.products.isEmpty }.enumerated()), id: \.element.id) { index, sc in
                        if index == 1 {
                            // Deep Slate Accent Card for visual cadence (using real store & products)
                            darkAccentShopStoreCard(showcase: sc)
                                .padding(.horizontal, 16)
                        } else {
                            // Clean White Shop Card (using real store & products)
                            genericShopStoreCard(showcase: sc)
                                .padding(.horizontal, 16)
                        }
                    }
                }

                Spacer(minLength: 120)
            }
        }
        .refreshable {
            await fetchShowcases()
        }
    }

    // MARK: - 1. "Elementi salvati" Section (100% Real Database Wishlist)

    private var savedItemsPreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Icon + Title + Count Pill + Chevron Button
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(red: 254/255, green: 226/255, blue: 226/255))
                        .frame(width: 34, height: 34)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255))
                }

                Text("Elementi salvati")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)

                if !wishlist.items.isEmpty {
                    Text("\(wishlist.items.count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 220/255, green: 38/255, blue: 38/255))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(red: 254/255, green: 242/255, blue: 242/255))
                        .clipShape(Capsule())
                }

                Spacer()

                Button(action: {
                    let gen = UIImpactFeedbackGenerator(style: .light)
                    gen.impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        activeSubTab = .salvati
                    }
                }) {
                    Circle()
                        .fill(Color(red: 244/255, green: 245/255, blue: 248/255))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(red: 70/255, green: 70/255, blue: 75/255))
                        )
                }
                .buttonStyle(.plain)
            }

            // Real Content: Products or Clean Empty State
            if !wishlist.items.isEmpty {
                HStack(spacing: 10) {
                    let items = Array(wishlist.items.prefix(3))
                    ForEach(items) { item in
                        NavigationLink(destination: ProductDetailView(product: item.toMatchedProduct())) {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .bottomLeading) {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(red: 245/255, green: 246/255, blue: 249/255))
                                        .aspectRatio(1.0, contentMode: .fit)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.black.opacity(0.04), lineWidth: 1)
                                        )

                                    if let imgUrl = item.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                                        AsyncImage(url: url) { phase in
                                            if let img = phase.image {
                                                img
                                                    .resizable()
                                                    .scaledToFit()
                                                    .padding(8)
                                            } else {
                                                Image(systemName: "tag.fill")
                                                    .font(.system(size: 24))
                                                    .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                                            }
                                        }
                                    } else {
                                        Image(systemName: "bag.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                    }

                                    // Floating Price Pill
                                    Text(item.formattedCurrentPrice)
                                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.white.opacity(0.94))
                                        .clipShape(Capsule())
                                        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                                        .padding(6)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 16))

                                VStack(alignment: .leading, spacing: 2) {
                                    if let brand = item.brand, !brand.isEmpty {
                                        Text(brand.uppercased())
                                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                            .foregroundColor(.shopTextMuted)
                                            .lineLimit(1)
                                    }

                                    Text(item.canonical_name)
                                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                        .foregroundColor(.shopDark)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 28, alignment: .topLeading)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Fill remaining slots if less than 3
                    if items.count < 3 {
                        ForEach(0..<(3 - items.count), id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 6) {
                                Button(action: {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                        activeSubTab = .offerte
                                    }
                                }) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                            .foregroundColor(Color(red: 215/255, green: 218/255, blue: 226/255))
                                            .aspectRatio(1.0, contentMode: .fit)

                                        VStack(spacing: 4) {
                                            Image(systemName: "plus")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.shopTextMuted)
                                            Text("Aggiungi")
                                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                                .foregroundColor(.shopTextMuted)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer()
                                    .frame(height: 28)
                            }
                        }
                    }
                }
            } else {
                // Honest, Clean Empty State (No Fake Data)
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 254/255, green: 242/255, blue: 242/255))
                            .frame(width: 44, height: 44)

                        Image(systemName: "heart")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nessun articolo salvato ancora")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Text("Tocca l'icona del cuore sui prodotti per monitorare sconti e ribassi di prezzo in tempo reale.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.shopTextMuted)
                            .lineLimit(2)
                    }

                    Spacer()

                    Button(action: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            activeSubTab = .offerte
                        }
                    }) {
                        Text("Esplora")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.shopPurple)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.shopPurpleLight)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Color(red: 249/255, green: 250/255, blue: 252/255))
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(red: 238/255, green: 240/255, blue: 245/255), lineWidth: 1)
                )
            }
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 3)
    }

    // MARK: - 2. "Visti di recente" Section (100% Real User History)

    private var previewRecentProducts: [MatchedProduct] {
        let productActivities = recentManager.activities.compactMap { act -> MatchedProduct? in
            guard act.type == .product else { return nil }
            return act.productData
        }

        var seen = Set<String>()
        var unique: [MatchedProduct] = []
        for p in productActivities {
            let key = p.canonical_name.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(enrichMatchedProduct(p))
            }
        }
        return Array(unique.prefix(3))
    }

    private func enrichMatchedProduct(_ prod: MatchedProduct) -> MatchedProduct {
        if !prod.offers.isEmpty { return prod }
        for sc in showcases {
            if let found = sc.products.first(where: {
                $0.canonical_name.caseInsensitiveCompare(prod.canonical_name) == .orderedSame || $0.id == prod.id
            }) {
                return found.toMatchedProduct(storeId: sc.store_id, storeName: sc.store_name)
            }
        }
        return prod
    }

    private var recentlyViewedPreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Icon + Title + Count Pill + Chevron Button
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(red: 238/255, green: 242/255, blue: 255/255))
                        .frame(width: 34, height: 34)

                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 79/255, green: 70/255, blue: 229/255))
                }

                Text("Visti di recente")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)

                let productCount = recentManager.activities.filter { $0.type == .product }.count
                if productCount > 0 {
                    Text("\(productCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 79/255, green: 70/255, blue: 229/255))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(red: 238/255, green: 242/255, blue: 255/255))
                        .clipShape(Capsule())
                }

                Spacer()

                NavigationLink(destination: RecentlyViewedView()) {
                    Circle()
                        .fill(Color(red: 244/255, green: 245/255, blue: 248/255))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(red: 70/255, green: 70/255, blue: 75/255))
                        )
                }
                .buttonStyle(.plain)
            }

            // Real Content: Products or Clean Empty State
            let recentItems = previewRecentProducts
            if !recentItems.isEmpty {
                HStack(spacing: 10) {
                    ForEach(recentItems) { prod in
                        NavigationLink(destination: ProductDetailView(product: prod)) {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .bottomLeading) {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(red: 245/255, green: 246/255, blue: 249/255))
                                        .aspectRatio(1.0, contentMode: .fit)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.black.opacity(0.04), lineWidth: 1)
                                        )

                                    if let imgUrl = prod.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                                        AsyncImage(url: url) { phase in
                                            if let img = phase.image {
                                                img
                                                    .resizable()
                                                    .scaledToFit()
                                                    .padding(8)
                                            } else {
                                                Image(systemName: "photo")
                                                    .font(.system(size: 24))
                                                    .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                                            }
                                        }
                                    } else {
                                        Image(systemName: "clock")
                                            .font(.system(size: 24))
                                            .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                    }

                                    // Floating Price Tag
                                    if let price = prod.best_price ?? prod.bestOffer?.price {
                                        Text(String(format: "%.2f €", price).replacingOccurrences(of: ".", with: ","))
                                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                            .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.white.opacity(0.94))
                                            .clipShape(Capsule())
                                            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                                            .padding(6)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 16))

                                VStack(alignment: .leading, spacing: 2) {
                                    if let brand = prod.brand, !brand.isEmpty {
                                        Text(brand.uppercased())
                                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                            .foregroundColor(.shopTextMuted)
                                            .lineLimit(1)
                                    }

                                    Text(prod.canonical_name)
                                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                        .foregroundColor(.shopDark)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 28, alignment: .topLeading)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Fill remaining slots if less than 3
                    if recentItems.count < 3 {
                        ForEach(0..<(3 - recentItems.count), id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 6) {
                                NavigationLink(destination: SearchView()) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                            .foregroundColor(Color(red: 215/255, green: 218/255, blue: 226/255))
                                            .aspectRatio(1.0, contentMode: .fit)

                                        VStack(spacing: 4) {
                                            Image(systemName: "magnifyingglass")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.shopTextMuted)
                                            Text("Cerca")
                                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                                .foregroundColor(.shopTextMuted)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer()
                                    .frame(height: 28)
                            }
                        }
                    }
                }
            } else {
                // Honest, Clean Empty State (No Fake Data)
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 238/255, green: 242/255, blue: 255/255))
                            .frame(width: 44, height: 44)

                        Image(systemName: "clock")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color(red: 79/255, green: 70/255, blue: 229/255))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nessun prodotto visto di recente")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Text("I modelli che visualizzi o cerchi appariranno qui automaticamente con confronto prezzi.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.shopTextMuted)
                            .lineLimit(2)
                    }

                    Spacer()

                    NavigationLink(destination: SearchView()) {
                        Text("Cerca")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 79/255, green: 70/255, blue: 229/255))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 238/255, green: 242/255, blue: 255/255))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Color(red: 249/255, green: 250/255, blue: 252/255))
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(red: 238/255, green: 240/255, blue: 245/255), lineWidth: 1)
                )
            }
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 3)
    }

    // MARK: - Dark Slate Accent Card (100% Real Database Store & Offers)

    private func darkAccentShopStoreCard(showcase: StoreShowcase) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 12) {
                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 46)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(showcase.store_name)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)

                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color(red: 196/255, green: 181/255, blue: 253/255))
                            }

                            HStack(spacing: 6) {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Color(red: 250/255, green: 204/255, blue: 21/255))
                                    Text(showcase.rating)
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())

                                Text("•")
                                    .foregroundColor(.white.opacity(0.4))
                                    .font(.system(size: 10))

                                Text("\(showcase.total_offers) offerte reali")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Quick Follow Button & Menu
                HStack(spacing: 6) {
                    Button(action: {
                        let gen = UIImpactFeedbackGenerator(style: .light)
                        gen.impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            followedManager.toggleFollow(storeId: showcase.store_id, storeName: showcase.store_name)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: followedManager.isFollowing(storeId: showcase.store_id) ? "checkmark" : "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text(followedManager.isFollowing(storeId: showcase.store_id) ? "Seguito" : "Segui")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(followedManager.isFollowing(storeId: showcase.store_id) ? Color.white.opacity(0.22) : Color.clear)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Menu {
                        NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                            Label("Visualizza negozio", systemImage: "arrow.right.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            // Horizontal Carousel of Real Product Cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(showcase.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                        ShopHomeProductCard(
                            product: prod,
                            matchedProduct: matched,
                            isDarkTheme: true
                        )
                    }
                }
                .padding(.horizontal, 18)
            }

            // Bottom Row: "Acquista tutto" + Arrow Button
            NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Acquista tutto")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Catalogo completo di \(showcase.store_name) con \(showcase.total_offers) articoli")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                    }

                    Spacer()

                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
            .buttonStyle(.plain)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 28/255, green: 28/255, blue: 34/255), Color(red: 18/255, green: 18/255, blue: 22/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(26)
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    // MARK: - Reusable Clean Shop Store Card Component with Real Database Showcase

    private func genericShopStoreCard(showcase: StoreShowcase) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Avatar + Store Name + Rating + Follow Button
            HStack(spacing: 12) {
                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 46)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(showcase.store_name)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.shopDark)

                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.shopPurple)
                            }

                            HStack(spacing: 6) {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Color(red: 245/255, green: 158/255, blue: 11/255))
                                    Text(showcase.rating)
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopDark)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(red: 245/255, green: 246/255, blue: 250/255))
                                .clipShape(Capsule())

                                Text("•")
                                    .foregroundColor(.shopTextMuted.opacity(0.5))
                                    .font(.system(size: 10))

                                Text("\(showcase.total_offers) offerte reali")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.shopTextMuted)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Quick Follow Button & Menu
                HStack(spacing: 6) {
                    Button(action: {
                        let gen = UIImpactFeedbackGenerator(style: .light)
                        gen.impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            followedManager.toggleFollow(storeId: showcase.store_id, storeName: showcase.store_name)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: followedManager.isFollowing(storeId: showcase.store_id) ? "checkmark" : "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text(followedManager.isFollowing(storeId: showcase.store_id) ? "Seguito" : "Segui")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(followedManager.isFollowing(storeId: showcase.store_id) ? .shopPurple : Color(red: 50/255, green: 50/255, blue: 60/255))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(followedManager.isFollowing(storeId: showcase.store_id) ? Color.shopPurpleLight : Color(red: 245/255, green: 246/255, blue: 250/255))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color(red: 230/255, green: 232/255, blue: 238/255), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Menu {
                        NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                            Label("Visualizza negozio", systemImage: "arrow.right.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.shopTextMuted)
                            .frame(width: 32, height: 32)
                            .background(Color(red: 245/255, green: 246/255, blue: 250/255))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            // Horizontal Carousel of Real Product Cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(showcase.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                        ShopHomeProductCard(
                            product: prod,
                            matchedProduct: matched,
                            isDarkTheme: false
                        )
                    }
                }
                .padding(.horizontal, 18)
            }

            // Bottom Row: "Acquista tutto" + Circular Arrow Button
            NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Acquista tutto")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Text("Catalogo completo di \(showcase.store_name) con \(showcase.total_offers) articoli")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                    }

                    Spacer()

                    Circle()
                        .fill(Color(red: 242/255, green: 243/255, blue: 246/255))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.shopDark)
                        )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
            .buttonStyle(.plain)
        }
        .background(Color.white)
        .cornerRadius(26)
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 3)
    }

    private func fetchShowcases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let sc = try await api.getStoreShowcases()
            await MainActor.run {
                self.showcases = sc
            }
        } catch {
            print("HomeView fetchShowcases error: \(error)")
        }
    }
}

// MARK: - Modern Polished Product Card (Real DB Data, Micro-Typography & Translucent Price Tag)

struct ShopHomeProductCard: View {
    let product: StoreShowcaseProduct
    let matchedProduct: MatchedProduct
    var isDarkTheme: Bool = false

    @ObservedObject private var wishlist = WishlistManager.shared

    var body: some View {
        NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            VStack(alignment: .leading, spacing: 8) {
                // Image Box with Floating Glass Badges
                ZStack(alignment: .topLeading) {
                    // Card Background
                    RoundedRectangle(cornerRadius: 18)
                        .fill(isDarkTheme ? Color.white.opacity(0.1) : Color(red: 245/255, green: 246/255, blue: 249/255))
                        .frame(width: 158, height: 138)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(isDarkTheme ? Color.white.opacity(0.08) : Color.black.opacity(0.04), lineWidth: 1)
                        )

                    // Product Image Centered
                    VStack {
                        Spacer()
                        if let imgUrl = product.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img
                                        .resizable()
                                        .scaledToFit()
                                        .padding(10)
                                        .frame(width: 142, height: 118)
                                } else {
                                    Image(systemName: "photo")
                                        .font(.system(size: 26))
                                        .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                                        .frame(width: 142, height: 118)
                                }
                            }
                        } else {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 26))
                                .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                                .frame(width: 142, height: 118)
                        }
                        Spacer()
                    }
                    .frame(width: 158, height: 138)

                    // Top-Left Floating Price Tag (Frosted Glass)
                    HStack(spacing: 4) {
                        Text(String(format: "%.2f €", product.current_price).replacingOccurrences(of: ".", with: ","))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        if let orig = product.original_price, orig > product.current_price {
                            Text(String(format: "%.2f €", orig).replacingOccurrences(of: ".", with: ","))
                                .font(.system(size: 9.5, weight: .regular))
                                .foregroundColor(.white.opacity(0.65))
                                .strikethrough()
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding([.top, .leading], 8)

                    // Top-Right Discount Pill (if on substantial discount)
                    if let disc = product.discount_pct, disc >= 10 {
                        VStack {
                            HStack {
                                Spacer()
                                Text("-\(Int(disc.rounded()))%")
                                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(red: 239/255, green: 68/255, blue: 68/255))
                                    .clipShape(Capsule())
                                    .padding([.top, .trailing], 8)
                            }
                            Spacer()
                        }
                        .frame(width: 158, height: 138)
                    }

                    // Bottom-Right Translucent Heart Button
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                let gen = UIImpactFeedbackGenerator(style: .medium)
                                gen.impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    wishlist.toggleFavorite(product: matchedProduct)
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.35))
                                        .frame(width: 30, height: 30)

                                    Image(systemName: wishlist.isFavorite(matchedProduct.canonical_name) ? "heart.fill" : "heart")
                                        .font(.system(size: 12.5, weight: .bold))
                                        .foregroundColor(wishlist.isFavorite(matchedProduct.canonical_name) ? Color(red: 239/255, green: 68/255, blue: 68/255) : .white)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding([.bottom, .trailing], 8)
                        }
                    }
                    .frame(width: 158, height: 138)
                }

                // Bottom Product Caption (Brand + Canonical Title)
                VStack(alignment: .leading, spacing: 2) {
                    if let brand = product.brand, !brand.isEmpty {
                        Text(brand.uppercased())
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(isDarkTheme ? .white.opacity(0.6) : .shopTextMuted)
                            .lineLimit(1)
                    }

                    Text(product.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(isDarkTheme ? .white : .shopDark)
                        .lineLimit(2)
                        .lineSpacing(1.2)
                        .frame(height: 32, alignment: .topLeading)
                }
                .frame(width: 158, alignment: .leading)
            }
            .frame(width: 158)
        }
        .buttonStyle(.plain)
    }
}
