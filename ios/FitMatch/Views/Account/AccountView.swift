import SwiftUI

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

    private let fallbackPartnerStores: [AccountPartnerStore] = [
        AccountPartnerStore(id: "nike", name: "Nike", subtitle: "Store ufficiale Nike · Sped. da €5,00", logoURL: nil),
        AccountPartnerStore(id: "adidas", name: "Adidas", subtitle: "Store ufficiale Adidas · Gratis da €50", logoURL: nil),
        AccountPartnerStore(id: "misterrunning", name: "Mister Running", subtitle: "DHL / UPS · Gratis da €49", logoURL: nil),
        AccountPartnerStore(id: "cisalfa", name: "Cisalfa Sport", subtitle: "BRT / GLS · Gratis da €99", logoURL: nil),
        AccountPartnerStore(id: "maxisport", name: "Maxi Sport", subtitle: "GLS / DHL · Gratis da €99", logoURL: nil),
        AccountPartnerStore(id: "top4running", name: "Top4Running", subtitle: "DPD / BRT · Gratis da €75", logoURL: nil),
        AccountPartnerStore(id: "runningwarehouse", name: "Running Warehouse Europe", subtitle: "UPS / FedEx · Gratis da €59", logoURL: nil),
        AccountPartnerStore(id: "deporvillage", name: "Deporvillage", subtitle: "GLS / DPD · Gratis da €80", logoURL: nil),
        AccountPartnerStore(id: "alltricks", name: "Alltricks", subtitle: "Bartolini (BRT) · Gratis da €69", logoURL: nil),
        AccountPartnerStore(id: "decathlon", name: "Decathlon", subtitle: "Corriere Espresso · Gratis da €60", logoURL: nil),
        AccountPartnerStore(id: "nencini", name: "Nencini Sport", subtitle: "BRT / UPS · Gratis da €100", logoURL: nil),
        AccountPartnerStore(id: "sportler", name: "Sportler", subtitle: "SDA / Espresso · Gratis da €100", logoURL: nil),
        AccountPartnerStore(id: "df_sportspecialist", name: "DF Sport Specialist", subtitle: "Corriere Espresso · Gratis da €100", logoURL: nil),
        AccountPartnerStore(id: "tradeinn", name: "Tradeinn", subtitle: "DHL / UPS · Sped. da €4,99", logoURL: nil),
        AccountPartnerStore(id: "sportit", name: "SportIT", subtitle: "GLS / DHL · Gratis da €59,90", logoURL: nil),
        AccountPartnerStore(id: "tennis_point", name: "Tennis-Point", subtitle: "DHL / UPS · Gratis da €59", logoURL: nil),
        AccountPartnerStore(id: "basketballstore", name: "Basketball Store", subtitle: "BRT / UPS · Gratis da €50", logoURL: nil),
        AccountPartnerStore(id: "nonsolosport", name: "NonSoloSport", subtitle: "BRT · Gratis da €89,99", logoURL: nil),
        AccountPartnerStore(id: "intersport", name: "Intersport Italia", subtitle: "GLS / BRT · Gratis da €59", logoURL: nil),
        AccountPartnerStore(id: "bshopzone", name: "Bshopzone", subtitle: "BRT / GLS · Gratis da €100", logoURL: nil)
    ]

    var partnerStores: [AccountPartnerStore] {
        guard !prefs.activeStores.isEmpty else { return fallbackPartnerStores }
        return prefs.activeStores.map { store in
            let sub = (store.subtitle?.isEmpty == false) ? store.subtitle! : store.base_url
            return AccountPartnerStore(id: store.id, name: store.name, subtitle: sub, logoURL: store.logo_url)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var monitoredItemsCount: Int {
        wishlist.items.filter { $0.isAlertEnabled }.count
    }

    private var targetAlertsCount: Int {
        wishlist.items.filter { $0.isAlertEnabled && $0.targetAlertPrice != nil }.count
    }

    private var totalWishlistSavings: Double {
        wishlist.totalDroppedSavingsEur
    }

    /// Matches the exact items displayed by `RecentlyViewedView` (products & stores only, deduplicated).
    private var recentlyViewedDisplayCount: Int {
        var seen = Set<String>()
        for act in recentManager.activities where act.type == .product || act.type == .store {
            seen.insert(RecentActivityManager.normalizedKey(type: act.type, title: act.title))
        }
        return seen.count
    }

    private var displayUserName: String {
        let trimmed = prefs.preferences.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed.lowercased() != "ospite" {
            return trimmed
        }
        if let email = supabase.currentUserEmail, let namePart = email.components(separatedBy: "@").first, !namePart.isEmpty {
            return namePart.capitalized
        }
        return "Atleta FitMatch"
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

    private var guestSubtitleText: String {
        let savedCount = wishlist.items.count
        let followedCount = followedManager.followedStores.count
        if savedCount > 0 && followedCount > 0 {
            return "Hai \(savedCount) salvati e \(followedCount) negozi seguiti solo su questo dispositivo. Accedi per sincronizzarli nel cloud."
        } else if savedCount > 0 {
            return savedCount == 1
                ? "Hai 1 prodotto salvato solo su questo dispositivo. Accedi per non perderlo e sincronizzarlo."
                : "Hai \(savedCount) prodotti salvati solo su questo dispositivo. Accedi per sincronizzarli nel cloud."
        } else if followedCount > 0 {
            return "Segui già \(followedCount) negozi in locale. Accedi per ritrovarli su tutti i tuoi dispositivi."
        }
        return "Salva ciò che vuoi, monitora ogni prezzo e sincronizza taglie e preferenze su tutti i tuoi dispositivi."
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Pinned Modal Header Bar
                headerBar
                    .shopHeaderBarPadding()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // MARK: - 1. Hero Auth / Profile Section
                        heroSection
                            .padding(.top, 6)

                        // MARK: - 2. Quick Action Grid (Salvati | Segui già)
                        quickActionsGrid

                        // MARK: - 3. Price Monitoring / Tracking Spotlight
                        priceMonitoringSection

                        // MARK: - 4. Grouped Settings Card
                        groupedSettingsCard

                        // MARK: - 5. Secondary Sign Out (Authenticated only, placed cleanly at bottom)
                        if supabase.isAuthenticated {
                            signOutButton
                        }

                        // MARK: - 6. Footer (Version, Legal Links, FitMatch)
                        footerSection
                            .padding(.top, 4)
                            .padding(.bottom, 32)
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
                }
            }
            .background(Color.shopSurface.ignoresSafeArea())
            .navigationBarHidden(true)
            .task {
                notifManager.checkAuthorization()
                async let storesTask: Void = prefs.fetchActiveStores(apiService: api)
                async let statsTask: Void = prefs.fetchAccountMonitorStats()
                _ = await (storesTask, statsTask)
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
            } message: {
                Text("Il nome viene salvato e sincronizzato con il tuo profilo FitMatch.")
            }
            .alert("Disconnetti Account", isPresented: $showingSignOutAlert) {
                Button("Annulla", role: .cancel) { }
                Button("Disconnetti", role: .destructive) {
                    Task { await supabase.signOutAsync() }
                }
            } message: {
                Text("Verrai disconnesso e passerai a una nuova sessione ospite su questo dispositivo. I tuoi prodotti salvati e le preferenze resteranno al sicuro nel cloud e torneranno al prossimo accesso.")
            }
        }
    }

    // MARK: - Modal Header Bar

    private var headerBar: some View {
        ZStack {
            Text("Account")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            HStack {
                Button(action: {
                    ShopHaptics.impact(.light)
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
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
                        .frame(width: 68, height: 68)
                        .shadow(color: Color.shopPurple.opacity(0.24), radius: 10, x: 0, y: 4)

                    Text(userInitial)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(spacing: 4) {
                    Button(action: {
                        ShopHaptics.impact(.light)
                        tempName = prefs.preferences.userName == "Ospite" ? "" : prefs.preferences.userName
                        showingEditNameAlert = true
                    }) {
                        HStack(spacing: 6) {
                            Text(displayUserName)
                                .font(.system(size: 21, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 17))
                                .foregroundColor(.shopTextMuted)
                        }
                        .frame(minHeight: 40)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Modifica nome profilo")

                    if let email = supabase.currentUserEmail, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 13.5))
                            .foregroundColor(.shopTextMuted)
                    }

                    // Dynamic Cloud Sync pill (reflects real connection state)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(supabase.isCloudConnected ? Color.shopGreen : Color.shopOrange)
                            .frame(width: 7, height: 7)
                        Text(supabase.isCloudConnected ? "Cloud Sync attivo" : "Offline · cache locale")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(supabase.isCloudConnected ? .shopGreen : .shopOrange)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(supabase.isCloudConnected ? Color.shopGreenLight : Color.shopOrange.opacity(0.14))
                    .clipShape(Capsule())
                    .padding(.top, 4)
                }

                // Interactive Athlete Profile Quick Pills (taps straight to Preferences)
                if prefs.preferences.hasAnySize || !prefs.preferences.selectedSports.isEmpty || !prefs.preferences.favoriteBrands.isEmpty {
                    NavigationLink(destination: AccountPreferencesDetailView()) {
                        HStack(spacing: 6) {
                            if prefs.preferences.hasShoeSize {
                                profileMetaChip(icon: "shoeprints.fill", text: "EU \(prefs.preferences.preferredShoeSize)")
                            }
                            if prefs.preferences.hasApparelSize {
                                profileMetaChip(icon: "tshirt.fill", text: prefs.preferences.preferredApparelSize)
                            }
                            if !prefs.preferences.selectedSports.isEmpty {
                                let cnt = prefs.preferences.selectedSports.count
                                profileMetaChip(icon: "figure.run", text: cnt == 1 ? prefs.preferences.selectedSports[0] : "\(cnt) sport")
                            }
                        }
                        .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
        } else {
            VStack(spacing: 14) {
                FitMatchBrandEmblem(size: 38)
                    .padding(.bottom, 2)

                VStack(spacing: 7) {
                    Text("Accedi o crea un account")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)
                        .multilineTextAlignment(.center)

                    Text(guestSubtitleText)
                        .font(.system(size: 13.5))
                        .foregroundColor(.shopTextMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2.5)
                        .padding(.horizontal, 12)
                }

                Button(action: {
                    ShopHaptics.impact(.medium)
                    showingAuthSheet = true
                }) {
                    Text("Accedi o registrati")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.shopPurple)
                        .clipShape(Capsule())
                        .shadow(color: Color.shopPurple.opacity(0.24), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.975, pressedOpacity: 0.92))
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func profileMetaChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.shopPurple)
            Text(text)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundColor(.shopDark)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.white)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.shopBorder.opacity(0.8), lineWidth: 1))
    }

    // MARK: - 2. Quick Actions Grid (Salvati | Segui già)

    private var quickActionsGrid: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: AccountSavedProductsDestinationView()) {
                quickActionCard(
                    icon: "heart.fill",
                    iconColor: wishlist.items.isEmpty ? .shopDark : .shopPurple,
                    title: "Salvati",
                    subtitle: wishlist.items.isEmpty ? "Nessun articolo" : (wishlist.items.count == 1 ? "1 articolo" : "\(wishlist.items.count) articoli"),
                    count: wishlist.items.count
                )
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.97, pressedOpacity: 0.94))

            NavigationLink(destination: AccountFollowedStoresDestinationView(partnerStores: partnerStores)) {
                quickActionCard(
                    icon: "storefront.fill",
                    iconColor: followedManager.followedStores.isEmpty ? .shopDark : .shopPurple,
                    title: "Segui già",
                    subtitle: followedManager.followedStores.isEmpty ? "Esplora \(partnerStores.count) store" : (followedManager.followedStores.count == 1 ? "1 negozio" : "\(followedManager.followedStores.count) negozi"),
                    count: followedManager.followedStores.count
                )
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.97, pressedOpacity: 0.94))
        }
    }

    private func quickActionCard(icon: String, iconColor: Color, title: String, subtitle: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(Color.shopSurfaceElevated)
                        .frame(width: 42, height: 42)

                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(iconColor)
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

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.shopDark)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.shopTextMuted)
                    .lineLimit(1)
            }
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
            HStack {
                Text("Monitoraggio prezzi")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                Spacer()
                if let stats = prefs.accountMonitorStats, stats.latestCatalogCheckDate != nil {
                    Text(stats.formattedLastCheckRelative)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                }
            }
            .padding(.horizontal, 2)

            NavigationLink(destination: AccountPriceMonitorView(partnerStores: partnerStores)) {
                HStack(spacing: 14) {
                    priceTrackerIllustration

                    VStack(alignment: .leading, spacing: 4) {
                        if monitoredItemsCount == 0 {
                            Text("Nessun prodotto monitorato")
                                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            let sizeSuffix = prefs.preferences.hasAnySize ? " (\(prefs.preferences.formattedSizeSummary))" : ""
                            Text("I prodotti salvati e i cali di prezzo\(sizeSuffix) appariranno qui")
                                .font(.system(size: 13))
                                .foregroundColor(.shopTextMuted)
                                .lineSpacing(2)
                                .multilineTextAlignment(.leading)
                        } else {
                            let targetPart = targetAlertsCount > 0 ? " · \(targetAlertsCount) con soglia" : ""
                            Text((monitoredItemsCount == 1 ? "1 prodotto monitorato" : "\(monitoredItemsCount) prodotti monitorati") + targetPart)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            let sizeTag = prefs.preferences.hasAnySize ? " · \(prefs.preferences.formattedSizeSummary)" : ""
                            if totalWishlistSavings >= 1.0 {
                                Text("Risparmio rilevato: \(WishlistItem.formatEuro(totalWishlistSavings)) su \(partnerStores.count) store\(sizeTag)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.shopGreen)
                                    .lineSpacing(2)
                                    .multilineTextAlignment(.leading)
                            } else if wishlist.targetReachedCount > 0 {
                                Text("\(wishlist.targetReachedCount) soglia raggiunta! Tocca per vedere le offerte.")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.shopGreen)
                                    .lineSpacing(2)
                                    .multilineTextAlignment(.leading)
                            } else {
                                Text("Controllo automatico attivo su \(partnerStores.count) store partner\(sizeTag)")
                                    .font(.system(size: 13))
                                    .foregroundColor(.shopTextMuted)
                                    .lineSpacing(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.shopTextMuted.opacity(0.75))
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
                .frame(width: 56, height: 56)

            ZStack(alignment: .topTrailing) {
                Image(systemName: monitoredItemsCount > 0 ? "chart.line.downtrend.xyaxis" : "tag.fill")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundColor(.shopPurple)

                Circle()
                    .fill(monitoredItemsCount > 0 ? Color.shopGreen : Color.shopOrange)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: 4, y: -3)
            }
        }
        .frame(width: 56, height: 56)
    }

    // MARK: - 4. Grouped Settings Card

    private var notificationsTrailingLabel: String? {
        if notifManager.unreadCount > 0 { return nil }
        if !notifManager.isAuthorized || !prefs.preferences.isPushNotificationEnabled {
            return "Disattivate"
        }
        return nil
    }

    private var groupedSettingsCard: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: RecentlyViewedView()) {
                settingsRow(
                    iconName: "clock.arrow.circlepath",
                    title: "Visti di recente",
                    trailingValue: recentlyViewedDisplayCount > 0 ? "\(recentlyViewedDisplayCount)" : nil
                )
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.99, pressedOpacity: 0.92))

            rowDivider

            NavigationLink(destination: AccountPreferencesDetailView()) {
                settingsRow(
                    iconName: "ruler.fill",
                    title: "Misure e preferenze",
                    trailingValue: prefs.preferences.configuredPreferencesSummary
                )
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.99, pressedOpacity: 0.92))

            rowDivider

            NavigationLink(destination: AccountNotificationsSettingsView()) {
                settingsRow(
                    iconName: "bell.fill",
                    title: "Notifiche",
                    trailingValue: notificationsTrailingLabel,
                    badgeCount: notifManager.unreadCount
                )
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.99, pressedOpacity: 0.92))

            if !followedManager.hiddenStoreIds.isEmpty {
                rowDivider

                NavigationLink(destination: AccountHiddenStoresView(partnerStores: partnerStores)) {
                    settingsRow(
                        iconName: "eye.slash.fill",
                        title: "Negozi nascosti",
                        trailingValue: "\(followedManager.hiddenStoreIds.count)"
                    )
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.99, pressedOpacity: 0.92))
            }

            rowDivider

            NavigationLink(destination: AccountPrivacyDataView(storeCount: partnerStores.count)) {
                settingsRow(
                    iconName: "lock.shield.fill",
                    title: "Dati e privacy"
                )
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.99, pressedOpacity: 0.92))

            rowDivider

            NavigationLink(destination: AccountSupportView(storeCount: partnerStores.count)) {
                settingsRow(
                    iconName: "questionmark.bubble.fill",
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
        iconName: String,
        title: String,
        trailingValue: String? = nil,
        badgeCount: Int = 0
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.shopDark)
                .frame(width: 24, height: 24)

            Text(title)
                .font(.system(size: 15.5, weight: .medium, design: .rounded))
                .foregroundColor(.shopDark)

            Spacer(minLength: 8)

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
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.shopTextMuted.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .contentShape(Rectangle())
    }

    // MARK: - 5. Secondary Sign Out Button

    private var signOutButton: some View {
        Button(action: {
            ShopHaptics.impact(.light)
            showingSignOutAlert = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                Text("Disconnetti")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.shopRed)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.shopBorder.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.025), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(ShopCardPressStyle(scale: 0.98, pressedOpacity: 0.92))
    }

    // MARK: - 6. Footer Section

    private var footerSection: some View {
        VStack(spacing: 10) {
            Text("Versione \(appVersion) (\(buildNumber))")
                .font(.system(size: 13))
                .foregroundColor(.shopTextMuted)

            HStack(spacing: 14) {
                Button(action: { legalSheetType = .privacy }) {
                    Text("Privacy")
                        .font(.system(size: 13))
                        .underline()
                        .foregroundColor(.shopTextMuted)
                }
                .buttonStyle(.plain)

                Button(action: { legalSheetType = .terms }) {
                    Text("Termini")
                        .font(.system(size: 13))
                        .underline()
                        .foregroundColor(.shopTextMuted)
                }
                .buttonStyle(.plain)

                Button(action: { legalSheetType = .affiliate }) {
                    Text("Affiliazioni")
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
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - FitMatch Brand Emblem

struct FitMatchBrandEmblem: View {
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

struct AccountSubPageHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            HStack {
                Button(action: {
                    ShopHaptics.impact(.light)
                    dismiss()
                }) {
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
