import SwiftUI

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case overview = 0
    case sports = 1
    case sizes = 2
    case brandsAndStores = 3
    case notifications = 4

    var id: Int { rawValue }
}

struct OnboardingView: View {
    var onFinished: ((_ personalized: Bool) -> Void)? = nil

    @ObservedObject private var prefs = UserPreferencesManager.shared
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var notifManager = NotificationManager.shared

    @State private var currentStep: OnboardingStep = .overview
    @State private var transitionDirection: Int = 1
    @State private var isRequestingNotifications: Bool = false
    @State private var brandSearchQuery: String = ""
    @State private var showAllSuggestedStores: Bool = false

    private var storeCountLabel: String {
        let count = max(prefs.activeStores.count, prefs.suggestedOnboardingStores.count)
        return "\(count)+"
    }

    private var hasAnyPersonalization: Bool {
        !prefs.preferences.selectedSports.isEmpty
            || prefs.preferences.hasAnySize
            || !prefs.preferences.favoriteBrands.isEmpty
            || !followedManager.followedStores.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            topNavigationBar

            ZStack {
                stepContent(for: currentStep)
                    .id(currentStep.rawValue)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: transitionDirection >= 0 ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: transitionDirection >= 0 ? .leading : .trailing).combined(with: .opacity)
                        )
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomActionBar
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .task {
            if prefs.activeStores.isEmpty {
                await prefs.fetchActiveStores(apiService: APIService.shared)
            }
        }
    }

    // MARK: - Top Progress & Skip Bar

    private var topNavigationBar: some View {
        HStack(spacing: 12) {
            if currentStep != .overview {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.shopDark)
                        .shopNavCircle(size: 38)
                }
                .buttonStyle(ShopCardPressStyle(scale: 0.92))
            } else {
                Color.clear.frame(width: 38, height: 38)
            }

            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases) { step in
                    Capsule()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.shopPurple : Color.shopBorder)
                        .frame(height: 5)
                        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: currentStep)
                }
            }

            if currentStep != .notifications {
                Button(action: skipOnboarding) {
                    Text("Salta")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.shopTextMuted)
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 48, height: 38)
            }
        }
        .padding(.horizontal, ShopLayout.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Step Router

    @ViewBuilder
    private func stepContent(for step: OnboardingStep) -> some View {
        switch step {
        case .overview:
            overviewStepView
        case .sports:
            sportsStepView
        case .sizes:
            sizesStepView
        case .brandsAndStores:
            brandsAndStoresStepView
        case .notifications:
            notificationsStepView
        }
    }

    // MARK: - Step 0: Cosa fa FitMatch

    private var overviewStepView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        onboardingBrandEmblem
                        Text("FitMatch")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(.shopDark)
                    }

                    Text("Lo sport al miglior prezzo, su misura per te")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.shopDark)
                        .lineSpacing(2)

                    Text("Confronta offerte reali sui principali negozi sportivi in pochi secondi e personalizza subito il tuo feed.")
                        .font(.system(size: 15))
                        .foregroundColor(.shopTextMuted)
                        .lineSpacing(3)
                }
                .padding(.top, 10)

                VStack(spacing: 12) {
                    featureCard(
                        icon: "storefront.fill",
                        iconColor: .shopPurple,
                        iconBg: .shopPurpleLight,
                        title: "Confronto su \(storeCountLabel) store partner",
                        subtitle: "Prezzi live, spese di spedizione e sconti reali riuniti in un unico posto."
                    )

                    featureCard(
                        icon: "sparkles",
                        iconColor: Color(red: 14/255, green: 116/255, blue: 144/255),
                        iconBg: Color(red: 224/255, green: 242/255, blue: 254/255),
                        title: "Ricerca AI & Match Taglia",
                        subtitle: "Chiedi ciò che ti serve all’assistente AI e verifica la disponibilità della tua taglia."
                    )

                    featureCard(
                        icon: "bell.badge.fill",
                        iconColor: .shopGreen,
                        iconBg: .shopGreenLight,
                        title: "Avvisi automatici di ribasso",
                        subtitle: "Salva scarpe, abbigliamento o GPS in wishlist e ricevi una notifica quando calano."
                    )
                }
            }
            .padding(.horizontal, ShopLayout.screenPadding)
            .padding(.bottom, 24)
        }
    }

    private func featureCard(
        icon: String,
        iconColor: Color,
        iconBg: Color,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(iconBg)
                    .frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                Text(subtitle)
                    .font(.system(size: 13.5))
                    .foregroundColor(.shopTextMuted)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .shopCard()
    }

    // MARK: - Step 1: Sport & Discipline

    private var sportsStepView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                stepHeader(
                    badge: "1 · Discipline",
                    title: "Quali sport pratichi?",
                    subtitle: "Seleziona una o più attività per dare priorità ai prodotti più adatti nella home Per te e nell'Assistente AI."
                )

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(prefs.availableSports, id: \.0) { sport in
                        let isSelected = prefs.preferences.selectedSports.contains(sport.0)
                        Button(action: {
                            triggerLightHaptic()
                            prefs.toggleSport(sport.0)
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: sport.1)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(isSelected ? .white : .shopPurple)
                                    .frame(width: 22)

                                Text(sport.0)
                                    .font(.system(size: 13.5, weight: isSelected ? .bold : .semibold, design: .rounded))
                                    .foregroundColor(isSelected ? .white : .shopDark)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)

                                Spacer(minLength: 0)

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.95))
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(isSelected ? Color.shopPurple : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.02), radius: 5, x: 0, y: 2)
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.97))
                    }
                }
            }
            .padding(.horizontal, ShopLayout.screenPadding)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 2: Taglie (Facoltative)

    private var sizesStepView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                stepHeader(
                    badge: "2 · Facoltativo",
                    title: "Vuoi filtrare per taglia?",
                    subtitle: "Seleziona le tue misure per vedere subito i modelli disponibili. Se cerchi solo smartwatch, GPS o accessori puoi saltare."
                )

                // Shoe size card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Taglia Scarpe (EU)", systemImage: "shoeprints.fill")
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Spacer()

                        Text(prefs.preferences.hasShoeSize ? "EU \(prefs.preferences.preferredShoeSize)" : "Facoltativa")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundColor(prefs.preferences.hasShoeSize ? .shopPurple : .shopTextMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(prefs.preferences.hasShoeSize ? Color.shopPurpleLight : Color.shopSurface)
                            .clipShape(Capsule())
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                        ForEach(UserPreferencesManager.shoeSizes, id: \.self) { size in
                            let isSelected = prefs.preferences.preferredShoeSize == size
                            Button(action: {
                                triggerLightHaptic()
                                prefs.preferences.preferredShoeSize = isSelected ? "" : size
                            }) {
                                Text(size)
                                    .font(.system(size: 13.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .foregroundColor(isSelected ? .white : .shopDark)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(isSelected ? Color.shopPurple : Color.shopSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .shopCard()

                // Apparel size card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Taglia Abbigliamento", systemImage: "tshirt.fill")
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Spacer()

                        Text(prefs.preferences.hasApparelSize ? prefs.preferences.preferredApparelSize : "Facoltativa")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundColor(prefs.preferences.hasApparelSize ? .shopPurple : .shopTextMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(prefs.preferences.hasApparelSize ? Color.shopPurpleLight : Color.shopSurface)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 8) {
                        ForEach(UserPreferencesManager.apparelSizes, id: \.self) { size in
                            let isSelected = prefs.preferences.preferredApparelSize == size
                            Button(action: {
                                triggerLightHaptic()
                                prefs.preferences.preferredApparelSize = isSelected ? "" : size
                            }) {
                                Text(size)
                                    .font(.system(size: 13.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .foregroundColor(isSelected ? .white : .shopDark)
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .background(isSelected ? Color.shopPurple : Color.shopSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .shopCard()

                if prefs.preferences.hasAnySize {
                    Button(action: {
                        triggerLightHaptic()
                        prefs.preferences.preferredShoeSize = ""
                        prefs.preferences.preferredApparelSize = ""
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 13))
                            Text("Rimuovi taglie selezionate")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.shopTextMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ShopLayout.screenPadding)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 3: Brand e Store da seguire

    private var displayedOnboardingBrands: [String] {
        let allBrands = prefs.availableBrands
        let query = brandSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if query.isEmpty {
            // Pin selected brands first, then fill up to 12 popular brands so the card stays compact
            var result: [String] = []
            var seen = Set<String>()
            for selected in prefs.preferences.favoriteBrands {
                let key = selected.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(selected)
                }
            }
            for brand in allBrands {
                if result.count >= 12 { break }
                let key = brand.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(brand)
                }
            }
            return result
        }

        let lowQuery = query.lowercased()
        let prefixMatches = allBrands.filter { $0.lowercased().hasPrefix(lowQuery) }
        let prefixSet = Set(prefixMatches.map { $0.lowercased() })
        let containsMatches = allBrands.filter {
            let low = $0.lowercased()
            return !prefixSet.contains(low) && low.contains(lowQuery)
        }
        return Array((prefixMatches + containsMatches).prefix(24))
    }

    private var brandsAndStoresStepView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                stepHeader(
                    badge: "3 · Brand & Store",
                    title: "Marchi e negozi preferiti",
                    subtitle: "Scegli i tuoi brand del cuore e segui subito gli store che vuoi ritrovare nel tab Segui già."
                )

                // Searchable Brands card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Brand del cuore", systemImage: "tag.fill")
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                        Spacer()
                        if !prefs.preferences.favoriteBrands.isEmpty {
                            Text("\(prefs.preferences.favoriteBrands.count) scelti")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.shopPurple)
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.shopTextMuted)

                        TextField(
                            "Cerca tra \(prefs.availableBrands.count) brand (es. Nike, Garmin...)",
                            text: $brandSearchQuery
                        )
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.shopDark)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)

                        if !brandSearchQuery.isEmpty {
                            Button(action: {
                                brandSearchQuery = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(.shopTextMuted.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color.shopSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.shopBorder, lineWidth: 1)
                    )

                    let brandsToDisplay = displayedOnboardingBrands
                    if brandsToDisplay.isEmpty {
                        Text("Nessun brand trovato per \"\(brandSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines))\".")
                            .font(.system(size: 13))
                            .foregroundColor(.shopTextMuted)
                            .padding(.vertical, 8)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 102), spacing: 8)], spacing: 8) {
                            ForEach(brandsToDisplay, id: \.self) { brand in
                                let isSelected = prefs.preferences.favoriteBrands.contains(brand)
                                Button(action: {
                                    triggerLightHaptic()
                                    prefs.toggleBrand(brand)
                                }) {
                                    HStack(spacing: 5) {
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                        }
                                        Text(brand)
                                            .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(isSelected ? .white : .shopDark)
                                    .padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .background(isSelected ? Color.shopPurple : Color.shopSurface)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if brandSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && prefs.availableBrands.count > brandsToDisplay.count {
                            Text("Usa la ricerca sopra per trovare tutti gli altri marchi del catalogo.")
                                .font(.system(size: 11.5))
                                .foregroundColor(.shopTextMuted)
                                .padding(.top, 2)
                        }
                    }
                }
                .shopCard()

                // Stores to follow card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Store da seguire", systemImage: "storefront.fill")
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                        Spacer()
                        if !followedManager.followedStores.isEmpty {
                            Text("\(followedManager.followedStores.count) seguiti")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.shopPurple)
                        }
                    }

                    let allStores = prefs.suggestedOnboardingStores
                    let visibleStores = showAllSuggestedStores ? allStores : Array(allStores.prefix(6))
                    VStack(spacing: 0) {
                        ForEach(visibleStores, id: \.id) { store in
                            let isFollowed = followedManager.isFollowing(storeId: store.id)
                            HStack(spacing: 12) {
                                ShopStoreLogo(
                                    storeName: store.name,
                                    showVerified: false,
                                    showLabel: false,
                                    size: 36
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.name)
                                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopDark)
                                        .lineLimit(1)
                                    Text(store.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundColor(.shopTextMuted)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 6)

                                Button(action: {
                                    followedManager.toggleFollow(storeId: store.id, storeName: store.name)
                                }) {
                                    HStack(spacing: 4) {
                                        if isFollowed {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                        }
                                        Text(isFollowed ? "Seguito" : "Segui")
                                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                    }
                                    .foregroundColor(isFollowed ? .shopPurple : .white)
                                    .padding(.horizontal, 13)
                                    .frame(height: 32)
                                    .background(isFollowed ? Color.shopPurpleLight : Color.shopDark)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 10)

                            if store.id != visibleStores.last?.id {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }

                    if allStores.count > 6 {
                        Button(action: {
                            triggerLightHaptic()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                showAllSuggestedStores.toggle()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Text(showAllSuggestedStores ? "Mostra meno store" : "Mostra tutti i \(allStores.count) store")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                Image(systemName: showAllSuggestedStores ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(.shopPurple)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.shopPurpleLight.opacity(0.65))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .shopCard()
            }
            .padding(.horizontal, ShopLayout.screenPadding)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Step 4: Avvisi Prezzi & Riepilogo

    private var notificationsStepView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                stepHeader(
                    badge: "4 · Avvisi & Avvio",
                    title: "Tutto pronto per iniziare",
                    subtitle: "Attiva gli avvisi di calo prezzo per sapere subito quando un prodotto salvato raggiunge il miglior prezzo."
                )

                // Pre-permission spotlight card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.shopPurpleLight)
                                .frame(width: 48, height: 48)
                            Image(systemName: notifManager.isAuthorized ? "bell.badge.fill" : "bell.and.waves.left.and.right.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.shopPurple)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(notifManager.isAuthorized ? "Notifiche già attive" : "Avvisi ribassi intelligenti")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                            Text("Solo cali di prezzo reali e offerte in linea con le tue preferenze.")
                                .font(.system(size: 13))
                                .foregroundColor(.shopTextMuted)
                        }
                    }
                }
                .shopCard()

                // Recap card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Il tuo profilo iniziale")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    recapRow(
                        icon: "figure.run",
                        label: "Sport",
                        value: prefs.preferences.selectedSports.isEmpty
                            ? "Tutti gli sport"
                            : prefs.preferences.selectedSports.joined(separator: ", ")
                    )

                    Divider()

                    recapRow(
                        icon: "ruler.fill",
                        label: "Taglie",
                        value: prefs.preferences.formattedSizeSummary
                    )

                    Divider()

                    recapRow(
                        icon: "tag.fill",
                        label: "Brand",
                        value: prefs.preferences.favoriteBrands.isEmpty
                            ? "Nessuna preferenza"
                            : prefs.preferences.favoriteBrands.joined(separator: ", ")
                    )

                    Divider()

                    recapRow(
                        icon: "storefront.fill",
                        label: "Store seguiti",
                        value: followedManager.followedStores.isEmpty
                            ? "Nessuno per ora"
                            : followedManager.followedStores.map(\.store_name).joined(separator: ", ")
                    )
                }
                .shopCard()

                Text("Potrai modificare tutte queste impostazioni in qualsiasi momento dal tuo Account.")
                    .font(.system(size: 12.5))
                    .foregroundColor(.shopTextMuted)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, ShopLayout.screenPadding)
            .padding(.bottom, 24)
        }
    }

    private func recapRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(.shopPurple)
                .frame(width: 20)
                .padding(.top, 2)

            Text(label)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(.shopTextMuted)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundColor(.shopDark)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
    }

    // MARK: - Bottom CTA Bar

    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            Button(action: handlePrimaryAction) {
                HStack(spacing: 8) {
                    if isRequestingNotifications {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    }
                    Text(primaryButtonTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.shopPurple)
                .clipShape(Capsule())
                .shadow(color: Color.shopPurple.opacity(0.28), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.98))
            .disabled(isRequestingNotifications)

            if currentStep == .notifications && !notifManager.isAuthorized {
                Button(action: finishWithoutNotifications) {
                    Text("Inizia senza notifiche")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.shopTextMuted)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.plain)
                .disabled(isRequestingNotifications)
            }
        }
        .padding(.horizontal, ShopLayout.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(
            Color.shopSurface
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: -3)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var primaryButtonTitle: String {
        switch currentStep {
        case .overview:
            return "Inizia e personalizza"
        case .sports:
            let count = prefs.preferences.selectedSports.count
            return count > 0 ? "Continua (\(count))" : "Continua"
        case .sizes:
            return prefs.preferences.hasAnySize ? "Continua" : "Salta taglie"
        case .brandsAndStores:
            return "Continua"
        case .notifications:
            return notifManager.isAuthorized ? "Inizia su FitMatch" : "Attiva avvisi e inizia"
        }
    }

    // MARK: - Shared Helpers

    private func stepHeader(badge: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(badge.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.shopPurple)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.shopPurpleLight)
                .clipShape(Capsule())

            Text(title)
                .font(.system(size: 25, weight: .black, design: .rounded))
                .foregroundColor(.shopDark)

            Text(subtitle)
                .font(.system(size: 14.5))
                .foregroundColor(.shopTextMuted)
                .lineSpacing(2)
        }
        .padding(.top, 4)
    }

    private var onboardingBrandEmblem: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(
                    Color.shopPurple,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-25))
                .frame(width: 28, height: 28)

            Circle()
                .fill(Color.shopPurple)
                .frame(width: 8, height: 8)
                .offset(x: 9, y: -9)
        }
        .frame(width: 36, height: 36)
    }

    // MARK: - Navigation & Completion

    private func handlePrimaryAction() {
        triggerLightHaptic()
        if currentStep == .notifications {
            if notifManager.isAuthorized {
                prefs.preferences.isPushNotificationEnabled = true
                finishOnboarding()
            } else {
                isRequestingNotifications = true
                notifManager.requestAuthorization { granted in
                    isRequestingNotifications = false
                    prefs.preferences.isPushNotificationEnabled = granted
                    finishOnboarding()
                }
            }
            return
        }

        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        transitionDirection = 1
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            currentStep = next
        }
    }

    private func goBack() {
        guard let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        triggerLightHaptic()
        transitionDirection = -1
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            currentStep = prev
        }
    }

    private func skipOnboarding() {
        triggerLightHaptic()
        finishOnboarding()
    }

    private func finishWithoutNotifications() {
        triggerLightHaptic()
        prefs.preferences.isPushNotificationEnabled = false
        finishOnboarding()
    }

    private func finishOnboarding() {
        let personalized = hasAnyPersonalization
        prefs.completeOnboarding()
        onFinished?(personalized)
    }

    private func triggerLightHaptic() {
        guard prefs.preferences.isHapticFeedbackEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
