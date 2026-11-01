import SwiftUI

struct ProductDetailView: View {
    let product: MatchedProduct
    @State private var selectedOfferIndex: Int = 0
    @State private var selectedSize: String? = nil
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

    private var allSizes: [String] {
        var set = Set<String>()
        for offer in product.offers {
            if let sizes = offer.available_sizes {
                for s in sizes { set.insert(s) }
            }
        }
        if set.isEmpty {
            return ["40", "41", "42", "42.5", "43", "44", "45"]
        }
        return set.sorted()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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

                            WishlistButton(product: product, size: selectedSize)
                        }
                        .padding(14)
                    }
                    .padding(.horizontal, 16)

                    // 2. Canonical Product Title & Brand
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
                            Text(currentOffer?.formattedPrice ?? product.formattedBestPrice)
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundColor(.shopDark)

                            if let current = currentOffer, let orig = current.formattedOriginalPrice {
                                Text(orig)
                                    .font(.system(size: 16))
                                    .strikethrough()
                                    .foregroundColor(.shopTextMuted)
                            }

                            if let current = currentOffer, let badge = current.discountBadge {
                                DiscountBadge(discountText: badge)
                            }
                        }

                        if let current = currentOffer {
                            HStack(spacing: 6) {
                                Image(systemName: "box.truck.fill")
                                    .font(.system(size: 11))
                                Text(current.isFreeShipping ? "Spedizione gratuita inclusa" : "\(current.formattedShipping) (Totale \(current.formattedTotalPrice))")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(current.isFreeShipping ? .shopGreen : .shopTextMuted)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 16)

                    // 3. Size Filter Chips
                    if !allSizes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("FILTRA PER TAGLIA")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(.shopTextMuted)
                                    .tracking(0.6)
                                Spacer()
                                if let sz = selectedSize {
                                    Text("Selezionata: \(sz)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.shopPurple)
                                }
                            }
                            .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(allSizes, id: \.self) { sz in
                                        let isSel = (selectedSize == sz)
                                        Button(action: {
                                            selectedSize = (selectedSize == sz) ? nil : sz
                                        }) {
                                            SizeChip(size: sz, isSelected: isSel)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    // 4. Cross-Store Savings Sparkle Banner
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

                                Text("Risparmi fino a \(String(format: "€%.2f", savings)) scegliendo l'offerta migliore tra i 10 negozi partner.")
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

                    // Versus Mode Quick Action
                    NavigationLink(destination: ModelCompareView()) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.left.arrow.right.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.shopPurple)
                            Text("Confronta questo articolo con un altro modello (IA)")
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.shopBorder, lineWidth: 1))
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)

                    // 5. Comparison Cards: All Partner Store Offers
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("OFFERTE NEGOZI PARTNER (\(product.offers.count))")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.shopTextMuted)
                                .tracking(0.6)
                            Spacer()
                            Text("Tocca per selezionare")
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

                                        // Pricing & Shipping
                                        VStack(alignment: .trailing, spacing: 3) {
                                            HStack(spacing: 6) {
                                                if isBest {
                                                    BestPriceBadge()
                                                }
                                                Text(offer.formattedPrice)
                                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                                    .foregroundColor(.shopDark)
                                            }

                                            HStack(spacing: 4) {
                                                if offer.isFreeShipping {
                                                    Text("Sped. Gratis")
                                                        .font(.system(size: 10, weight: .heavy))
                                                        .foregroundColor(.shopGreen)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 2)
                                                        .background(Color.shopGreenLight)
                                                        .cornerRadius(4)
                                                } else {
                                                    Text(offer.formattedShipping)
                                                        .font(.system(size: 10.5, weight: .medium))
                                                        .foregroundColor(.shopTextMuted)
                                                }

                                                Text("• Totale \(offer.formattedTotalPrice)")
                                                    .font(.system(size: 10.5, weight: .bold))
                                                    .foregroundColor(.shopDark)
                                            }

                                            if let sizes = offer.available_sizes, !sizes.isEmpty {
                                                Text("Taglie: " + sizes.prefix(4).joined(separator: ", "))
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.shopTextMuted)
                                            }
                                        }

                                        // Radio checkmark
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

                    // 6. Shop Guarantees
                    VStack(alignment: .leading, spacing: 12) {
                        Text("GARANZIE COMPARATORE FITMATCH")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.shopTextMuted)
                            .tracking(0.6)
                            .padding(.horizontal, 16)

                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "shield.checkmark.fill")
                                    .foregroundColor(.shopGreen)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("10 Store Ufficiali")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("Rivenditori verificati")
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
                                Image(systemName: "shippingbox.fill")
                                    .foregroundColor(.shopPurple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Spedizione Calcolata")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("Costi reali inclusi")
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

                    Spacer(minLength: 110)
                }
                .padding(.top, 10)
            }

            // 7. Sticky Floating Bottom Bar: Direct Link to Retailer Offer
            if let offer = currentOffer, let url = URL(string: offer.url) {
                VStack(spacing: 6) {
                    Divider()
                        .background(Color.shopBorder)

                    HStack(spacing: 12) {
                        // Price Alert Bell Button
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

                        // Primary Action Button (Opens Store's Real Product Page)
                        Link(destination: url) {
                            HStack(spacing: 8) {
                                Text("Vai all'offerta a \(offer.formattedPrice) su \(offer.store_name)")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .lineLimit(1)

                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.shopPurple)
                            .cornerRadius(24) // Shop capsule
                            .shadow(color: Color.shopPurple.opacity(0.35), radius: 8, x: 0, y: 4)
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 10))
                        Text(offer.isFreeShipping ? "Spedizione gratis • Nessun costo nascosto" : "Totale stimato: \(offer.formattedTotalPrice) con spedizione")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.shopTextMuted)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(Color.white.ignoresSafeArea(edges: .bottom))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAlertSheet) {
            PriceAlertSheet(product: product)
        }
        .onAppear {
            RecentActivityManager.shared.recordProductView(product)
        }
    }
}
