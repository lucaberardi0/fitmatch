import SwiftUI

struct ProductDetailView: View {
    let product: MatchedProduct
    @State private var selectedOfferIndex: Int = 0
    @Environment(\.dismiss) private var dismiss

    var currentOffer: Offer? {
        if product.offers.indices.contains(selectedOfferIndex) {
            return product.offers[selectedOfferIndex]
        }
        return product.bestOffer
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Hero Image in Shop Style
                    ZStack(alignment: .topTrailing) {
                        if let imageUrl = product.image_url, let url = URL(string: imageUrl) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 280)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(Color(.systemGray6).opacity(0.5))
                                } else {
                                    Rectangle()
                                        .fill(Color(.systemGray6))
                                        .frame(height: 280)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .cornerRadius(20)
                        }

                        WishlistButton()
                            .padding(16)
                    }
                    .padding(.horizontal, 16)

                    // Title & Brand
                    VStack(alignment: .leading, spacing: 6) {
                        if let brand = product.brand {
                            Text(brand.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.shopPurple)
                                .tracking(0.8)
                        }

                        Text(product.canonical_name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(product.formattedBestPrice)
                                .font(.system(size: 26, weight: .black))
                                .foregroundColor(.primary)

                            if let best = product.bestOffer, let orig = best.formattedOriginalPrice {
                                Text(orig)
                                    .font(.system(size: 16))
                                    .strikethrough()
                                    .foregroundColor(.secondary)

                                if let badge = best.discountBadge {
                                    DiscountBadge(discountText: badge)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // Cross-Store Savings Callout (Shop signature banner)
                    if let savings = product.cross_store_savings, savings > 1.0 {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.shopPurpleLight)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.shopPurple)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("CONFRONTO PREZZI ATTIVO")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(.shopPurple)
                                Text("Risparmi fino a \(String(format: "€%.2f", savings)) confrontando i negozi!")
                                    .font(.system(size: 13, weight: .bold))
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.shopPurpleLight.opacity(0.6))
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                    }

                    // Offers Selector List
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PREZZI DISPONIBILI NEI NEGOZI PARTNER")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(0.5)
                            .padding(.horizontal, 16)

                        VStack(spacing: 10) {
                            ForEach(Array(product.offers.enumerated()), id: \.offset) { index, offer in
                                let isSelected = (index == selectedOfferIndex)
                                let isBest = (offer.price == product.best_price)

                                Button(action: {
                                    selectedOfferIndex = index
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18))
                                            .foregroundColor(isSelected ? .shopPurple : .secondary)

                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 6) {
                                                StoreBadge(storeName: offer.store_name)
                                                if isBest {
                                                    BestPriceBadge()
                                                }
                                            }

                                            if let sizes = offer.available_sizes, !sizes.isEmpty {
                                                Text("Taglie: \(sizes.prefix(5).joined(separator: ", "))\(sizes.count > 5 ? ".." : "")")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        Spacer()

                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(offer.formattedPrice)
                                                .font(.system(size: 16, weight: .heavy))
                                                .foregroundColor(isBest ? .shopPurple : .primary)

                                            if let orig = offer.formattedOriginalPrice {
                                                Text(orig)
                                                    .font(.system(size: 11))
                                                    .strikethrough()
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .padding(14)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(14)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: isSelected ? 2 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer()
                        .frame(height: 100) // Space for sticky bottom bar
                }
                .padding(.vertical, 12)
            }

            // Sticky Bottom Shop-style CTA Bar
            if let offer = currentOffer, let url = URL(string: offer.url) {
                VStack(spacing: 0) {
                    Divider()

                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Totale da")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(offer.formattedPrice)
                                .font(.system(size: 20, weight: .black))
                        }

                        Link(destination: url) {
                            HStack {
                                Image(systemName: "bag.fill")
                                    .font(.system(size: 14))
                                Text("Acquista su \(offer.store_name)")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.shopPurple) // Shopify Shop signature CTA button
                            .cornerRadius(25)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
    }
}
