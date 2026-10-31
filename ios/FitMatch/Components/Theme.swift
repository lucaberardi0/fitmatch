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
}

// MARK: - Shop Store Logo Component for 8 Verified Retailers

struct ShopStoreLogo: View {
    let storeName: String
    var showVerified: Bool = true
    var showLabel: Bool = true
    var size: CGFloat = 16

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
        return nil
    }

    var initials: String {
        let s = storeName.lowercased()
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
        if s.contains("deporvillage") || s.contains("depor") { return Color(red: 232/255, green: 67/255, blue: 17/255) }
        if s.contains("alltricks") { return Color(red: 0/255, green: 163/255, blue: 224/255) }
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
                            .stroke(Color.shopBorder, lineWidth: 0.8)
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
                    Text(initials)
                        .font(.system(size: size * 0.42, weight: .black, design: .rounded))
                        .foregroundColor(.white)
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
