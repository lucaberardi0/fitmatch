import SwiftUI

extension Color {
    // Shopify "Shop" signature brand colors
    static let shopPurple = Color(red: 90/255, green: 49/255, blue: 244/255) // #5A31F4
    static let shopPurpleLight = Color(red: 90/255, green: 49/255, blue: 244/255).opacity(0.12)
    static let shopDark = Color(red: 17/255, green: 17/255, blue: 20/255)
    static let shopCardBg = Color(.systemBackground)
    static let shopBorder = Color(.systemGray5)
    static let shopGreen = Color(red: 16/255, green: 149/255, blue: 82/255)
    static let shopGreenLight = Color(red: 16/255, green: 149/255, blue: 82/255).opacity(0.12)
}

struct ShopStoreLogo: View {
    let storeName: String

    var initials: String {
        switch storeName.lowercased() {
        case let s where s.contains("cisalfa"): return "CS"
        case let s where s.contains("maxi"): return "MS"
        case let s where s.contains("mister"): return "MR"
        case let s where s.contains("nencini"): return "NS"
        default: return "FM"
        }
    }

    var brandColor: Color {
        switch storeName.lowercased() {
        case let s where s.contains("cisalfa"): return .red
        case let s where s.contains("maxi"): return .orange
        case let s where s.contains("mister"): return .blue
        case let s where s.contains("nencini"): return Color(red: 0, green: 0.55, blue: 0.3)
        default: return .shopPurple
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(brandColor)
                .frame(width: 14, height: 14)
                .overlay(
                    Text(initials.prefix(1))
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.white)
                )

            Text(storeName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }
}
