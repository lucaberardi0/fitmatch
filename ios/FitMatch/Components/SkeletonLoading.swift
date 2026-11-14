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

// MARK: - Custom Crisp Rotating Arc Spinner for Agentic Steps

private struct AgentOrbitRing: View {
    var size: CGFloat = 34
    var lineWidth: CGFloat = 2.2
    var iconSize: CGFloat = 13
    var showIcon: Bool = true
    @State private var rotation: Double = 0
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            if showIcon {
                Circle()
                    .fill(Color.shopPurple.opacity(pulse ? 0.14 : 0.06))
                    .frame(width: size + 6, height: size + 6)
                    .scaleEffect(pulse ? 1.06 : 0.94)
            }

            Circle()
                .stroke(Color.shopPurple.opacity(0.12), lineWidth: lineWidth)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0.05, to: 0.72)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color.shopPurple.opacity(0.05),
                            Color.shopPurple.opacity(0.55),
                            Color.shopPurple
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotation))

            if showIcon {
                Image(systemName: "sparkles")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(.shopPurple)
                    .scaleEffect(pulse ? 1.06 : 0.95)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Agent Thinking & Operations HUD (Flagship Agentic Search Experience)

struct ShopAgentThinkingCardView: View {
    var query: String
    var isFollowUp: Bool = false
    var steps: [SearchThinkingStep] = []
    var startedAt: Date = Date()

    @State private var isExpanded: Bool = true

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
            localDetail = "Collegamento al contesto della conversazione per «\(cleanQuery)»"
        } else {
            localDetail = "Estrazione intent, categorie e vincoli per «\(cleanQuery)»"
        }
        return [
            SearchThinkingStep(
                id: "init",
                status: .running,
                title: isFollowUp ? "Analizzo il follow-up" : "Analizzo la richiesta",
                detail: localDetail,
                elapsedMs: nil
            )
        ]
    }

    private var activeStep: SearchThinkingStep? {
        displaySteps.last(where: { $0.status == .running }) ?? displaySteps.last
    }

    private var dynamicHeadline: String {
        if let active = activeStep {
            return active.title.replacingOccurrences(of: "…", with: "")
        }
        return isFollowUp ? "Elaboro il follow-up" : "Ricerca in corso"
    }

    private var progressFraction: Double {
        if displaySteps.isEmpty { return 0.18 }
        let doneCount = displaySteps.filter { $0.status == .done }.count
        let total = max(displaySteps.count, 3)
        let runningBonus = displaySteps.contains(where: { $0.status == .running }) ? 0.16 : 0.0
        return min(0.94, max(0.22, (Double(doneCount) / Double(total)) + runningBonus))
    }

    private func formattedSeconds(from elapsedMs: Int) -> String {
        let secs = Double(elapsedMs) / 1000.0
        return String(format: "%.1fs", max(0.1, secs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Header: Orbital Core + Live Headline + Timer Pill + Toggle
            Button(action: {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(alignment: .center, spacing: 12) {
                    AgentOrbitRing(size: 32, lineWidth: 2.2, iconSize: 12.5, showIcon: true)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("FITMATCH AI")
                                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                .tracking(0.8)
                                .foregroundColor(.shopPurple)
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 2)
                                .background(Color.shopPurpleLight)
                                .clipShape(Capsule())

                            if isFollowUp {
                                Text("Follow-up")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.shopTextMuted)
                            }
                        }

                        Text(dynamicHeadline)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.shopDark)
                            .lineLimit(1)
                            .id(dynamicHeadline)
                            .transition(.opacity)
                    }

                    Spacer(minLength: 8)

                    // Live Elapsed Timer Pill
                    TimelineView(.periodic(from: startedAt, by: 0.1)) { ctx in
                        let sec = max(0.0, ctx.date.timeIntervalSince(startedAt))
                        Text(String(format: "%.1fs", sec))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.shopTextMuted)
                            .padding(.horizontal, 8.5)
                            .padding(.vertical, 4)
                            .background(Color.shopSurface)
                            .clipShape(Capsule())
                    }

                    // Collapse Chevron Button
                    ZStack {
                        Circle()
                            .fill(Color.shopSurface)
                            .frame(width: 28, height: 28)
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.shopTextMuted)
                            .rotationEffect(.degrees(isExpanded ? 0 : 180))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, isExpanded ? 12 : 13)

            // 2. Instant Extracted Query Constraint Chips
            if isExpanded && !queryAnalysis.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(queryAnalysis.tags) { tag in
                            HStack(spacing: 4.5) {
                                Image(systemName: tag.icon)
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(.shopPurple)
                                Text(tag.text)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.shopDark)
                            }
                            .padding(.horizontal, 9.5)
                            .padding(.vertical, 5)
                            .background(Color.shopPurpleLight.opacity(0.62))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.shopPurple.opacity(0.12), lineWidth: 0.8)
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 3. Elevated Live Execution Trace Well
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displaySteps.enumerated()), id: \.element.id) { idx, step in
                        let isLast = idx == displaySteps.count - 1
                        let isRunning = step.status == .running
                        let isDone = step.status == .done

                        HStack(alignment: .top, spacing: 10) {
                            // Vertical Rail + Crisp Node
                            VStack(spacing: 0) {
                                ZStack {
                                    if isDone {
                                        Circle()
                                            .fill(Color.shopPurple.opacity(0.13))
                                            .frame(width: 20, height: 20)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9.5, weight: .bold))
                                            .foregroundColor(.shopPurple)
                                    } else if isRunning {
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 20, height: 20)
                                            .shadow(color: Color.shopPurple.opacity(0.18), radius: 3)
                                        AgentOrbitRing(size: 15, lineWidth: 1.8, iconSize: 0, showIcon: false)
                                    } else {
                                        Circle()
                                            .fill(Color.black.opacity(0.06))
                                            .frame(width: 20, height: 20)
                                        Image(systemName: "minus")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(Color(red: 155/255, green: 155/255, blue: 168/255))
                                    }
                                }
                                .padding(.top, isRunning ? 6 : 2)

                                if !isLast {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(isDone ? Color.shopPurple.opacity(0.28) : Color.black.opacity(0.08))
                                        .frame(width: 1.5)
                                        .frame(maxHeight: .infinity)
                                        .padding(.vertical, 3)
                                }
                            }
                            .frame(width: 20)

                            // Step Card Content
                            VStack(alignment: .leading, spacing: 2.5) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(step.title)
                                        .font(.system(size: 13, weight: isRunning ? .bold : .medium))
                                        .foregroundColor(isRunning ? .shopDark : Color(red: 82/255, green: 82/255, blue: 96/255))
                                        .lineLimit(2)

                                    Spacer(minLength: 6)

                                    if isDone, let ms = step.elapsedMs, ms > 0 {
                                        Text(formattedSeconds(from: ms))
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundColor(.shopTextMuted)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.white)
                                            .clipShape(Capsule())
                                    }
                                }

                                if let detail = step.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.system(size: 11.5, weight: .regular))
                                        .foregroundColor(isRunning ? Color(red: 95/255, green: 95/255, blue: 112/255) : Color(red: 135/255, green: 135/255, blue: 150/255))
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.horizontal, isRunning ? 10 : 2)
                            .padding(.vertical, isRunning ? 7 : 2)
                            .background(
                                Group {
                                    if isRunning {
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .fill(Color.white)
                                            .shadow(color: Color.black.opacity(0.035), radius: 4, x: 0, y: 1.5)
                                    }
                                }
                            )
                            .padding(.bottom, isLast ? 0 : 8)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(11)
                .background(Color(red: 247/255, green: 247/255, blue: 251/255))
                .cornerRadius(15)
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 4. Luminous Progress Track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.shopPurple.opacity(0.08))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color.shopPurple, Color(red: 139/255, green: 92/255, blue: 246/255)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(24, geo.size.width * progressFraction))
                        .shimmering(duration: 1.2)
                        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: progressFraction)
                }
            }
            .frame(height: 3)
        }
        .background(
            ZStack(alignment: .topLeading) {
                Color.white
                RadialGradient(
                    colors: [Color.shopPurple.opacity(0.065), Color.clear],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 210
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.shopPurple.opacity(0.24), Color.shopBorder],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.shopPurple.opacity(0.08), radius: 16, x: 0, y: 6)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        .animation(.easeOut(duration: 0.24), value: steps)
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
            VStack(alignment: .leading, spacing: 22) {
                // 1. Flagship Live Agentic Card
                ShopAgentThinkingCardView(
                    query: query,
                    isFollowUp: false,
                    steps: thinkingSteps,
                    startedAt: thinkingStartedAt
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // 2. Conversational Editorial Narrative Preview
                VStack(alignment: .leading, spacing: 8) {
                    ShopSkeletonTextLine(height: 13, cornerRadius: 5)
                        .frame(maxWidth: .infinity)
                    ShopSkeletonTextLine(width: 270, height: 13, cornerRadius: 5)
                    ShopSkeletonTextLine(width: 185, height: 13, cornerRadius: 5)
                }
                .padding(.horizontal, 18)
                .opacity(0.82)

                // 3. Curated Horizontal Carousel Preview (Matches ShopThemedCarouselCard)
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        ShopSkeletonTextLine(width: 175, height: 16, cornerRadius: 6)
                        ShopSkeletonTextLine(width: 230, height: 11, cornerRadius: 4)
                    }
                    .padding(.horizontal, 18)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ShopThemedCarouselSkeletonCard()
                            ShopThemedCarouselSkeletonCard()
                            ShopThemedCarouselSkeletonCard()
                        }
                        .padding(.horizontal, 18)
                    }
                    .disabled(true)
                }
                .opacity(0.84)

                // 4. Comparative Spec Strip Preview (Matches ShopComparativeCard)
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        ShopSkeletonTextLine(width: 145, height: 16, cornerRadius: 6)
                        ShopSkeletonTextLine(width: 195, height: 11, cornerRadius: 4)
                    }
                    .padding(.horizontal, 18)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ShopComparativeSkeletonCard()
                            ShopComparativeSkeletonCard()
                        }
                        .padding(.horizontal, 18)
                    }
                    .disabled(true)
                }
                .opacity(0.76)

                Spacer(minLength: 130)
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
