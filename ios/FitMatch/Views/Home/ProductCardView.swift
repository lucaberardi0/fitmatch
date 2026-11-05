import SwiftUI

struct ProductCardView: View {
    let product: MatchedProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Image Container with Floating Overlays (Shop Style)
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Color.shopSurface

                    if let imageUrl = product.image_url, let url = URL(string: imageUrl) {
                        ShopCachedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .padding(10)
                            case .failure:
                                imagePlaceholder
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: 14, height: 165)
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

                // Top Floating Overlays
                HStack(alignment: .top) {
                    if product.offers.count > 1 {
                        StoreCountBadge(count: product.offers.count)
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
                // Best Store Pill with Verified Badge
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

                // Price Section
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

                    // Cross-Store Savings Pill or Discount Badge
                    if let savings = product.cross_store_savings, savings > 1.0 {
                        SavingsPill(amountText: "Risparmi €\(String(format: "%.0f", savings))")
                    } else if let best = product.bestOffer, let badge = best.discountBadge {
                        DiscountBadge(discountText: badge)
                    }

                    // Shipping breakdown preview
                    if let best = product.bestOffer {
                        HStack(spacing: 3) {
                            Image(systemName: "box.truck.fill")
                                .font(.system(size: 8.5))
                            Text(best.formattedShipping)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(best.isFreeShipping ? .shopGreen : .shopTextMuted)
                        .padding(.top, 1)
                    }
                }

                // Available Sizes
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
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    private var imagePlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 26))
                .foregroundColor(.shopTextMuted.opacity(0.4))
        }
    }
}
