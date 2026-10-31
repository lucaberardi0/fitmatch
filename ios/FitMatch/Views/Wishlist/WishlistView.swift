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
                // Top Filter Chips & Live Refresh Button
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

                                Button(action: { selectedFilter = filter }) {
                                    HStack(spacing: 4) {
                                        Text(filter.rawValue)
                                        if count > 0 {
                                            Text("\(count)")
                                                .font(.system(size: 11, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(selectedFilter == filter ? Color.white.opacity(0.3) : Color(.systemGray4))
                                                .cornerRadius(8)
                                        }
                                    }
                                    .font(.system(size: 13, weight: selectedFilter == filter ? .bold : .medium))
                                    .foregroundColor(selectedFilter == filter ? .white : .primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(selectedFilter == filter ? Color.shopDark : Color(.systemGray6))
                                    .cornerRadius(20)
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
                                        .font(.system(size: 15, weight: .bold))
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
                            .foregroundColor(.secondary)
                        Text("Nessun articolo per questo filtro")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
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
                // Build a temporary MatchedProduct to configure alert
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
                    .font(.system(size: 20, weight: .bold))
                Text("Tocca l'icona del cuore sui prodotti per salvarli, monitorare i ribassi di prezzo e ricevere notifiche appena scendono.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
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
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                // Product Thumbnail
                ZStack {
                    Color(.systemGray6)
                    if let imgUrl = item.image_url, let url = URL(string: imgUrl) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit().padding(4)
                            } else {
                                Color(.systemGray5)
                            }
                        }
                    }
                }
                .frame(width: 84, height: 84)
                .cornerRadius(14)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let brand = item.brand {
                            Text(brand.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(item.canonical_name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    // Price row
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.formattedCurrentPrice)
                            .font(.system(size: 17, weight: .black))
                            .foregroundColor(.primary)

                        if item.hasPriceDropped {
                            Text(item.formattedInitialPrice)
                                .font(.system(size: 13))
                                .strikethrough()
                                .foregroundColor(.secondary)

                            if let savings = item.formattedSavingsSinceAdded {
                                Text(savings)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12))
                                    .cornerRadius(6)
                            }
                        }
                    }

                    if let store = item.bestStore {
                        Text("Miglior prezzo su \(store)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Alert Status & Quick Action Buttons
            HStack {
                // Alert Pill
                Button(action: onEditAlert) {
                    HStack(spacing: 5) {
                        Image(systemName: item.isAlertEnabled ? "bell.fill" : "bell.slash")
                            .font(.system(size: 11))
                            .foregroundColor(item.isAlertEnabled ? .shopPurple : .secondary)

                        if item.isAlertEnabled, let target = item.formattedTargetPrice {
                            Text("Alert: < \(target)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.shopPurple)
                        } else {
                            Text(item.isAlertEnabled ? "Alert attivo" : "Alert disattivato")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(item.isAlertEnabled ? Color.shopPurpleLight : Color(.systemGray6))
                    .cornerRadius(12)
                }

                Spacer()

                // Test simulation button
                Button(action: onSimulateDrop) {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text("Simula calo")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(12)
                }

                // Buy link if available
                if let urlString = item.bestStoreUrl, let url = URL(string: urlString) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text("Compra")
                                .font(.system(size: 12, weight: .bold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.shopDark)
                        .cornerRadius(14)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }
}
