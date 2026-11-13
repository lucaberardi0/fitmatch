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
            .padding(.bottom, 12)

            // Scrollable Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 1. Top Carousel Cards Skeleton (with Card 2 peeking on right edge)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            let cardWidth = max(UIScreen.main.bounds.width - 56, 320)
                            ShopSkeletonBlock(cornerRadius: 24, width: cardWidth, height: 180)
                            ShopSkeletonBlock(cornerRadius: 24, width: cardWidth, height: 180)
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 4)

                    // 2. Large Tall Feed Card Skeleton (Store Showcase)
                    ShopSkeletonBlock(
                        cornerRadius: 24,
                        width: UIScreen.main.bounds.width - 32,
                        height: 390
                    )
                    .padding(.horizontal, 16)

                    // 3. Third Bottom Card Peeking
                    ShopSkeletonBlock(
                        cornerRadius: 24,
                        width: UIScreen.main.bounds.width - 32,
                        height: 220
                    )
                    .padding(.horizontal, 16)

                    Spacer(minLength: 120)
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

struct QueryAnalysis {
    var category: String? = nil
    var budget: String? = nil
    var brand: String? = nil
    var technicalSpec: String? = nil

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
            res.budget = "Miglior rapporto qualità/prezzo"
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

        // 3. Category detection
        let categories: [(keywords: [String], name: String)] = [
            (["occhiali", "occhialini", "lenti"], "Occhiali & Protezione"),
            (["scarpe", "scarpa", "sneaker", "footwear"], "Calzature Tecniche"),
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

        // 4. Activity / Technical specs
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

    var summaryText: String {
        var parts: [String] = []
        if let cat = category { parts.append(cat) }
        if let spec = technicalSpec { parts.append(spec) }
        if let br = brand { parts.append("Brand: \(br)") }
        if let bg = budget { parts.append(bg) }
        if parts.isEmpty {
            return "Ricerca semantica cataloghi partner"
        }
        return parts.joined(separator: " • ")
    }
}

// MARK: - Agent Thinking & Operations HUD (Antigravity Live Thinking Style)

struct ShopAgentThinkingCardView: View {
    var query: String
    var isFollowUp: Bool = false
    var steps: [SearchThinkingStep] = []
    var startedAt: Date = Date()

    @State private var isExpanded: Bool = true
    @State private var isPulsing: Bool = false

    private var cleanQuery: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? "la tua ricerca" : q
    }

    private var displaySteps: [SearchThinkingStep] {
        if !steps.isEmpty {
            return steps
        }
        let localAnalysis = QueryAnalysis.analyze(query)
        let localDetail: String
        if localAnalysis.brand != nil || localAnalysis.budget != nil || localAnalysis.category != nil || localAnalysis.technicalSpec != nil {
            localDetail = localAnalysis.summaryText
        } else if isFollowUp {
            localDetail = "Collegamento al contesto della conversazione per «\(cleanQuery)»"
        } else {
            localDetail = "Interpretazione parametri per «\(cleanQuery)»"
        }
        return [
            SearchThinkingStep(
                id: "init",
                status: .running,
                title: isFollowUp ? "Analizzo il follow-up…" : "Analizzo la richiesta…",
                detail: localDetail,
                elapsedMs: nil
            )
        ]
    }

    private var activeStepTitle: String? {
        displaySteps.last(where: { $0.status == .running })?.title ?? displaySteps.last?.title
    }

    private func formattedSeconds(from elapsedMs: Int) -> String {
        let secs = Double(elapsedMs) / 1000.0
        return String(format: "%.1fs", max(0.1, secs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Antigravity-style Collapsible Thinking Header
            Button(action: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(alignment: .center, spacing: 11) {
                    // Subtle Breathing Orb
                    ZStack {
                        Circle()
                            .fill(Color.shopPurple.opacity(isPulsing ? 0.18 : 0.08))
                            .frame(width: 28, height: 28)
                            .scaleEffect(isPulsing ? 1.12 : 0.94)

                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.shopPurple, Color(red: 132/255, green: 84/255, blue: 246/255)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 10, height: 10)
                            .shadow(color: Color.shopPurple.opacity(0.45), radius: 4)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Sto pensando…")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.shopDark)

                            TimelineView(.periodic(from: startedAt, by: 0.2)) { ctx in
                                let sec = max(0.0, ctx.date.timeIntervalSince(startedAt))
                                Text(String(format: "%.1fs", sec))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color(red: 135/255, green: 135/255, blue: 150/255))
                            }
                        }

                        if !isExpanded, let subtitle = activeStepTitle {
                            Text(subtitle)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(Color(red: 115/255, green: 115/255, blue: 130/255))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Color(red: 150/255, green: 150/255, blue: 165/255))
                        .frame(width: 24, height: 24)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Live Execution Trace
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displaySteps.enumerated()), id: \.element.id) { idx, step in
                        let isLast = idx == displaySteps.count - 1
                        HStack(alignment: .top, spacing: 10) {
                            // Vertical Rail + Node
                            VStack(spacing: 0) {
                                ZStack {
                                    if step.status == .done {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(Color.shopPurple.opacity(0.88))
                                    } else if step.status == .running {
                                        ProgressView()
                                            .tint(Color.shopPurple)
                                            .scaleEffect(0.65)
                                    } else {
                                        Image(systemName: "minus.circle")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Color(red: 170/255, green: 170/255, blue: 180/255))
                                    }
                                }
                                .frame(width: 16, height: 18)

                                if !isLast {
                                    Rectangle()
                                        .fill(Color.shopPurple.opacity(step.status == .done ? 0.25 : 0.10))
                                        .frame(width: 1.2)
                                        .frame(maxHeight: .infinity)
                                        .padding(.vertical, 2)
                                }
                            }
                            .frame(width: 16)

                            // Real Step Text & Backend Detail
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(step.title)
                                        .font(.system(size: 13, weight: step.status == .running ? .semibold : .medium))
                                        .foregroundColor(step.status == .running ? .shopDark : Color(red: 75/255, green: 75/255, blue: 90/255))

                                    Spacer(minLength: 4)

                                    if step.status == .done, let ms = step.elapsedMs, ms > 0 {
                                        Text(formattedSeconds(from: ms))
                                            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                                            .foregroundColor(Color(red: 160/255, green: 160/255, blue: 172/255))
                                    }
                                }

                                if let detail = step.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.system(size: 11.5, weight: .regular))
                                        .foregroundColor(Color(red: 130/255, green: 130/255, blue: 145/255))
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.bottom, isLast ? 2 : 10)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.leading, 5)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(Color(red: 250/255, green: 249/255, blue: 254/255))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.shopPurple.opacity(0.14), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.22), value: steps)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

struct ShopSearchDeepDiveSkeletonView: View {
    var query: String = ""
    var thinkingSteps: [SearchThinkingStep] = []
    var thinkingStartedAt: Date = Date()
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Antigravity Live Thinking Trace Card
                ShopAgentThinkingCardView(
                    query: query,
                    isFollowUp: false,
                    steps: thinkingSteps,
                    startedAt: thinkingStartedAt
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)

                // Spotlight Card Skeleton
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ShopSkeletonCapsule(width: 90, height: 22)
                        Spacer()
                    }
                    ShopSkeletonBlock(cornerRadius: 16, height: 140)
                    ShopSkeletonTextLine(height: 14, cornerRadius: 5)
                    ShopSkeletonTextLine(width: 160, height: 12, cornerRadius: 4)
                }
                .padding(16)
                .background(Color.white)
                .cornerRadius(22)
                .padding(.horizontal, 16)

                // Curated Grid Skeleton
                VStack(alignment: .leading, spacing: 10) {
                    ShopSkeletonTextLine(width: 170, height: 15, cornerRadius: 5)
                        .padding(.horizontal, 20)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ShopProductCardSkeleton()
                        ShopProductCardSkeleton()
                        ShopProductCardSkeleton()
                        ShopProductCardSkeleton()
                    }
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 120)
            }
        }
    }
}

struct ShopSearchGridSkeletonView: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                // Filter pills placeholder
                HStack(spacing: 8) {
                    ShopSkeletonCapsule(width: 80, height: 32)
                    ShopSkeletonCapsule(width: 90, height: 32)
                    ShopSkeletonCapsule(width: 75, height: 32)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<6, id: \.self) { _ in
                        ShopProductCardSkeleton()
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 120)
            }
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
        VStack(alignment: .leading, spacing: 26) {
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
