import SwiftUI

enum HomeSubTab: Int, CaseIterable {
    case perTe = 0
    case offerte = 1
    case seguiGia = 2
    case salvati = 3

    var title: String {
        switch self {
        case .perTe: return "Per te"
        case .offerte: return "Saldi per le feste"
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

    // Interactive Menu States (Screenshot 3)
    @State private var reportingStore: StoreShowcase? = nil
    @State private var showingReportAlert = false
    @State private var toastMessage: String? = nil
    @State private var hiddenStoreIdToUndo: String? = nil
    @State private var navigatingStore: StoreShowcase? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // MARK: - 1. Pinned Top Header: Avatar "L" | Search Bar "Cerca" | Bell
                    topHeaderBar
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 10)

                    // MARK: - 2. Sub-Navigation Pills: Per te | Saldi per le feste | Segui già | Salvati
                    subNavigationPills
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

                // MARK: - Floating Toast Notification (Undo Hide Store, Confirmation)
                if let msg = toastMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)

                        Text(msg)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        if let undoId = hiddenStoreIdToUndo {
                            Button(action: {
                                followedManager.unhideStore(storeId: undoId)
                                withAnimation {
                                    hiddenStoreIdToUndo = nil
                                    toastMessage = nil
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
                    .cornerRadius(18)
                    .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 4)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 82)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $navigatingStore) { sc in
                StoreDetailView(storeId: sc.store_id, initialStoreName: sc.store_name)
            }
            .sheet(isPresented: $showingAccountSheet) {
                AccountView()
            }
            .alert("Notifiche Attive", isPresented: $showingNotificationsAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Riceverai notifiche push istantanee per cali di prezzo dei tuoi articoli salvati e per i nuovi drop dei negozi che segui.")
            }
            .alert("Segnala Negozio", isPresented: $showingReportAlert, presenting: reportingStore) { store in
                Button("Invia Segnalazione", role: .destructive) {
                    followedManager.reportStore(storeId: store.store_id, storeName: store.store_name)
                    withAnimation {
                        toastMessage = "Grazie per la segnalazione su \(store.store_name)."
                        hiddenStoreIdToUndo = nil
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        withAnimation { toastMessage = nil }
                    }
                }
                Button("Annulla", role: .cancel) { }
            } message: { store in
                Text("Vuoi segnalare '\(store.store_name)' al team di FitMatch per prezzi non aggiornati o violazioni?")
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

    // MARK: - Sub-Navigation Pills (Screenshot 1: Per te | Saldi per le feste | Segui già | Salvati)

    private var subNavigationPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
                            .padding(.horizontal, 16)
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
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - "Per te" Feed Content (100% Matching Screenshots 1, 2, 3, 4, 5)

    private var perTeContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // MARK: 1. Top Carousel of Summary Cards: "Visti di recente" & "Elementi salvati" (Screenshots 1 & 2)
                topSummaryCardsCarousel
                    .padding(.top, 4)

                // MARK: 2. Real Database Partner Stores
                let activeShowcases = showcases.filter {
                    !$0.products.isEmpty && !followedManager.isStoreHidden(storeId: $0.store_id)
                }

                if isLoading && activeShowcases.isEmpty {
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
                    ForEach(Array(activeShowcases.enumerated()), id: \.element.id) { index, sc in
                        if sc.card_theme == "olive" || (sc.card_theme == nil && index == 0) {
                            // Accent / Olive Card (driven by database card_theme or accent_color)
                            oliveShopStoreCard(showcase: sc)
                                .padding(.horizontal, 16)
                        } else if sc.card_theme == "grid" || (sc.card_theme == nil && index == 2 && sc.products.count >= 4) {
                            // 2-Column Grid Card (driven by database card_theme == "grid")
                            gridShopStoreCard(showcase: sc)
                                .padding(.horizontal, 16)
                        } else {
                            // Clean White Horizontal Carousel Card (driven by database card_theme == "white")
                            whiteShopStoreCard(showcase: sc)
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

    // MARK: - 1. Top Summary Cards Carousel (Screenshots 1 & 2: Visti di recente | Elementi salvati)

    private var topSummaryCardsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Card 1: "Visti di recente"
                recentlyViewedSummaryCard

                // Card 2: "Elementi salvati"
                savedItemsSummaryCard
            }
            .padding(.horizontal, 16)
        }
    }

    // Card 1: Visti di recente (Screenshot 1)
    private var recentlyViewedSummaryCard: some View {
        let cardWidth = max(UIScreen.main.bounds.width - 56, 320)
        let thumbSize = (cardWidth - 32 - 20) / 3

        return VStack(alignment: .leading, spacing: 14) {
            // Header: Title + Circular Chevron Button
            HStack {
                Text("Visti di recente")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

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

            // Row of 3 Thumbnails
            HStack(spacing: 10) {
                let items = previewRecentProducts
                ForEach(items) { prod in
                    NavigationLink(destination: ProductDetailView(product: prod)) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 245/255, green: 246/255, blue: 249/255))
                                .frame(width: thumbSize, height: thumbSize)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                                )

                            if let imgUrl = prod.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img
                                            .resizable()
                                            .scaledToFit()
                                            .padding(6)
                                    } else {
                                        Image(systemName: "photo")
                                            .font(.system(size: 22))
                                            .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                                    }
                                }
                            } else {
                                Image(systemName: "clock")
                                    .font(.system(size: 22))
                                    .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // If user has viewed fewer than 3 items, fill with top database shoes
                if items.count < 3 {
                    let fallbackPicks = fallbackPopularProducts.prefix(3 - items.count)
                    ForEach(fallbackPicks) { prod in
                        NavigationLink(destination: ProductDetailView(product: prod)) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color(red: 245/255, green: 246/255, blue: 249/255))
                                    .frame(width: thumbSize, height: thumbSize)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                                    )

                                if let imgUrl = prod.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                                    AsyncImage(url: url) { phase in
                                        if let img = phase.image {
                                            img
                                                .resizable()
                                                .scaledToFit()
                                                .padding(6)
                                        } else {
                                            Image(systemName: "tag.fill")
                                                .font(.system(size: 22))
                                                .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: cardWidth)
        .background(Color.white)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    // Card 2: Elementi salvati (Screenshot 2)
    private var savedItemsSummaryCard: some View {
        let cardWidth = max(UIScreen.main.bounds.width - 56, 320)
        let thumbSize = (cardWidth - 32 - 20) / 3

        return VStack(alignment: .leading, spacing: 14) {
            // Header: Title + Circular Chevron Button (switches to Salvati tab)
            HStack {
                Text("Elementi salvati")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

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

            // Row of 3 Thumbnails
            HStack(spacing: 10) {
                let saved = Array(wishlist.items.prefix(3))
                ForEach(saved) { item in
                    NavigationLink(destination: ProductDetailView(product: item.toMatchedProduct())) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 245/255, green: 246/255, blue: 249/255))
                                .frame(width: thumbSize, height: thumbSize)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                                )

                            if let imgUrl = item.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img
                                            .resizable()
                                            .scaledToFit()
                                            .padding(6)
                                    } else {
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.4))
                                    }
                                }
                            } else {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.4))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // If user has saved fewer than 3 items, fill with top picks
                if saved.count < 3 {
                    let fallbackPicks = fallbackPopularProducts.suffix(3 - saved.count)
                    ForEach(fallbackPicks) { prod in
                        NavigationLink(destination: ProductDetailView(product: prod)) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color(red: 245/255, green: 246/255, blue: 249/255))
                                    .frame(width: thumbSize, height: thumbSize)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                                    )

                                if let imgUrl = prod.image_url, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                                    AsyncImage(url: url) { phase in
                                        if let img = phase.image {
                                            img
                                                .resizable()
                                                .scaledToFit()
                                                .padding(6)
                                        } else {
                                            Image(systemName: "tag.fill")
                                                .font(.system(size: 22))
                                                .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: cardWidth)
        .background(Color.white)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
    }

    // MARK: - 2. Olive / Accent Shop Store Card (Driven by Database card_theme & accent_color)

    private func oliveShopStoreCard(showcase: StoreShowcase) -> some View {
        let cardBgColor: Color = {
            if let hex = showcase.accent_color, let c = Color(hex: hex) {
                return c
            }
            return Color(red: 98/255, green: 125/255, blue: 86/255) // #627D56 authentic olive fallback
        }()

        return VStack(alignment: .leading, spacing: 16) {
            // Header: Avatar + Store Name + Rating + Three-dots Menu
            HStack(spacing: 12) {
                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 46)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(showcase.store_name)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text(showcase.formattedRatingWithReviews)
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.92))
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Three-Dots Interactive Context Menu (Screenshot 3)
                storeContextMenu(showcase: showcase, isDarkBackground: true)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            // Horizontal Carousel of Pure White Product Cards (Screenshot 1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(showcase.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                        cleanProductCard(product: prod, matchedProduct: matched, cardBg: .white)
                    }
                }
                .padding(.horizontal, 18)
            }

            // Bottom Row: "Acquista tutto" + Circular Arrow Button
            NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                HStack {
                    Text("Acquista tutto")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()

                    Circle()
                        .fill(Color.white.opacity(0.24))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .buttonStyle(.plain)
        }
        .background(cardBgColor)
        .cornerRadius(26)
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    // MARK: - 3. Clean White Horizontal Carousel Store Card (Screenshots 1 & 5: PeakPulse / dripuniqueuk)

    private func whiteShopStoreCard(showcase: StoreShowcase) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: Avatar + Store Name + Rating + Three-dots Menu
            HStack(spacing: 12) {
                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 46)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(showcase.store_name)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

                            Text(showcase.formattedRatingWithReviews)
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 45/255, green: 45/255, blue: 50/255))
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Three-Dots Interactive Context Menu (Screenshot 3)
                storeContextMenu(showcase: showcase, isDarkBackground: false)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            // Horizontal Carousel of Clean Light Neutral Product Cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(showcase.products) { prod in
                        let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                        cleanProductCard(product: prod, matchedProduct: matched, cardBg: Color(red: 242/255, green: 243/255, blue: 246/255))
                    }
                }
                .padding(.horizontal, 18)
            }

            // Bottom Row: "Acquista tutto" + Circular Arrow Button
            NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                HStack {
                    Text("Acquista tutto")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

                    Spacer()

                    Circle()
                        .fill(Color(red: 242/255, green: 243/255, blue: 246/255))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                        )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
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

    // MARK: - 4. 2-Column Grid Store Card (Screenshot 4: il Numero Diez Style)

    private func gridShopStoreCard(showcase: StoreShowcase) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: Avatar + Store Name + Rating + Three-dots Menu
            HStack(spacing: 12) {
                NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 46)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(showcase.store_name)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

                            Text(showcase.formattedRatingWithReviews)
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 45/255, green: 45/255, blue: 50/255))
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Three-Dots Interactive Context Menu (Screenshot 3)
                storeContextMenu(showcase: showcase, isDarkBackground: false)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            // 2-Column Grid of 6 Items (Screenshot 4)
            let items = Array(showcase.products.prefix(6))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(items) { prod in
                    let matched = prod.toMatchedProduct(storeId: showcase.store_id, storeName: showcase.store_name)
                    cleanProductGridItem(product: prod, matchedProduct: matched)
                }
            }
            .padding(.horizontal, 18)

            // Bottom Row: "Acquista tutto" + Circular Arrow Button
            NavigationLink(destination: StoreDetailView(storeId: showcase.store_id, initialStoreName: showcase.store_name)) {
                HStack {
                    Text("Acquista tutto")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

                    Spacer()

                    Circle()
                        .fill(Color(red: 242/255, green: 243/255, blue: 246/255))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                        )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
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

    // MARK: - Store Context Menu (Screenshot 3: Visita il negozio | Segui | Non mi interessa | Segnala negozio)

    private func storeContextMenu(showcase: StoreShowcase, isDarkBackground: Bool) -> some View {
        Menu {
            // 1. Visita il negozio
            Button {
                navigatingStore = showcase
            } label: {
                Label("Visita il negozio", systemImage: "storefront")
            }

            // 2. Segui / Smetti di seguire
            Button {
                followedManager.toggleFollow(storeId: showcase.store_id, storeName: showcase.store_name)
            } label: {
                if followedManager.isFollowing(storeId: showcase.store_id) {
                    Label("Smetti di seguire", systemImage: "checkmark.circle.fill")
                } else {
                    Label("Segui", systemImage: "plus.circle")
                }
            }

            // 3. Non mi interessa
            Button {
                followedManager.hideStore(storeId: showcase.store_id, storeName: showcase.store_name)
                hiddenStoreIdToUndo = showcase.store_id
                withAnimation {
                    toastMessage = "Hai nascosto \(showcase.store_name) dai consigli."
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    withAnimation {
                        if hiddenStoreIdToUndo == showcase.store_id {
                            toastMessage = nil
                        }
                    }
                }
            } label: {
                Label("Non mi interessa", systemImage: "hand.thumbsdown")
            }

            // 4. Segnala negozio (Destructive in Red)
            Button(role: .destructive) {
                reportingStore = showcase
                showingReportAlert = true
            } label: {
                Label("Segnala negozio", systemImage: "exclamationmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(isDarkBackground ? .white : Color(red: 45/255, green: 45/255, blue: 50/255))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
    }

    // MARK: - Minimal Clean Product Card (Screenshots 1, 2, 5: Image + Top-Left Price + Bottom-Right Heart)

    private func cleanProductCard(product: StoreShowcaseProduct, matchedProduct: MatchedProduct, cardBg: Color) -> some View {
        NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            ZStack(alignment: .topLeading) {
                // Card Box
                RoundedRectangle(cornerRadius: 18)
                    .fill(cardBg)
                    .frame(width: 138, height: 178)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
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
                                    .padding(8)
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                            }
                        }
                    } else {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 26))
                            .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                    }
                    Spacer()
                }
                .frame(width: 138, height: 178)

                // Top-Left Translucent Price Capsule
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
                .frame(width: 138, height: 178)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2-Column Grid Product Item (Screenshot 4)

    private func cleanProductGridItem(product: StoreShowcaseProduct, matchedProduct: MatchedProduct) -> some View {
        NavigationLink(destination: ProductDetailView(product: matchedProduct)) {
            ZStack(alignment: .topLeading) {
                // Card Box
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 242/255, green: 243/255, blue: 246/255))
                    .frame(height: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
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
                                    .padding(8)
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                            }
                        }
                    } else {
                        Image(systemName: "tshirt.fill")
                            .font(.system(size: 26))
                            .foregroundColor(Color(red: 210/255, green: 210/255, blue: 215/255))
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)

                // Top-Left Translucent Price Capsule
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
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

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

    // Fallback real products from the catalog if recent/saved are completely empty on first launch
    private var fallbackPopularProducts: [MatchedProduct] {
        var picks: [MatchedProduct] = []
        for sc in showcases {
            for prod in sc.products {
                let m = prod.toMatchedProduct(storeId: sc.store_id, storeName: sc.store_name)
                picks.append(m)
                if picks.count >= 6 { return picks }
            }
        }
        return picks
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
