import SwiftUI

struct ProductDetailView: View {
    let product: MatchedProduct
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Image
                if let imageUrl = product.image_url, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(height: 240)
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemBackground))
                        } else {
                            Rectangle()
                                .fill(Color(.systemGray6))
                                .frame(height: 240)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .cornerRadius(16)
                }

                // Brand and Name
                VStack(alignment: .leading, spacing: 6) {
                    if let brand = product.brand {
                        Text(brand.uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.blue)
                    }

                    Text(product.canonical_name)
                        .font(.system(size: 22, weight: .bold))
                }

                // Cross-Store Savings Banner
                if let savings = product.cross_store_savings, savings > 1.0 {
                    HStack(spacing: 12) {
                        Image(systemName: "banknote.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("RISPARMIO CONFRONTO PREZZI")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.green)
                            Text("Risparmi fino a \(String(format: "€%.2f", savings)) confrontando i negozi!")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(12)
                }

                // Offers Comparison Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Offerte a Confronto (\(product.offers.count))")
                        .font(.system(size: 17, weight: .bold))

                    ForEach(Array(product.offers.enumerated()), id: \.offset) { index, offer in
                        let isBest = (offer.price == product.best_price)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                StoreBadge(storeName: offer.store_name)

                                if isBest {
                                    BestPriceBadge()
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(offer.formattedPrice)
                                        .font(.system(size: 18, weight: .heavy))
                                        .foregroundColor(isBest ? .green : .primary)

                                    if let orig = offer.formattedOriginalPrice {
                                        Text(orig)
                                            .font(.system(size: 12))
                                            .strikethrough()
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            // Available sizes preview for this offer
                            if let sizes = offer.available_sizes, !sizes.isEmpty {
                                HStack(spacing: 6) {
                                    Text("Taglie:")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 4) {
                                            ForEach(sizes, id: \.self) { sz in
                                                Text(sz)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color(.systemGray5))
                                                    .cornerRadius(4)
                                            }
                                        }
                                    }
                                }
                            }

                            if let destUrl = URL(string: offer.url) {
                                Link(destination: destUrl) {
                                    HStack {
                                        Text("Acquista su \(offer.store_name)")
                                            .font(.system(size: 14, weight: .bold))
                                        Spacer()
                                        Image(systemName: "arrow.up.right.square")
                                    }
                                    .foregroundColor(isBest ? .white : .blue)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 14)
                                    .background(isBest ? Color.green : Color.blue.opacity(0.12))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isBest ? Color.green : Color.clear, lineWidth: 2)
                        )
                    }
                }
            }
            .padding(16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }
}
