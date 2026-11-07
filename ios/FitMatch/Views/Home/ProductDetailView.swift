import SwiftUI
import Charts

struct ProductDetailView: View {
    let product: MatchedProduct
    private let userPreferredSize: String?

    @State private var selectedOfferIndex: Int = 0
    @State private var selectedSize: String? = nil
    @State private var showingAlertSheet: Bool = false
    @State private var showingMoveToCollection: Bool = false
    @State private var selectedImageIndex: Int = 0
    @State private var priceHistory: PriceHistoryResponse? = nil
    @State private var isLoadingPriceHistory: Bool = false

    init(product: MatchedProduct, initialSize: String? = nil) {
        self.product = product
        let prefs = UserPreferencesManager.shared.preferences
        let prefSize = product.isComparable ? prefs.preferredShoeSize : prefs.preferredApparelSize
        let normPref = prefSize.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        self.userPreferredSize = normPref.isEmpty ? nil : normPref

        if let explicit = initialSize, !explicit.isEmpty {
            self._selectedSize = State(initialValue: explicit)
        } else if !normPref.isEmpty && product.allAvailableSizes.contains(where: {
            $0.replacingOccurrences(of: ",", with: ".") == normPref
        }) {
            // Auto-select user's preferred size!
            self._selectedSize = State(initialValue: normPref)
        } else {
            self._selectedSize = State(initialValue: nil)
        }
    }

    @ObservedObject private var wishlist = WishlistManager.shared
    @Environment(\.dismiss) private var dismiss

    private var displayedImages: [String] {
        product.allImages
    }

    var currentOffer: Offer? {
        if let sz = selectedSize {
            return product.bestOffer(for: sz)
        }
        if product.offers.indices.contains(selectedOfferIndex) {
            return product.offers[selectedOfferIndex]
        }
        return product.bestOffer
    }

    private var wishlistItem: WishlistItem? {
        wishlist.getItem(product.canonical_name)
    }

    private var allSizes: [String] {
        product.allAvailableSizes
    }

    private var sortedOffers: [(index: Int, offer: Offer, hasSize: Bool)] {
        var list: [(index: Int, offer: Offer, hasSize: Bool)] = []
        for (idx, off) in product.offers.enumerated() {
            let has = off.hasSize(selectedSize)
            list.append((index: idx, offer: off, hasSize: has))
        }
        if selectedSize != nil {
            return list.sorted {
                let s0 = $0.offer.sizeMatchStatus(selectedSize)
                let s1 = $1.offer.sizeMatchStatus(selectedSize)
                if s0 != s1 {
                    return s0 > s1
                }
                return $0.offer.price < $1.offer.price
            }
        }
        return list
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                    // 1. Hero Image / Multi-Photo Carousel in Shop Style
                    VStack(spacing: 12) {
                        ZStack(alignment: .topTrailing) {
                            ZStack(alignment: .bottom) {
                                Color.shopSurface

                                if displayedImages.count > 1 {
                                    TabView(selection: $selectedImageIndex) {
                                        ForEach(Array(displayedImages.enumerated()), id: \.offset) { index, imgUrlString in
                                            if let url = URL(string: imgUrlString) {
                                                ShopCachedAsyncImage(url: url, maxPixelSize: 1200) { phase in
                                                    if let image = phase.image {
                                                        image
                                                            .resizable()
                                                            .scaledToFit()
                                                            .frame(height: 290)
                                                            .frame(maxWidth: .infinity)
                                                            .padding(.vertical, 20)
                                                    } else {
                                                        ShopSkeletonBlock(cornerRadius: 18, height: 290)
                                                            .frame(maxWidth: .infinity)
                                                    }
                                                }
                                                .tag(index)
                                            }
                                        }
                                    }
                                    .frame(height: 310)
                                    .tabViewStyle(.page(indexDisplayMode: .never))

                                    // Modern Capsule Indicators
                                    HStack(spacing: 5) {
                                        ForEach(0..<min(displayedImages.count, 7), id: \.self) { idx in
                                            Capsule()
                                                .fill(selectedImageIndex == idx ? Color.shopDark : Color.black.opacity(0.18))
                                                .frame(width: selectedImageIndex == idx ? 16 : 6, height: 6)
                                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedImageIndex)
                                        }
                                        if displayedImages.count > 7 {
                                            Text("+\(displayedImages.count - 7)")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.88))
                                    .clipShape(Capsule())
                                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 1)
                                    .padding(.bottom, 12)
                                } else if let firstImg = displayedImages.first ?? product.image_url, let url = URL(string: firstImg) {
                                    ShopCachedAsyncImage(url: url, maxPixelSize: 1200) { phase in
                                        if let image = phase.image {
                                            image
                                                .resizable()
                                                .scaledToFit()
                                                .frame(height: 290)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 20)
                                        } else {
                                            ShopSkeletonBlock(cornerRadius: 18, height: 290)
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                    .frame(height: 310)
                                } else {
                                    Rectangle()
                                        .fill(Color.shopSurface)
                                        .frame(height: 310)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .cornerRadius(22)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(Color.shopBorder, lineWidth: 1)
                            )

                            // Top Badges & Action Buttons
                            HStack(alignment: .top) {
                                Button(action: {
                                    dismiss()
                                }) {
                                    Circle()
                                        .fill(Color.white.opacity(0.95))
                                        .frame(width: 38, height: 38)
                                        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                                        .overlay(
                                            Image(systemName: "chevron.left")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundColor(.shopDark)
                                        )
                                }
                                .buttonStyle(.plain)

                                if displayedImages.count > 1 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "photo.stack")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("\(selectedImageIndex + 1)/\(displayedImages.count)")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .foregroundColor(.shopDark)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.9))
                                    .clipShape(Capsule())
                                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 1)
                                }

                                Spacer()

                                HStack(spacing: 10) {
                                    if let item = wishlistItem {
                                        Button(action: {
                                            showingMoveToCollection = true
                                        }) {
                                            Circle()
                                                .fill(Color.white)
                                                .frame(width: 38, height: 38)
                                                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                                                .overlay(
                                                    Image(systemName: item.collectionName != nil ? "folder.fill" : "folder.badge.plus")
                                                        .font(.system(size: 15, weight: .semibold))
                                                        .foregroundColor(item.collectionName != nil ? .shopPurple : .shopDark)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }

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
                            }
                            .padding(14)
                        }
                        .padding(.horizontal, 16)

                        // Thumbnails strip when multiple angles are available
                        if displayedImages.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(displayedImages.enumerated()), id: \.offset) { idx, imgUrl in
                                        if let u = URL(string: imgUrl) {
                                            Button(action: {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    selectedImageIndex = idx
                                                }
                                            }) {
                                                ShopCachedAsyncImage(url: u, maxPixelSize: 200) { phase in
                                                    if let img = phase.image {
                                                        img.resizable().scaledToFit()
                                                    } else {
                                                        ShopSkeletonBlock(cornerRadius: 8)
                                                    }
                                                }
                                                .frame(width: 54, height: 54)
                                                .padding(4)
                                                .background(Color.shopSurface)
                                                .cornerRadius(10)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .stroke(selectedImageIndex == idx ? Color.shopDark : Color.shopBorder, lineWidth: selectedImageIndex == idx ? 2 : 1)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    // 2. Canonical Product Title & Brand Header
                    VStack(alignment: .leading, spacing: 6) {
                        let brandLabel = product.effectiveBrand
                        if !brandLabel.isEmpty {
                            Text(brandLabel.uppercased())
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundColor(.shopPurple)
                                .tracking(1.2)
                        }

                        Text(product.cleanTitle)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                            .lineSpacing(2)

                        // Variant / Colorway subtitle if present
                        if let current = currentOffer, let variant = current.displayVariant {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.shopPurple)
                                    .frame(width: 5, height: 5)
                                Text(variant)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.shopTextMuted)
                            }
                            .padding(.top, -1)
                        }

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
                        .padding(.top, 2)

                        if let current = currentOffer {
                            HStack(spacing: 6) {
                                Image(systemName: current.isFreeShipping ? "checkmark.circle.fill" : "box.truck.fill")
                                    .font(.system(size: 12))
                                Text(current.isFreeShipping ? "Spedizione gratuita inclusa" : "\(current.formattedShipping) (Totale \(current.formattedTotalPrice))")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundColor(current.isFreeShipping ? .shopGreen : .shopTextMuted)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 16)

                    // 3. Size Filter Chips (Only shown when product actually has available sizes)
                    if !allSizes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("TAGLIA DISPONIBILE")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundColor(.shopTextMuted)
                                    .tracking(0.8)

                                Spacer()

                                if let sz = selectedSize {
                                    Button(action: {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                                            selectedSize = nil
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Text("Filtro: \(sz)")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.shopPurple)
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(.shopPurple)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Text("Tocca per filtrare")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.shopTextMuted)
                                }
                            }
                            .padding(.horizontal, 16)

                            // Preferred size hint or auto-selected badge
                            if let pref = userPreferredSize {
                                if selectedSize == pref {
                                    HStack(spacing: 5) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.shopPurple)
                                        Text("Selezionata in automatico la tua taglia (\(pref))")
                                            .font(.system(size: 11.5, weight: .bold))
                                            .foregroundColor(.shopPurple)
                                    }
                                    .padding(.horizontal, 16)
                                } else if !allSizes.isEmpty && !allSizes.contains(where: { $0.replacingOccurrences(of: ",", with: ".") == pref }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.orange)
                                        Text("La tua taglia (\(pref)) non risulta a stock nei 14 negozi partner")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.shopTextMuted)
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(allSizes, id: \.self) { sz in
                                        let isSel = (selectedSize == sz)
                                        let isUserPref = (userPreferredSize == sz)
                                        Button(action: {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                                                selectedSize = (selectedSize == sz) ? nil : sz
                                            }
                                        }) {
                                            HStack(spacing: 3) {
                                                if isUserPref && !isSel {
                                                    Circle()
                                                        .fill(Color.shopPurple)
                                                        .frame(width: 5, height: 5)
                                                }
                                                Text(sz)
                                                    .font(.system(size: 13, weight: isSel ? .bold : .semibold, design: .rounded))
                                                    .foregroundColor(isSel ? .white : .shopDark)
                                            }
                                            .frame(minWidth: 44)
                                            .frame(height: 38)
                                            .padding(.horizontal, 10)
                                            .background(isSel ? Color.shopDark : Color.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(isSel ? Color.shopDark : (isUserPref ? Color.shopPurple.opacity(0.6) : Color.shopBorder), lineWidth: isUserPref && !isSel ? 1.5 : 1)
                                            )
                                            .shadow(color: isSel ? Color.black.opacity(0.12) : Color.clear, radius: 4, x: 0, y: 2)
                                        }
                                        .buttonStyle(.plain)
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

                                Text("Risparmi fino a \(String(format: "€%.2f", savings)) scegliendo l'offerta migliore tra i 14 negozi partner.")
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

                    // 5. Versus Mode AI Comparison (Only for footwear & GPS watches, hidden on accessories)
                    if product.isComparable {
                        NavigationLink(destination: ModelCompareView(initialModelA: product.cleanTitle)) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.shopPurpleLight)
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.shopPurple)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Confronta con modelli simili (IA)")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopDark)
                                    Text("Analisi tecnica su peso, drop e prestazioni")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.shopTextMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.shopPurple)
                            }
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.shopPurple.opacity(0.18), lineWidth: 1)
                            )
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    }

                    // 6. Price History & Market Intelligence Chart
                    if let history = priceHistory {
                        PriceHistorySectionView(history: history)
                    } else if isLoadingPriceHistory {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(.shopPurple)
                            Text("Caricamento storico prezzi...")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }

                    // 7. Comparison Cards: All Partner Store Offers
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("OFFERTE NEGOZI PARTNER (\(product.offers.count))")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.shopTextMuted)
                                .tracking(0.6)
                            Spacer()
                            if let sz = selectedSize {
                                Text("Filtrato tg. \(sz)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.shopPurple)
                            } else {
                                Text("Tocca per selezionare")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.shopPurple)
                            }
                        }
                        .padding(.horizontal, 16)

                        VStack(spacing: 10) {
                            ForEach(sortedOffers, id: \.offer.id) { item in
                                let index = item.index
                                let offer = item.offer
                                let hasSize = item.hasSize
                                let status = offer.sizeMatchStatus(selectedSize)
                                let isSelected = (index == selectedOfferIndex)
                                let isBest = (offer.price == (currentOffer?.price ?? product.best_price)) && (status != .unavailable)

                                Button(action: {
                                    selectedOfferIndex = index
                                }) {
                                    VStack(alignment: .leading, spacing: 9) {
                                        // Row 1: Store Logo + Full Store Name + Price + Radio Button
                                        HStack(alignment: .center, spacing: 10) {
                                            ShopStoreLogo(storeName: offer.store_name, showVerified: false, showLabel: false, size: 30)

                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 4) {
                                                    Text(offer.store_name)
                                                        .font(.system(size: 14.5, weight: .bold))
                                                        .foregroundColor(.shopDark)
                                                        .lineLimit(1)

                                                    Image(systemName: "checkmark.seal.fill")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.shopPurple)
                                                }

                                                if let variant = offer.displayVariant {
                                                    Text(variant)
                                                        .font(.system(size: 11, weight: .medium))
                                                        .foregroundColor(.shopTextMuted)
                                                        .lineLimit(1)
                                                }
                                            }

                                            Spacer()

                                            // Price
                                            Text(offer.formattedPrice)
                                                .font(.system(size: 17, weight: .black, design: .rounded))
                                                .foregroundColor(status != .unavailable ? .shopDark : .secondary)

                                            // Radio checkmark
                                            ZStack {
                                                Circle()
                                                    .fill(isSelected ? Color.shopPurple : Color.clear)
                                                    .frame(width: 20, height: 20)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1.5)
                                                    )

                                                if isSelected {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(.white)
                                                }
                                            }
                                        }

                                        // Row 2: Badges (Best Price) + Availability + Shipping Details
                                        HStack(spacing: 8) {
                                            if isBest {
                                                BestPriceBadge()
                                            }

                                            if let sz = selectedSize {
                                                switch status {
                                                case .available:
                                                    HStack(spacing: 3) {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .font(.system(size: 9))
                                                        Text("Disponibile tg. \(sz)")
                                                            .font(.system(size: 10.5, weight: .semibold))
                                                    }
                                                    .foregroundColor(.shopGreen)
                                                case .unknown:
                                                    HStack(spacing: 3) {
                                                        Image(systemName: "questionmark.circle")
                                                            .font(.system(size: 9))
                                                        Text("Verifica tg. \(sz) su store")
                                                            .font(.system(size: 10, weight: .medium))
                                                    }
                                                    .foregroundColor(.shopTextMuted)
                                                case .unavailable:
                                                    Text("Non disp. in tg. \(sz)")
                                                        .font(.system(size: 10, weight: .medium))
                                                        .foregroundColor(Color.secondary.opacity(0.8))
                                                }
                                            } else if let sizes = offer.available_sizes, !sizes.isEmpty {
                                                Text("Taglie: " + sizes.prefix(5).joined(separator: ", ") + (sizes.count > 5 ? "..." : ""))
                                                    .font(.system(size: 10.5))
                                                    .foregroundColor(.shopTextMuted)
                                            } else {
                                                Text("Vedi taglie su store")
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(.shopTextMuted)
                                            }

                                            Spacer()

                                            HStack(spacing: 4) {
                                                if offer.isFreeShipping {
                                                    Text("Sped. Gratis")
                                                        .font(.system(size: 9.5, weight: .heavy))
                                                        .foregroundColor(.shopGreen)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 2)
                                                        .background(Color.shopGreenLight)
                                                        .cornerRadius(4)
                                                } else {
                                                    Text(offer.formattedShipping)
                                                        .font(.system(size: 10, weight: .medium))
                                                        .foregroundColor(.shopTextMuted)
                                                }

                                                Text("• Tot. \(offer.formattedTotalPrice)")
                                                    .font(.system(size: 10.5, weight: .bold))
                                                    .foregroundColor(status != .unavailable ? .shopDark : .secondary)
                                            }
                                        }
                                    }
                                    .padding(14)
                                    .background(isSelected ? Color.shopPurpleLight.opacity(0.35) : Color.white)
                                    .opacity(hasSize ? 1.0 : 0.6)
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
                    .id("offers_section")

                    // 7. Shop Guarantees
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
                                    Text("14 Store Ufficiali")
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

                    Spacer(minLength: 120)
                }
                .padding(.top, 10)
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-testScrollOffers") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("offers_section", anchor: .top)
                        }
                    }
                }
            }
        }

            // 8. Sticky Floating Bottom Bar: Direct Link to Retailer Offer (No dock overlap!)
            if let offer = currentOffer, let url = URL(string: offer.url) {
                VStack(spacing: 8) {
                    Divider()
                        .background(Color.shopBorder.opacity(0.8))

                    HStack(spacing: 12) {
                        // Price Alert Bell Button
                        Button(action: {
                            showingAlertSheet = true
                        }) {
                            Circle()
                                .fill(Color(red: 246/255, green: 247/255, blue: 249/255))
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Image(systemName: wishlistItem?.isAlertEnabled == true ? "bell.badge.fill" : "bell")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(wishlistItem?.isAlertEnabled == true ? .shopPurple : .shopDark)
                                )
                        }
                        .buttonStyle(.plain)

                        // Primary Action Button (Opens Store's Real Product Page via Monetized Gateway)
                        let outboundUrl = APIService.shared.outboundRedirectURL(
                            targetUrl: offer.url,
                            storeId: offer.store_id,
                            offerId: offer.id,
                            source: "product_detail"
                        )
                        Link(destination: outboundUrl) {
                            HStack(spacing: 8) {
                                Text("Acquista su \(offer.store_name) • \(offer.formattedPrice)")
                                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                    .lineLimit(1)

                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .heavy))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.shopPurple)
                            .clipShape(Capsule())
                            .shadow(color: Color.shopPurple.opacity(0.35), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "shield.checkmark.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.shopGreen)
                        Text(offer.isFreeShipping ? "Spedizione gratuita inclusa • Negozio partner ufficiale" : "Spedizione stimata: \(offer.formattedShipping) • Rivenditore verificato")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(
                    Color.white
                        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: -4)
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAlertSheet) {
            PriceAlertSheet(product: product)
        }
        .sheet(isPresented: $showingMoveToCollection) {
            if let item = wishlistItem {
                MoveToCollectionSheet(item: item)
            }
        }
        .onAppear {
            TabBarVisibilityManager.shared.hide()
            RecentActivityManager.shared.recordProductView(product)
        }
        .onDisappear {
            TabBarVisibilityManager.shared.show()
        }
        .task {
            await loadPriceHistory()
        }
    }

    private func loadPriceHistory() async {
        guard priceHistory == nil else { return }
        isLoadingPriceHistory = true
        do {
            let res = try await APIService.shared.fetchPriceHistory(
                canonicalName: product.canonical_name,
                productId: product.id_val
            )
            await MainActor.run {
                self.priceHistory = res
                self.isLoadingPriceHistory = false
            }
        } catch {
            await MainActor.run {
                self.isLoadingPriceHistory = false
            }
        }
    }
}

// MARK: - Price History & Market Intelligence Chart

struct PriceHistorySectionView: View {
    let history: PriceHistoryResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("STORICO PREZZI & MERCATO")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.shopTextMuted)
                            .tracking(0.8)

                        if history.is_all_time_low {
                            HStack(spacing: 3) {
                                Text("🔥 MINIMO STORICO")
                                    .font(.system(size: 9.5, weight: .heavy))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.shopPurple)
                            .clipShape(Capsule())
                        }
                    }

                    Text("Rilevamento cross-store tra i 14 partner")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.shopTextMuted)
                }

                Spacer()

                if let dropPct = history.price_drop_percentage, dropPct > 3 {
                    Text("-\(String(format: "%.0f", dropPct))% vs media")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.shopGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.shopGreenLight)
                        .clipShape(Capsule())
                }
            }

            // Stat capsules: Minimo, Media, Massimo
            HStack(spacing: 8) {
                PriceStatPill(
                    title: "Minimo",
                    value: history.formattedLowestPrice,
                    accent: .shopGreen,
                    icon: "arrow.down.right"
                )
                PriceStatPill(
                    title: "Media",
                    value: history.formattedAveragePrice,
                    accent: .shopDark,
                    icon: "chart.bar.fill"
                )
                PriceStatPill(
                    title: "Massimo",
                    value: history.formattedHighestPrice,
                    accent: .secondary,
                    icon: "arrow.up.right"
                )
            }

            // Interactive Swift Chart
            if history.history_points.count >= 2 {
                VStack(alignment: .leading, spacing: 6) {
                    Chart {
                        ForEach(history.history_points) { point in
                            AreaMark(
                                x: .value("Data", point.parsedDate),
                                y: .value("Prezzo", point.price)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color.shopPurple.opacity(0.20),
                                        Color.shopPurple.opacity(0.01)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Data", point.parsedDate),
                                y: .value("Prezzo", point.price)
                            )
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.2))
                            .foregroundStyle(Color.shopPurple)

                            PointMark(
                                x: .value("Data", point.parsedDate),
                                y: .value("Prezzo", point.price)
                            )
                            .foregroundStyle(Color.shopPurple)
                            .symbolSize(CGSize(width: 4.5, height: 4.5))
                        }

                        // Rule mark for Average Price
                        RuleMark(y: .value("Media", history.average_price))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.40))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("Media \(history.formattedAveragePrice)")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 4)
                            }
                    }
                    .chartYScale(domain: (max(0, history.lowest_price * 0.85))...(history.highest_price * 1.08))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(Color.black.opacity(0.05))
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                .font(.system(size: 9))
                                .foregroundStyle(Color.shopTextMuted)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.black.opacity(0.04))
                            AxisValueLabel {
                                if let dbl = value.as(Double.self) {
                                    Text("€\(Int(dbl))")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(Color.shopTextMuted)
                                }
                            }
                        }
                    }
                    .frame(height: 150)
                    .padding(.top, 4)
                }
            }

            // Summary advice
            HStack(spacing: 6) {
                Image(systemName: history.is_all_time_low ? "sparkles" : "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(history.is_all_time_low ? .shopPurple : .shopTextMuted)
                Text(history.is_all_time_low ?
                     "Questo prodotto è attualmente al minimo storico mai registrato su FitMatch." :
                     (history.formattedSavingsVsAverage != nil ? "Prezzo attuale \(history.formattedSavingsVsAverage!)." : "Prezzo monitorato e verificato.")
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.shopTextMuted)
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.shopBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}

struct PriceStatPill: View {
    let title: String
    let value: String
    let accent: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundColor(.shopTextMuted)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(accent)
            }
            Text(value)
                .font(.system(size: 13.5, weight: .black, design: .rounded))
                .foregroundColor(accent == .shopGreen ? .shopGreen : .shopDark)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.shopSurface)
        .cornerRadius(10)
    }
}
