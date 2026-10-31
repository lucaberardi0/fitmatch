import SwiftUI

struct WishlistView: View {
    @ObservedObject private var wishlist = WishlistManager.shared
    @StateObject private var api = APIService.shared
    @State private var selectedFilter: WishlistFilter = .all
    @State private var itemToEditAlert: WishlistItem? = nil

    enum WishlistFilter: String, CaseIterable {
        case all = "Tutti"
        case priceDrops = "In Calo"
        case alertsOnly = "Alert Attivi"
    }

    private var filteredItems: [WishlistItem] {
        switch selectedFilter {
        case .all:
            return wishlist.items
        case .priceDrops:
            return wishlist.items.filter { $0.hasPriceDropped || ($0.lastPriceDrop ?? 0) > 0 }
        case .alertsOnly:
            return wishlist.items.filter { $0.isAlertEnabled }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header & Filter Chips
                if !wishlist.items.isEmpty {
                    VStack(spacing: 12) {
                        HStack {
                            ForEach(WishlistFilter.allCases, id: \.self) { filter in
                                let count: Int = {
                                    switch filter {
                                    case .all: return wishlist.items.count
                                    case .priceDrops: return wishlist.items.filter { $0.hasPriceDropped }.count
                                    case .alertsOnly: return wishlist.items.filter { $0.isAlertEnabled }.count
                                    }
                                }()

                                let isSelected = selectedFilter == filter

                                Button(action: {
                                    withAnimation(.spring(response: 0.25)) {
                                        selectedFilter = filter
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Text(filter.rawValue)
                                        if count > 0 {
                                            Text("\(count)")
                                                .font(.system(size: 11, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(isSelected ? Color.white.opacity(0.3) : Color.shopBorder)
                                                .cornerRadius(8)
                                        }
                                    }
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .foregroundColor(isSelected ? .white : .shopDark)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? Color.shopDark : Color.white)
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(isSelected ? Color.shopDark : Color.shopBorder, lineWidth: 1)
                                    )
                                }
                            }

                            Spacer()

                            Button(action: {
                                Task {
                                    await wishlist.refreshAllPrices(apiService: api)
                                }
                            }) {
                                if wishlist.isCheckingPrices {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.shopPurple)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.shopPurple)
                                }
                            }
                            .padding(8)
                            .background(Color.shopPurpleLight)
                            .clipShape(Circle())
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // Status message banner
                        if let msg = wishlist.lastCheckMessage {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 11))
                                Text(msg)
                                    .font(.system(size: 12))
                                Spacer()
                            }
                            .foregroundColor(.shopPurple)
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 8)
                }

                // Content
                if wishlist.items.isEmpty {
                    emptyStateView
                } else if filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.shopTextMuted)
                        Text("Nessun articolo per questo filtro")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.shopTextMuted)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredItems) { item in
                                WishlistCard(
                                    item: item,
                                    onEditAlert: {
                                        itemToEditAlert = item
                                    },
                                    onSimulateDrop: {
                                        wishlist.simulatePriceDrop(for: item.canonical_name, dropAmount: 20.0)
                                    },
                                    onDelete: {
                                        withAnimation {
                                            wishlist.removeFromWishlist(item.canonical_name)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    .refreshable {
                        await wishlist.refreshAllPrices(apiService: api)
                    }
                }
            }
            .background(Color.shopSurface.ignoresSafeArea())
            .navigationTitle("Preferiti & Alert")
            .sheet(item: $itemToEditAlert) { item in
                let dummyMatched = MatchedProduct(
                    canonical_name: item.canonical_name,
                    brand: item.brand,
                    image_url: item.image_url,
                    offers: [],
                    best_price: item.currentBestPrice,
                    highest_price: item.highestPrice,
                    cross_store_savings: nil
                )
                PriceAlertSheet(product: dummyMatched)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.shopPurpleLight)
                    .frame(width: 90, height: 90)
                Image(systemName: "heart.slash")
                    .font(.system(size: 40))
                    .foregroundColor(.shopPurple)
            }

            VStack(spacing: 8) {
                Text("Nessun preferito salvato")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                Text("Tocca l'icona del cuore sui prodotti per salvarli, monitorare i ribassi di prezzo e ricevere notifiche appena scendono.")
                    .font(.system(size: 13.5))
                    .foregroundColor(.shopTextMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }
}

// MARK: - Wishlist Item Card

struct WishlistCard: View {
    let item: WishlistItem
    let onEditAlert: () -> Void
    let onSimulateDrop: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Image Box
                ZStack {
                    Color.shopSurface
                    if let imgUrl = item.image_url, let url = URL(string: imgUrl) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFit().padding(4)
                            } else {
                                Image(systemName: "shoeprints.fill")
                                    .foregroundColor(.shopTextMuted.opacity(0.4))
                            }
                        }
                    } else {
                        Image(systemName: "shoeprints.fill")
                            .foregroundColor(.shopTextMuted.opacity(0.4))
                    }
                }
                .frame(width: 72, height: 72)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.shopBorder, lineWidth: 0.8)
                )

                // Info Content
                VStack(alignment: .leading, spacing: 3) {
                    if let brand = item.brand {
                        Text(brand.uppercased())
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.shopPurple)
                    }

                    Text(item.canonical_name)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(.shopDark)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(item.formattedCurrentPrice)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.shopDark)

                        if item.hasPriceDropped {
                            Text(item.formattedInitialPrice)
                                .font(.system(size: 11.5))
                                .strikethrough()
                                .foregroundColor(.shopTextMuted)

                            if let savings = item.formattedSavingsSinceAdded {
                                SavingsPill(amountText: "Calato di \(savings)")
                            }
                        }
                    }

                    if let store = item.bestStore {
                        ShopStoreLogo(storeName: store, showVerified: true, size: 12)
                            .padding(.top, 2)
                    }
                }

                Spacer()

                // Actions: Alert & Delete
                VStack(spacing: 8) {
                    Button(action: onEditAlert) {
                        Image(systemName: item.isAlertEnabled ? "bell.badge.fill" : "bell")
                            .font(.system(size: 15))
                            .foregroundColor(item.isAlertEnabled ? .shopPurple : .shopTextMuted)
                            .frame(width: 32, height: 32)
                            .background(item.isAlertEnabled ? Color.shopPurpleLight : Color.shopSurface)
                            .clipShape(Circle())
                    }

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(.shopTextMuted)
                            .frame(width: 32, height: 32)
                            .background(Color.shopSurface)
                            .clipShape(Circle())
                    }
                }
            }

            // Bottom Action Bar: Direct Link to Retailer Offer
            if let storeUrl = item.bestStoreUrl, let url = URL(string: storeUrl) {
                Divider()

                HStack {
                    if let target = item.formattedTargetPrice {
                        HStack(spacing: 3) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 10))
                            Text("Alert attivo: sotto \(target)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.shopPurple)
                    }

                    Spacer()

                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text("Vedi su \(item.bestStore ?? "Store")")
                                .font(.system(size: 12, weight: .bold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.shopPurple)
                        .cornerRadius(14)
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
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
    }
}
