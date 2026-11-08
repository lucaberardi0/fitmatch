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

// MARK: - Agent Thinking & Operations HUD (Redesigned Antigravity Style)

struct ShopAgentThinkingCardView: View {
    var query: String
    var isFollowUp: Bool = false

    @State private var activeStep: Int = 0
    @State private var progress: CGFloat = 0.18
    @State private var isPulsing: Bool = false

    private var cleanQuery: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? "Sport" : q
    }

    private var analysis: QueryAnalysis {
        QueryAnalysis.analyze(query)
    }

    private var steps: [(title: String, detail: String)] {
        if isFollowUp {
            let detailParams = analysis.summaryText == "Ricerca semantica cataloghi partner"
                ? "Applicazione criteri per «\(cleanQuery)»"
                : analysis.summaryText
            return [
                ("Integrazione contesto", "Collegamento alla ricerca precedente e storico"),
                ("Raffinamento parametri", detailParams),
                ("Aggiornamento offerte", "Ricalcolo modelli e prezzi migliori tra i partner")
            ]
        } else {
            let detailIntent = analysis.summaryText == "Ricerca semantica cataloghi partner"
                ? "Identificazione modelli e caratteristiche per «\(cleanQuery)»"
                : analysis.summaryText
            return [
                ("Analisi richiesta", detailIntent),
                ("Scansione 14 partner in tempo reale", "Nike, Alltricks, Cisalfa, Deporvillage, Maxi Sport..."),
                ("Confronto prezzi & sconti", "Calcolo miglior prezzo assoluto e modelli consigliati")
            ]
        }
    }

    private var currentHeadline: String {
        if isFollowUp {
            return "Raffino su «\(cleanQuery)»"
        } else {
            return "Ricerca intelligente in corso..."
        }
    }

    private var currentTickerText: String {
        switch activeStep {
        case 0:
            if let b = analysis.brand {
                return "⚡ Riconosciuto brand \(b) e requisiti tecnici..."
            }
            return "⚡ Analisi dell'intento e dei parametri sportivi..."
        case 1:
            return "🔍 Verifica prezzi e stock su 14 store partner..."
        case 2:
            return "🏷️ Calcolo offerte con sconti fino al 40%..."
        default:
            return "✨ Composizione schede e modelli consigliati..."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Bar
            HStack(alignment: .center, spacing: 12) {
                // Agent Glowing Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.shopPurple, Color(red: 130/255, green: 75/255, blue: 255/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                        .shadow(color: Color.shopPurple.opacity(isPulsing ? 0.35 : 0.15), radius: 6, y: 2)

                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(red: 34/255, green: 197/255, blue: 94/255))
                            .frame(width: 6, height: 6)
                            .scaleEffect(isPulsing ? 1.25 : 0.8)

                        Text(isFollowUp ? "AGENTE FITMATCH • APPROFONDIMENTO" : "AGENTE FITMATCH • RICERCA AI")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(.shopPurple)
                            .tracking(0.5)
                    }

                    Text(currentHeadline)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(.shopDark)
                        .lineLimit(1)
                }

                Spacer()

                // Progress Percentage Pill
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.shopPurple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color.shopPurpleLight)
                    .cornerRadius(10)
            }

            // Fluid Animated Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 3.5)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.shopPurple, Color(red: 160/255, green: 100/255, blue: 255/255)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(16, geo.size.width * progress), height: 3.5)
                        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: progress)
                }
            }
            .frame(height: 3.5)

            // Step List
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                    HStack(alignment: .top, spacing: 12) {
                        // Left step indicator
                        VStack(spacing: 0) {
                            if idx < activeStep {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.shopPurple)
                                    .frame(width: 18, height: 18)
                            } else if idx == activeStep {
                                ZStack {
                                    Circle()
                                        .fill(Color.shopPurpleLight)
                                        .frame(width: 18, height: 18)
                                    ProgressView()
                                        .tint(Color.shopPurple)
                                        .scaleEffect(0.65)
                                }
                                .frame(width: 18, height: 18)
                            } else {
                                Circle()
                                    .stroke(Color.black.opacity(0.12), lineWidth: 1.5)
                                    .frame(width: 14, height: 14)
                                    .frame(width: 18, height: 18)
                            }

                            if idx < steps.count - 1 {
                                Rectangle()
                                    .fill(idx < activeStep ? Color.shopPurple.opacity(0.4) : Color.black.opacity(0.06))
                                    .frame(width: 1.5)
                                    .frame(maxHeight: .infinity)
                                    .padding(.vertical, 2)
                            }
                        }
                        .frame(width: 18)

                        // Title & Detail
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.system(size: 13, weight: idx == activeStep ? .bold : (idx < activeStep ? .semibold : .regular)))
                                .foregroundColor(idx <= activeStep ? .shopDark : Color(red: 165/255, green: 165/255, blue: 175/255))

                            if idx <= activeStep {
                                Text(step.detail)
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(idx == activeStep ? Color.shopPurple : Color(red: 125/255, green: 125/255, blue: 135/255))
                                    .lineLimit(2)
                            }
                        }
                        .padding(.bottom, idx < steps.count - 1 ? 8 : 0)

                        Spacer()
                    }
                }
            }
            .padding(.top, 2)

            // Dynamic Live Activity Ticker Pill
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.shopPurple)

                Text(currentTickerText)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Color(red: 70/255, green: 70/255, blue: 85/255))
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color(red: 247/255, green: 245/255, blue: 255/255))
            .cornerRadius(11)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.shopPurple.opacity(0.18), lineWidth: 1.2)
        )
        .shadow(color: Color.shopPurple.opacity(0.06), radius: 12, y: 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isPulsing = true
            }

            let timeline: [(delay: Double, step: Int, prog: CGFloat)] = isFollowUp
                ? [(0.4, 1, 0.55), (1.1, 2, 0.92)]
                : [(0.4, 1, 0.45), (1.1, 2, 0.78), (1.8, 3, 0.96)]

            for item in timeline {
                DispatchQueue.main.asyncAfter(deadline: .now() + item.delay) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        activeStep = item.step
                        progress = item.prog
                    }
                }
            }
        }
    }
}

struct ShopSearchDeepDiveSkeletonView: View {
    var query: String = ""
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Agent Thinking / Operations HUD Card
                ShopAgentThinkingCardView(query: query, isFollowUp: false)
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
