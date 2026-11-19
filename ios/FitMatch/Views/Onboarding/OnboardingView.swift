import SwiftUI

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case overview = 0
    case sports = 1
    case sizes = 2
    case brandsAndStores = 3
    case notifications = 4

    var id: Int { rawValue }
}

private struct OrbitProductItem: Identifiable {
    let id = UUID()
    let imageName: String
    let size: CGFloat
    let tiltDegrees: Double
}

struct OnboardingView: View {
    var onFinished: ((_ personalized: Bool) -> Void)? = nil

    @ObservedObject private var prefs = UserPreferencesManager.shared
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var notifManager = NotificationManager.shared

    @State private var currentStep: OnboardingStep = .overview
    @State private var transitionDirection: Int = 1

    init(onFinished: ((_ personalized: Bool) -> Void)? = nil) {
        self.onFinished = onFinished
        #if DEBUG
        if let rawStr = ProcessInfo.processInfo.environment["FITMATCH_ONBOARDING_STEP"],
           let raw = Int(rawStr),
           let step = OnboardingStep(rawValue: raw) {
            self._currentStep = State(initialValue: step)
        }
        #endif
    }
    @State private var isRequestingNotifications: Bool = false
    @State private var brandSearchQuery: String = ""
    @State private var showAllSuggestedStores: Bool = false
    @State private var activeLegalSheet: AccountLegalType? = nil

    // Overview headline carousel
    @State private var heroSlideIndex: Int = 0
    @State private var heroHeadlineOpacity: Double = 1.0

    // Notification live-tracking card animation phase (0: Monitoring, 1: Price Drop)
    @State private var trackingPhase: Int = 0

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

    private var heroHeadlines: [String] {
        [
            "Confronta i prezzi\nsu \(storeCountLabel) store",
            "Scopri il tuo prossimo\nbrand preferito",
            "Trova subito\nla tua taglia",
            "Ricevi avvisi quando\nil prezzo scende"
        ]
    }

    private static let orbitItems: [OrbitProductItem] = [
        OrbitProductItem(imageName: "onb_shoe", size: 106, tiltDegrees: -10),
        OrbitProductItem(imageName: "onb_cap", size: 90, tiltDegrees: 8),
        OrbitProductItem(imageName: "onb_glasses", size: 96, tiltDegrees: -9),
        OrbitProductItem(imageName: "onb_red_helmet", size: 92, tiltDegrees: 7),
        OrbitProductItem(imageName: "onb_backpack", size: 90, tiltDegrees: -6),
        OrbitProductItem(imageName: "onb_orange_shoe", size: 104, tiltDegrees: -8),
        OrbitProductItem(imageName: "onb_socks", size: 84, tiltDegrees: 11),
        OrbitProductItem(imageName: "onb_samba", size: 100, tiltDegrees: -8),
        OrbitProductItem(imageName: "onb_watch", size: 84, tiltDegrees: -7)
    ]

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
        .background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
        .task {
            if prefs.activeStores.isEmpty {
                await prefs.fetchActiveStores(apiService: APIService.shared)
            }
        }
        .task(id: currentStep) {
            if currentStep == .overview {
                await runOverviewHeadlineLoop()
            } else if currentStep == .notifications {
                await runTrackingPreviewLoop()
            }
        }
        .sheet(item: $activeLegalSheet) { legalType in
            let count = max(prefs.activeStores.count, prefs.suggestedOnboardingStores.count)
            AccountLegalSheetView(type: legalType, storeCount: count)
        }
    }

    // MARK: - Loops

    private func runOverviewHeadlineLoop() async {
        heroHeadlineOpacity = 1.0
        while !Task.isCancelled && currentStep == .overview {
            try? await Task.sleep(nanoseconds: 3_100_000_000)
            guard !Task.isCancelled && currentStep == .overview else { break }
            withAnimation(.easeOut(duration: 0.18)) {
                heroHeadlineOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled && currentStep == .overview else { break }
            heroSlideIndex = (heroSlideIndex + 1) % heroHeadlines.count
            withAnimation(.easeIn(duration: 0.24)) {
                heroHeadlineOpacity = 1.0
            }
        }
    }

    private func runTrackingPreviewLoop() async {
        trackingPhase = 0
        while !Task.isCancelled && currentStep == .notifications {
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            guard !Task.isCancelled && currentStep == .notifications else { break }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) {
                trackingPhase = trackingPhase == 0 ? 1 : 0
            }
        }
    }

    // MARK: - Top Navigation Chrome

    @ViewBuilder
    private var topNavigationBar: some View {
        if currentStep == .overview {
            HStack(spacing: 6) {
                Text("Scopri lo sport con")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundColor(.shopTextMuted)

                HStack(spacing: 5) {
                    onboardingBrandEmblem(size: 18)
                    Text("FitMatch")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, 6)
        } else {
            ZStack {
                HStack(spacing: 6) {
                    ForEach(OnboardingStep.allCases.filter { $0 != .overview }) { step in
                        Capsule()
                            .fill(step.rawValue <= currentStep.rawValue ? Color.shopPurple : Color.black.opacity(0.08))
                            .frame(width: step == currentStep ? 24 : 16, height: 4)
                            .animation(.spring(response: 0.34, dampingFraction: 0.85), value: currentStep)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 12) {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.shopDark)
                            .frame(width: 40, height: 40)
                            .background(Color.white)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.92))

                    Spacer()

                    if currentStep != .notifications || !notifManager.isAuthorized {
                        Button(action: handleSkipButton) {
                            Text("Salta")
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundColor(.shopDark)
                                .padding(.horizontal, 18)
                                .frame(height: 40)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 3)
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.94))
                        .disabled(isRequestingNotifications)
                    }
                }
            }
            .frame(height: 40)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
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

    // MARK: - Step 0: Circular Product Orbit & Centered Editorial Headline

    private var overviewStepView: some View {
        GeometryReader { geo in
            let compactHeight = geo.size.height < 520
            let scaleFactor: CGFloat = compactHeight ? 0.84 : 1.0
            let orbitRadius = min(geo.size.width * 0.50, max(130, (geo.size.height - 92) * 0.5))

            ZStack {
                CircularProductOrbitView(
                    items: Self.orbitItems,
                    radius: orbitRadius,
                    scaleFactor: scaleFactor
                )

                // Center editorial headline
                Text(heroHeadlines[heroSlideIndex])
                    .font(.system(size: compactHeight ? 23 : 26, weight: .medium))
                    .tracking(-0.5)
                    .foregroundColor(.shopDark)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .opacity(heroHeadlineOpacity)
                    .frame(maxWidth: max(190, orbitRadius * 1.32))
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        triggerLightHaptic()
                        withAnimation(.easeOut(duration: 0.14)) {
                            heroHeadlineOpacity = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            heroSlideIndex = (heroSlideIndex + 1) % heroHeadlines.count
                            withAnimation(.easeIn(duration: 0.2)) {
                                heroHeadlineOpacity = 1.0
                            }
                        }
                    }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    // MARK: - Step 1: Sport & Discipline

    private var sportsStepView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                centeredStepHeader(
                    title: "Quali sport pratichi?",
                    subtitle: "Scegli una o più attività per dare priorità ai prodotti giusti nella home Per te e nell'Assistente AI."
                )

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)],
                    spacing: 11
                ) {
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
                                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                                    .foregroundColor(isSelected ? .white : .shopDark)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.84)

                                Spacer(minLength: 0)

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.95))
                                }
                            }
                            .padding(.horizontal, 13)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(isSelected ? Color.shopPurple : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(isSelected ? Color.shopPurple : Color.black.opacity(0.07), lineWidth: 1)
                            )
                            .shadow(
                                color: isSelected ? Color.shopPurple.opacity(0.22) : Color.black.opacity(0.04),
                                radius: isSelected ? 10 : 8,
                                x: 0,
                                y: 3
                            )
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.97))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 2: Taglie (Facoltative)

    private var sizesStepView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                centeredStepHeader(
                    title: "Vuoi filtrare per taglia?",
                    subtitle: "Mostriamo subito i modelli disponibili nella tua misura. Se cerchi GPS o accessori puoi saltare."
                )

                // Shoe size card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Taglia Scarpe (EU)", systemImage: "shoeprints.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.shopDark)

                        Spacer()

                        Text(prefs.preferences.hasShoeSize ? "EU \(prefs.preferences.preferredShoeSize)" : "Facoltativa")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(prefs.preferences.hasShoeSize ? .shopPurple : .shopTextMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(prefs.preferences.hasShoeSize ? Color.shopPurpleLight : Color(red: 245/255, green: 245/255, blue: 247/255))
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
                                    .font(.system(size: 13.5, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? .white : .shopDark)
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .background(isSelected ? Color.shopPurple : Color(red: 246/255, green: 246/255, blue: 248/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(isSelected ? Color.shopPurple : Color.black.opacity(0.05), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .shopOnboardingCard()

                // Apparel size card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Taglia Abbigliamento", systemImage: "tshirt.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.shopDark)

                        Spacer()

                        Text(prefs.preferences.hasApparelSize ? prefs.preferences.preferredApparelSize : "Facoltativa")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(prefs.preferences.hasApparelSize ? .shopPurple : .shopTextMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(prefs.preferences.hasApparelSize ? Color.shopPurpleLight : Color(red: 245/255, green: 245/255, blue: 247/255))
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
                                    .font(.system(size: 13.5, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? .white : .shopDark)
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .background(isSelected ? Color.shopPurple : Color(red: 246/255, green: 246/255, blue: 248/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(isSelected ? Color.shopPurple : Color.black.opacity(0.05), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .shopOnboardingCard()

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
                                .font(.system(size: 13.5, weight: .medium))
                        }
                        .foregroundColor(.shopTextMuted)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 3: Brand e Store da seguire

    private var displayedOnboardingBrands: [String] {
        let allBrands = prefs.availableBrands
        let query = brandSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if query.isEmpty {
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
            VStack(spacing: 20) {
                centeredStepHeader(
                    title: "Marchi e store preferiti",
                    subtitle: "Scegli i tuoi brand del cuore e segui subito i negozi da ritrovare in Segui già."
                )

                // Searchable Brands card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Brand del cuore", systemImage: "tag.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.shopDark)
                        Spacer()
                        if !prefs.preferences.favoriteBrands.isEmpty {
                            Text("\(prefs.preferences.favoriteBrands.count) scelti")
                                .font(.system(size: 12.5, weight: .semibold))
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
                        .font(.system(size: 14))
                        .foregroundColor(.shopDark)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)

                        if !brandSearchQuery.isEmpty {
                            Button(action: { brandSearchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(.shopTextMuted.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color(red: 245/255, green: 245/255, blue: 247/255))
                    .clipShape(Capsule())

                    let brandsToDisplay = displayedOnboardingBrands
                    if brandsToDisplay.isEmpty {
                        Text("Nessun brand trovato per \"\(brandSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines))\".")
                            .font(.system(size: 13))
                            .foregroundColor(.shopTextMuted)
                            .padding(.vertical, 8)
                    } else {
                        OnboardingFlowLayout(spacing: 8) {
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
                                            .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(isSelected ? .white : .shopDark)
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                                    .background(isSelected ? Color.shopPurple : Color(red: 246/255, green: 246/255, blue: 248/255))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(isSelected ? Color.shopPurple : Color.black.opacity(0.05), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if brandSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && prefs.availableBrands.count > brandsToDisplay.count {
                            Text("Usa la ricerca sopra per trovare tutti gli altri marchi del catalogo.")
                                .font(.system(size: 12))
                                .foregroundColor(.shopTextMuted)
                                .padding(.top, 2)
                        }
                    }
                }
                .shopOnboardingCard()

                // Stores to follow card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Store da seguire", systemImage: "storefront.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.shopDark)
                        Spacer()
                        if !followedManager.followedStores.isEmpty {
                            Text("\(followedManager.followedStores.count) seguiti")
                                .font(.system(size: 12.5, weight: .semibold))
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
                                    size: 38
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.name)
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                        .lineLimit(1)
                                    Text(store.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundColor(.shopTextMuted)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 6)

                                Button(action: {
                                    triggerLightHaptic()
                                    followedManager.toggleFollow(storeId: store.id, storeName: store.name)
                                }) {
                                    HStack(spacing: 4) {
                                        if isFollowed {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                        }
                                        Text(isFollowed ? "Seguito" : "Segui")
                                            .font(.system(size: 12.5, weight: .semibold))
                                    }
                                    .foregroundColor(isFollowed ? .shopPurple : .white)
                                    .padding(.horizontal, 14)
                                    .frame(height: 32)
                                    .background(isFollowed ? Color.shopPurpleLight : Color.shopDark)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 10)

                            if store.id != visibleStores.last?.id {
                                Divider()
                                    .padding(.leading, 50)
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
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: showAllSuggestedStores ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.shopPurple)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.shopPurpleLight.opacity(0.65))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .shopOnboardingCard()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Step 4: Avvisi Prezzi (Inspired by Reference Screenshots 3 & 4)

    private var previewStoreSubtitle: String {
        let storeName = followedManager.followedStores.first?.store_name ?? "Mister Running"
        if prefs.preferences.hasShoeSize {
            return "\(storeName) · EU \(prefs.preferences.preferredShoeSize)"
        }
        return storeName
    }

    private var summaryTokens: [String] {
        var tokens: [String] = []
        if !prefs.preferences.selectedSports.isEmpty {
            let count = prefs.preferences.selectedSports.count
            tokens.append(count == 1 ? prefs.preferences.selectedSports[0] : "\(count) sport")
        }
        if prefs.preferences.hasAnySize {
            tokens.append(prefs.preferences.formattedSizeSummary)
        }
        if !prefs.preferences.favoriteBrands.isEmpty {
            let count = prefs.preferences.favoriteBrands.count
            tokens.append(count == 1 ? prefs.preferences.favoriteBrands[0] : "\(count) brand")
        }
        if !followedManager.followedStores.isEmpty {
            let count = followedManager.followedStores.count
            tokens.append(count == 1 ? followedManager.followedStores[0].store_name : "\(count) store seguiti")
        }
        return tokens
    }

    private var notificationsStepView: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Text("Segui ogni calo di prezzo\nin tempo reale")
                    .font(.system(size: 25, weight: .medium))
                    .tracking(-0.4)
                    .foregroundColor(.shopDark)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.top, geo.size.height > 540 ? 32 : 16)
                    .padding(.horizontal, 24)

                Spacer()

                // Centerpiece floating live price-tracking card (Reference Screenshots 3 & 4)
                VStack(spacing: 16) {
                    priceTrackingShowcaseCard

                    if !summaryTokens.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(summaryTokens.prefix(4), id: \.self) { token in
                                Text(token)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(.shopTextMuted)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(red: 245/255, green: 245/255, blue: 247/255))
                                    .clipShape(Capsule())
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.horizontal, 18)

                Spacer()
                Spacer().frame(height: 16)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var priceTrackingShowcaseCard: some View {
        let isDropPhase = trackingPhase == 1
        let progress: CGFloat = isDropPhase ? 0.78 : 0.40

        return HStack(spacing: 14) {
            // Left: product thumbnail inside soft #F5F5F7 rounded square
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 245/255, green: 245/255, blue: 247/255))
                Image("onb_shoe")
                    .resizable()
                    .scaledToFit()
                    .padding(7)
            }
            .frame(width: 66, height: 66)

            // Center: store label, bold status, purple progress line + dot, price info
            VStack(alignment: .leading, spacing: 5) {
                Text(previewStoreSubtitle)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(.shopTextMuted)
                    .lineLimit(1)

                Text(isDropPhase ? "Prezzo calato (-30%)" : "Monitoraggio attivo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.shopDark)
                    .contentTransition(.opacity)
                    .lineLimit(1)

                // Purple tracking progress line with dot
                GeometryReader { barGeo in
                    let barWidth = max(barGeo.size.width, 40)
                    let dotX = max(5, min(barWidth - 5, barWidth * progress))

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.shopPurple.opacity(0.18))
                            .frame(height: 3)

                        Capsule()
                            .fill(Color.shopPurple)
                            .frame(width: dotX, height: 3)

                        Circle()
                            .fill(Color.shopPurple)
                            .frame(width: 9, height: 9)
                            .shadow(color: Color.shopPurple.opacity(0.35), radius: 3, x: 0, y: 1)
                            .offset(x: dotX - 4.5)
                    }
                    .frame(height: 10)
                }
                .frame(height: 10)
                .padding(.vertical, 1)

                Text(isDropPhase ? "Miglior prezzo: €104,99" : "Prezzo attuale: €149,99")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(.shopTextMuted)
                    .contentTransition(.opacity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }

            // Right: animated soft-3D alert/radar tile
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 245/255, green: 245/255, blue: 247/255))

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isDropPhase
                                    ? [Color.shopPurple.opacity(0.22), Color.shopPurple.opacity(0.08)]
                                    : [Color(red: 199/255, green: 210/255, blue: 254/255), Color(red: 238/255, green: 242/255, blue: 255/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: isDropPhase ? "bell.badge.fill" : "tag.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isDropPhase
                                    ? [Color.shopPurple, Color(red: 124/255, green: 58/255, blue: 237/255)]
                                    : [Color(red: 99/255, green: 102/255, blue: 241/255), Color.shopPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .rotationEffect(.degrees(isDropPhase ? -8 : 0))
                        .scaleEffect(isDropPhase ? 1.06 : 1.0)
                }
            }
            .frame(width: 66, height: 66)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 18, x: 0, y: 6)
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
        .onTapGesture {
            triggerLightHaptic()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                trackingPhase = trackingPhase == 0 ? 1 : 0
            }
        }
    }

    // MARK: - Bottom CTA Bar & Footnote

    private var bottomActionBar: some View {
        VStack(spacing: 12) {
            Button(action: handlePrimaryAction) {
                HStack(spacing: 8) {
                    if isRequestingNotifications {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    }
                    Text(primaryButtonTitle)
                        .font(.system(size: 16.5, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.shopPurple)
                .clipShape(Capsule())
                .shadow(color: Color.shopPurple.opacity(0.24), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(ShopCardPressStyle(scale: 0.98))
            .disabled(isRequestingNotifications)

            if currentStep == .overview {
                overviewLegalFooter
            } else if currentStep == .notifications {
                Text("Ti invieremo anche aggiornamenti sui cali di prezzo dei prodotti salvati, offerte speciali e novità.")
                    .font(.system(size: 12.5))
                    .foregroundColor(.shopTextMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 10)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(Color.white.ignoresSafeArea(edges: .bottom))
    }

    private var overviewLegalFooter: some View {
        Text(overviewLegalAttributedText)
            .font(.system(size: 12.5))
            .foregroundColor(.shopTextMuted)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .padding(.horizontal, 12)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "fitmatch-legal" {
                    triggerLightHaptic()
                    if url.host == "terms" {
                        activeLegalSheet = .terms
                    } else if url.host == "privacy" {
                        activeLegalSheet = .privacy
                    }
                    return .handled
                }
                return .systemAction
            })
    }

    private var overviewLegalAttributedText: AttributedString {
        var prefix = AttributedString("Continuando a utilizzare FitMatch accetti ")
        prefix.foregroundColor = Color.shopTextMuted

        var terms = AttributedString("termini e condizioni del servizio")
        terms.foregroundColor = Color.shopPurple
        terms.link = URL(string: "fitmatch-legal://terms")

        var middle = AttributedString(" e ")
        middle.foregroundColor = Color.shopTextMuted

        var privacy = AttributedString("informativa sulla privacy")
        privacy.foregroundColor = Color.shopPurple
        privacy.link = URL(string: "fitmatch-legal://privacy")

        var dot = AttributedString(".")
        dot.foregroundColor = Color.shopTextMuted

        return prefix + terms + middle + privacy + dot
    }

    private var primaryButtonTitle: String {
        switch currentStep {
        case .overview:
            return "Inizia"
        case .sports:
            let count = prefs.preferences.selectedSports.count
            return count > 0 ? "Continua (\(count))" : "Continua"
        case .sizes:
            return prefs.preferences.hasAnySize ? "Continua" : "Salta taglie"
        case .brandsAndStores:
            return "Continua"
        case .notifications:
            return notifManager.isAuthorized ? "Inizia su FitMatch" : "Ricevi avvisi sui prezzi"
        }
    }

    // MARK: - Shared Helpers

    private func centeredStepHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 25, weight: .medium))
                .tracking(-0.4)
                .foregroundColor(.shopDark)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 14.5))
                .foregroundColor(.shopTextMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 8)
        }
        .padding(.top, 10)
    }

    private func onboardingBrandEmblem(size: CGFloat) -> some View {
        let stroke = max(3.5, size * 0.22)
        return ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(
                    Color.shopPurple,
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-25))
                .frame(width: size * 0.78, height: size * 0.78)

            Circle()
                .fill(Color.shopPurple)
                .frame(width: stroke, height: stroke)
                .offset(x: size * 0.25, y: -size * 0.25)
        }
        .frame(width: size, height: size)
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

    private func handleSkipButton() {
        if currentStep == .notifications {
            finishWithoutNotifications()
        } else {
            skipOnboarding()
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

// MARK: - GPU-Driven Circular Product Orbit (120fps)

private struct CircularProductOrbitView: View {
    let items: [OrbitProductItem]
    let radius: CGFloat
    let scaleFactor: CGFloat

    @State private var isOrbiting: Bool = false

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let angleRad = (Double(index) / Double(max(items.count, 1))) * 2.0 * .pi - (.pi / 2.0)
                let itemSize = item.size * scaleFactor

                Image(item.imageName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: itemSize, height: itemSize)
                    .rotationEffect(.degrees(item.tiltDegrees))
                    .rotationEffect(.degrees(isOrbiting ? -360 : 0))
                    .offset(
                        x: CGFloat(cos(angleRad)) * radius,
                        y: CGFloat(sin(angleRad)) * radius
                    )
            }
        }
        .rotationEffect(.degrees(isOrbiting ? 360 : 0))
        .allowsHitTesting(false)
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(.linear(duration: 38).repeatForever(autoreverses: false)) {
                    isOrbiting = true
                }
            }
        }
    }
}

// MARK: - Onboarding White Card Styling

private extension View {
    func shopOnboardingCard() -> some View {
        self
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 5)
    }
}

// MARK: - Wrapping Pill Flow Layout

private struct OnboardingFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
