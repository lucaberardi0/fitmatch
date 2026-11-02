import SwiftUI
import AuthenticationServices

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var prefs = UserPreferencesManager.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var supabase = SupabaseManager.shared
    @StateObject private var api = APIService.shared

    @State private var showingEditNameAlert = false
    @State private var tempName = ""
    @State private var showingClearCacheAlert = false
    @State private var showingDeleteAccountAlert = false

    private let shoeSizes = [
        "38", "39", "40", "40.5", "41", "42", "42.5", "43", "43.5", "44", "44.5", "45", "45.5", "46", "47", "48"
    ]
    private let apparelSizes = ["XS", "S", "M", "L", "XL", "XXL"]

    private let availableSports = [
        ("Running Corsa", "figure.run"),
        ("Trail Running", "mountain.2.fill"),
        ("Ciclismo & GPS", "bicycle"),
        ("Fitness & Palestra", "dumbbell.fill"),
        ("Outdoor & Trekking", "tent.fill"),
        ("Padel & Tennis", "tennis.racket")
    ]

    private let availableBrands = [
        "Nike", "Asics", "Garmin", "Salomon", "Hoka", "Brooks", "New Balance", "Under Armour", "Polar", "Oakley"
    ]

    private let partnerStores = [
        ("decathlon", "Decathlon", "Marketplace & Catalogo Globale", "store_decathlon"),
        ("cisalfa", "Cisalfa Sport", "Salesforce Commerce Cloud", "store_cisalfa"),
        ("maxisport", "Maxi Sport", "Magento REST API", "store_maxisport"),
        ("misterrunning", "Mister Running", "Clerk Fast Search", "store_misterrunning"),
        ("nencini", "Nencini Sport", "CSRF Session & GTM Sync", "store_nencini"),
        ("top4running", "Top4Running", "Luigi's Box AI Search", "store_top4running"),
        ("runningwarehouse", "Running Warehouse EU", "VAT IT & Multi-Store", "store_runningwarehouse"),
        ("deporvillage", "Deporvillage", "Algolia Fast Search", "store_deporvillage"),
        ("alltricks", "Alltricks", "Constructor.io API", "store_alltricks"),
        ("sportler", "Sportler", "FactFinder & GTM Alpino", "store_sportler"),
        ("nike", "Nike Official Store", "Next.js Wall State & PDP Engine", "store_nike")
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // MARK: - 1. Hero Profile Header
                    profileHeaderCard

                    // MARK: - 1.5. Production Supabase Cloud Status & Auth
                    supabaseCloudCard

                    // MARK: - 2. Personal Savings & Monitored Stats
                    statsOverviewCard

                    // MARK: - 3. Preferred Sizes (Shoes & Apparel)
                    preferredSizesSection

                    // MARK: - 4. Automated Price Sync & Background Updater
                    automatedUpdaterSection

                    // MARK: - 5. Favorite Sports & Categories
                    favoriteSportsSection

                    // MARK: - 6. Favorite Brands
                    favoriteBrandsSection

                    // MARK: - 7. Monitored Stores (9 Stores)
                    monitoredStoresSection

                    // MARK: - 8. Alert & App Settings
                    settingsSection

                    // Bottom padding
                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(Color(red: 247/255, green: 248/255, blue: 250/255))
            .navigationTitle("Profilo & Misure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Text("Fine")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.shopPurple)
                    }
                }
            }
            .task {
                _ = await api.checkHealth()
                await prefs.checkUpdaterStatus(apiService: api)
            }
            .alert("Modifica Nome", isPresented: $showingEditNameAlert) {
                TextField("Il tuo nome", text: $tempName)
                Button("Annulla", role: .cancel) { }
                Button("Salva") {
                    if !tempName.trimmingCharacters(in: .whitespaces).isEmpty {
                        prefs.preferences.userName = tempName.trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            .alert("Cache Svuotata", isPresented: $showingClearCacheAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("La cache locale dei prezzi e delle ricerche recenti è stata svuotata.")
            }
            .alert("Elimina Account", isPresented: $showingDeleteAccountAlert) {
                Button("Annulla", role: .cancel) { }
                Button("Elimina Definitivamente", role: .destructive) {
                    supabase.signOut()
                    wishlist.items.removeAll()
                    wishlist.saveItems()
                }
            } message: {
                Text("Questa azione rimuoverà tutti i tuoi articoli salvati, le collezioni e i dati memorizzati sul cloud.")
            }
        }
    }

    // MARK: - Profile Header Card

    private var profileHeaderCard: some View {
        HStack(spacing: 16) {
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
                    .shadow(color: Color.shopPurple.opacity(0.35), radius: 8, x: 0, y: 4)

                Image(systemName: "figure.run")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(prefs.preferences.userName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Button(action: {
                        tempName = prefs.preferences.userName
                        showingEditNameAlert = true
                    }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.shopTextMuted)
                    }
                }

                HStack(spacing: 6) {
                    Text("SMART SHOPPER")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.shopPurple)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.shopPurpleLight)
                        .cornerRadius(6)

                    Text("• 9 Negozi Collegati")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                }

                Text(prefs.preferences.userEmail)
                    .font(.system(size: 12))
                    .foregroundColor(.shopTextMuted)
            }

            Spacer()
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(22)
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    // MARK: - Supabase Production Cloud Card & Apple Auth

    private var supabaseCloudCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(red: 62/255, green: 207/255, blue: 142/255).opacity(0.18))
                        .frame(width: 36, height: 36)

                    Circle()
                        .fill(Color(red: 62/255, green: 207/255, blue: 142/255))
                        .frame(width: 12, height: 12)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("FitMatch Cloud Production")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Text("PROD")
                            .font(.system(size: 9.5, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(red: 62/255, green: 207/255, blue: 142/255))
                            .cornerRadius(5)
                    }

                    Text("Render Docker Backend + Supabase PostgreSQL eu-central-1")
                        .font(.system(size: 11))
                        .foregroundColor(.shopTextMuted)
                }

                Spacer()

                Button(action: {
                    Task {
                        _ = await api.checkHealth()
                        _ = await supabase.checkCloudHealth()
                        await wishlist.syncWithDatabase()
                    }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.shopPurple)
                        .padding(8)
                        .background(Color.shopPurpleLight)
                        .clipShape(Circle())
                }
            }

            // Sync & Backend Status
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(api.isCloudOnline ? Color(red: 62/255, green: 207/255, blue: 142/255) : Color.orange)
                        .frame(width: 8, height: 8)

                    Text(api.isCloudOnline ? "Backend Live: fitmatch-backend-klhv.onrender.com" : "Connessione backend in corso...")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.shopDark)
                }

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 62/255, green: 207/255, blue: 142/255))

                    Text("Database: " + supabase.syncStatusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.shopDark)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 243/255, green: 249/255, blue: 246/255))
            .cornerRadius(10)

            Divider()

            // Apple Sign-In / User Profile
            if supabase.isAuthenticated {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Account Connesso")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.shopTextMuted)
                        Text(supabase.currentUserEmail ?? "Utente Apple")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.shopDark)
                    }

                    Spacer()

                    Button("Disconnetti") {
                        supabase.signOut()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red)
                }
            } else {
                SignInWithAppleButton(
                    onRequest: { request in
                        request.requestedScopes = [.fullName, .email]
                    },
                    onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                let userId = appleIDCredential.user
                                let email = appleIDCredential.email ?? prefs.preferences.userEmail
                                supabase.saveSession(token: userId, userId: userId, email: email)
                            }
                        case .failure(let error):
                            print("Apple Sign In failed: \(error)")
                        }
                    }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 44)
                .cornerRadius(12)
            }
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(22)
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    // MARK: - Personal Savings & Monitored Stats Overview

    private var statsOverviewCard: some View {
        let totalSavings = prefs.calculateTotalWishlistSavings(wishlistItems: wishlist.items)
        let activeAlerts = wishlist.items.filter { $0.isAlertEnabled }.count

        return HStack(spacing: 12) {
            // Stat 1: Savings
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.right.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.shopGreen)
                    Text("Risparmio")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.shopTextMuted)
                }
                Text(String(format: "€%.2f", totalSavings))
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(totalSavings > 0 ? .shopGreen : .shopDark)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.03), radius: 5, y: 2)

            // Stat 2: Wishlist Items
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.pink)
                    Text("Salvati")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.shopTextMuted)
                }
                Text("\(wishlist.items.count)")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.shopDark)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.03), radius: 5, y: 2)

            // Stat 3: Active Alerts
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.shopPurple)
                    Text("Alert Attivi")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.shopTextMuted)
                }
                Text("\(activeAlerts)")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.shopDark)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.03), radius: 5, y: 2)
        }
    }

    // MARK: - Preferred Sizes Section

    private var preferredSizesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "ruler.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.shopPurple)
                Text("Le Mie Misure & Taglie")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                Spacer()
            }

            Text("FitMatch userà queste taglie predefinite per verificare la disponibilità reale in magazzino sui 9 store partner.")
                .font(.system(size: 12))
                .foregroundColor(.shopTextMuted)

            // 1. Shoe Size Selector
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Taglia Scarpe (EU)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.shopDark)
                    Spacer()
                    Text("Selezionata: EU \(prefs.preferences.preferredShoeSize)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.shopPurple)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shoeSizes, id: \.self) { size in
                            let isSelected = prefs.preferences.preferredShoeSize == size
                            Button(action: {
                                let gen = UIImpactFeedbackGenerator(style: .light)
                                gen.impactOccurred()
                                prefs.preferences.preferredShoeSize = size
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
                                    .shadow(color: isSelected ? Color.shopPurple.opacity(0.3) : Color.black.opacity(0.02), radius: 3, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider().padding(.vertical, 4)

            // 2. Apparel Size Selector
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Taglia Abbigliamento")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.shopDark)
                    Spacer()
                    Text("Selezionata: \(prefs.preferences.preferredApparelSize)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.shopPurple)
                }

                HStack(spacing: 8) {
                    ForEach(apparelSizes, id: \.self) { size in
                        let isSelected = prefs.preferences.preferredApparelSize == size
                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.impactOccurred()
                            prefs.preferences.preferredApparelSize = size
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
                                .shadow(color: isSelected ? Color.shopPurple.opacity(0.3) : Color.black.opacity(0.02), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(22)
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    // MARK: - Automated Price Sync & Background Updater Section

    private var automatedUpdaterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.shopPurple)
                Text("Sincronizzazione Prezzi & Scheduler")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                Spacer()

                if prefs.updaterStatus?.scheduler_active == true {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.shopGreen)
                            .frame(width: 7, height: 7)
                        Text("Auto-Sync Attivo")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.shopGreen)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.shopGreenLight)
                    .cornerRadius(8)
                }
            }

            Text("Un motore in background monitora periodicamente le offerte dei prodotti salvati, registra lo storico dei prezzi e rileva sconti e cali istantanei.")
                .font(.system(size: 12))
                .foregroundColor(.shopTextMuted)

            // Last Run Info Box
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ultimo controllo prezzi:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                    Text(prefs.updaterStatus?.last_run ?? "Schedulatore attivo ogni 4 ore")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.shopDark)
                }
                Spacer()

                if let drops = prefs.updaterStatus?.last_stats?.price_drops, drops > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("\(drops) cali rilevati")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(8)
                }
            }
            .padding(12)
            .background(Color.shopSurface)
            .cornerRadius(14)

            // Manual Refresh Button
            Button(action: {
                Task {
                    await prefs.triggerPriceRefresh(apiService: api)
                }
            }) {
                HStack(spacing: 8) {
                    if prefs.isRefreshingPrices {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                    }

                    Text(prefs.isRefreshingPrices ? "Aggiornamento in corso..." : "Aggiorna Prezzi Ora su Tutti i 9 Store")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(prefs.isRefreshingPrices ? Color.gray : Color.shopPurple)
                .cornerRadius(14)
                .shadow(color: Color.shopPurple.opacity(0.3), radius: 6, y: 3)
            }
            .disabled(prefs.isRefreshingPrices)

            if let msg = prefs.refreshMessage {
                Text(msg)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.shopPurple)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(22)
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    // MARK: - Favorite Sports & Categories

    private var favoriteSportsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sportscourt.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.shopPurple)
                Text("Sport & Discipline")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                Spacer()
            }

            Text("Seleziona le tue attività sportive per ricevere suggerimenti su misura dal Coach IA.")
                .font(.system(size: 12))
                .foregroundColor(.shopTextMuted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
                ForEach(availableSports, id: \.0) { sport in
                    let isSelected = prefs.preferences.selectedSports.contains(sport.0)
                    Button(action: {
                        let gen = UIImpactFeedbackGenerator(style: .light)
                        gen.impactOccurred()
                        prefs.toggleSport(sport.0)
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: sport.1)
                                .font(.system(size: 13))
                            Text(sport.0)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
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
        .padding(18)
        .background(Color.white)
        .cornerRadius(22)
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    // MARK: - Favorite Brands Section

    private var favoriteBrandsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "tag.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.shopPurple)
                Text("Brand del Cuore")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                Spacer()
            }

            Text("I brand selezionati avranno priorità nei risultati di ricerca e nelle notifiche di ribasso.")
                .font(.system(size: 12))
                .foregroundColor(.shopTextMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableBrands, id: \.self) { brand in
                        let isSelected = prefs.preferences.favoriteBrands.contains(brand)
                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.impactOccurred()
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
                            .shadow(color: isSelected ? Color.shopPurple.opacity(0.25) : Color.black.opacity(0.02), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(22)
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    // MARK: - Monitored Stores (9 Stores)

    private var monitoredStoresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.shopPurple)
                Text("9 Negozi Partner Integrati")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                Spacer()

                HStack(spacing: 4) {
                    Circle().fill(Color.shopGreen).frame(width: 7, height: 7)
                    Text("Tutti Online")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.shopGreen)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.shopGreenLight)
                .cornerRadius(8)
            }

            Text("Connessione multi-thread attiva con bypass TLS JA3 e normalizzazione automatica dei cataloghi.")
                .font(.system(size: 12))
                .foregroundColor(.shopTextMuted)

            VStack(spacing: 10) {
                ForEach(partnerStores, id: \.0) { store in
                    HStack(spacing: 12) {
                        ShopStoreLogo(storeName: store.1, showVerified: false, showLabel: false, size: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(store.1)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.shopDark)

                                if store.0 == "decathlon" {
                                    Text("NOVITÀ")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue)
                                        .cornerRadius(6)
                                }
                            }

                            Text(store.2)
                                .font(.system(size: 11))
                                .foregroundColor(.shopTextMuted)
                        }

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.shopGreen)
                    }
                    .padding(.vertical, 4)

                    if store.0 != partnerStores.last?.0 {
                        Divider()
                    }
                }
            }
            .padding(14)
            .background(Color.shopSurface)
            .cornerRadius(16)
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(22)
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    // MARK: - Settings & Cache

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.shopPurple)
                Text("Impostazioni & Cache")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                Spacer()
            }

            VStack(spacing: 14) {
                // Push Notifications Toggle
                Toggle(isOn: $prefs.preferences.isPushNotificationEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifiche Push Ribassi")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.shopDark)
                        Text("Avvisa quando un prodotto della wishlist scende di prezzo")
                            .font(.system(size: 11))
                            .foregroundColor(.shopTextMuted)
                    }
                }
                .tint(.shopPurple)

                Divider()

                // Haptics Toggle
                Toggle(isOn: $prefs.preferences.isHapticFeedbackEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Feedback Aptico")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.shopDark)
                        Text("Vibrazione al tocco su filtri e salvataggio")
                            .font(.system(size: 11))
                            .foregroundColor(.shopTextMuted)
                    }
                }
                .tint(.shopPurple)

                Divider()

                // Minimum Discount Threshold Stepper
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Soglia Minima di Sconto")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.shopDark)
                        Text("Notifica solo offerte con sconto pari o superiore")
                            .font(.system(size: 11))
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
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.shopPurple)
                }

                Divider()

                // Clear Cache Button
                Button(action: {
                    showingClearCacheAlert = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(.shopDark)
                        Text("Svuota Cache Locale")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.shopDark)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Divider()

                // Delete Account (Apple App Store Requirement)
                Button(action: {
                    showingDeleteAccountAlert = true
                }) {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                        Text("Elimina Account & Dati Cloud")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(14)
            .background(Color.shopSurface)
            .cornerRadius(16)

            // App Version Footer
            VStack(spacing: 3) {
                Text("FitMatch • Engine di Comparazione Sportswear v1.0")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.shopTextMuted)
                Text("Connesso al backend FastAPI: \(api.baseURL)")
                    .font(.system(size: 10))
                    .foregroundColor(.shopTextMuted.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(22)
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }
}
