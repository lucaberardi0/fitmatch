import SwiftUI

struct StoreShowcaseCard: View {
    let showcase: StoreShowcase
    let onSelectStore: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. Store Header (Shop Merchant Style)
            HStack(spacing: 12) {
                // Store Avatar
                ShopStoreLogo(storeName: showcase.store_name, showVerified: false, showLabel: false, size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(showcase.store_name)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.shopPurple)
                    }

                    Text("★ \(showcase.rating) • \(showcase.total_offers) articoli • Sconti fino a -\(String(format: "%.0f", showcase.avg_discount))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                }

                Spacer()

                Button(action: {
                    onSelectStore(showcase.store_name)
                }) {
                    HStack(spacing: 3) {
                        Text("Vedi tutto")
                            .font(.system(size: 12.5, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.shopPurple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.shopPurpleLight)
                    .cornerRadius(12)
                }
            }

            Divider()
                .background(Color.shopBorder.opacity(0.8))

            // 2. Horizontal Product Carousel Inside the Store Card
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(showcase.products) { item in
                        let matched = item.toMatchedProduct(
                            storeId: showcase.store_id,
                            storeName: showcase.store_name
                        )

                        NavigationLink(destination: ProductDetailView(product: matched)) {
                            VStack(alignment: .leading, spacing: 6) {
                                // Product Image Box
                                ZStack(alignment: .topTrailing) {
                                    ZStack {
                                        Color.shopSurface

                                        if let imgUrl = item.image_url, let url = URL(string: imgUrl) {
                                            AsyncImage(url: url) { phase in
                                                if let img = phase.image {
                                                    img
                                                        .resizable()
                                                        .scaledToFit()
                                                        .padding(6)
                                                } else {
                                                    Color.shopSurface
                                                }
                                            }
                                        }
                                    }
                                    .frame(width: 110, height: 105)
                                    .cornerRadius(12)

                                    if let badge = item.discountBadge {
                                        Text(badge)
                                            .font(.system(size: 9, weight: .black, design: .rounded))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2.5)
                                            .background(Color.shopPurple)
                                            .cornerRadius(5)
                                            .padding(5)
                                    }
                                }

                                // Info
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.canonical_name)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                        .lineLimit(1)
                                        .frame(width: 110, alignment: .leading)

                                    HStack(spacing: 4) {
                                        Text(item.formattedPrice)
                                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                                            .foregroundColor(.shopDark)

                                        if let orig = item.formattedOriginalPrice {
                                            Text(orig)
                                                .font(.system(size: 10))
                                                .strikethrough()
                                                .foregroundColor(.shopTextMuted)
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.shopBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}
