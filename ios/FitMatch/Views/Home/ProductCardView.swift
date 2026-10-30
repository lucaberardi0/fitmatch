import SwiftUI

struct ProductCardView: View {
    let product: MatchedProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image Frame with Floating Badges
            ZStack(alignment: .topTrailing) {
                // Product Image Container
                ZStack {
                    Color(.systemGray6).opacity(0.6)

                    if let imageUrl = product.image_url, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .padding(8)
                            case .failure:
                                imagePlaceholder
                            case .empty:
                                ProgressView()
                            @unknown default:
                                imagePlaceholder
                            }
                        }
                    } else {
                        imagePlaceholder
                    }
                }
                .frame(height: 155)
                .frame(maxWidth: .infinity)
                .cornerRadius(14)

                // Top Floating Overlays
                HStack {
                    if product.offers.count > 1 {
                        Text("\(product.offers.count) STORES")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.shopDark.opacity(0.85))
                            .cornerRadius(5)
                    }

                    Spacer()

                    WishlistButton(product: product)
                }
                .padding(8)
            }

            // Info Section
            VStack(alignment: .leading, spacing: 4) {
                // Brand
                if let brand = product.brand {
                    Text(brand.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                }

                // Canonical Name
                Text(product.canonical_name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .frame(height: 36, alignment: .topLeading)

                // Prices
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(product.formattedBestPrice)
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        if let best = product.bestOffer, let badge = best.discountBadge {
                            DiscountBadge(discountText: badge)
                        }
                    }

                    if let best = product.bestOffer, let orig = best.formattedOriginalPrice {
                        Text(orig)
                            .font(.system(size: 11))
                            .strikethrough()
                            .foregroundColor(.secondary)
                    }
                }

                // Store
                if let best = product.bestOffer {
                    ShopStoreLogo(storeName: best.store_name)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(6)
        .background(Color.shopCardBg)
        .cornerRadius(16)
    }

    private var imagePlaceholder: some View {
        Image(systemName: "shoeprints.fill")
            .font(.system(size: 32))
            .foregroundColor(.secondary.opacity(0.5))
    }
}
