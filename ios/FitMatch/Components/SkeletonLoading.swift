import SwiftUI

// MARK: - Shopify "Shop" Skeleton & Shimmer Color Palette

extension Color {
    /// Exact soft neutral gray used for skeleton placeholders in Shopify Shop
    static let shopSkeleton = Color(red: 236/255, green: 238/255, blue: 242/255)
    static let shopSkeletonHighlight = Color(red: 248/255, green: 249/255, blue: 251/255)
}

// MARK: - High-Performance 60/120fps Shimmer Modifier

public struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.2
    var isAnimating: Bool = true
    var duration: Double = 1.35

    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    if isAnimating {
                        let w = geo.size.width
                        let h = geo.size.height
                        let bandWidth = max(w * 1.1, 160)

                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.0), location: 0.0),
                                .init(color: Color.white.opacity(0.55), location: 0.5),
                                .init(color: Color.white.opacity(0.0), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: bandWidth, height: max(h * 1.8, 100))
                        .rotationEffect(.degrees(15))
                        .offset(x: phase * (w + bandWidth) - (bandWidth * 0.4))
                        .blendMode(.screen)
                        .mask(content)
                    }
                }
            )
            .onAppear {
                guard isAnimating else { return }
                withAnimation(
                    .linear(duration: duration)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.3
                }
            }
    }
}

public extension View {
    func shimmering(active: Bool = true, duration: Double = 1.35) -> some View {
        self.modifier(ShimmerModifier(isAnimating: active, duration: duration))
    }
}

// MARK: - Reusable Skeleton Primitives

struct ShopSkeletonBlock: View {
    var cornerRadius: CGFloat = 20
    var width: CGFloat? = nil
    var height: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.shopSkeleton)
            .frame(width: width, height: height)
            .shimmering()
    }
}

struct ShopSkeletonCapsule: View {
    var width: CGFloat? = nil
    var height: CGFloat = 36

    var body: some View {
        Capsule()
            .fill(Color.shopSkeleton)
            .frame(width: width, height: height)
            .shimmering()
    }
}

struct ShopSkeletonCircle: View {
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(Color.shopSkeleton)
            .frame(width: size, height: size)
            .shimmering()
    }
}

struct ShopSkeletonTextLine: View {
    var width: CGFloat? = nil
    var height: CGFloat = 13
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.shopSkeleton)
            .frame(width: width, height: height)
            .shimmering()
    }
}

// MARK: - 1. Home Screen Skeleton (100% Identical to Shopify Shop App Screenshot)

struct ShopHomeSkeletonView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Horizontal Skeleton Pills Bar (Matching Per te, Saldi, Segui già, Salvati)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ShopSkeletonCapsule(width: 74, height: 36)
                    ShopSkeletonCapsule(width: 145, height: 36)
                    ShopSkeletonCapsule(width: 90, height: 36)
                    ShopSkeletonCapsule(width: 80, height: 36)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, ShopLayout.compactSpacing)

            // Scrollable Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: ShopLayout.sectionSpacing) {
                    // 1. Top Carousel Cards Skeleton (with Card 2 peeking on right edge)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            let cardWidth = max(UIScreen.main.bounds.width - 56, 310)
                            let thumbSize = (cardWidth - (ShopLayout.cardPadding * 2) - 20) / 3
                            let cardHeight = max(164, thumbSize + (ShopLayout.cardPadding * 2) + 14 + 32)
                            ShopSkeletonBlock(cornerRadius: ShopLayout.largeCardRadius, width: cardWidth, height: cardHeight)
                            ShopSkeletonBlock(cornerRadius: ShopLayout.largeCardRadius, width: cardWidth, height: cardHeight)
                        }
                        .padding(.horizontal, ShopLayout.screenPadding)
                    }
                    .padding(.top, 2)

                    // 2. Large Tall Feed Card Skeleton (Store Showcase)
                    ShopSkeletonBlock(
                        cornerRadius: ShopLayout.largeCardRadius,
                        width: UIScreen.main.bounds.width - (ShopLayout.screenPadding * 2),
                        height: 390
                    )
                    .padding(.horizontal, ShopLayout.screenPadding)

                    // 3. Third Bottom Card Peeking
                    ShopSkeletonBlock(
                        cornerRadius: ShopLayout.largeCardRadius,
                        width: UIScreen.main.bounds.width - (ShopLayout.screenPadding * 2),
                        height: 220
                    )
                    .padding(.horizontal, ShopLayout.screenPadding)

                    Spacer(minLength: ShopLayout.bottomDockClearance)
                }
            }
        }
    }
}

// MARK: - 2. Product Card Skeleton (for 2-Column Grids)

struct ShopProductCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Product Image Box
            ShopSkeletonBlock(cornerRadius: 16, height: 165)
                .frame(maxWidth: .infinity)

            // Store Tag Line
            ShopSkeletonTextLine(width: 75, height: 10, cornerRadius: 4)

            // Title Line 1 & 2
            ShopSkeletonTextLine(height: 12, cornerRadius: 5)
                .frame(maxWidth: .infinity)

            ShopSkeletonTextLine(width: 105, height: 12, cornerRadius: 5)

            // Price Line
            HStack(spacing: 8) {
                ShopSkeletonTextLine(width: 65, height: 16, cornerRadius: 6)
                ShopSkeletonTextLine(width: 45, height: 12, cornerRadius: 4)
            }
            .padding(.top, 2)
        }
        .padding(6)
        .background(Color.white)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }
}

// MARK: - 3. Deals Screen Skeleton

struct ShopDealsSkeletonView: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Category Pills Skeleton
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { i in
                        ShopSkeletonCapsule(width: i == 0 ? 70 : 85, height: 34)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)

            // Deals Cards Grid
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Store 1 Section Skeleton
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ShopSkeletonCircle(size: 32)
                            ShopSkeletonTextLine(width: 120, height: 16, cornerRadius: 6)
                            Spacer()
                            ShopSkeletonCapsule(width: 75, height: 28)
                        }
                        .padding(.horizontal, 16)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ShopProductCardSkeleton()
                            ShopProductCardSkeleton()
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(24)
                    .padding(.horizontal, 16)

                    // Store 2 Section Skeleton
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ShopSkeletonCircle(size: 32)
                            ShopSkeletonTextLine(width: 140, height: 16, cornerRadius: 6)
                            Spacer()
                            ShopSkeletonCapsule(width: 75, height: 28)
                        }
                        .padding(.horizontal, 16)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ShopProductCardSkeleton()
                            ShopProductCardSkeleton()
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(24)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 120)
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - 4. Search Screen Skeletons & Agent Thinking HUD (AI Deep Dive & Classic)

// MARK: - AI Query Analysis for Agent Thinking

struct QueryAnalysisTag: Identifiable, Equatable {
    let id: String
    let icon: String
    let text: String
}

struct QueryAnalysis {
    var category: String? = nil
    var budget: String? = nil
    var brand: String? = nil
    var technicalSpec: String? = nil
    var size: String? = nil
    var gender: String? = nil

    static func analyze(_ query: String) -> QueryAnalysis {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = clean.lowercased()
        var res = QueryAnalysis()

        // 1. Budget extraction
        let budgetPatterns = [
            #"(?:sotto|meno di|entro|fino a|max|massimo)\s+(?:i\s+)?(\d+)(?:\s*€|\s*euro)?"#,
            #"<\s*(\d+)(?:\s*€|\s*euro)?"#,
            #"(\d+)(?:\s*€|\s*euro)\s+max"#
        ]
        for pattern in budgetPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let r = Range(match.range(at: 1), in: lower) {
                let amount = String(lower[r])
                res.budget = "max €\(amount)"
                break
            }
        }
        if res.budget == nil && (lower.contains("economiche") || lower.contains("economici") || lower.contains("sconto") || lower.contains("offerta")) {
            res.budget = "Miglior prezzo"
        }

        // 2. Brand detection
        let knownBrands = [
            "Nike", "Adidas", "Asics", "Hoka", "Saucony", "Brooks", "Salomon", "Puma",
            "Garmin", "Oakley", "Coros", "New Balance", "Regatta", "Arena", "Tyr", "Mizuno", "On"
        ]
        for b in knownBrands {
            if lower.contains(b.lowercased()) {
                res.brand = b
                break
            }
        }

        // 3. Size extraction (e.g. "taglia 42.5", "tg M", "numero 43")
        let sizePattern = #"(?:taglia|tg|numero|n°)\s*([0-9]{2}(?:[.,]5)?|xs|s|m|l|xl|xxl)\b"#
        if let regex = try? NSRegularExpression(pattern: sizePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let r = Range(match.range(at: 1), in: lower) {
            let rawSize = String(lower[r]).replacingOccurrences(of: ",", with: ".").uppercased()
            res.size = "Taglia \(rawSize)"
        }

        // 4. Gender detection
        if lower.range(of: #"\buomo\b"#, options: .regularExpression) != nil {
            res.gender = "Uomo"
        } else if lower.range(of: #"\bdonna\b"#, options: .regularExpression) != nil {
            res.gender = "Donna"
        }

        // 5. Category detection
        let categories: [(keywords: [String], name: String)] = [
            (["occhiali", "occhialini", "lenti"], "Occhiali & Protezione"),
            (["scarpe", "scarpa", "sneaker", "footwear", "scarpini"], "Calzature Tecniche"),
            (["pantaloncini", "shorts", "leggings", "tights", "pantaloni"], "Pantaloni & Shorts"),
            (["maglia", "t-shirt", "long sleeve", "top", "canotta", "termica"], "Abbigliamento Tecnico"),
            (["giacca", "antivento", "antipioggia", "k-way"], "Giacche & Protezione"),
            (["orologio", "smartwatch", "cardio", "gps", "forerunner"], "Smartwatch & GPS"),
            (["zaino", "gilet idratazione", "cintura", "borraccia"], "Accessori & Idratazione")
        ]
        for cat in categories {
            if cat.keywords.contains(where: { lower.contains($0) }) {
                res.category = cat.name
                break
            }
        }

        // 6. Activity / Technical specs
        if lower.contains("running") || lower.contains("corsa") || lower.contains("maratona") {
            res.technicalSpec = "Running su strada"
        } else if lower.contains("trail") {
            res.technicalSpec = "Trail Running"
        } else if lower.contains("hyrox") || lower.contains("crossfit") || lower.contains("palestra") {
            res.technicalSpec = "Allenamento Ibrido / Hyrox"
        } else if lower.contains("nuoto") || lower.contains("piscina") {
            res.technicalSpec = "Nuoto & Sport acquatici"
        } else if lower.contains("bici") || lower.contains("ciclismo") {
            res.technicalSpec = "Ciclismo & Bici"
        } else if lower.contains("ammortizzat") {
            res.technicalSpec = "Ammortizzazione avanzata"
        } else if lower.contains("carbonio") || lower.contains("gara") {
            res.technicalSpec = "Piastra in carbonio / Gara"
        } else if lower.contains("pioggia") || lower.contains("gtx") || lower.contains("impermeabil") {
            res.technicalSpec = "Membrana impermeabile"
        } else if lower.contains("sport") {
            res.technicalSpec = "Attrezzatura & Sport"
        }

        return res
    }

    var tags: [QueryAnalysisTag] {
        var result: [QueryAnalysisTag] = []
        if let br = brand {
            result.append(QueryAnalysisTag(id: "brand", icon: "tag.fill", text: br))
        }
        if let cat = category {
            result.append(QueryAnalysisTag(id: "cat", icon: "square.grid.2x2.fill", text: cat))
        }
        if let spec = technicalSpec {
            result.append(QueryAnalysisTag(id: "spec", icon: "bolt.fill", text: spec))
        }
        if let g = gender {
            result.append(QueryAnalysisTag(id: "gender", icon: "person.fill", text: g))
        }
        if let sz = size {
            result.append(QueryAnalysisTag(id: "size", icon: "ruler.fill", text: sz))
        }
        if let bg = budget {
            result.append(QueryAnalysisTag(id: "budget", icon: "eurosign.circle.fill", text: bg))
        }
        return result
    }

    var summaryText: String {
        var parts: [String] = []
        if let cat = category { parts.append(cat) }
        if let spec = technicalSpec { parts.append(spec) }
        if let br = brand { parts.append("Brand: \(br)") }
        if let sz = size { parts.append(sz) }
        if let bg = budget { parts.append(bg) }
        if parts.isEmpty {
            return "Ricerca semantica cataloghi partner"
        }
        return parts.joined(separator: " • ")
    }
}

// MARK: - Minimal ChatGPT-Style Agent Thinking Indicator

struct ShopAgentThinkingCardView: View {
    var query: String
    var isFollowUp: Bool = false
    var steps: [SearchThinkingStep] = []
    var startedAt: Date = Date()

    @State private var isExpanded: Bool = true
    @State private var dotPulse: Bool = false

    private var cleanQuery: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? "la tua ricerca" : q
    }

    private var queryAnalysis: QueryAnalysis {
        QueryAnalysis.analyze(query)
    }

    private var displaySteps: [SearchThinkingStep] {
        if !steps.isEmpty {
            return steps
        }
        let localDetail: String
        if !queryAnalysis.tags.isEmpty {
            localDetail = queryAnalysis.summaryText
        } else if isFollowUp {
            localDetail = "Collegamento al contesto per «\(cleanQuery)»"
        } else {
            localDetail = "Analisi della richiesta per «\(cleanQuery)»"
        }
        return [
            SearchThinkingStep(
                id: "init",
                status: .running,
                title: "Sto pensando…",
                detail: localDetail,
                elapsedMs: nil
            )
        ]
    }

    private var activeStep: SearchThinkingStep? {
        displaySteps.last(where: { $0.status == .running }) ?? displaySteps.last
    }

    private var dynamicHeadline: String {
        guard let active = activeStep else {
            return "Sto pensando…"
        }
        let id = active.id.lowercased()
        let lowerTitle = active.title.lowercased()

        if id == "init" || id == "context" || id == "parse" || lowerTitle.contains("analizz") || lowerTitle.contains("recupero") || lowerTitle.contains("interpret") {
            return "Sto pensando…"
        }
        if id == "catalog" || lowerTitle.contains("cerco") || lowerTitle.contains("catalogo") {
            return active.status == .done ? "Confronto i prezzi…" : "Cerco prodotti…"
        }
        if id == "synthesis" || lowerTitle.contains("confronto") || lowerTitle.contains("sintesi") {
            return active.status == .done ? "Preparo la risposta…" : "Confronto i prezzi…"
        }
        if id == "cache" {
            return "Recupero le offerte…"
        }
        return active.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Minimal ChatGPT-style inline thinking row (dot + shimmering status + discreet chevron)
            Button(action: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.shopPurple.opacity(dotPulse ? 0.22 : 0.10))
                            .frame(width: 18, height: 18)
                            .scaleEffect(dotPulse ? 1.15 : 0.90)

                        Circle()
                            .fill(Color.shopPurple)
                            .frame(width: 8, height: 8)
                            .scaleEffect(dotPulse ? 1.08 : 0.92)
                    }

                    HStack(spacing: 5) {
                        Text(dynamicHeadline)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(red: 72/255, green: 72/255, blue: 86/255))
                            .lineLimit(1)
                            .shimmering(duration: 1.45)
                            .id(dynamicHeadline)
                            .transition(.opacity)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 150/255, green: 150/255, blue: 162/255))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable reasoning trace (shown by default during search loading)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(displaySteps) { step in
                        let isRunning = step.status == .running
                        let isDone = step.status == .done

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: isDone ? "checkmark" : (isRunning ? "circle.fill" : "minus"))
                                .font(.system(size: isRunning ? 6 : 9.5, weight: .bold))
                                .foregroundColor(isDone || isRunning ? .shopPurple : .shopTextMuted)
                                .frame(width: 12, height: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .font(.system(size: 13, weight: isRunning ? .semibold : .medium))
                                    .foregroundColor(isRunning ? .shopDark : Color(red: 110/255, green: 110/255, blue: 122/255))

                                if let detail = step.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(red: 145/255, green: 145/255, blue: 158/255))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 12)
                .overlay(
                    Rectangle()
                        .fill(Color.shopPurple.opacity(0.18))
                        .frame(width: 1.5),
                    alignment: .leading
                )
                .padding(.leading, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.22), value: steps)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                dotPulse = true
            }
        }
    }
}

// MARK: - Preview Carousel Skeleton Cards (Mirrors Real AI Deep Dive Layout)

struct ShopThemedCarouselSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShopSkeletonBlock(cornerRadius: 16, width: 152, height: 152)

            ShopSkeletonTextLine(width: 64, height: 10, cornerRadius: 4)
            ShopSkeletonTextLine(width: 140, height: 12, cornerRadius: 5)
            ShopSkeletonTextLine(width: 104, height: 12, cornerRadius: 5)

            HStack(spacing: 6) {
                ShopSkeletonTextLine(width: 58, height: 14, cornerRadius: 5)
                ShopSkeletonCapsule(width: 54, height: 18)
            }
            .padding(.top, 2)
        }
        .frame(width: 152)
    }
}

struct ShopComparativeSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShopSkeletonBlock(cornerRadius: 16, width: 200, height: 132)
            ShopSkeletonTextLine(width: 145, height: 13, cornerRadius: 5)
            ShopSkeletonTextLine(width: 175, height: 11, cornerRadius: 4)
            ShopSkeletonTextLine(width: 118, height: 11, cornerRadius: 4)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

struct ShopSearchDeepDiveSkeletonView: View {
    var query: String = ""
    var thinkingSteps: [SearchThinkingStep] = []
    var thinkingStartedAt: Date = Date()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Minimal ChatGPT-style Thinking Line
                ShopAgentThinkingCardView(
                    query: query,
                    isFollowUp: false,
                    steps: thinkingSteps,
                    startedAt: thinkingStartedAt
                )
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 10)

                // 2. Quiet Editorial Narrative Preview
                VStack(alignment: .leading, spacing: 8) {
                    ShopSkeletonTextLine(height: 12, cornerRadius: 5)
                        .frame(maxWidth: .infinity)
                    ShopSkeletonTextLine(width: 260, height: 12, cornerRadius: 5)
                    ShopSkeletonTextLine(width: 175, height: 12, cornerRadius: 5)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .opacity(0.65)

                // 3. Soft Horizontal Product Placeholder Row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ShopThemedCarouselSkeletonCard()
                        ShopThemedCarouselSkeletonCard()
                        ShopThemedCarouselSkeletonCard()
                    }
                    .padding(.horizontal, ShopLayout.screenPadding)
                }
                .disabled(true)
                .opacity(0.65)

                Spacer(minLength: ShopLayout.bottomFilterDockClearance)
            }
        }
    }
}

// MARK: - 3c. Search Landing ("Visti di recente" & "Conversazioni recenti") Skeleton

struct ShopSearchRecentlyViewedSkeletonSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ShopSkeletonTextLine(width: 132, height: 19, cornerRadius: 6)
                ShopSkeletonBlock(cornerRadius: 4, width: 10, height: 14)
                Spacer()
            }
            .padding(.horizontal, ShopLayout.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ShopLayout.compactSpacing) {
                    ForEach(0..<4, id: \.self) { _ in
                        ShopSkeletonBlock(cornerRadius: 18, width: 136, height: 140)
                    }
                }
                .padding(.horizontal, ShopLayout.screenPadding)
            }
            .disabled(true)
        }
    }
}

struct ShopSearchRecentChatsSkeletonSection: View {
    var rowCount: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ShopSkeletonTextLine(width: 184, height: 19, cornerRadius: 6)
                ShopSkeletonCapsule(width: 24, height: 20)
                Spacer()
            }
            .padding(.horizontal, ShopLayout.screenPadding)

            VStack(spacing: 10) {
                ForEach(0..<rowCount, id: \.self) { index in
                    HStack(spacing: 13) {
                        ShopSkeletonBlock(cornerRadius: 13, width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 6) {
                            ShopSkeletonTextLine(width: index == 1 ? 190 : 155, height: 14, cornerRadius: 5)
                            HStack(spacing: 6) {
                                if index == 0 {
                                    ShopSkeletonCapsule(width: 68, height: 17)
                                }
                                ShopSkeletonTextLine(width: index == 2 ? 120 : 88, height: 11, cornerRadius: 4)
                            }
                        }

                        Spacer(minLength: 6)

                        ShopSkeletonBlock(cornerRadius: 3, width: 8, height: 13)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Color.white)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 8, y: 2)
                }
            }
            .padding(.horizontal, ShopLayout.screenPadding)
        }
    }
}

struct ShopSearchHomeSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ShopSearchRecentlyViewedSkeletonSection()
            ShopSearchRecentChatsSkeletonSection(rowCount: 3)
        }
    }
}

struct ShopSearchGridSkeletonView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(0..<6, id: \.self) { _ in
                    HStack(alignment: .top, spacing: 14) {
                        ShopSkeletonBlock(cornerRadius: 18, width: 124, height: 124)

                        VStack(alignment: .leading, spacing: 8) {
                            ShopSkeletonTextLine(width: 190, height: 15, cornerRadius: 5)
                            ShopSkeletonTextLine(width: 135, height: 13, cornerRadius: 5)
                            ShopSkeletonTextLine(width: 85, height: 12, cornerRadius: 4)
                            ShopSkeletonTextLine(width: 110, height: 16, cornerRadius: 5)
                            Spacer(minLength: 4)
                            HStack(spacing: 8) {
                                ShopSkeletonCircle(size: 18)
                                ShopSkeletonTextLine(width: 95, height: 12, cornerRadius: 4)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                Spacer(minLength: 120)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }
}

// MARK: - 5. Store Detail Screen Skeleton

struct ShopStoreDetailSkeletonView: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Store Banner Placeholder
                ShopSkeletonBlock(cornerRadius: 0, height: 190)

                // Store Avatar + Name + Follow button
                VStack(spacing: 10) {
                    ShopSkeletonCircle(size: 64)
                        .offset(y: -32)
                        .padding(.bottom, -28)

                    ShopSkeletonTextLine(width: 180, height: 20, cornerRadius: 7)
                    ShopSkeletonTextLine(width: 120, height: 13, cornerRadius: 5)

                    HStack(spacing: 12) {
                        ShopSkeletonCapsule(width: 130, height: 40)
                        ShopSkeletonCapsule(width: 50, height: 40)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)

                // Product Grid Skeleton
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<6, id: \.self) { _ in
                        ShopProductCardSkeleton()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer(minLength: 80)
            }
        }
    }
}

// MARK: - 6. Wishlist Screen Skeleton

struct ShopWishlistSkeletonView: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Collections Card Skeleton
                ShopSkeletonBlock(
                    cornerRadius: 22,
                    width: UIScreen.main.bounds.width - 32,
                    height: 120
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)

                // Filter Pills Skeleton
                HStack(spacing: 8) {
                    ShopSkeletonCapsule(width: 70, height: 32)
                    ShopSkeletonCapsule(width: 90, height: 32)
                    ShopSkeletonCapsule(width: 80, height: 32)
                }
                .padding(.horizontal, 16)

                // 2-Column Product Cards
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        ShopProductCardSkeleton()
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 120)
            }
        }
    }
}

// MARK: - 7. Following ("Segui già") Screen Skeleton

struct ShopFollowingSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ShopLayout.sectionSpacing) {
            // 1. Stories Avatar Row Skeleton
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { _ in
                        ShopSkeletonCircle(size: 62)
                    }
                    ShopSkeletonCircle(size: 62)
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 6)

            // 2. Store 1 Section Skeleton
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 12) {
                    ShopSkeletonCircle(size: 42)
                    VStack(alignment: .leading, spacing: 5) {
                        ShopSkeletonTextLine(width: 140, height: 16, cornerRadius: 6)
                        ShopSkeletonTextLine(width: 190, height: 12, cornerRadius: 4)
                    }
                    Spacer()
                    ShopSkeletonCircle(size: 20)
                }
                .padding(.horizontal, 16)

                // Horizontal Carousel of Products
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(0..<3, id: \.self) { _ in
                            ShopSkeletonBlock(cornerRadius: 18, width: 165, height: 170)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            // 3. Store 2 Section Skeleton
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 12) {
                    ShopSkeletonCircle(size: 42)
                    VStack(alignment: .leading, spacing: 5) {
                        ShopSkeletonTextLine(width: 120, height: 16, cornerRadius: 6)
                        ShopSkeletonTextLine(width: 170, height: 12, cornerRadius: 4)
                    }
                    Spacer()
                    ShopSkeletonCircle(size: 20)
                }
                .padding(.horizontal, 16)

                // Horizontal Carousel of Products
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(0..<3, id: \.self) { _ in
                            ShopSkeletonBlock(cornerRadius: 18, width: 165, height: 170)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}
