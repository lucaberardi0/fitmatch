import SwiftUI

// MARK: - Sub-Page: Misure e Preferenze (Taglie complete EU 35-48, Sport, Brand ricercabili)

struct AccountPreferencesDetailView: View {
    @ObservedObject private var prefs = UserPreferencesManager.shared
    @State private var showingOnboardingReplay = false
    @State private var brandSearchQuery = ""

    private var displayedBrands: [String] {
        let allBrands = prefs.availableBrands
        let query = brandSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if query.isEmpty {
            var result: [String] = []
            var seen = Set<String>()
            for selected in prefs.preferences.favoriteBrands {
                let key = selected.lowercased()
                if seen.insert(key).inserted {
                    result.append(selected)
                }
            }
            for brand in allBrands {
                if result.count >= 16 { break }
                let key = brand.lowercased()
                if seen.insert(key).inserted {
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

    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Misure e preferenze")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    sizesCard
                    sportsCard
                    brandsCard
                    replayOnboardingCard

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 6)
            }
            .scrollDismissesKeyboard(.interactively)
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

    // MARK: - Sizes Card

    private var sizesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "ruler.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.shopPurple)
                Text("Le Mie Misure & Taglie")
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                Spacer()

                if prefs.preferences.hasAnySize {
                    Button("Rimuovi") {
                        ShopHaptics.impact(.light)
                        prefs.preferences.preferredShoeSize = ""
                        prefs.preferences.preferredApparelSize = ""
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.shopTextMuted)
                    .buttonStyle(.plain)
                } else {
                    Text("Facoltative")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.shopTextMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.shopSurface)
                        .clipShape(Capsule())
                }
            }

            Text("FitMatch usa queste taglie per verificare la disponibilità reale in magazzino e prioritizzare le offerte. Tocca una taglia attiva per rimuoverla.")
                .font(.system(size: 12.5))
                .foregroundColor(.shopTextMuted)
                .lineSpacing(2)

            // Shoe Size (EU 35 - 48 with half sizes + auto-scroll to active)
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

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(UserPreferencesManager.shoeSizes, id: \.self) { size in
                                let isSelected = prefs.preferences.preferredShoeSize == size
                                Button(action: {
                                    ShopHaptics.impact(.light)
                                    prefs.preferences.preferredShoeSize = isSelected ? "" : size
                                }) {
                                    Text(size)
                                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                        .foregroundColor(isSelected ? .white : .shopDark)
                                        .frame(minWidth: 46, minHeight: 38)
                                        .background(isSelected ? Color.shopPurple : Color.shopSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .id(size)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onAppear {
                        let target = prefs.preferences.hasShoeSize ? prefs.preferences.preferredShoeSize : "41"
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }

            Divider().padding(.vertical, 2)

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
                            ShopHaptics.impact(.light)
                            prefs.preferences.preferredApparelSize = isSelected ? "" : size
                        }) {
                            Text(size)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .white : .shopDark)
                                .frame(maxWidth: .infinity, minHeight: 38)
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
        }
        .shopCard()
    }

    // MARK: - Sports Card

    private var sportsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sportscourt.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.shopPurple)
                Text("Sport & Discipline")
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                Spacer()
                if !prefs.preferences.selectedSports.isEmpty {
                    Text("\(prefs.preferences.selectedSports.count) scelti")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.shopPurple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.shopPurpleLight)
                        .clipShape(Capsule())
                }
            }

            Text("Seleziona le tue discipline per personalizzare la home e i consigli dell'Assistente AI.")
                .font(.system(size: 12.5))
                .foregroundColor(.shopTextMuted)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(prefs.availableSports, id: \.0) { sport in
                    let isSelected = prefs.preferences.selectedSports.contains(sport.0)
                    Button(action: {
                        ShopHaptics.impact(.light)
                        prefs.toggleSport(sport.0)
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: sport.1)
                                .font(.system(size: 13))
                                .foregroundColor(isSelected ? .white : .shopPurple)
                            Text(sport.0)
                                .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.84)
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(isSelected ? .white : .shopDark)
                        .padding(.horizontal, 12)
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
    }

    // MARK: - Searchable Brands Card

    private var brandsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "tag.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.shopPurple)
                Text("Brand del Cuore")
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                Spacer()
                if !prefs.preferences.favoriteBrands.isEmpty {
                    Text("\(prefs.preferences.favoriteBrands.count) scelti")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.shopPurple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.shopPurpleLight)
                        .clipShape(Capsule())
                }
            }

            Text("I brand selezionati avranno priorità nella home Per te e nei consigli personalizzati.")
                .font(.system(size: 12.5))
                .foregroundColor(.shopTextMuted)

            // Search bar (aligned with OnboardingView)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(.shopTextMuted)

                TextField(
                    "Cerca tra \(prefs.availableBrands.count) brand (es. Nike, Garmin...)",
                    text: $brandSearchQuery
                )
                .font(.system(size: 13.5))
                .foregroundColor(.shopDark)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)

                if !brandSearchQuery.isEmpty {
                    Button(action: { brandSearchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.shopTextMuted.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 40)
            .background(Color.shopSurface)
            .clipShape(Capsule())

            let brandsToShow = displayedBrands
            if brandsToShow.isEmpty {
                Text("Nessun brand trovato per \"\(brandSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines))\".")
                    .font(.system(size: 12.5))
                    .foregroundColor(.shopTextMuted)
                    .padding(.vertical, 6)
            } else {
                AccountFlowLayout(spacing: 8) {
                    ForEach(brandsToShow, id: \.self) { brand in
                        let isSelected = prefs.preferences.favoriteBrands.contains(brand)
                        Button(action: {
                            ShopHaptics.impact(.light)
                            prefs.toggleBrand(brand)
                        }) {
                            HStack(spacing: 5) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                Text(brand)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                    .lineLimit(1)
                            }
                            .foregroundColor(isSelected ? .white : .shopDark)
                            .padding(.horizontal, 13)
                            .frame(height: 36)
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

                if brandSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && prefs.availableBrands.count > brandsToShow.count {
                    Text("Usa la ricerca sopra per esplorare tutti i \(prefs.availableBrands.count) marchi del catalogo.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.shopTextMuted)
                        .padding(.top, 2)
                }
            }
        }
        .shopCard()
    }

    private var replayOnboardingCard: some View {
        Button(action: {
            ShopHaptics.impact(.light)
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
    }
}

// MARK: - Wrapping Chip Flow Layout

struct AccountFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
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
            if x + size.width > bounds.maxX, x > bounds.minX {
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
