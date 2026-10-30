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
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.shopPurple)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.shopPurpleLight)
            .cornerRadius(4)
    }
}

struct BestPriceBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .bold))
            Text("MIGLIOR PREZZO")
                .font(.system(size: 9, weight: .black))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.shopPurple)
        .cornerRadius(6)
    }
}

struct SizeChip: View {
    let size: String
    let isSelected: Bool

    var body: some View {
        Text(size)
            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isSelected ? Color.shopDark : Color(.systemGray6))
            .cornerRadius(20) // Shop pill shape
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.shopDark : Color.clear, lineWidth: 1)
            )
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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                wishlist.toggleFavorite(product: product, selectedSize: size)
            }
        }) {
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 34, height: 34)
                .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                .overlay(
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isFavorite ? .red : .primary)
                        .scaleEffect(isFavorite ? 1.1 : 1.0)
                )
        }
        .buttonStyle(.plain)
    }
}
