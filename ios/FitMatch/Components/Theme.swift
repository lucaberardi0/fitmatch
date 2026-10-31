import SwiftUI

extension Color {
    // Shopify "Shop" official design system color palette
    static let shopPurple = Color(red: 90/255, green: 49/255, blue: 244/255)       // #5A31F4
    static let shopPurpleLight = Color(red: 241/255, green: 238/255, blue: 254/255)// #F1EEFE
    static let shopDark = Color(red: 17/255, green: 17/255, blue: 20/255)           // #111114
    static let shopTextMuted = Color(red: 113/255, green: 113/255, blue: 122/255)  // #71717A
    static let shopSurface = Color(red: 247/255, green: 247/255, blue: 250/255)    // #F7F7FA canvas background
    static let shopCardBg = Color(.systemBackground)
    static let shopBorder = Color(red: 232/255, green: 232/255, blue: 236/255)     // #E8E8EC
    static let shopGreen = Color(red: 0/255, green: 138/255, blue: 72/255)          // #008A48
    static let shopGreenLight = Color(red: 230/255, green: 247/255, blue: 236/255) // #E6F7EC
    static let shopYellow = Color(red: 255/255, green: 179/255, blue: 0/255)
}

struct ShopStoreLogo: View {
    let storeName: String
    var showVerified: Bool = true
    var size: CGFloat = 16

    var initials: String {
        let s = storeName.lowercased()
        if s.contains("cisalfa") { return "CS" }
        if s.contains("maxi") { return "MS" }
        if s.contains("mister") { return "MR" }
        if s.contains("nencini") { return "NS" }
        if s.contains("top4") { return "T4" }
        if s.contains("running warehouse") || s.contains("warehouse") { return "RW" }
        return "FM"
    }

    var brandColor: Color {
        let s = storeName.lowercased()
        if s.contains("cisalfa") { return Color(red: 227/255, green: 28/255, blue: 37/255) }
        if s.contains("maxi") { return Color(red: 245/255, green: 130/255, blue: 32/255) }
        if s.contains("mister") { return Color(red: 0/255, green: 114/255, blue: 206/255) }
        if s.contains("nencini") { return Color(red: 0/255, green: 140/255, blue: 70/255) }
        if s.contains("top4") { return Color(red: 0/255, green: 185/255, blue: 241/255) }
        if s.contains("running warehouse") || s.contains("warehouse") { return Color(red: 10/255, green: 55/255, blue: 140/255) }
        return .shopPurple
    }

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(brandColor)
                    .frame(width: size, height: size)

                Text(initials)
                    .font(.system(size: size * 0.45, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }

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
