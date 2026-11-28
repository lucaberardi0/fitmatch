import SwiftUI

struct AccountPartnerStore: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let logoURL: String?
}

// MARK: - Quick Action Destination: Salvati

struct AccountSavedProductsDestinationView: View {
    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Salvati")
            WishlistView(embedded: true)
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Quick Action Destination: Segui già

struct AccountFollowedStoresDestinationView: View {
    let partnerStores: [AccountPartnerStore]
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @State private var searchQuery: String = ""

    private var filteredPartnerStores: [AccountPartnerStore] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return partnerStores }
        return partnerStores.filter {
            $0.name.lowercased().contains(q) || $0.subtitle.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Segui già")

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if followedManager.followedStores.isEmpty {
                        FitMatchEmptyStateView(
                            icon: "storefront",
                            title: "Nessun negozio seguito",
                            subtitle: "Segui i tuoi store preferiti per vedere qui arrivi e ribassi."
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Negozi che segui (\(followedManager.followedStores.count))")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)

                            VStack(spacing: 0) {
                                ForEach(followedManager.followedStores) { store in
                                    let resolvedLogo = store.store_logo ?? partnerStores.first(where: { $0.id.lowercased() == store.store_id.lowercased() })?.logoURL
                                    HStack(spacing: 12) {
                                        NavigationLink(destination: StoreDetailView(storeId: store.store_id, initialStoreName: store.store_name)) {
                                            HStack(spacing: 12) {
                                                ShopStoreLogo(storeName: store.store_name, showVerified: false, showLabel: false, size: 36, logoURL: resolvedLogo)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(store.store_name)
                                                        .font(.system(size: 15, weight: .bold))
                                                        .foregroundColor(.shopDark)
                                                    Text("Apri catalogo negozio")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.shopTextMuted)
                                                }
                                                Spacer()
                                            }
                                        }
                                        .buttonStyle(.plain)

                                        Button(action: {
                                            followedManager.unfollowStore(storeId: store.store_id)
                                        }) {
                                            Text("Segui già")
                                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                                .foregroundColor(.shopDark)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.shopSurfaceElevated)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(14)

                                    if store.id != followedManager.followedStores.last?.id {
                                        Divider().padding(.leading, 62)
                                    }
                                }
                            }
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.shopBorder.opacity(0.65), lineWidth: 1)
                            )
                        }
                    }

                    if !followedManager.hiddenStoreIds.isEmpty {
                        NavigationLink(destination: AccountHiddenStoresView(partnerStores: partnerStores)) {
                            HStack(spacing: 12) {
                                Image(systemName: "eye.slash.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.shopTextMuted)
                                Text("Negozi nascosti (\(followedManager.hiddenStoreIds.count))")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.shopDark)
                                Spacer()
                                Text("Gestisci")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(.shopPurple)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.shopTextMuted)
                            }
                            .shopCard(padding: 14)
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.99))
                    }

                    // Partner stores discovery with search
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Tutti i negozi partner (\(partnerStores.count))")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                            Spacer()
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                            TextField("Cerca un negozio partner...", text: $searchQuery)
                                .font(.system(size: 13.5))
                                .foregroundColor(.shopDark)
                                .autocorrectionDisabled()
                            if !searchQuery.isEmpty {
                                Button(action: { searchQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundColor(.shopTextMuted.opacity(0.75))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 40)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.shopBorder.opacity(0.8), lineWidth: 1))

                        if filteredPartnerStores.isEmpty {
                            Text("Nessun negozio trovato per \"\(searchQuery)\".")
                                .font(.system(size: 13))
                                .foregroundColor(.shopTextMuted)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(filteredPartnerStores) { store in
                                    let isFollowed = followedManager.isFollowing(storeId: store.id)
                                    HStack(spacing: 12) {
                                        NavigationLink(destination: StoreDetailView(storeId: store.id, initialStoreName: store.name)) {
                                            HStack(spacing: 12) {
                                                ShopStoreLogo(storeName: store.name, showVerified: false, showLabel: false, size: 34, logoURL: store.logoURL)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(store.name)
                                                        .font(.system(size: 14.5, weight: .bold))
                                                        .foregroundColor(.shopDark)
                                                    Text(store.subtitle)
                                                        .font(.system(size: 11.5))
                                                        .foregroundColor(.shopTextMuted)
                                                        .lineLimit(1)
                                                }
                                                Spacer()
                                            }
                                        }
                                        .buttonStyle(.plain)

                                        Button(action: {
                                            followedManager.toggleFollow(storeId: store.id, storeName: store.name, storeLogo: store.logoURL)
                                        }) {
                                            Text(isFollowed ? "Segui già" : "Segui")
                                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                                .foregroundColor(isFollowed ? .shopDark : .white)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 6)
                                                .background(isFollowed ? Color.shopSurfaceElevated : Color.shopDark)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(14)

                                    if store.id != filteredPartnerStores.last?.id {
                                        Divider().padding(.leading, 60)
                                    }
                                }
                            }
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.shopBorder.opacity(0.65), lineWidth: 1)
                            )
                        }
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 6)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await followedManager.fetchFollowedStores()
                await followedManager.fetchHiddenStores()
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Sub-Page: Negozi Nascosti

struct AccountHiddenStoresView: View {
    let partnerStores: [AccountPartnerStore]
    @ObservedObject private var followedManager = FollowedStoresManager.shared

    private var sortedHiddenIds: [String] {
        followedManager.hiddenStoreIds.sorted()
    }

    private func resolveStoreMeta(for storeId: String) -> (name: String, logoURL: String?) {
        let low = storeId.lowercased()
        if let partner = partnerStores.first(where: { $0.id.lowercased() == low }) {
            return (partner.name, partner.logoURL)
        }
        if let dynamic = DynamicCatalogRegistry.shared.storeItem(for: low) {
            return (dynamic.name, dynamic.logo_url)
        }
        return (storeId.replacingOccurrences(of: "_", with: " ").capitalized, nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Negozi nascosti")

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if sortedHiddenIds.isEmpty {
                        FitMatchEmptyStateView(
                            icon: "eye.fill",
                            title: "Nessun negozio nascosto",
                            subtitle: "Tutti i negozi partner sono visibili nella tua Home Per te."
                        )
                        .padding(.top, 18)
                    } else {
                        Text("I negozi nascosti non appaiono nel feed Home. Puoi ripristinarli in qualsiasi momento.")
                            .font(.system(size: 13))
                            .foregroundColor(.shopTextMuted)
                            .lineSpacing(2)

                        VStack(spacing: 0) {
                            ForEach(sortedHiddenIds, id: \.self) { storeId in
                                let meta = resolveStoreMeta(for: storeId)
                                HStack(spacing: 12) {
                                    ShopStoreLogo(storeName: meta.name, showVerified: false, showLabel: false, size: 36, logoURL: meta.logoURL)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(meta.name)
                                            .font(.system(size: 14.5, weight: .bold))
                                            .foregroundColor(.shopDark)
                                        Text("Nascosto dalla Home")
                                            .font(.system(size: 11.5))
                                            .foregroundColor(.shopTextMuted)
                                    }

                                    Spacer()

                                    Button(action: {
                                        followedManager.unhideStore(storeId: storeId)
                                    }) {
                                        Text("Ripristina")
                                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                            .foregroundColor(.shopPurple)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.shopPurpleLight)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(14)

                                if storeId != sortedHiddenIds.last {
                                    Divider().padding(.leading, 62)
                                }
                            }
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.shopBorder.opacity(0.65), lineWidth: 1)
                        )

                        if sortedHiddenIds.count > 1 {
                            Button(action: {
                                for id in sortedHiddenIds {
                                    followedManager.unhideStore(storeId: id)
                                }
                            }) {
                                Text("Ripristina tutti i negozi")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.shopPurple)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 46)
                                    .background(Color.shopPurpleLight)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(ShopCardPressStyle(scale: 0.98))
                        }
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 6)
            }
            .refreshable {
                await followedManager.fetchHiddenStores()
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Sub-Page: Monitoraggio Prezzi & Statistiche (Live & Interactive)

struct AccountPriceMonitorView: View {
    let partnerStores: [AccountPartnerStore]
    @ObservedObject private var prefs = UserPreferencesManager.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var notifManager = NotificationManager.shared

    @State private var selectedItemForAlert: WishlistItem? = nil

    private var monitoredItems: [WishlistItem] {
        wishlist.items
            .filter { $0.isAlertEnabled }
            .sorted { lhs, rhs in
                if lhs.isTargetReachedEffective != rhs.isTargetReachedEffective {
                    return lhs.isTargetReachedEffective
                }
                if abs(lhs.droppedAmountSinceSaved - rhs.droppedAmountSinceSaved) > 0.01 {
                    return lhs.droppedAmountSinceSaved > rhs.droppedAmountSinceSaved
                }
                if (lhs.targetAlertPrice != nil) != (rhs.targetAlertPrice != nil) {
                    return lhs.targetAlertPrice != nil
                }
                return lhs.dateAdded > rhs.dateAdded
            }
    }

    private var targetAlertsCount: Int {
        wishlist.items.filter { $0.isAlertEnabled && $0.targetAlertPrice != nil }.count
    }

    var body: some View {
        let totalSavings = wishlist.totalDroppedSavingsEur
        let dropsCount = wishlist.priceDropsCount

        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Monitoraggio prezzi")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 1. Unified Live KPI Row (aligned with WishlistManager)
                    HStack(spacing: 10) {
                        statCard(
                            icon: "arrow.down.right.circle.fill",
                            color: .shopGreen,
                            label: "Risparmio",
                            value: WishlistItem.formatEuro(totalSavings)
                        )
                        statCard(
                            icon: "flame.fill",
                            color: dropsCount > 0 ? .shopOrange : .shopTextMuted,
                            label: "In calo",
                            value: "\(dropsCount)"
                        )
                        statCard(
                            icon: "bell.badge.fill",
                            color: .shopPurple,
                            label: "Soglie",
                            value: targetAlertsCount > 0 ? "\(targetAlertsCount)" : "\(monitoredItems.count)"
                        )
                    }

                    // Push warning banner if notifications are off
                    if !notifManager.isAuthorized || !prefs.preferences.isPushNotificationEnabled {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.shopOrange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(!notifManager.isAuthorized ? "Notifiche iOS disattivate" : "Avvisi push in pausa")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.shopDark)
                                Text("Attivale per ricevere avvisi istantanei sui cali di prezzo.")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.shopTextMuted)
                            }

                            Spacer()

                            if !notifManager.isAuthorized && notifManager.authorizationStatus == .denied {
                                Button("Impostazioni") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Color.shopPurple)
                                .clipShape(Capsule())
                            } else {
                                Button("Attiva") {
                                    ShopHaptics.impact(.light)
                                    prefs.preferences.isPushNotificationEnabled = true
                                    if !notifManager.isAuthorized {
                                        notifManager.requestAuthorization()
                                    }
                                }
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Color.shopPurple)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(14)
                        .background(Color.shopOrange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    // 2. Live Automatic Monitoring Status Card (powered by Supabase `get_account_monitor_stats_v1`)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "bell.and.waves.left.and.right.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.shopPurple)
                            Text("Monitoraggio Automatico")
                                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                            Spacer()

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.shopGreen)
                                    .frame(width: 7, height: 7)
                                Text("Attivo")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundColor(.shopGreen)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.shopGreenLight)
                            .clipShape(Capsule())
                        }

                        let sizeDetail = prefs.preferences.hasAnySize ? " nelle tue taglie (\(prefs.preferences.formattedSizeSummary))" : ""
                        let activeStoreCount = max(prefs.accountMonitorStats?.active_store_count ?? 0, partnerStores.count)
                        Text("FitMatch controlla automaticamente i prezzi dei tuoi prodotti salvati sui \(activeStoreCount) negozi partner\(sizeDetail) e ti avvisa quando scendono.")
                            .font(.system(size: 12.5))
                            .foregroundColor(.shopTextMuted)
                            .lineSpacing(2)

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Ultimo controllo catalogo")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(.shopTextMuted)
                                Text(prefs.accountMonitorStats?.formattedLastCheckRelative ?? "Controllo automatico attivo")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.shopDark)
                            }
                            Spacer()

                            if let recentDrops = prefs.accountMonitorStats?.recent_drops_7d, recentDrops > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.shopOrange)
                                    Text(recentDrops == 1 ? "1 calo (7g)" : "\(recentDrops) cali (7g)")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(.shopOrange)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.shopOrange.opacity(0.12))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(12)
                        .background(Color.shopSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .shopCard()

                    // 3. Interactive Monitored Items List
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Prodotti monitorati (\(monitoredItems.count))")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                            Spacer()
                            if !monitoredItems.isEmpty {
                                Text("Tocca campanella per soglia")
                                    .font(.system(size: 11))
                                    .foregroundColor(.shopTextMuted)
                            }
                        }

                        if monitoredItems.isEmpty {
                            FitMatchInlineEmptyRow(
                                icon: "bell",
                                title: "Nessun avviso attivo",
                                subtitle: "Salva un prodotto e imposta una soglia prezzo per monitorarlo qui."
                            )
                        } else {
                            ForEach(monitoredItems) { item in
                                monitoredItemRow(item: item)

                                if item.id != monitoredItems.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .shopCard()

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 6)
            }
            .refreshable {
                await prefs.fetchAccountMonitorStats()
                await wishlist.syncWithDatabase(force: true)
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .task {
            notifManager.checkAuthorization()
            async let statsTask: Void = prefs.fetchAccountMonitorStats()
            async let wishTask: Void = wishlist.syncWithDatabase()
            _ = await (statsTask, wishTask)
        }
        .sheet(item: $selectedItemForAlert) { item in
            PriceAlertSheet(product: item.toMatchedProduct(), existingWishlistItem: item)
        }
    }

    private func monitoredItemRow(item: WishlistItem) -> some View {
        HStack(spacing: 12) {
            NavigationLink(destination: ProductDetailView(product: item.toMatchedProduct())) {
                HStack(spacing: 12) {
                    if let img = item.image_url, let url = URL(string: img) {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 160) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit().padding(4)
                            } else {
                                Color.shopSurface
                            }
                        }
                        .frame(width: 52, height: 52)
                        .background(Color.shopSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.canonical_name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(.shopDark)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            Text(item.formattedCurrentPrice)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                            Text("· \(item.bestStore ?? "Store partner")")
                                .font(.system(size: 11.5))
                                .foregroundColor(.shopTextMuted)
                                .lineLimit(1)
                        }

                        // Live metadata chips (Target reached / Price drop / Target / Monitored size)
                        HStack(spacing: 6) {
                            if item.isTargetReachedEffective {
                                miniBadge(text: "Soglia raggiunta", fg: .shopGreen, bg: .shopGreenLight)
                            } else if let dropText = item.formattedPriceDropSinceSaved {
                                miniBadge(text: dropText, fg: .shopGreen, bg: .shopGreenLight)
                            } else if let target = item.targetAlertPrice {
                                miniBadge(text: "Soglia ≤ \(WishlistItem.formatEuro(target))", fg: .shopPurple, bg: .shopPurpleLight)
                            }

                            if let sz = item.monitoredSize ?? item.selectedSize, !sz.isEmpty {
                                let sizePrefix = item.isFootwearCategory ? "EU \(sz)" : "Tg. \(sz)"
                                miniBadge(text: sizePrefix, fg: .shopDark, bg: .shopSurfaceElevated)
                            }
                        }
                    }

                    Spacer(minLength: 4)
                }
            }
            .buttonStyle(.plain)

            Button(action: {
                ShopHaptics.impact(.light)
                selectedItemForAlert = item
            }) {
                ZStack {
                    Circle()
                        .fill(item.targetAlertPrice != nil ? Color.shopPurpleLight : Color.shopSurfaceElevated)
                        .frame(width: 36, height: 36)
                    Image(systemName: item.targetAlertPrice != nil ? "bell.badge.fill" : "bell.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.shopPurple)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Modifica alert prezzo per \(item.canonical_name)")
        }
        .padding(.vertical, 4)
    }

    private func miniBadge(text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundColor(fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(bg)
            .clipShape(Capsule())
    }

    private func statCard(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12.5))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.shopTextMuted)
            }
            Text(value)
                .font(.system(size: 16.5, weight: .black, design: .rounded))
                .foregroundColor(.shopDark)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.shopBorder.opacity(0.65), lineWidth: 1)
        )
    }
}
