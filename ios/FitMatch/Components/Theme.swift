import SwiftUI

extension Color {
    // Shopify "Shop" official design system color palette
    static let shopPurple = Color(red: 90/255, green: 49/255, blue: 244/255)       // #5A31F4
    static let shopPurpleLight = Color(red: 241/255, green: 238/255, blue: 254/255)// #F1EEFE
    static let shopPurpleDark = Color(red: 67/255, green: 30/255, blue: 204/255)   // #431ECC
    static let shopDark = Color(red: 17/255, green: 17/255, blue: 20/255)           // #111114
    static let shopTextMuted = Color(red: 113/255, green: 113/255, blue: 122/255)  // #71717A
    static let shopSurface = Color(red: 247/255, green: 247/255, blue: 250/255)    // #F7F7FA canvas background
    static let shopCardBg = Color(.systemBackground)
    static let shopBorder = Color(red: 232/255, green: 232/255, blue: 236/255)     // #E8E8EC
    static let shopGreen = Color(red: 0/255, green: 138/255, blue: 72/255)          // #008A48
    static let shopGreenLight = Color(red: 230/255, green: 247/255, blue: 236/255) // #E6F7EC
    static let shopYellow = Color(red: 255/255, green: 179/255, blue: 0/255)
    static let shopOrange = Color(red: 255/255, green: 122/255, blue: 0/255)
    static let shopRed = Color(red: 235/255, green: 52/255, blue: 62/255)
    static let shopSurfaceElevated = Color(red: 242/255, green: 243/255, blue: 247/255)

    init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if cleanHex.count == 6 {
            cleanHex.append("FF")
        }
        guard cleanHex.count == 8, let intVal = UInt64(cleanHex, radix: 16) else { return nil }
        let r = Double((intVal >> 24) & 0xFF) / 255.0
        let g = Double((intVal >> 16) & 0xFF) / 255.0
        let b = Double((intVal >> 8) & 0xFF) / 255.0
        let a = Double(intVal & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Extracts HSB components in sRGB space for building harmonious multi-stop gradients.
    var hsbComponents: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        let uiColor = UIColor(self)
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            return (h, s, b, a)
        }
        var w: CGFloat = 0
        if uiColor.getWhite(&w, alpha: &a) {
            return (0, 0, w, a)
        }
        return (0.28, 0.31, 0.49, 1.0)
    }

    /// Derives a 3-stop (topLeading highlight, authentic mid, bottomTrailing depth) gradient
    /// tuned to preserve white foreground text contrast across dark, saturated, and bright brand colors.
    func cardGradientStops() -> (start: Color, mid: Color, end: Color) {
        let (h, s, b, _) = hsbComponents

        // Near-achromatic dark brand colors (e.g. #111111) -> slate-to-obsidian gradient
        if s < 0.10 && b < 0.24 {
            let start = Color(hue: 0.63, saturation: 0.12, brightness: Double(max(b + 0.17, 0.24)))
            let mid = Color(hue: 0.63, saturation: 0.10, brightness: Double(max(b + 0.06, 0.14)))
            let end = Color(hue: 0.63, saturation: 0.14, brightness: Double(max(b * 0.65, 0.05)))
            return (start, mid, end)
        }

        // Pale low-saturation accents -> deepen gently so white text remains crisp
        if s < 0.20 && b >= 0.72 {
            let start = Color(hue: Double(h), saturation: Double(max(s, 0.22)), brightness: 0.56)
            let mid = Color(hue: Double(h), saturation: Double(max(s + 0.08, 0.28)), brightness: 0.44)
            let end = Color(hue: Double(h), saturation: Double(max(s + 0.14, 0.34)), brightness: 0.30)
            return (start, mid, end)
        }

        let wrapHue: (CGFloat) -> Double = { raw in
            let mod = raw.truncatingRemainder(dividingBy: 1.0)
            return Double(mod < 0 ? mod + 1.0 : mod)
        }

        let isWarm = (h < 0.14 || h > 0.88)
        let startHue = wrapHue(isWarm ? h + 0.032 : h - 0.032)
        let endHue = wrapHue(isWarm ? h - 0.036 : h + 0.042)

        let maxStartBrightness: CGFloat = s < 0.45 ? 0.64 : 0.84
        let startBrightness = Double(min(max(b + 0.10, 0.36), maxStartBrightness))
        let startSaturation = Double(max(s * 0.88, min(s, 0.22)))

        let midBrightness = Double(min(max(b, 0.28), 0.78))
        let midSaturation = Double(s)

        let endBrightness = Double(max(b * 0.58, 0.16))
        let endSaturation = Double(min(s * 1.12, 1.0))

        return (
            start: Color(hue: startHue, saturation: startSaturation, brightness: startBrightness),
            mid: Color(hue: Double(h), saturation: midSaturation, brightness: midBrightness),
            end: Color(hue: endHue, saturation: endSaturation, brightness: endBrightness)
        )
    }
}

// MARK: - Unified Design Tokens & Layout Modifiers

enum ShopLayout {
    /// Horizontal outer margin used across all screens, carousels, and sheets
    static let screenPadding: CGFloat = 16
    /// Vertical gap between distinct sections on a screen
    static let sectionSpacing: CGFloat = 20
    /// Vertical gap between cards or medium blocks
    static let cardSpacing: CGFloat = 16
    /// Vertical/horizontal gap between related list items
    static let compactSpacing: CGFloat = 12
    /// Tight element spacing (chips, inline metadata)
    static let tightSpacing: CGFloat = 8
    /// Two-column product grid spacing
    static let gridColumnSpacing: CGFloat = 12
    static let gridRowSpacing: CGFloat = 16

    /// Standard internal padding for elevated surface cards
    static let cardPadding: CGFloat = 16
    /// Compact internal padding for dense list/notification cards
    static let compactCardPadding: CGFloat = 14

    /// Unified corner radius tiers
    static let largeCardRadius: CGFloat = 24
    static let cardRadius: CGFloat = 20
    static let mediumRadius: CGFloat = 16
    static let smallRadius: CGFloat = 12

    /// Standard control sizes & header chrome
    static let headerTopPadding: CGFloat = 8
    static let headerBottomPadding: CGFloat = 10
    static let headerButtonSize: CGFloat = 42
    static let navButtonSize: CGFloat = 40
    static let searchPillHeight: CGFloat = 42

    /// Scroll bottom clearances
    static let bottomDockClearance: CGFloat = 104
    static let bottomFilterDockClearance: CGFloat = 136
    static let bottomDetailClearance: CGFloat = 40
    static let toastBottomOffset: CGFloat = 88
}

struct ShopCardModifier: ViewModifier {
    var padding: CGFloat = ShopLayout.cardPadding
    var cornerRadius: CGFloat = ShopLayout.cardRadius
    var background: Color = .white
    var borderColor: Color = .shopBorder
    var borderWidth: CGFloat = 1
    var shadowOpacity: Double = 0.03
    var shadowRadius: CGFloat = 8
    var shadowY: CGFloat = 3

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
    }
}

struct ShopNavCircleModifier: ViewModifier {
    var size: CGFloat = ShopLayout.navButtonSize
    var background: Color = .white
    var showBorder: Bool = true

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background(background)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(showBorder ? Color.shopBorder : Color.clear, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

extension View {
    func shopCard(
        padding: CGFloat = ShopLayout.cardPadding,
        cornerRadius: CGFloat = ShopLayout.cardRadius,
        background: Color = .white,
        borderColor: Color = .shopBorder,
        borderWidth: CGFloat = 1,
        shadowOpacity: Double = 0.03,
        shadowRadius: CGFloat = 8,
        shadowY: CGFloat = 3
    ) -> some View {
        modifier(
            ShopCardModifier(
                padding: padding,
                cornerRadius: cornerRadius,
                background: background,
                borderColor: borderColor,
                borderWidth: borderWidth,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }

    func shopNavCircle(
        size: CGFloat = ShopLayout.navButtonSize,
        background: Color = .white,
        showBorder: Bool = true
    ) -> some View {
        modifier(ShopNavCircleModifier(size: size, background: background, showBorder: showBorder))
    }

    func shopHeaderBarPadding() -> some View {
        self
            .padding(.horizontal, ShopLayout.screenPadding)
            .padding(.top, ShopLayout.headerTopPadding)
            .padding(.bottom, ShopLayout.headerBottomPadding)
    }
}

// MARK: - Shop Store Logo Component for 8 Verified Retailers

struct ShopStoreLogo: View {
    let storeName: String
    var showVerified: Bool = true
    var showLabel: Bool = true
    var size: CGFloat = 16
    var hasRedRing: Bool = false
    var logoURL: String? = nil

    var assetName: String? {
        let s = storeName.lowercased()
        if s.contains("cisalfa") { return "store_cisalfa" }
        if s.contains("maxi") { return "store_maxisport" }
        if s.contains("mister") { return "store_misterrunning" }
        if s.contains("nencini") { return "store_nencini" }
        if s.contains("top4") { return "store_top4running" }
        if s.contains("running warehouse") || s.contains("warehouse") { return "store_runningwarehouse" }
        if s.contains("nike") { return "store_nike" }
        if s.contains("adidas") { return "store_adidas" }
        return nil
    }

    var initials: String {
        if let dynamic = DynamicCatalogRegistry.shared.storeItem(for: storeName) {
            return dynamic.computedInitials
        }
        let s = storeName.lowercased()
        if s.contains("cisalfa") { return "CS" }
        if s.contains("maxi") { return "MS" }
        if s.contains("mister") { return "MR" }
        if s.contains("nencini") { return "NS" }
        if s.contains("top4") { return "T4" }
        if s.contains("running warehouse") || s.contains("warehouse") { return "RW" }
        if s.contains("deporvillage") || s.contains("depor") { return "DV" }
        if s.contains("alltricks") { return "AT" }
        if s.contains("decathlon") { return "DC" }
        if s.contains("sportler") { return "SP" }
        if s.contains("sportit") { return "SI" }
        if s.contains("df sport") || s.contains("sportspecialist") { return "DF" }
        if s.contains("tradeinn") { return "TI" }
        if s.contains("tennis-point") || s.contains("tennis_point") { return "TP" }
        if s.contains("basketball") { return "BS" }
        if s.contains("nonsolosport") { return "NS" }
        if s.contains("intersport") { return "IS" }
        if s.contains("bshopzone") { return "BZ" }
        if s.contains("nike") { return "NK" }
        if s.contains("adidas") { return "AD" }
        let words = storeName.components(separatedBy: " ").filter { !$0.isEmpty }
        if words.count >= 2 {
            return "\(words[0].prefix(1))\(words[1].prefix(1))".uppercased()
        }
        return String(storeName.prefix(2)).uppercased()
    }

    var brandColor: Color {
        if let hex = DynamicCatalogRegistry.shared.storeItem(for: storeName)?.accent_color,
           let parsed = Color(hex: hex) {
            return parsed
        }
        let s = storeName.lowercased()
        if s.contains("cisalfa") { return Color(red: 200/255, green: 16/255, blue: 46/255) }
        if s.contains("maxi") { return Color(red: 245/255, green: 130/255, blue: 32/255) }
        if s.contains("mister") { return Color(red: 0/255, green: 94/255, blue: 184/255) }
        if s.contains("nencini") { return Color(red: 0/255, green: 122/255, blue: 61/255) }
        if s.contains("top4") { return Color(red: 0/255, green: 185/255, blue: 241/255) }
        if s.contains("running warehouse") || s.contains("warehouse") { return Color(red: 10/255, green: 55/255, blue: 140/255) }
        if s.contains("deporvillage") || s.contains("depor") { return Color(red: 214/255, green: 59/255, blue: 14/255) }
        if s.contains("alltricks") { return Color(red: 0/255, green: 122/255, blue: 184/255) }
        if s.contains("decathlon") { return Color(red: 0/255, green: 130/255, blue: 200/255) }
        if s.contains("sportler") { return Color(red: 184/255, green: 24/255, blue: 32/255) }
        if s.contains("sportit") { return Color(red: 0/255, green: 85/255, blue: 164/255) }
        if s.contains("df sport") || s.contains("sportspecialist") { return Color(red: 227/255, green: 6/255, blue: 19/255) }
        if s.contains("tradeinn") { return Color(red: 242/255, green: 90/255, blue: 36/255) }
        if s.contains("tennis-point") || s.contains("tennis_point") { return Color(red: 227/255, green: 6/255, blue: 19/255) }
        if s.contains("basketball") { return Color(red: 255/255, green: 107/255, blue: 0/255) }
        if s.contains("nonsolosport") { return Color(red: 29/255, green: 29/255, blue: 27/255) }
        if s.contains("intersport") { return Color(red: 226/255, green: 0/255, blue: 26/255) }
        if s.contains("bshopzone") { return Color(red: 46/255, green: 125/255, blue: 50/255) }
        if s.contains("nike") { return Color(red: 98/255, green: 125/255, blue: 86/255) }
        if s.contains("adidas") { return Color(red: 17/255, green: 17/255, blue: 17/255) }
        return .shopPurple
    }

    var remoteLogoURL: URL? {
        if let explicit = logoURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty,
           let parsed = URL(string: explicit) {
            return parsed
        }
        guard let raw = DynamicCatalogRegistry.shared.storeItem(for: storeName)?.logo_url,
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    @ViewBuilder
    private var localOrInitialsFallback: some View {
        if let asset = assetName, let uiImage = UIImage(named: asset) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.84, height: size * 0.84)
                .clipShape(Circle())
        } else {
            initialsBadge
        }
    }

    @ViewBuilder
    private var initialsBadge: some View {
        Circle()
            .fill(brandColor)
            .frame(width: size, height: size)
            .overlay(
                hasRedRing ?
                    Circle()
                        .stroke(Color(red: 225/255, green: 55/255, blue: 45/255), lineWidth: 1.6)
                    : nil
            )
        Text(initials)
            .font(.system(size: initials.count > 4 ? size * 0.22 : (initials.count > 2 ? size * 0.32 : size * 0.42), weight: .black, design: .rounded))
            .foregroundColor(brandColor == Color(red: 235/255, green: 235/255, blue: 230/255) ? .black : .white)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(.horizontal, 2)
    }

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: size, height: size)
                    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                    .overlay(
                        Circle()
                            .stroke(hasRedRing ? Color(red: 225/255, green: 55/255, blue: 45/255) : Color.shopBorder, lineWidth: hasRedRing ? 1.6 : 0.8)
                    )

                if let logoURL = remoteLogoURL {
                    ShopCachedAsyncImage(url: logoURL) { phase in
                        if let img = phase.image {
                            img
                                .resizable()
                                .scaledToFit()
                                .frame(width: size * 0.84, height: size * 0.84)
                                .clipShape(Circle())
                        } else {
                            localOrInitialsFallback
                        }
                    }
                } else {
                    localOrInitialsFallback
                }
            }

            if showLabel {
                Text(storeName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)

                if showVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.shopPurple)
                }
            }
        }
    }
}

// MARK: - Unified Motion Curves, Interactive Press & Transition Helpers

enum ShopMotion {
    /// Tab bar and major root view switches
    static let tabSwitch = Animation.spring(response: 0.34, dampingFraction: 0.88)
    /// Horizontal sub-tab pill and filter indicator glide
    static let pillSlide = Animation.spring(response: 0.32, dampingFraction: 0.82)
    /// Tactile card & CTA press response
    static let cardPress = Animation.interactiveSpring(response: 0.24, dampingFraction: 0.78)
    /// Async image cross-dissolve reveal
    static let imageFade = Animation.easeOut(duration: 0.26)
    /// Gallery paging, thumbnail sync, and expandable sections
    static let gallerySpring = Animation.spring(response: 0.38, dampingFraction: 0.85)
    /// Interactive grid reflow when filtering or sorting
    static let gridReflow = Animation.spring(response: 0.36, dampingFraction: 0.86)
}

/// Tactile micro-scale press feedback for cards and navigation links.
struct ShopCardPressStyle: ButtonStyle {
    var scale: CGFloat = 0.968
    var pressedOpacity: Double = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(ShopMotion.cardPress, value: configuration.isPressed)
    }
}

extension View {
    /// Applies subtle iOS 17+ interactive horizontal carousel scale and opacity curves.
    func shopCarouselTransition() -> some View {
        self.scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1.0 : 0.965)
                .opacity(phase.isIdentity ? 1.0 : 0.86)
        }
    }

    /// Standard subtle fade + slight scale transition for state swaps (skeleton -> content, category filters).
    func shopFadeScaleTransition() -> some View {
        self.transition(
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.975)),
                removal: .opacity
            )
        )
    }

    /// Safe wrapper for iOS 18+ hero zoom transition source; no-op on iOS 17.
    @ViewBuilder
    func shopMatchedTransitionSource<ID: Hashable>(id: ID, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Safe wrapper for iOS 18+ fluid zoom navigation transition; falls back to standard push on iOS 17.
    @ViewBuilder
    func shopZoomNavigationTransition<ID: Hashable>(sourceID: ID?, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let sourceID, let namespace {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}
