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

    var assetName: String? {
        let s = storeName.lowercased()
        if s.contains("end") { return "store_end" }
        if s.contains("arc") { return "store_arcteryx" }
        if s.contains("cisalfa") { return "store_cisalfa" }
        if s.contains("maxi") { return "store_maxisport" }
        if s.contains("mister") { return "store_misterrunning" }
        if s.contains("nencini") { return "store_nencini" }
        if s.contains("top4") { return "store_top4running" }
        if s.contains("running warehouse") || s.contains("warehouse") { return "store_runningwarehouse" }
        if s.contains("deporvillage") || s.contains("depor") { return "store_deporvillage" }
        if s.contains("alltricks") { return "store_alltricks" }
        if s.contains("decathlon") { return "store_decathlon" }
        if s.contains("nike") { return "store_nike" }
        if s.contains("adidas") { return "store_adidas" }
        return nil
    }

    var initials: String {
        let s = storeName.lowercased()
        if s.contains("starcow") { return "STARCOW" }
        if s.contains("peakpulse") || s.contains("peak") { return "PP" }
        if s.contains("diez") || s.contains("numero") { return "10" }
        if s.contains("drip") { return "DRIP" }
        if s.contains("outlet") { return "SO" }
        if s.contains("end") { return "END." }
        if s.contains("arc") { return "ARC" }
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
        let s = storeName.lowercased()
        if s.contains("starcow") { return Color.black }
        if s.contains("peak") { return Color(red: 24/255, green: 24/255, blue: 27/255) }
        if s.contains("diez") || s.contains("numero") { return Color(red: 235/255, green: 235/255, blue: 230/255) }
        if s.contains("cisalfa") { return Color(red: 227/255, green: 28/255, blue: 37/255) }
        if s.contains("maxi") { return Color(red: 245/255, green: 130/255, blue: 32/255) }
        if s.contains("mister") { return Color(red: 0/255, green: 114/255, blue: 206/255) }
        if s.contains("nencini") { return Color(red: 0/255, green: 140/255, blue: 70/255) }
        if s.contains("top4") { return Color(red: 0/255, green: 185/255, blue: 241/255) }
        if s.contains("running warehouse") || s.contains("warehouse") { return Color(red: 10/255, green: 55/255, blue: 140/255) }
        if s.contains("deporvillage") || s.contains("depor") { return Color(red: 232/255, green: 67/255, blue: 17/255) }
        if s.contains("alltricks") { return Color(red: 0/255, green: 163/255, blue: 224/255) }
        if s.contains("decathlon") { return Color(red: 0/255, green: 130/255, blue: 200/255) }
        if s.contains("sportler") { return Color(red: 220/255, green: 30/255, blue: 40/255) }
        if s.contains("sportit") { return Color(red: 230/255, green: 85/255, blue: 20/255) }
        if s.contains("tennis-point") || s.contains("tennis_point") { return Color(red: 240/255, green: 120/255, blue: 0/255) }
        if s.contains("basketball") { return Color(red: 200/255, green: 50/255, blue: 35/255) }
        if s.contains("nonsolosport") { return Color(red: 18/255, green: 75/255, blue: 155/255) }
        if s.contains("intersport") { return Color(red: 0/255, green: 60/255, blue: 145/255) }
        if s.contains("bshopzone") { return Color(red: 25/255, green: 115/255, blue: 165/255) }
        if s.contains("nike") { return Color(red: 17/255, green: 17/255, blue: 17/255) }
        return .shopPurple
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

                if let asset = assetName, let uiImage = UIImage(named: asset) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.84, height: size * 0.84)
                        .clipShape(Circle())
                } else {
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
