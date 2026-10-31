import SwiftUI

struct StoreBadge: View {
    let storeName: String

    var body: some View {
        ShopStoreLogo(storeName: storeName)
    }
}

struct DiscountBadge: View {
    let discountText: String

    var body: some View {
        Text(discountText)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.shopPurple)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.shopPurpleLight)
            .cornerRadius(6)
    }
}

struct SavingsPill: View {
    let amountText: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.down.right")
                .font(.system(size: 8.5, weight: .bold))
            Text(amountText)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
        }
        .foregroundColor(.shopGreen)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Color.shopGreenLight)
        .cornerRadius(5)
    }
}

struct BestPriceBadge: View {
    var body: some View {
        HStack(spacing: 3.5) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .bold))
            Text("MIGLIOR PREZZO")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Color.shopPurple)
        .cornerRadius(6)
    }
}

struct StoreCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count) STORE")
            .font(.system(size: 9, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color.shopDark.opacity(0.85))
            .cornerRadius(6)
    }
}

struct SizeChip: View {
    let size: String
    let isSelected: Bool

    var body: some View {
        Text(size)
            .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
            .foregroundColor(isSelected ? .white : .shopDark)
            .padding(.horizontal, 15)
            .padding(.vertical, 7.5)
            .background(isSelected ? Color.shopPurple : Color.white)
            .cornerRadius(20) // Shop signature pill
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1)
            )
            .shadow(color: isSelected ? Color.shopPurple.opacity(0.25) : Color.black.opacity(0.02), radius: 3, y: 1)
    }
}

struct WishlistButton: View {
    let product: MatchedProduct
    var size: String? = nil
    @ObservedObject private var wishlist = WishlistManager.shared

    private var isFavorite: Bool {
        wishlist.isFavorite(product.canonical_name)
    }

    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                wishlist.toggleFavorite(product: product, selectedSize: size)
            }
        }) {
            Circle()
                .fill(Color.white)
                .frame(width: 34, height: 34)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                .overlay(
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isFavorite ? Color(red: 235/255, green: 40/255, blue: 60/255) : Color.shopDark)
                        .scaleEffect(isFavorite ? 1.15 : 1.0)
                )
        }
        .buttonStyle(.plain)
    }
}
