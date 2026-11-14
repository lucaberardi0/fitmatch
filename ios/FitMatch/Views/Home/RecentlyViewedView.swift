import SwiftUI

struct StoreNavigationTarget: Identifiable, Hashable {
    let id: String
    let name: String
}

struct RecentlyViewedView: View {
    @ObservedObject private var recentManager = RecentActivityManager.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProduct: MatchedProduct? = nil
    @State private var selectedStore: StoreNavigationTarget? = nil
    @State private var showingClearConfirmation = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var displayedActivities: [RecentActivityItem] {
        var seen = Set<String>()
        var list: [RecentActivityItem] = []
        for act in recentManager.activities where act.type == .product || act.type == .store {
            let key = RecentActivityManager.normalizedKey(type: act.type, title: act.title)
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
            headerBar

            if displayedActivities.isEmpty {
                emptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(displayedActivities) { item in
                            if item.type == .store {
                                storeCard(item: item)
                            } else {
                                productCard(item: item)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 90)
                }
                .refreshable {
                    await recentManager.syncFromDatabase()
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await recentManager.syncFromDatabase()
        }
        .onAppear {
            TabBarVisibilityManager.shared.hide(for: "recently_viewed")
        }
        .onDisappear {
            TabBarVisibilityManager.shared.show(for: "recently_viewed")
        }
        .navigationDestination(item: $selectedProduct) { prod in
            ProductDetailView(product: prod)
        }
        .navigationDestination(item: $selectedStore) { store in
            StoreDetailView(storeId: store.id, initialStoreName: store.name)
        }
        .alert("Cancella cronologia", isPresented: $showingClearConfirmation) {
            Button("Annulla", role: .cancel) { }
            Button("Cancella tutto", role: .destructive) {
                withAnimation(.easeInOut) {
                    recentManager.clearAll()
                }
            }
        } message: {
            Text("Vuoi davvero rimuovere tutti gli elementi visti di recente?")
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack {
            // Back Button
            Button(action: { dismiss() }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 40, height: 40)
                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                        .overlay(
                            Circle()
                                .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 0.8)
                        )
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Visti di recente")
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

            Spacer()

            // Balance spacer with subtle options menu
            if !displayedActivities.isEmpty {
                Menu {
                    Button(role: .destructive, action: { showingClearConfirmation = true }) {
                        Label("Cancella cronologia", systemImage: "trash")
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 40, height: 40)
                            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                            .overlay(
                                Circle()
                                    .stroke(Color(red: 232/255, green: 233/255, blue: 238/255), lineWidth: 0.8)
                            )
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 70/255, green: 70/255, blue: 75/255))
                    }
                }
            } else {
                Color.clear
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Product Card (Matching Shopify Shop Style)
    private func productCard(item: RecentActivityItem) -> some View {
        let product = item.effectiveProduct
        let isFav = wishlist.isFavorite(product.canonical_name)
        let bestPrice = product.best_price ?? product.bestOffer?.price
        let origPrice = product.highest_price ?? product.bestOffer?.original_price

        return ZStack {
            // Card background
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 242/255, green: 243/255, blue: 245/255))

            // Center Product Image
            if let imgUrl = product.image_url ?? item.imageUrl, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                ShopCachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                    case .failure(_):
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
                    case .empty:
                        ShopSkeletonBlock(cornerRadius: 18)
                            .padding(12)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "tag.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color(red: 200/255, green: 200/255, blue: 205/255))
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            selectedProduct = product
        }
        .overlay(alignment: .topLeading) {
            // Price Pill (Top-Left)
            if let best = bestPrice {
                HStack(spacing: 4) {
                    Text(formatPrice(best))
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let orig = origPrice, orig > best {
                        Text(formatPrice(orig))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.72))
                            .strikethrough(true, color: .white.opacity(0.75))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.32))
                )
                .padding([.top, .leading], 10)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Dismiss "X" Button (Top-Right)
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    recentManager.removeActivity(item)
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.32))
                        .frame(width: 30, height: 30)

                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding([.top, .trailing], 10)
        }
        .overlay(alignment: .bottomTrailing) {
            // Wishlist Heart Button (Bottom-Right)
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    wishlist.toggleFavorite(product: product)
                }
            }) {
                ZStack {
                    Circle()
                        .fill(isFav ? Color.shopPurple : Color.black.opacity(0.32))
                        .frame(width: 34, height: 34)

                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding([.bottom, .trailing], 10)
        }
    }

    // MARK: - Store Card (Matching Shop Store Tiles)
    private func storeCard(item: RecentActivityItem) -> some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 26/255, green: 26/255, blue: 30/255), Color(red: 16/255, green: 16/255, blue: 20/255)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Center Logo or Stylized Name
            if let imgUrl = item.imageUrl, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                ShopCachedAsyncImage(url: url, maxPixelSize: 400) { phase in
                    if let img = phase.image {
                        img
                            .resizable()
                            .scaledToFit()
                            .padding(24)
                    } else {
                        storeLogoPlaceholder(title: item.title)
                    }
                }
            } else {
                storeLogoPlaceholder(title: item.title)
            }

            // Bottom Store Label
            VStack {
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "bag.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))

                    Text(item.title.uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .tracking(0.6)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.45))
                )
                .padding(.bottom, 12)
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            selectedStore = StoreNavigationTarget(id: item.storeId ?? item.title.lowercased(), name: item.title)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    recentManager.removeActivity(item)
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 30, height: 30)

                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding([.top, .trailing], 10)
        }
    }

    private func storeLogoPlaceholder(title: String) -> some View {
        VStack(spacing: 8) {
            ShopStoreLogo(storeName: title, showVerified: false, showLabel: false, size: 52)
                .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)

            Text(title.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
                .padding(.horizontal, 12)
        }
    }

    private func formatPrice(_ val: Double) -> String {
        return String(format: "%.2f €", val).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack {
            Spacer()

            FitMatchEmptyStateView(
                icon: "clock.arrow.circlepath",
                accentColor: .shopPurple,
                badgeText: "CRONOLOGIA FITMATCH",
                title: "Nessun prodotto consultato di recente",
                subtitle: "Esplora scarpe da running, orologi GPS, ciclismo e padel: ogni modello aperto viene salvato qui per confrontare subito taglie e negozi.",
                primaryTitle: "Esplora attrezzatura sportiva",
                primaryIcon: "magnifyingglass",
                primaryColor: .shopDark,
                onPrimaryTap: {
                    dismiss()
                }
            )
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
