import SwiftUI

struct ProductCardView: View {
    let product: MatchedProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Image Container with Floating Overlays
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Color.shopSurface

                    if let imageUrl = product.image_url, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .padding(10)
                            case .failure:
                                imagePlaceholder
                            case .empty:
                                ProgressView()
                                    .tint(.shopPurple)
                            @unknown default:
                                imagePlaceholder
                            }
                        }
                    } else {
                        imagePlaceholder
                    }
                }
                .frame(height: 165)
                .frame(maxWidth: .infinity)
                .cornerRadius(14)

                // Top Floating Elements
                HStack(alignment: .top) {
                    if product.offers.count > 1 {
                        HStack(spacing: 3) {
                            Text("\(product.offers.count) STORES")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.shopDark.opacity(0.85))
                        .cornerRadius(6)
                    } else if let best = product.bestOffer, let badge = best.discountBadge {
                        DiscountBadge(discountText: badge)
                    }

                    Spacer()

                    WishlistButton(product: product)
                }
                .padding(8)
            }
            .padding(6)

            // 2. Info Content
            VStack(alignment: .leading, spacing: 5) {
                // Store Pill with Verified Badge
                if let best = product.bestOffer {
                    ShopStoreLogo(storeName: best.store_name, showVerified: true, size: 13)
                }

                // Canonical Product Title
                Text(product.canonical_name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.shopDark)
                    .lineLimit(2)
                    .lineSpacing(1.5)
                    .frame(height: 38, alignment: .topLeading)

                // Price Section (Shop Style)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(product.formattedBestPrice)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundColor(.shopDark)

                        if let best = product.bestOffer, let orig = best.formattedOriginalPrice {
                            Text(orig)
                                .font(.system(size: 11.5, weight: .regular))
                                .strikethrough()
                                .foregroundColor(.shopTextMuted)
                        }
                    }

                    // Savings Pill if multi-store comparison found savings
                    if let savings = product.cross_store_savings, savings > 1.0 {
                        SavingsPill(amountText: "Risparmi €\(String(format: "%.0f", savings))")
                    } else if let best = product.bestOffer, let badge = best.discountBadge {
                        DiscountBadge(discountText: badge)
                    }
                }

                // Sizes availability preview
                if let best = product.bestOffer, let sizes = best.available_sizes, !sizes.isEmpty {
                    Text("Taglie: " + sizes.prefix(4).joined(separator: ", ") + (sizes.count > 4 ? ".." : ""))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 12)
        }
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.shopBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private var imagePlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 26))
                .foregroundColor(.shopTextMuted.opacity(0.5))
        }
    }
}
