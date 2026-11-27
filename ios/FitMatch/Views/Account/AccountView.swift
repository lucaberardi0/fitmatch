import SwiftUI
import AuthenticationServices

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var prefs = UserPreferencesManager.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var notifManager = NotificationManager.shared
    @ObservedObject private var recentManager = RecentActivityManager.shared
    @ObservedObject private var supabase = SupabaseManager.shared
    @StateObject private var api = APIService.shared

    @State private var showingEditNameAlert = false
    @State private var tempName = ""
    @State private var showingAuthSheet = false
    @State private var showingSignOutAlert = false
    @State private var legalSheetType: AccountLegalType? = nil

    private let fallbackPartnerStores: [(String, String, String, String)] = [
        ("nike", "Nike", "Store ufficiale Nike · Sped. da €5,00", "store_nike"),
        ("adidas", "Adidas", "Store ufficiale Adidas · Gratis da €50", "store_adidas"),
        ("misterrunning", "Mister Running", "DHL / UPS · Gratis da €49", "store_misterrunning"),
        ("cisalfa", "Cisalfa Sport", "BRT / GLS · Gratis da €99", "store_cisalfa"),
        ("maxisport", "Maxi Sport", "GLS / DHL · Gratis da €99", "store_maxisport"),
        ("top4running", "Top4Running", "DPD / BRT · Gratis da €75", "store_top4running"),
        ("runningwarehouse", "Running Warehouse Europe", "UPS / FedEx · Gratis da €59", "store_runningwarehouse"),
        ("deporvillage", "Deporvillage", "GLS / DPD · Gratis da €80", "store_deporvillage"),
        ("alltricks", "Alltricks", "Bartolini (BRT) · Gratis da €69", "store_alltricks"),
        ("decathlon", "Decathlon", "Corriere Espresso · Gratis da €60", "store_decathlon"),
        ("nencini", "Nencini Sport", "BRT / UPS · Gratis da €100", "store_nencini"),
        ("sportler", "Sportler", "SDA / Espresso · Gratis da €100", "store_sportler"),
        ("df_sportspecialist", "DF Sport Specialist", "Corriere Espresso · Gratis da €100", "store_df_sportspecialist"),
        ("tradeinn", "Tradeinn", "DHL / UPS · Sped. da €4,99", "store_tradeinn"),
        ("sportit", "SportIT", "GLS / DHL · Gratis da €59,90", "store_sportit"),
        ("tennis_point", "Tennis-Point", "DHL / UPS · Gratis da €59", "store_tennis_point"),
        ("basketballstore", "Basketball Store", "BRT / UPS · Gratis da €50", "store_basketballstore"),
        ("nonsolosport", "NonSoloSport", "BRT · Gratis da €89,99", "store_nonsolosport"),
        ("intersport", "Intersport Italia", "GLS / BRT · Gratis da €59", "store_intersport"),
        ("bshopzone", "Bshopzone", "BRT / GLS · Gratis da €100", "store_bshopzone")
    ]

    var partnerStores: [(String, String, String, String)] {
        guard !prefs.activeStores.isEmpty else { return fallbackPartnerStores }
        return prefs.activeStores.map { store in
            let sub = (store.subtitle?.isEmpty == false) ? store.subtitle! : store.base_url
            return (store.id, store.name, sub, "store_\(store.id)")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var activePriceAlertsCount: Int {
        wishlist.items.filter { $0.isAlertEnabled }.count
    }

    private var totalWishlistSavings: Double {
        prefs.calculateTotalWishlistSavings(wishlistItems: wishlist.items)
    }

    private var userInitial: String {
        let trimmed = prefs.preferences.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, !trimmed.isEmpty, trimmed.lowercased() != "ospite" {
            return String(first).uppercased()
        }
        if let emailFirst = supabase.currentUserEmail?.first {
            return String(emailFirst).uppercased()
        }
        return "F"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Pinned Header Bar
                headerBar
                    .shopHeaderBarPadding()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        // MARK: - 1. Hero Auth / Profile Section
                        heroSection
                            .padding(.top, 8)

                        // MARK: - 2. Quick Action Grid (Salvati | Segui già)
                        quickActionsGrid

                        // MARK: - 3. Price Monitoring / Tracking Spotlight
                        priceMonitoringSection

                        // MARK: - 4. Grouped Settings Card
                        groupedSettingsCard

                        // MARK: - 5. Footer (Version, Terms, Licenses, FitMatch)
                        footerSection
                            .padding(.top, 6)
                            .padding(.bottom, 32)
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
                }
            }
            .background(Color.shopSurface.ignoresSafeArea())
            .navigationBarHidden(true)
            .task {
                await prefs.fetchActiveStores(apiService: api)
            }
            .sheet(isPresented: $showingAuthSheet) {
                AuthSheetView()
            }
            .sheet(item: $legalSheetType) { legal in
                AccountLegalSheetView(type: legal, storeCount: partnerStores.count)
            }
            .alert("Modifica Nome", isPresented: $showingEditNameAlert) {
                TextField("Il tuo nome", text: $tempName)
                Button("Annulla", role: .cancel) { }
                Button("Salva") {
                    let trimmed = tempName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        prefs.preferences.userName = trimmed
                    }
                }
            }
            .alert("Disconnetti Account", isPresented: $showingSignOutAlert) {
                Button("Annulla", role: .cancel) { }
                Button("Disconnetti", role: .destructive) {
                    supabase.signOut()
                }
            } message: {
                Text("Tornerai alla modalità ospite locale. I tuoi prodotti salvati su questo dispositivo rimarranno disponibili.")
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        ZStack {
            Text("Account")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.shopDark)
                        .shopNavCircle(size: 40)
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.92, pressedOpacity: 0.85))
                .accessibilityLabel("Chiudi Account")

                Spacer()
            }
        }
    }

    // MARK: - 1. Hero Section (Guest Sign In vs Authenticated Profile)

    @ViewBuilder
    private var heroSection: some View {
        if supabase.isAuthenticated {
            VStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.shopPurple, Color.shopPurpleDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.shopPurple.opacity(0.24), radius: 10, x: 0, y: 4)

                    Text(userInitial)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text(prefs.preferences.userName.isEmpty || prefs.preferences.userName == "Ospite" ? "Atleta FitMatch" : prefs.preferences.userName)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Button(action: {
                            tempName = prefs.preferences.userName == "Ospite" ? "" : prefs.preferences.userName
                            showingEditNameAlert = true
                        }) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 17))
                                .foregroundColor(.shopTextMuted)
                        }
                        .buttonStyle(.plain)
                    }

                    if let email = supabase.currentUserEmail, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 14))
                            .foregroundColor(.shopTextMuted)
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.shopGreen)
                            .frame(width: 7, height: 7)
                        Text("Cloud Sync Attivo · \(partnerStores.count) Store")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.shopGreen)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.shopGreenLight)
                    .clipShape(Capsule())
                    .padding(.top, 4)
                }

                Button(action: {
                    showingSignOutAlert = true
                }) {
                    Text("Disconnetti")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.shopTextMuted)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.shopBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.96, pressedOpacity: 0.9))
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
        } else {
            VStack(spacing: 14) {
                FitMatchBrandEmblem(size: 36)
                    .padding(.bottom, 2)

                VStack(spacing: 7) {
                    Text("Accedi o crea un account")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)
                        .multilineTextAlignment(.center)

                    Text("Salva ciò che vuoi. Monitora ogni prezzo. Non perderti le offerte e le taglie disponibili.")
                        .font(.system(size: 14))
                        .foregroundColor(.shopTextMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 16)
                }

                Button(action: {
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    showingAuthSheet = true
                }) {
                    Text("Accedi")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.shopPurple)
                        .clipShape(Capsule())
                        .shadow(color: Color.shopPurple.opacity(0.24), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.975, pressedOpacity: 0.92))
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 2. Quick Actions Grid (Salvati | Segui già)

    private var quickActionsGrid: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: AccountSavedProductsDestinationView()) {
                quickActionCard(
                    icon: "heart",
                    title: "Salvati",
                    count: wishlist.items.count
                )
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.97, pressedOpacity: 0.94))

            NavigationLink(destination: AccountFollowedStoresDestinationView(partnerStores: partnerStores)) {
                quickActionCard(
                    icon: "storefront",
                    title: "Segui già",
                    count: followedManager.followedStores.count
                )
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.97, pressedOpacity: 0.94))
        }
    }

    private func quickActionCard(icon: String, title: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(Color.shopSurfaceElevated)
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.shopDark)
                }

                Spacer()

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.shopPurple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.shopPurpleLight)
                        .clipShape(Capsule())
                }
            }

            Text(title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundColor(.shopDark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.shopBorder.opacity(0.65), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 4)
    }

    // MARK: - 3. Price Monitoring Spotlight Card

    private var priceMonitoringSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Monitoraggio prezzi")
                .font(.system(size: 18.5, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
                .padding(.horizontal, 2)

            NavigationLink(destination: AccountPriceMonitorView(partnerStores: partnerStores)) {
                HStack(spacing: 14) {
                    priceTrackerIllustration

                    VStack(alignment: .leading, spacing: 4) {
                        if activePriceAlertsCount == 0 {
                            Text("Nessun avviso per ora")
                                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            let sizeSuffix = prefs.preferences.hasShoeSize ? " nella taglia EU \(prefs.preferences.preferredShoeSize)" : ""
                            Text("I prodotti monitorati dalla wishlist e i cali di prezzo\(sizeSuffix) appariranno qui")
                                .font(.system(size: 13.5))
                                .foregroundColor(.shopTextMuted)
                                .lineSpacing(2)
                                .multilineTextAlignment(.leading)
                        } else {
                            Text(activePriceAlertsCount == 1 ? "1 prodotto monitorato" : "\(activePriceAlertsCount) prodotti monitorati")
                                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            let sizeTag = prefs.preferences.hasShoeSize ? " · Taglia EU \(prefs.preferences.preferredShoeSize)" : ""
                            if totalWishlistSavings > 0 {
                                Text(String(format: "Risparmio rilevato: €%.2f sui %d store partner%@", totalWishlistSavings, partnerStores.count, sizeTag))
                                    .font(.system(size: 13.5))
                                    .foregroundColor(.shopTextMuted)
                                    .lineSpacing(2)
                                    .multilineTextAlignment(.leading)
                            } else {
                                let sizeFor = prefs.preferences.hasShoeSize ? " per la taglia EU \(prefs.preferences.preferredShoeSize)" : ""
                                Text("Controllo automatico attivo sui \(partnerStores.count) store partner\(sizeFor)")
                                    .font(.system(size: 13.5))
                                    .foregroundColor(.shopTextMuted)
                                    .lineSpacing(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.shopTextMuted.opacity(0.7))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.shopBorder.opacity(0.65), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.98, pressedOpacity: 0.95))
        }
    }

    private var priceTrackerIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.shopPurpleLight,
                            Color(red: 228/255, green: 221/255, blue: 253/255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 58, height: 58)

            ZStack(alignment: .topTrailing) {
                Image(systemName: activePriceAlertsCount > 0 ? "chart.line.downtrend.xyaxis" : "tag.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.shopPurple)

                Circle()
                    .fill(activePriceAlertsCount > 0 ? Color.shopGreen : Color.shopOrange)
                    .frame(width: 11, height: 11)
                    .overlay(
                        Circle().stroke(Color.white, lineWidth: 2)
                    )
                    .offset(x: 4, y: -3)
            }
        }
        .frame(width: 58, height: 58)
    }

    // MARK: - 4. Grouped Settings Card

    private var groupedSettingsCard: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: AccountPreferencesDetailView()) {
                settingsRow(
                    icon: AnyView(
                        Image(systemName: "ruler.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.shopDark)
                    ),
                    title: "Misure e preferenze",
                    trailingValue: prefs.preferences.formattedSizeSummary
                )
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.99, pressedOpacity: 0.92))

            rowDivider

            NavigationLink(destination: AccountNotificationsSettingsView()) {
                settingsRow(
                    icon: AnyView(
                        Image(systemName: "bell.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.shopDark)
                    ),
                    title: "Notifiche",
                    badgeCount: notifManager.unreadCount
                )
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.99, pressedOpacity: 0.92))

            rowDivider

            NavigationLink(destination: AccountPrivacyDataView(recentCount: recentManager.activities.count, storeCount: partnerStores.count)) {
                settingsRow(
                    icon: AnyView(
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.shopDark)
                    ),
                    title: "Dati e privacy"
                )
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.99, pressedOpacity: 0.92))

            rowDivider

            NavigationLink(destination: AccountSupportView(storeCount: partnerStores.count)) {
                settingsRow(
                    icon: AnyView(
                        Image(systemName: "questionmark.bubble.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.shopDark)
                    ),
                    title: "Assistenza"
                )
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.99, pressedOpacity: 0.92))
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.shopBorder.opacity(0.65), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 4)
    }

    private var rowDivider: some View {
        Divider()
            .background(Color.shopBorder.opacity(0.6))
            .padding(.leading, 54)
            .padding(.trailing, 16)
    }

    private func settingsRow(
        icon: AnyView,
        title: String,
        trailingValue: String? = nil,
        badgeCount: Int = 0
    ) -> some View {
        HStack(spacing: 14) {
            icon
                .frame(width: 24, height: 24)

            Text(title)
                .font(.system(size: 15.5, weight: .medium, design: .rounded))
                .foregroundColor(.shopDark)

            Spacer()

            if badgeCount > 0 {
                Text("\(min(badgeCount, 99))")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.shopPurple)
                    .clipShape(Capsule())
            } else if let trailingValue {
                Text(trailingValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.shopTextMuted)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.shopDark)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .contentShape(Rectangle())
    }

    // MARK: - 5. Footer Section

    private var footerSection: some View {
        VStack(spacing: 10) {
            Text("Versione \(appVersion) (\(buildNumber))")
                .font(.system(size: 13))
                .foregroundColor(.shopTextMuted)

            HStack(spacing: 16) {
                Button(action: { legalSheetType = .privacy }) {
                    Text("Privacy")
                        .font(.system(size: 13))
                        .underline()
                        .foregroundColor(.shopTextMuted)
                }
                .buttonStyle(.plain)

                Button(action: { legalSheetType = .terms }) {
                    Text("Termini e condizioni")
                        .font(.system(size: 13))
                        .underline()
                        .foregroundColor(.shopTextMuted)
                }
                .buttonStyle(.plain)

                Button(action: { legalSheetType = .licenses }) {
                    Text("Licenze")
                        .font(.system(size: 13))
                        .underline()
                        .foregroundColor(.shopTextMuted)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Text("Offerto da")
                    .font(.system(size: 13.5))
                    .foregroundColor(.shopTextMuted)

                HStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.shopDark)
                            .frame(width: 18, height: 18)
                        Text("F")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Text("fitmatch")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)
                }

                Text("|")
                    .font(.system(size: 13))
                    .foregroundColor(.shopTextMuted.opacity(0.5))

                NavigationLink(destination: AccountFollowedStoresDestinationView(partnerStores: partnerStores)) {
                    Text("\(partnerStores.count) negozi partner")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - FitMatch Brand Emblem

private struct FitMatchBrandEmblem: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(
                    Color.shopPurple,
                    style: StrokeStyle(lineWidth: size * 0.23, lineCap: .round)
                )
                .rotationEffect(.degrees(-25))
                .frame(width: size * 0.78, height: size * 0.78)

            Circle()
                .fill(Color.shopPurple)
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: size * 0.24, y: -size * 0.24)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Sub-Page Header Helper

private struct AccountSubPageHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.shopDark)
                        .shopNavCircle(size: 40)
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.92, pressedOpacity: 0.85))
                Spacer()
            }
        }
        .shopHeaderBarPadding()
    }
}

// MARK: - Quick Action Destination: Salvati

private struct AccountSavedProductsDestinationView: View {
    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Salvati")
            WishlistView(embedded: true)
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Quick Action Destination: Segui già

private struct AccountFollowedStoresDestinationView: View {
    let partnerStores: [(String, String, String, String)]
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @StateObject private var api = APIService.shared
    @State private var showcases: [StoreShowcase] = []

    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Segui già")

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if followedManager.followedStores.isEmpty {
                        FitMatchEmptyStateView(
                            icon: "storefront",
                            title: "Nessun negozio seguito",
                            subtitle: "Segui i tuoi store preferiti per vedere qui arrivi e ribassi."
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Negozi che segui (\(followedManager.followedStores.count))")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            VStack(spacing: 0) {
                                ForEach(followedManager.followedStores) { store in
                                    HStack(spacing: 12) {
                                        NavigationLink(destination: StoreDetailView(storeId: store.store_id, initialStoreName: store.store_name)) {
                                            HStack(spacing: 12) {
                                                ShopStoreLogo(storeName: store.store_name, showVerified: false, showLabel: false, size: 36, logoURL: store.store_logo)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(store.store_name)
                                                        .font(.system(size: 15, weight: .bold))
                                                        .foregroundColor(.shopDark)
                                                    Text("Apri catalogo negozio")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.shopTextMuted)
                                                }
                                                Spacer()
                                            }
                                        }
                                        .buttonStyle(.plain)

                                        Button(action: {
                                            followedManager.unfollowStore(storeId: store.store_id)
                                        }) {
                                            Text("Segui già")
                                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                                .foregroundColor(.shopDark)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.shopSurfaceElevated)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(14)

                                    if store.id != followedManager.followedStores.last?.id {
                                        Divider().padding(.leading, 62)
                                    }
                                }
                            }
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.shopBorder.opacity(0.65), lineWidth: 1)
                            )
                        }
                    }

                    // Partner stores discovery
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tutti i negozi partner")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        VStack(spacing: 0) {
                            ForEach(partnerStores, id: \.0) { store in
                                let isFollowed = followedManager.isFollowing(storeId: store.0)
                                HStack(spacing: 12) {
                                    NavigationLink(destination: StoreDetailView(storeId: store.0, initialStoreName: store.1)) {
                                        HStack(spacing: 12) {
                                            ShopStoreLogo(storeName: store.1, showVerified: false, showLabel: false, size: 34)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(store.1)
                                                    .font(.system(size: 14.5, weight: .bold))
                                                    .foregroundColor(.shopDark)
                                                Text(store.2)
                                                    .font(.system(size: 11.5))
                                                    .foregroundColor(.shopTextMuted)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Button(action: {
                                        followedManager.toggleFollow(storeId: store.0, storeName: store.1)
                                    }) {
                                        Text(isFollowed ? "Segui già" : "Segui")
                                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                            .foregroundColor(isFollowed ? .shopDark : .white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(isFollowed ? Color.shopSurfaceElevated : Color.shopDark)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(14)

                                if store.0 != partnerStores.last?.0 {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.shopBorder.opacity(0.65), lineWidth: 1)
                        )
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 6)
            }
            .refreshable {
                await followedManager.fetchFollowedStores()
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Sub-Page: Monitoraggio Prezzi & Statistiche

private struct AccountPriceMonitorView: View {
    let partnerStores: [(String, String, String, String)]
    @ObservedObject private var prefs = UserPreferencesManager.shared
    @ObservedObject private var wishlist = WishlistManager.shared

    var body: some View {
        let totalSavings = prefs.calculateTotalWishlistSavings(wishlistItems: wishlist.items)
        let monitoredItems = wishlist.items.filter { $0.isAlertEnabled }

        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Monitoraggio prezzi")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Stats Overview
                    HStack(spacing: 12) {
                        statCard(
                            icon: "arrow.down.right.circle.fill",
                            color: .shopGreen,
                            label: "Risparmio",
                            value: String(format: "€%.2f", totalSavings)
                        )
                        statCard(
                            icon: "heart.fill",
                            color: .pink,
                            label: "Salvati",
                            value: "\(wishlist.items.count)"
                        )
                        statCard(
                            icon: "bell.badge.fill",
                            color: .shopPurple,
                            label: "Alert Attivi",
                            value: "\(monitoredItems.count)"
                        )
                    }

                    // Passive Automatic Monitoring Card (no manual price check actions)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "bell.and.waves.left.and.right.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.shopPurple)
                            Text("Monitoraggio Automatico")
                                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                            Spacer()

                            if prefs.updaterStatus?.scheduler_active == true {
                                HStack(spacing: 4) {
                                    Circle().fill(Color.shopGreen).frame(width: 7, height: 7)
                                    Text("Attivo")
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundColor(.shopGreen)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.shopGreenLight)
                                .clipShape(Capsule())
                            }
                        }

                        let sizeDetail = prefs.preferences.hasShoeSize ? " nella tua taglia (EU \(prefs.preferences.preferredShoeSize))" : ""
                        Text("FitMatch verifica automaticamente i prezzi dei prodotti salvati sui \(partnerStores.count) negozi partner per segnalarti i cali\(sizeDetail).")
                            .font(.system(size: 12.5))
                            .foregroundColor(.shopTextMuted)

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Ultimo aggiornamento")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(.shopTextMuted)
                                Text(prefs.updaterStatus?.last_run ?? "Monitoraggio automatico attivo")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundColor(.shopDark)
                            }
                            Spacer()

                            if let drops = prefs.updaterStatus?.last_stats?.price_drops, drops > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.orange)
                                    Text("\(drops) cali")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(.orange)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(12)
                        .background(Color.shopSurface)
                        .cornerRadius(12)
                    }
                    .shopCard()

                    // Monitored items list
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Prodotti con avviso attivo (\(monitoredItems.count))")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        if monitoredItems.isEmpty {
                            FitMatchInlineEmptyRow(
                                icon: "bell",
                                title: "Nessun avviso attivo",
                                subtitle: "Attiva la campanella sui salvati per monitorare i prezzi"
                            )
                        } else {
                            ForEach(monitoredItems) { item in
                                HStack(spacing: 12) {
                                    if let img = item.image_url, let url = URL(string: img) {
                                        ShopCachedAsyncImage(url: url, maxPixelSize: 160) { phase in
                                            if let image = phase.image {
                                                image.resizable().scaledToFit()
                                            } else {
                                                Color.shopSurface
                                            }
                                        }
                                        .frame(width: 48, height: 48)
                                        .background(Color.shopSurface)
                                        .cornerRadius(10)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.canonical_name)
                                            .font(.system(size: 13.5, weight: .semibold))
                                            .foregroundColor(.shopDark)
                                            .lineLimit(1)
                                        Text("\(item.bestStore ?? "Store partner") · €\(String(format: "%.2f", item.currentBestPrice))")
                                            .font(.system(size: 12))
                                            .foregroundColor(.shopTextMuted)
                                    }

                                    Spacer()

                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.shopPurple)
                                }
                                .padding(.vertical, 4)

                                if item.id != monitoredItems.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .shopCard()

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 6)
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }

    private func statCard(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.shopTextMuted)
            }
            Text(value)
                .font(.system(size: 17.5, weight: .black, design: .rounded))
                .foregroundColor(.shopDark)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.shopBorder.opacity(0.65), lineWidth: 1)
        )
    }
}

// MARK: - Sub-Page: Misure e Preferenze (Taglie, Sport, Brand)

private struct AccountPreferencesDetailView: View {
    @ObservedObject private var prefs = UserPreferencesManager.shared
    @State private var showingOnboardingReplay = false

    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Misure e preferenze")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Sizes Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "ruler.fill")
                                .font(.system(size: 15))
                                .foregroundColor(.shopPurple)
                            Text("Le Mie Misure & Taglie")
                                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                            Spacer()
                            Text("Facoltative")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.shopTextMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.shopSurface)
                                .clipShape(Capsule())
                        }

                        Text("FitMatch usa queste taglie per verificare la disponibilità reale sui negozi partner. Tocca una taglia attiva per rimuoverla.")
                            .font(.system(size: 12.5))
                            .foregroundColor(.shopTextMuted)

                        // Shoe Size
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Taglia Scarpe (EU)")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Spacer()
                                Text(prefs.preferences.hasShoeSize ? "EU \(prefs.preferences.preferredShoeSize)" : "Non impostata")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundColor(prefs.preferences.hasShoeSize ? .shopPurple : .shopTextMuted)
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(UserPreferencesManager.shoeSizes, id: \.self) { size in
                                        let isSelected = prefs.preferences.preferredShoeSize == size
                                        Button(action: {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            prefs.preferences.preferredShoeSize = isSelected ? "" : size
                                        }) {
                                            Text(size)
                                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                                .foregroundColor(isSelected ? .white : .shopDark)
                                                .frame(minWidth: 46, minHeight: 38)
                                                .background(isSelected ? Color.shopPurple : Color.white)
                                                .cornerRadius(12)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        Divider().padding(.vertical, 4)

                        // Apparel Size
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Taglia Abbigliamento")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Spacer()
                                Text(prefs.preferences.hasApparelSize ? prefs.preferences.preferredApparelSize : "Non impostata")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundColor(prefs.preferences.hasApparelSize ? .shopPurple : .shopTextMuted)
                            }

                            HStack(spacing: 8) {
                                ForEach(UserPreferencesManager.apparelSizes, id: \.self) { size in
                                    let isSelected = prefs.preferences.preferredApparelSize == size
                                    Button(action: {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        prefs.preferences.preferredApparelSize = isSelected ? "" : size
                                    }) {
                                        Text(size)
                                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                            .foregroundColor(isSelected ? .white : .shopDark)
                                            .frame(maxWidth: .infinity, minHeight: 38)
                                            .background(isSelected ? Color.shopPurple : Color.white)
                                            .cornerRadius(12)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .shopCard()

                    // Sports Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "sportscourt.fill")
                                .font(.system(size: 15))
                                .foregroundColor(.shopPurple)
                            Text("Sport & Discipline")
                                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                            Spacer()
                        }

                        Text("Seleziona le tue discipline per personalizzare la home e i consigli dell'Assistente AI.")
                            .font(.system(size: 12.5))
                            .foregroundColor(.shopTextMuted)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
                            ForEach(prefs.availableSports, id: \.0) { sport in
                                let isSelected = prefs.preferences.selectedSports.contains(sport.0)
                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    prefs.toggleSport(sport.0)
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: sport.1)
                                            .font(.system(size: 13))
                                        Text(sport.0)
                                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(isSelected ? .white : .shopDark)
                                    .padding(.horizontal, 12)
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .background(isSelected ? Color.shopPurple : Color.shopSurface)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .shopCard()

                    // Favorite Brands Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 15))
                                .foregroundColor(.shopPurple)
                            Text("Brand del Cuore")
                                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                            Spacer()
                        }

                        Text("I brand selezionati avranno priorità nelle proposte e negli avvisi di ribasso.")
                            .font(.system(size: 12.5))
                            .foregroundColor(.shopTextMuted)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(prefs.availableBrands, id: \.self) { brand in
                                    let isSelected = prefs.preferences.favoriteBrands.contains(brand)
                                    Button(action: {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        prefs.toggleBrand(brand)
                                    }) {
                                        HStack(spacing: 6) {
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                            }
                                            Text(brand)
                                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                        }
                                        .foregroundColor(isSelected ? .white : .shopDark)
                                        .padding(.horizontal, 14)
                                        .frame(height: 38)
                                        .background(isSelected ? Color.shopPurple : Color.white)
                                        .cornerRadius(19)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 19)
                                                .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .shopCard()

                    // Replay Onboarding Card
                    Button(action: {
                        showingOnboardingReplay = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.shopPurple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Rivedi configurazione guidata")
                                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                    .foregroundColor(.shopDark)
                                Text("Riapri la presentazione iniziale e aggiorna sport, taglie, brand e store")
                                    .font(.system(size: 12))
                                    .foregroundColor(.shopTextMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.shopTextMuted)
                        }
                        .shopCard()
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.98))

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 6)
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(isPresented: $showingOnboardingReplay) {
            OnboardingView { _ in
                showingOnboardingReplay = false
            }
        }
    }
}

// MARK: - Sub-Page: Notifiche

private struct AccountNotificationsSettingsView: View {
    @ObservedObject private var prefs = UserPreferencesManager.shared
    @ObservedObject private var notifManager = NotificationManager.shared
    @State private var showingNotificationsSheet = false

    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Notifiche")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Open Notifications Center Card
                    Button(action: { showingNotificationsSheet = true }) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.shopPurpleLight)
                                    .frame(width: 42, height: 42)
                                Image(systemName: "bell.badge.fill")
                                    .font(.system(size: 17))
                                    .foregroundColor(.shopPurple)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Centro Notifiche")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.shopDark)
                                Text(notifManager.unreadCount > 0 ? "\(notifManager.unreadCount) non lette" : "Visualizza avvisi e cali di prezzo")
                                    .font(.system(size: 12.5))
                                    .foregroundColor(.shopTextMuted)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.shopTextMuted)
                        }
                        .shopCard()
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.98))

                    // Notification Preferences
                    VStack(spacing: 14) {
                        Toggle(isOn: $prefs.preferences.isPushNotificationEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notifiche Push Ribassi")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Text("Avvisa quando un prodotto della wishlist scende di prezzo")
                                    .font(.system(size: 12))
                                    .foregroundColor(.shopTextMuted)
                            }
                        }
                        .tint(.shopPurple)
                        .onChange(of: prefs.preferences.isPushNotificationEnabled) { enabled in
                            if enabled && !notifManager.isAuthorized {
                                notifManager.requestAuthorization()
                            }
                        }

                        Divider()

                        Toggle(isOn: $prefs.preferences.isHapticFeedbackEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Feedback Aptico")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Text("Vibrazione al tocco su filtri e salvataggio")
                                    .font(.system(size: 12))
                                    .foregroundColor(.shopTextMuted)
                            }
                        }
                        .tint(.shopPurple)

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Soglia Minima di Sconto")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Text("Notifica solo offerte con sconto pari o superiore")
                                    .font(.system(size: 12))
                                    .foregroundColor(.shopTextMuted)
                            }
                            Spacer()
                            Stepper(
                                "\(prefs.preferences.minDiscountThreshold)%",
                                value: $prefs.preferences.minDiscountThreshold,
                                in: 5...60,
                                step: 5
                            )
                            .labelsHidden()
                            Text("-\(prefs.preferences.minDiscountThreshold)%")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundColor(.shopPurple)
                        }
                    }
                    .shopCard()

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 6)
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showingNotificationsSheet) {
            NotificationsView()
        }
    }
}

// MARK: - Sub-Page: Dati e Privacy

private struct AccountPrivacyDataView: View {
    let recentCount: Int
    let storeCount: Int

    @ObservedObject private var supabase = SupabaseManager.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var prefs = UserPreferencesManager.shared
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var recentManager = RecentActivityManager.shared
    @ObservedObject private var notifManager = NotificationManager.shared
    @StateObject private var api = APIService.shared

    @State private var showingClearCacheAlert = false
    @State private var showingDeleteAccountAlert = false
    @State private var showingDeletedDoneAlert = false
    @State private var showingSignOutAlert = false
    @State private var isDeletingData = false
    @State private var exportFileURL: URL? = nil
    @State private var showingExportShareSheet = false

    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Dati e privacy")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 1. Supabase Cloud Sync & Identità Account
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.shopGreenLight)
                                    .frame(width: 36, height: 36)
                                Circle()
                                    .fill(Color.shopGreen)
                                    .frame(width: 11, height: 11)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("FitMatch Cloud Sync")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.shopDark)
                                Text(supabase.syncStatusMessage)
                                    .font(.system(size: 12))
                                    .foregroundColor(.shopTextMuted)
                            }

                            Spacer()

                            Button(action: {
                                Task {
                                    _ = await supabase.checkCloudHealth()
                                    await wishlist.syncWithDatabase()
                                }
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.shopPurple)
                                    .padding(9)
                                    .background(Color.shopPurpleLight)
                                    .clipShape(Circle())
                            }
                        }

                        Text("In modalità ospite i tuoi dati sono associati a un identificativo tecnico pseudonimo locale; effettuando l'accesso vengono sincronizzati in modo cifrato con il tuo profilo.")
                            .font(.system(size: 12))
                            .foregroundColor(.shopTextMuted)
                            .lineSpacing(2)

                        if supabase.isAuthenticated {
                            Divider()
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Account connesso")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundColor(.shopTextMuted)
                                    Text(supabase.currentUserEmail ?? "Utente")
                                        .font(.system(size: 13.5, weight: .bold))
                                        .foregroundColor(.shopDark)
                                }
                                Spacer()
                                Button("Disconnetti") {
                                    showingSignOutAlert = true
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.red)
                            }
                        }
                    }
                    .shopCard()

                    // 2. Consensi & Controllo Trattamento
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Consensi e Trasparenza")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Toggle(isOn: $prefs.preferences.isPushNotificationEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notifiche su ribassi e offerte")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Text("Base giuridica: consenso (art. 6.1.a GDPR) · Revocabile in ogni momento")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.shopTextMuted)
                            }
                        }
                        .tint(.shopPurple)

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Permessi di sistema iOS")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Text(notifManager.isAuthorized ? "Notifiche APNs autorizzate sul dispositivo" : "Notifiche di sistema disattivate")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.shopTextMuted)
                            }
                            Spacer()
                            Button("Impostazioni") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.shopPurple)
                        }
                    }
                    .shopCard()

                    // 3. Documenti Legali Obbligatori (GDPR, Termini, Omnibus/Affiliazioni, Licenze)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Documenti Legali")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                            .padding(.bottom, 8)

                        legalNavigationRow(
                            icon: "hand.raised.fill",
                            title: "Informativa sulla Privacy (GDPR)",
                            subtitle: "Reg. UE 2016/679 · Dati trattati, finalità e diritti",
                            type: .privacy
                        )
                        Divider()

                        legalNavigationRow(
                            icon: "doc.text.fill",
                            title: "Termini e Condizioni d'Uso",
                            subtitle: "Natura del servizio, prezzi e responsabilità",
                            type: .terms
                        )
                        Divider()

                        legalNavigationRow(
                            icon: "arrow.up.right.square.fill",
                            title: "Trasparenza Comparazione & Affiliazioni",
                            subtitle: "Criteri di ranking e link affiliati (Dir. Omnibus)",
                            type: .affiliate
                        )
                        Divider()

                        legalNavigationRow(
                            icon: "checkmark.seal.fill",
                            title: "Licenze Software & Attribuzioni",
                            subtitle: "Framework, servizi cloud e marchi terzi",
                            type: .licenses
                        )
                    }
                    .shopCard(padding: 16)

                    // 4. Diritti dell'Interessato (Accesso, Portabilità, Cancellazione - Artt. 15-20 GDPR)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("I Tuoi Dati e Diritti (GDPR)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                            .padding(.bottom, 6)

                        NavigationLink(destination: RecentlyViewedView()) {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                    .frame(width: 22)
                                Text("Visti di recente")
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Spacer()
                                if recentCount > 0 {
                                    Text("\(recentCount)")
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundColor(.shopTextMuted)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(.shopTextMuted)
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button(action: exportUserDataJSON) {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Esporta i tuoi dati (JSON)")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                    Text("Diritto alla portabilità · Art. 20 GDPR")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.shopTextMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(.shopTextMuted)
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button(action: {
                            ImageCacheManager.shared.clearMemoryCache()
                            URLCache.shared.removeAllCachedResponses()
                            showingClearCacheAlert = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "trash")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Svuota Cache Locale")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                    Text("Rimuove immagini e risposte memorizzate sul dispositivo")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.shopTextMuted)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button(action: {
                            showingDeleteAccountAlert = true
                        }) {
                            HStack(spacing: 12) {
                                if isDeletingData {
                                    ProgressView()
                                        .frame(width: 22)
                                } else {
                                    Image(systemName: "person.crop.circle.badge.xmark")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.red)
                                        .frame(width: 22)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Elimina Account & Tutti i Dati")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundColor(.red)
                                    Text("Diritto alla cancellazione · Art. 17 GDPR")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.shopTextMuted)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeletingData)
                    }
                    .shopCard(padding: 16)

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 6)
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showingExportShareSheet) {
            if let url = exportFileURL {
                AccountShareSheet(items: [url])
            }
        }
        .alert("Cache Svuotata", isPresented: $showingClearCacheAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("La cache locale delle immagini e delle risposte di rete è stata svuotata.")
        }
        .alert("Disconnetti Account", isPresented: $showingSignOutAlert) {
            Button("Annulla", role: .cancel) { }
            Button("Disconnetti", role: .destructive) {
                supabase.signOut()
            }
        } message: {
            Text("Tornerai alla modalità account anonimo locale.")
        }
        .alert("Elimina Account e Tutti i Dati", isPresented: $showingDeleteAccountAlert) {
            Button("Annulla", role: .cancel) { }
            Button("Elimina Definitivamente", role: .destructive) {
                Task { await performFullAccountAndDataDeletion() }
            }
        } message: {
            Text("Questa azione irreversibile eliminerà il tuo profilo, gli articoli salvati, le collezioni, i negozi seguiti, la cronologia e i dati sincronizzati sul cloud (Art. 17 GDPR).")
        }
        .alert("Dati Eliminati", isPresented: $showingDeletedDoneAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Tutti i dati personali locali e associati sul cloud sono stati eliminati con successo.")
        }
    }

    private func legalNavigationRow(icon: String, title: String, subtitle: String, type: AccountLegalType) -> some View {
        NavigationLink(destination: AccountLegalDocumentPage(type: type, storeCount: storeCount)) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.shopPurple)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.shopDark)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(.shopTextMuted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.shopTextMuted)
            }
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    private func exportUserDataJSON() {
        let payload: [String: Any] = [
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "app": "FitMatch",
            "account": [
                "is_authenticated": supabase.isAuthenticated,
                "email": supabase.currentUserEmail ?? NSNull(),
                "pseudonymous_device_id": supabase.deviceId
            ],
            "preferences": [
                "user_name": prefs.preferences.userName,
                "preferred_shoe_size": prefs.preferences.preferredShoeSize,
                "preferred_apparel_size": prefs.preferences.preferredApparelSize,
                "selected_sports": prefs.preferences.selectedSports,
                "favorite_brands": prefs.preferences.favoriteBrands,
                "min_discount_threshold": prefs.preferences.minDiscountThreshold,
                "push_notifications_enabled": prefs.preferences.isPushNotificationEnabled,
                "haptic_feedback_enabled": prefs.preferences.isHapticFeedbackEnabled
            ],
            "wishlist_items": wishlist.items.map { item in
                [
                    "canonical_name": item.canonical_name,
                    "brand": item.brand ?? "",
                    "best_store": item.bestStore ?? "",
                    "current_best_price": item.currentBestPrice,
                    "initial_price": item.initialPrice,
                    "selected_size": item.selectedSize ?? "",
                    "collection_name": item.collectionName ?? "",
                    "alert_enabled": item.isAlertEnabled
                ]
            },
            "collections": wishlist.collections.map(\.name),
            "followed_stores": followedManager.followedStores.map {
                ["store_id": $0.store_id, "store_name": $0.store_name]
            },
            "recent_activity_count": recentManager.activities.count
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("fitmatch_dati_personali.json")
        do {
            try data.write(to: tempURL, options: .atomic)
            self.exportFileURL = tempURL
            self.showingExportShareSheet = true
        } catch {
            print("Export error: \(error)")
        }
    }

    private func performFullAccountAndDataDeletion() async {
        isDeletingData = true
        defer { isDeletingData = false }

        _ = try? await supabase.deleteAccount()

        wishlist.items.removeAll()
        wishlist.collections.removeAll()
        wishlist.saveItems()
        wishlist.saveCollections()

        for store in followedManager.followedStores {
            followedManager.unfollowStore(storeId: store.store_id)
        }
        recentManager.clearAll()
        notifManager.clearAll()
        prefs.preferences = .default

        ImageCacheManager.shared.clearMemoryCache()
        URLCache.shared.removeAllCachedResponses()

        showingDeletedDoneAlert = true
    }
}

private struct AccountShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Sub-Page: Assistenza

private struct AccountSupportView: View {
    let storeCount: Int

    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Assistenza")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            FitMatchBrandEmblem(size: 30)
                            Text("Come funziona FitMatch")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                        }

                        Text("FitMatch confronta in tempo reale prezzi, sconti, spese di spedizione e disponibilità delle taglie su \(storeCount) store sportivi verificati.")
                            .font(.system(size: 13.5))
                            .foregroundColor(.shopTextMuted)
                            .lineSpacing(3)
                    }
                    .shopCard()

                    VStack(alignment: .leading, spacing: 14) {
                        faqRow(
                            question: "Come funzionano gli avvisi di prezzo?",
                            answer: "Salva un prodotto nella tua wishlist e attiva la campanella: FitMatch controlla periodicamente eventuali ribassi e ti invia una notifica."
                        )
                        Divider()
                        faqRow(
                            question: "I prezzi includono la disponibilità taglia?",
                            answer: "Sì! Impostando la tua taglia scarpe o abbigliamento in \"Misure e preferenze\", FitMatch evidenzia subito gli store che hanno la tua misura in stock."
                        )
                        Divider()
                        faqRow(
                            question: "Dove concludo l'acquisto?",
                            answer: "FitMatch ti reindirizza sempre al sito ufficiale del negozio partner selezionato al miglior prezzo."
                        )
                    }
                    .shopCard()

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 6)
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }

    private func faqRow(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
            Text(answer)
                .font(.system(size: 13))
                .foregroundColor(.shopTextMuted)
                .lineSpacing(2)
        }
    }
}

// MARK: - Legal Documents (Privacy, Termini, Trasparenza Affiliazioni, Licenze)

enum AccountLegalType: String, Identifiable {
    case privacy
    case terms
    case affiliate
    case licenses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: return "Informativa sulla Privacy"
        case .terms: return "Termini e condizioni"
        case .affiliate: return "Comparazione e Affiliazioni"
        case .licenses: return "Licenze e attribuzioni"
        }
    }
}

private struct LegalClause: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
}

private struct AccountLegalDocumentContent: View {
    let type: AccountLegalType
    let storeCount: Int

    private var lastUpdated: String { "Aggiornamento: Novembre 2026" }

    private var clauses: [LegalClause] {
        switch type {
        case .privacy:
            return [
                LegalClause(
                    heading: "1. Titolare del trattamento",
                    body: "Il trattamento dei dati personali raccolti tramite l'applicazione iOS FitMatch è effettuato sotto la responsabilità del progetto software FitMatch (sviluppatore Luca Berardi, Italia) in conformità al Regolamento (UE) 2016/679 (GDPR) e al D.Lgs. 196/2003 (Codice Privacy)."
                ),
                LegalClause(
                    heading: "2. Categorie di dati trattati",
                    body: "• Dati di account (facoltativi): indirizzo email e identificativo univoco in caso di registrazione/accesso tramite Email o Accedi con Apple.\n• Identificativo tecnico pseudonimo (device_id): UUID generato localmente per consentire il salvataggio in modalità ospite.\n• Preferenze sportive e misure: taglia scarpe EU, taglia abbigliamento, discipline sportive e brand preferiti.\n• Dati di utilizzo in-app: prodotti salvati in wishlist, collezioni, avvisi prezzo, negozi seguiti/nascosti, cronologia visti di recente, sessioni dell'Assistente AI, recensioni e segnalazioni store inviate volontariamente.\n• Dati tecnici di notifica e redirect: token push APNs (solo previa autorizzazione) e parametro tecnico pseudonimo di attribuzione click (CUID) verso i siti dei negozi partner."
                ),
                LegalClause(
                    heading: "3. Finalità e basi giuridiche (art. 6 GDPR)",
                    body: "• Esecuzione del servizio richiesto (art. 6.1.b): comparazione prezzi e taglie, gestione wishlist, collezioni, preferenze e sincronizzazione cloud.\n• Consenso esplicito (art. 6.1.a): invio di notifiche push su cali prezzo e offerte, sempre revocabile da \"Dati e privacy\", \"Notifiche\" o dalle Impostazioni iOS.\n• Legittimo interesse (art. 6.1.f): sicurezza dell'infrastruttura, prevenzione di abusi o spam sulle recensioni e miglioramento della rilevanza della ricerca."
                ),
                LegalClause(
                    heading: "4. Destinatari, infrastruttura e trasferimenti",
                    body: "FitMatch non vende né cede dati personali a terzi per pubblicità profilata. Per erogare il servizio utilizza:\n• Supabase: autenticazione e database cloud.\n• Render (regione UE - Francoforte): backend FastAPI per ricerca e monitoraggio prezzi.\n• Provider AI (OpenRouter): elaborazione delle sole query testuali sportive per l'Assistente AI, senza invio di email o dati identificativi dell'utente.\n• Apple APNs: recapito delle notifiche push.\n• Sovrn //Commerce: gestione tecnica opzionale dei redirect affiliati verso i negozi partner tramite CUID pseudonimo."
                ),
                LegalClause(
                    heading: "5. Conservazione dei dati",
                    body: "I dati rimangono conservati finché utilizzi l'app o mantieni attivo l'account. Puoi svuotare in qualsiasi momento la cache locale oppure eliminare definitivamente profilo e dati cloud dalla sezione \"Dati e privacy\"."
                ),
                LegalClause(
                    heading: "6. Diritti dell'interessato (artt. 15–22 GDPR)",
                    body: "Hai diritto di accedere ai tuoi dati, rettificarli, ottenerne la portabilità in formato JSON strutturato (funzione \"Esporta i tuoi dati\"), opporti o chiederne la cancellazione immediata (\"Elimina Account & Tutti i Dati\"). Resta fermo il diritto di proporre reclamo al Garante per la Protezione dei Dati Personali (garanteprivacy.it)."
                )
            ]
        case .terms:
            return [
                LegalClause(
                    heading: "1. Oggetto del servizio",
                    body: "FitMatch è una piattaforma informativa e di comparazione prezzi dedicata ad articoli sportivi, calzature running/outdoor, smartwatch GPS e abbigliamento tecnico su \(storeCount) negozi partner verificati."
                ),
                LegalClause(
                    heading: "2. Ruolo di FitMatch (nessuna vendita diretta)",
                    body: "FitMatch non è un negozio online, non vende direttamente alcun prodotto, non elabora pagamenti e non gestisce spedizioni, resi o garanzie legali. Ogni contratto di compravendita si conclude esclusivamente tra l'utente e il rivenditore partner terzo selezionato."
                ),
                LegalClause(
                    heading: "3. Accuratezza di prezzi, sconti e taglie",
                    body: "Prezzi, percentuali di sconto, costi di spedizione e disponibilità delle taglie sono aggiornati periodicamente tramite sincronizzazione dai cataloghi dei negozi partner. Poiché i listini possono variare in tempo reale sui siti dei rivenditori, fanno sempre fede il prezzo finale e la disponibilità mostrati sul sito del venditore prima del pagamento."
                ),
                LegalClause(
                    heading: "4. Assistente AI e suggerimenti tecnici",
                    body: "Le risposte generate dall'Assistente AI e i filtri di abbinamento taglia/sport hanno finalità puramente orientative e informative. Non costituiscono consulenza medica, fisioterapica, ortopedica o professionale."
                ),
                LegalClause(
                    heading: "5. Account, modalità ospite e condotta",
                    body: "Puoi utilizzare FitMatch come ospite oppure registrare un account per sincronizzare i dati. L'utente si impegna a non effettuare scraping automatizzato, richieste abusive verso le API o pubblicazioni di recensioni false o offensive verso i negozi."
                ),
                LegalClause(
                    heading: "6. Proprietà intellettuale",
                    body: "Il codice, l'interfaccia grafica e i testi originali di FitMatch sono protetti dalle vigenti norme sul diritto d'autore. I marchi commerciali, i loghi e le immagini prodotto appartengono ai rispettivi proprietari."
                ),
                LegalClause(
                    heading: "7. Limitazione di responsabilità e legge applicabile",
                    body: "Nei limiti consentiti dalla legge, FitMatch non risponde di eventuali disservizi dei siti terzi o variazioni improvvise di prezzo successive all'ultimo aggiornamento. I presenti Termini sono regolati dalla legge italiana, fatti salvi i diritti inderogabili riconosciuti ai consumatori dal D.Lgs. 206/2005 (Codice del Consumo)."
                )
            ]
        case .affiliate:
            return [
                LegalClause(
                    heading: "1. Trasparenza del ranking (Direttiva Omnibus)",
                    body: "Nella sezione \"Per te\" e nei risultati di ricerca, FitMatch ordina prodotti e negozi sulla base di criteri oggettivi e personalizzati: corrispondenza con la taglia preferita dell'utente, brand e sport selezionati, entità dello sconto e completezza/affidabilità del catalogo. Nessun negozio può acquistare posizionamenti occulti nei risultati di comparazione."
                ),
                LegalClause(
                    heading: "2. Prezzi precedenti e percentuali di sconto",
                    body: "Le percentuali di sconto e i prezzi barrati mostrati nelle schede prodotto derivano dai prezzi di riferimento/listino comunicati dai rispettivi store partner o dallo storico prezzi registrato da FitMatch."
                ),
                LegalClause(
                    heading: "3. Link affiliati e sostenibilità del servizio",
                    body: "FitMatch è gratuito per gli utenti. Alcuni collegamenti in uscita verso i negozi partner possono utilizzare reti di affiliazione (tra cui Sovrn //Commerce) con un identificativo tecnico di click anonimo (CUID). Se completi un acquisto dopo il reindirizzamento, FitMatch può ricevere una commissione dal rivenditore senza alcun costo aggiuntivo né maggiorazione di prezzo per te."
                )
            ]
        case .licenses:
            return [
                LegalClause(
                    heading: "1. Tecnologie Apple iOS",
                    body: "L'applicazione è sviluppata nativamente in Swift per iOS utilizzando framework di sistema Apple: SwiftUI, AuthenticationServices (Accedi con Apple), UserNotifications, Charts, BackgroundTasks e CryptoKit."
                ),
                LegalClause(
                    heading: "2. Servizi e librerie di supporto",
                    body: "• FastAPI & Python ecosystem (backend API e normalizzazione cataloghi)\n• Supabase PostgREST & GoTrue Auth (persistenza dati e autenticazione)\n• URLSession & ImageIO (cache locale immagini e rete)"
                ),
                LegalClause(
                    heading: "3. Marchi e contenuti di terze parti",
                    body: "Tutti i nomi commerciali, i loghi dei \(storeCount) negozi sportivi partner, i nomi dei brand (es. Nike, Asics, Garmin, Hoka, Salomon, Brooks, New Balance e altri) e le immagini dei prodotti sono di proprietà dei rispettivi titolari e vengono visualizzati esclusivamente a scopo descrittivo e di comparazione prezzi."
                )
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(type.title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)

                Text(lastUpdated)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.shopPurple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.shopPurpleLight)
                    .clipShape(Capsule())
            }

            ForEach(clauses) { clause in
                VStack(alignment: .leading, spacing: 6) {
                    Text(clause.heading)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Text(clause.body)
                        .font(.system(size: 13.5))
                        .foregroundColor(.shopTextMuted)
                        .lineSpacing(3.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.shopBorder.opacity(0.65), lineWidth: 1)
                )
            }
        }
    }
}

private struct AccountLegalDocumentPage: View {
    let type: AccountLegalType
    let storeCount: Int

    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: type.title)

            ScrollView(showsIndicators: false) {
                AccountLegalDocumentContent(type: type, storeCount: storeCount)
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }
}

struct AccountLegalSheetView: View {
    let type: AccountLegalType
    let storeCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                AccountLegalDocumentContent(type: type, storeCount: storeCount)
                    .padding(ShopLayout.screenPadding)
                    .padding(.bottom, 24)
            }
            .background(Color.shopSurface.ignoresSafeArea())
            .navigationTitle(type.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.shopPurple)
                }
            }
        }
    }
}

// MARK: - Auth Sheet (Apple Sign In + Email Login & Registration with Supabase Auth)

struct AuthSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabase = SupabaseManager.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var prefs = UserPreferencesManager.shared

    @State private var isRegistering: Bool = false
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Icon & Title
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.shopPurpleLight)
                                .frame(width: 60, height: 60)
                            Image(systemName: isRegistering ? "person.badge.plus" : "lock.shield.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.shopPurple)
                        }
                        .padding(.top, 12)

                        Text(isRegistering ? "Crea il tuo Account" : "Bentornato su FitMatch")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Text(isRegistering ?
                             "Registrati per sincronizzare preferiti, taglie e prezzi monitorati nel cloud." :
                             "Accedi con le tue credenziali per sincronizzare i tuoi prodotti salvati.")
                            .font(.system(size: 13))
                            .foregroundColor(.shopTextMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    // Apple Sign In
                    SignInWithAppleButton(
                        onRequest: { request in
                            errorMessage = nil
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { result in
                            switch result {
                            case .success(let authorization):
                                guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                                    errorMessage = "Credenziali Apple non valide."
                                    return
                                }
                                if let fullName = appleIDCredential.fullName {
                                    let name = [fullName.givenName, fullName.familyName].compactMap { $0 }.joined(separator: " ")
                                    if !name.isEmpty {
                                        prefs.preferences.userName = name
                                    }
                                }
                                guard let tokenData = appleIDCredential.identityToken,
                                      let idToken = String(data: tokenData, encoding: .utf8) else {
                                    errorMessage = "Token Apple mancante. Riprova."
                                    return
                                }
                                let resolvedEmail = appleIDCredential.email ?? SupabaseManager.extractEmailFromJWT(idToken)
                                isLoading = true
                                Task {
                                    do {
                                        try await supabase.signInWithApple(idToken: idToken, email: resolvedEmail)
                                        await wishlist.syncWithDatabase()
                                        await MainActor.run {
                                            isLoading = false
                                            dismiss()
                                        }
                                    } catch {
                                        await MainActor.run {
                                            isLoading = false
                                            errorMessage = error.localizedDescription
                                        }
                                    }
                                }
                            case .failure(let error):
                                let nsErr = error as NSError
                                if nsErr.domain == ASAuthorizationError.errorDomain && nsErr.code == ASAuthorizationError.canceled.rawValue {
                                    return
                                }
                                print("Apple Sign In error: \(error)")
                                errorMessage = "Accesso con Apple non disponibile (\(nsErr.localizedDescription)). Verifica che la capability Sign in with Apple sia attiva."
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 48)
                    .cornerRadius(14)

                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(Color.shopBorder)
                            .frame(height: 1)
                        Text("oppure con email")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                        Rectangle()
                            .fill(Color.shopBorder)
                            .frame(height: 1)
                    }

                    // Mode Selector (Accedi / Registrati)
                    Picker("Modalità", selection: $isRegistering) {
                        Text("Accedi").tag(false)
                        Text("Registrati").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 4)

                    // Error Banner
                    if let err = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(10)
                    }

                    // Success Banner
                    if let success = successMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(success)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(.green)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.green.opacity(0.08))
                        .cornerRadius(10)
                    }

                    // Form Fields
                    VStack(spacing: 14) {
                        // Email Field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.shopDark)

                            HStack {
                                Image(systemName: "envelope")
                                    .foregroundColor(.shopTextMuted)
                                    .frame(width: 20)
                                TextField("", text: $email, prompt: Text(verbatim: "nome@esempio.it").foregroundColor(.shopTextMuted.opacity(0.7)))
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                            }
                            .padding(14)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.shopBorder, lineWidth: 1)
                            )
                        }

                        // Password Field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.shopDark)

                            HStack {
                                Image(systemName: "lock")
                                    .foregroundColor(.shopTextMuted)
                                    .frame(width: 20)
                                if isPasswordVisible {
                                    TextField("Password", text: $password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                } else {
                                    SecureField("Password", text: $password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                }
                                Button(action: { isPasswordVisible.toggle() }) {
                                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                        .foregroundColor(.shopTextMuted)
                                }
                            }
                            .padding(14)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.shopBorder, lineWidth: 1)
                            )
                        }

                        // Confirm Password (Registration only)
                        if isRegistering {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Conferma Password")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.shopDark)

                                HStack {
                                    Image(systemName: "lock.shield")
                                        .foregroundColor(.shopTextMuted)
                                        .frame(width: 20)
                                    SecureField("Ripeti la password", text: $confirmPassword)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                }
                                .padding(14)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.shopBorder, lineWidth: 1)
                                )
                            }
                        }
                    }

                    // Action Button
                    Button(action: {
                        Task { await handleAuthSubmit() }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 4)
                            }
                            Text(isRegistering ? "Crea Account" : "Accedi")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.shopPurple)
                        .cornerRadius(14)
                        .shadow(color: Color.shopPurple.opacity(0.3), radius: 6, y: 3)
                    }
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    .opacity((isLoading || email.isEmpty || password.isEmpty) ? 0.6 : 1.0)
                    .padding(.top, 8)

                    // Anonymous Mode Note
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 11))
                            .foregroundColor(.shopTextMuted)
                        Text("I dati salvati finora come ospite verranno uniti al tuo account.")
                            .font(.system(size: 11))
                            .foregroundColor(.shopTextMuted)
                    }
                    .padding(.top, 4)
                }
                .padding(ShopLayout.screenPadding)
            }
            .background(Color.shopSurface)
            .navigationTitle(isRegistering ? "Registrazione" : "Accedi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") {
                        dismiss()
                    }
                    .foregroundColor(.shopPurple)
                }
            }
        }
    }

    private func handleAuthSubmit() async {
        errorMessage = nil
        successMessage = nil
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanEmail.contains("@") && cleanEmail.contains(".") else {
            errorMessage = "Inserisci un indirizzo email valido."
            return
        }
        guard password.count >= 6 else {
            errorMessage = "La password deve contenere almeno 6 caratteri."
            return
        }
        if isRegistering && password != confirmPassword {
            errorMessage = "Le due password non coincidono."
            return
        }

        isLoading = true
        defer { isLoading = false }

        if isRegistering {
            do {
                let res = try await supabase.signUp(email: cleanEmail, password: password)
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.success)
                if supabase.isAuthenticated {
                    await wishlist.syncWithDatabase()
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    dismiss()
                } else {
                    successMessage = res.message
                }
            } catch {
                errorMessage = error.localizedDescription
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.error)
            }
        } else {
            do {
                try await supabase.signIn(email: cleanEmail, password: password)
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.success)
                await wishlist.syncWithDatabase()
                try? await Task.sleep(nanoseconds: 600_000_000)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.error)
            }
        }
    }
}
