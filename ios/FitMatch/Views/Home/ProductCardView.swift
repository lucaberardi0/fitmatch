import SwiftUI

struct ProductCardView: View {
    let product: MatchedProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                // Product Image
                if let imageUrl = product.image_url, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(height: 160)
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemBackground))
                        case .failure:
                            imagePlaceholder
                        case .empty:
                            ProgressView()
                                .frame(height: 160)
                                .frame(maxWidth: .infinity)
                        @unknown default:
                            imagePlaceholder
                        }
                    }
                    .cornerRadius(12)
                } else {
                    imagePlaceholder
                }

                // Multi-store badge
                if product.offers.count > 1 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(product.offers.count) NEGOZI")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(8)
                    .padding(8)
                }
            }

            // Brand & Name
            VStack(alignment: .leading, spacing: 3) {
                if let brand = product.brand {
                    Text(brand.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }

                Text(product.canonical_name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Prices & Savings
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(product.formattedBestPrice)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(.green)

                    if let best = product.bestOffer, let orig = best.formattedOriginalPrice {
                        Text(orig)
                            .font(.system(size: 13))
                            .strikethrough()
                            .foregroundColor(.secondary)

                        if let badge = best.discountBadge {
                            DiscountBadge(discountText: badge)
                        }
                    }
                }

                if let best = product.bestOffer {
                    HStack(spacing: 4) {
                        Text("da")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        StoreBadge(storeName: best.store_name)
                    }
                }

                if let savings = product.formattedSavings {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 10))
                        Text(savings)
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.green)
                    .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray6))
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .overlay(
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
            )
            .cornerRadius(12)
    }
}
