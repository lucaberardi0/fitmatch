import SwiftUI

struct ProductDetailView: View {
    let product: MatchedProduct
    @State private var selectedOfferIndex: Int = 0
    @State private var showingAlertSheet: Bool = false
    @ObservedObject private var wishlist = WishlistManager.shared
    @Environment(\.dismiss) private var dismiss

    var currentOffer: Offer? {
        if product.offers.indices.contains(selectedOfferIndex) {
            return product.offers[selectedOfferIndex]
        }
        return product.bestOffer
    }

    private var wishlistItem: WishlistItem? {
        wishlist.getItem(product.canonical_name)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 1. Hero Image in Shop Style
                    ZStack(alignment: .topTrailing) {
                        ZStack {
                            Color.shopSurface

                            if let imageUrl = product.image_url, let url = URL(string: imageUrl) {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 290)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 20)
                                    } else {
                                        Rectangle()
                                            .fill(Color.shopSurface)
                                            .frame(height: 290)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                        .cornerRadius(22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(Color.shopBorder, lineWidth: 1)
                        )

                        // Floating Top Action Buttons
                        HStack(spacing: 10) {
                            Button(action: {
                                showingAlertSheet = true
                            }) {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 38, height: 38)
                                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                                    .overlay(
                                        Image(systemName: wishlistItem?.isAlertEnabled == true ? "bell.badge.fill" : "bell")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(wishlistItem?.isAlertEnabled == true ? .shopPurple : .shopDark)
                                    )
                            }

                            WishlistButton(product: product)
                        }
                        .padding(14)
                    }
                    .padding(.horizontal, 16)

                    // 2. Brand & Canonical Title
                    VStack(alignment: .leading, spacing: 6) {
                        if let brand = product.brand {
                            Text(brand.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.shopPurple)
                                .tracking(1.0)
                        }

                        Text(product.canonical_name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        // Price Block
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(product.formattedBestPrice)
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundColor(.shopDark)

                            if let best = product.bestOffer, let orig = best.formattedOriginalPrice {
                                Text(orig)
                                    .font(.system(size: 16))
                                    .strikethrough()
                                    .foregroundColor(.shopTextMuted)

                                if let badge = best.discountBadge {
                                    DiscountBadge(discountText: badge)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // 3. Cross-Store Savings Sparkle Banner (Shop Signature Feature)
                    if let savings = product.cross_store_savings, savings > 1.0 {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.shopPurpleLight)
                                    .frame(width: 42, height: 42)

                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.shopPurple)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("CONFRONTO PREZZI MULTI-STORE")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(.shopPurple)
                                    .tracking(0.5)

                                Text("Risparmi fino a \(String(format: "€%.2f", savings)) scegliendo l'offerta migliore tra i 6 negozi partner.")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundColor(.shopDark)
                                    .lineLimit(2)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.shopPurpleLight.opacity(0.6))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.shopPurple.opacity(0.18), lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                    }

                    // 4. Comparison Cards (The 6 Retailers)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("OFFERTE DISPONIBILI (\(product.offers.count))")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.shopTextMuted)
                                .tracking(0.6)
                            Spacer()
                            Text("Ordina per prezzo")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.shopPurple)
                        }
                        .padding(.horizontal, 16)

                        VStack(spacing: 10) {
                            ForEach(Array(product.offers.enumerated()), id: \.offset) { index, offer in
                                let isSelected = (index == selectedOfferIndex)
                                let isBest = (offer.price == product.best_price)

                                Button(action: {
                                    selectedOfferIndex = index
                                }) {
                                    HStack(spacing: 12) {
                                        // Store Logo with verified check
                                        ShopStoreLogo(storeName: offer.store_name, showVerified: true, size: 24)

                                        Spacer()

                                        // Pricing & Badge
                                        VStack(alignment: .trailing, spacing: 3) {
                                            HStack(spacing: 6) {
                                                if isBest {
                                                    BestPriceBadge()
                                                }
                                                Text(offer.formattedPrice)
                                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                                    .foregroundColor(.shopDark)
                                            }

                                            if let orig = offer.formattedOriginalPrice {
                                                HStack(spacing: 4) {
                                                    Text(orig)
                                                        .font(.system(size: 11))
                                                        .strikethrough()
                                                        .foregroundColor(.shopTextMuted)
                                                    if let badge = offer.discountBadge {
                                                        Text(badge)
                                                            .font(.system(size: 10, weight: .bold))
                                                            .foregroundColor(.shopPurple)
                                                    }
                                                }
                                            }

                                            if let sizes = offer.available_sizes, !sizes.isEmpty {
                                                Text("Taglie: " + sizes.prefix(3).joined(separator: ", "))
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.shopTextMuted)
                                            }
                                        }

                                        // Radio selection checkmark
                                        Circle()
                                            .fill(isSelected ? Color.shopPurple : Color.clear)
                                            .frame(width: 20, height: 20)
                                            .overlay(
                                                Circle()
                                                    .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1.5)
                                            )
                                            .overlay(
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .opacity(isSelected ? 1 : 0)
                                            )
                                    }
                                    .padding(14)
                                    .background(isSelected ? Color.shopPurpleLight.opacity(0.3) : Color.white)
                                    .cornerRadius(14)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: isSelected ? 1.5 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // 5. Shop Trust & Shipping Guarantees
                    VStack(alignment: .leading, spacing: 12) {
                        Text("GARANZIE DI ACQUISTO")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.shopTextMuted)
                            .tracking(0.6)
                            .padding(.horizontal, 16)

                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "shield.checkmark.fill")
                                    .foregroundColor(.shopGreen)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Negozi Verificati")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("Rivenditori ufficiali")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.shopBorder, lineWidth: 1))

                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.shopPurple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Reso Garantito")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("Fino a 30 giorni")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.shopBorder, lineWidth: 1))
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 100)
                }
                .padding(.top, 10)
            }

            // 6. Sticky Floating Bottom Bar (Shop Pay Style)
            if let offer = currentOffer {
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.shopBorder)

                    HStack(spacing: 12) {
                        // Quick Price Alert Bell Button
                        Button(action: {
                            showingAlertSheet = true
                        }) {
                            Circle()
                                .fill(Color.shopSurface)
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: wishlistItem?.isAlertEnabled == true ? "bell.badge.fill" : "bell.fill")
                                        .font(.system(size: 17))
                                        .foregroundColor(wishlistItem?.isAlertEnabled == true ? .shopPurple : .shopDark)
                                )
                        }

                        // Giant Shop-Pay Style Primary Button
                        if let url = URL(string: offer.url) {
                            Link(destination: url) {
                                HStack(spacing: 6) {
                                    Text("Acquista a \(offer.formattedPrice) su \(offer.store_name)")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .lineLimit(1)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.shopPurple)
                                .cornerRadius(25) // Shop pill button
                                .shadow(color: Color.shopPurple.opacity(0.35), radius: 8, x: 0, y: 4)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.ignoresSafeArea(edges: .bottom))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAlertSheet) {
            PriceAlertSheet(product: product)
        }
    }
}
