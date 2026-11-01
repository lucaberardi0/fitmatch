import SwiftUI

struct RecentlyViewedView: View {
    @ObservedObject private var recentManager = RecentActivityManager.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearConfirmation = false

    private var productActivities: [RecentActivityItem] {
        var seen = Set<String>()
        var list: [RecentActivityItem] = []
        for act in recentManager.activities where act.type == .product {
            let key = act.title.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                list.append(act)
            }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Button(action: { dismiss() }) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
                            )
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Visti di recente")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

                Spacer()

                if !productActivities.isEmpty {
                    Button(action: { showingClearConfirmation = true }) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 1)
                                )
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.red)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 40, height: 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)

            if productActivities.isEmpty {
                emptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(productActivities) { item in
                            if let prod = item.productData {
                                NavigationLink(destination: ProductDetailView(product: prod)) {
                                    recentlyViewedRow(item: item, product: prod)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive, action: {
                                        withAnimation {
                                            recentManager.removeActivity(item)
                                        }
                                    }) {
                                        Label("Rimuovi dalla cronologia", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(Color(red: 245/255, green: 246/255, blue: 248/255).ignoresSafeArea())
        .navigationBarHidden(true)
        .alert("Cancella cronologia", isPresented: $showingClearConfirmation) {
            Button("Annulla", role: .cancel) { }
            Button("Cancella tutto", role: .destructive) {
                withAnimation {
                    recentManager.activities.removeAll { $0.type == .product }
                }
            }
        } message: {
            Text("Vuoi davvero rimuovere tutti i prodotti visualizzati di recente?")
        }
    }

    private func recentlyViewedRow(item: RecentActivityItem, product: MatchedProduct) -> some View {
        HStack(spacing: 14) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 244/255, green: 245/255, blue: 248/255))
                    .frame(width: 76, height: 76)

                if let imgUrl = product.image_url ?? item.imageUrl, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img
                                .resizable()
                                .scaledToFit()
                                .padding(6)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                        }
                    }
                } else {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                }
            }
            .frame(width: 76, height: 76)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                if let brand = product.brand ?? item.subtitle {
                    Text(brand.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.shopPurple)
                        .tracking(0.5)
                }

                Text(product.canonical_name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.shopDark)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let price = product.best_price ?? product.bestOffer?.price {
                        Text(String(format: "%.2f €", price).replacingOccurrences(of: ".", with: ","))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                    }

                    if let orig = product.highest_price, let p = product.best_price, orig > p {
                        Text(String(format: "%.2f €", orig).replacingOccurrences(of: ".", with: ","))
                            .font(.system(size: 11))
                            .foregroundColor(.shopTextMuted)
                            .strikethrough()
                    }

                    Spacer()

                    Text(item.formattedDate)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                }
            }

            // Wishlist heart
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                wishlist.toggleFavorite(product: product)
            }) {
                Image(systemName: wishlist.isFavorite(product.canonical_name) ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(wishlist.isFavorite(product.canonical_name) ? .red : Color(red: 170/255, green: 170/255, blue: 180/255))
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 1)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Circle()
                .fill(Color.white)
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 34))
                        .foregroundColor(.shopPurple)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)

            Text("Nessun articolo visto di recente")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)

            Text("I prodotti che visualizzi nei negozi o nella ricerca appariranno qui per essere ritrovati al volo.")
                .font(.system(size: 14))
                .foregroundColor(.shopTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: { dismiss() }) {
                Text("Esplora prodotti")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.shopDark)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
