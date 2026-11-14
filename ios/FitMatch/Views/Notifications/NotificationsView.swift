import SwiftUI

enum NotificationFilter: String, CaseIterable, Identifiable {
    case all = "Tutte"
    case priceDrop = "Cali prezzo"
    case promo = "Promozioni"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "bell.fill"
        case .priceDrop: return "flame.fill"
        case .promo: return "tag.fill"
        }
    }
}

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notifManager = NotificationManager.shared

    @State private var selectedFilter: NotificationFilter = .all
    @State private var isRefreshing: Bool = false
    @State private var selectedProduct: MatchedProduct? = nil
    @State private var navigatingStoreId: String? = nil
    @State private var navigatingStoreName: String? = nil

    private var filteredNotifications: [AppNotification] {
        switch selectedFilter {
        case .all:
            return notifManager.notifications
        case .priceDrop:
            return notifManager.notifications.filter { $0.type == .priceDrop }
        case .promo:
            return notifManager.notifications.filter { $0.type == .promo }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - 1. Pinned Top Header Bar
                headerBar
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                // MARK: - 2. Filter Pills Bar (Tutte | Cali prezzo | Nuovi drop | Promozioni)
                filterPillsBar
                    .padding(.bottom, 10)

                // MARK: - 3. Content Area
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Push Authorization Banner if disabled
                        if !notifManager.isAuthorized {
                            pushPermissionCard
                                .padding(.horizontal, 16)
                        }

                        // Intelligent System Status & Live Actions Card
                        intelligentSystemCard
                            .padding(.horizontal, 16)

                        // Notification Cards Feed
                        if filteredNotifications.isEmpty {
                            emptyStateView
                                .padding(.top, 30)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredNotifications) { notif in
                                    NotificationCard(
                                        notification: notif,
                                        onTap: {
                                            let gen = UIImpactFeedbackGenerator(style: .light)
                                            gen.impactOccurred()
                                            notifManager.markAsRead(id: notif.id)
                                            handleNotificationAction(notif)
                                        },
                                        onDelete: {
                                            notifManager.deleteNotification(id: notif.id)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        Spacer(minLength: 80)
                    }
                    .padding(.top, 4)
                }
                .refreshable {
                    await notifManager.checkIntelligentNotifications(force: true)
                }
            }
            .background(Color(red: 245/255, green: 246/255, blue: 248/255).ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(item: $selectedProduct) { prod in
                ProductDetailView(product: prod)
            }
            .navigationDestination(isPresented: Binding(
                get: { navigatingStoreId != nil },
                set: { if !$0 { navigatingStoreId = nil } }
            )) {
                if let sId = navigatingStoreId {
                    StoreDetailView(storeId: sId, initialStoreName: navigatingStoreName ?? "Negozio Partner")
                }
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Dismiss Button ("✕")
            Button(action: { dismiss() }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 38, height: 38)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)

                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.shopDark)
                }
            }
            .buttonStyle(.plain)

            // Title & Unread Count Pill
            HStack(spacing: 8) {
                Text("Notifiche")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(Color.shopDark)

                if notifManager.unreadCount > 0 {
                    Text("\(notifManager.unreadCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(red: 99/255, green: 59/255, blue: 238/255))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            // Mark All As Read
            if notifManager.unreadCount > 0 {
                Button(action: {
                    let gen = UIImpactFeedbackGenerator(style: .light)
                    gen.impactOccurred()
                    notifManager.markAllAsRead()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text("Lette tutte")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color(red: 99/255, green: 59/255, blue: 238/255))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 99/255, green: 59/255, blue: 238/255).opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Filter Pills Bar

    private var filterPillsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotificationFilter.allCases) { filter in
                    let isSelected = selectedFilter == filter
                    let count: Int = {
                        switch filter {
                        case .all: return notifManager.notifications.count
                        case .priceDrop: return notifManager.notifications.filter { $0.type == .priceDrop }.count
                        case .promo: return notifManager.notifications.filter { $0.type == .promo }.count
                        }
                    }()

                    Button(action: {
                        let gen = UIImpactFeedbackGenerator(style: .light)
                        gen.impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            selectedFilter = filter
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: filter.icon)
                                .font(.system(size: 11, weight: .semibold))

                            Text(filter.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))

                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(isSelected ? Color.white.opacity(0.9) : Color.shopTextMuted)
                            }
                        }
                        .foregroundColor(isSelected ? .white : Color(red: 60/255, green: 60/255, blue: 70/255))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color(red: 25/255, green: 25/255, blue: 30/255) : Color.white)
                                .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.03), radius: 4, x: 0, y: 1)
                        )
                        .overlay(
                            isSelected ? nil : Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Push Permission Alert Card

    private var pushPermissionCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 254/255, green: 243/255, blue: 199/255))
                    .frame(width: 44, height: 44)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 19))
                    .foregroundColor(Color(red: 217/255, green: 119/255, blue: 6/255))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Attiva le notifiche push")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color.shopDark)

                Text("Ricevi notifiche istantanee in tempo reale sui cali di prezzo dei tuoi articoli salvati.")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(.shopTextMuted)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: {
                notifManager.requestAuthorization { _ in }
            }) {
                Text("Attiva")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 217/255, green: 119/255, blue: 6/255))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 251/255, green: 191/255, blue: 36/255).opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
    }

    // MARK: - Intelligent Monitoring System Card

    private var intelligentSystemCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // Pulsing Green Indicator
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.green.opacity(0.6), radius: 3)

                Text("Sistema Intelligente Attivo")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color.shopDark)

                Spacer()

                if notifManager.isChecking {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Verifica in corso...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.shopTextMuted)
                    }
                } else if let last = notifManager.lastCheckDate {
                    let formatter = RelativeDateTimeFormatter()
                    Text("Aggiornato " + formatter.localizedString(for: last, relativeTo: Date()))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.shopTextMuted)
                }
            }

            Text("FitMatch scansiona costantemente i 10 negozi partner ufficiali. Il watcher cloud sul server ti invia notifiche push APNs in tempo reale a schermo bloccato quando il prezzo di un articolo salvato cala o c'è un'offerta speciale.")
                .font(.system(size: 11.5, weight: .regular))
                .foregroundColor(Color(red: 100/255, green: 100/255, blue: 110/255))
                .lineSpacing(1.5)

            Divider()
                .padding(.vertical, 2)

            // Interactive Action Buttons
            HStack(spacing: 10) {
                Button(action: {
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    Task {
                        await notifManager.checkIntelligentNotifications(force: true)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .bold))
                        Text(notifManager.isChecking ? "Controllo in corso..." : "Verifica prezzi adesso")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Color(red: 99/255, green: 59/255, blue: 238/255))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(red: 99/255, green: 59/255, blue: 238/255).opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(notifManager.isChecking)

                Spacer()
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        let titleText: String
        let subtitleText: String
        let iconColor: Color

        switch selectedFilter {
        case .all:
            titleText = "Nessun avviso al momento"
            subtitleText = "Quando un prodotto nei tuoi preferiti scende di prezzo o torna disponibile nella tua taglia su uno degli store partner, lo troverai subito qui."
            iconColor = .shopPurple
        case .priceDrop:
            titleText = "Nessun calo di prezzo rilevato"
            subtitleText = "Salva scarpe da running, smartwatch GPS o attrezzatura tra i preferiti: monitoriamo i listini di tutti i negozi per avvisarti al primo ribasso."
            iconColor = .shopRed
        case .promo:
            titleText = "Nessuna promo negozio attiva"
            subtitleText = "Segui i tuoi store sportivi preferiti per ricevere notifiche su codici sconto, saldi stagionali e nuovi arrivi."
            iconColor = .shopGreen
        }

        return FitMatchEmptyStateView(
            icon: selectedFilter.icon,
            accentColor: iconColor,
            badgeText: "AVVISI IN TEMPO REALE",
            title: titleText,
            subtitle: subtitleText,
            primaryTitle: "Esplora prodotti e offerte",
            primaryIcon: "flame.fill",
            primaryColor: .shopDark,
            onPrimaryTap: {
                dismiss()
            },
            secondaryTitle: "Invia avviso di prova",
            secondaryIcon: "bell.badge",
            onSecondaryTap: {
                notifManager.simulateTestNotification(type: .priceDrop)
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Action Handler

    private func handleNotificationAction(_ notif: AppNotification) {
        // Priority 1: If notification is about a specific product (Price Drop / Product alert), open Product Detail directly!
        if let directProduct = notif.toMatchedProduct() {
            selectedProduct = directProduct
            if let pTitle = notif.productCanonicalName {
                Task {
                    if let results = try? await APIService.shared.search(query: pTitle), let first = results.first {
                        selectedProduct = first
                    }
                }
            }
            return
        }

        // Priority 2: If notification is about a Store Drop (new arrivals in a store), open Store Detail
        if let sId = notif.storeId, !sId.isEmpty {
            navigatingStoreId = sId
            navigatingStoreName = notif.storeName ?? "Negozio Partner"
            return
        }

        // Priority 3: External promotional link
        if let urlStr = notif.actionUrl, let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Notification Card Component

struct NotificationCard: View {
    let notification: AppNotification
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Top Meta Row: Badge Pill + Time Ago + Unread Indicator
                HStack(alignment: .center) {
                    HStack(spacing: 5) {
                        Image(systemName: notification.type.iconName)
                            .font(.system(size: 9.5, weight: .bold))
                        Text(notification.type.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(notification.type.badgeColor)
                    .clipShape(Capsule())

                    if let store = notification.storeName {
                        Text("•  \(store)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.shopDark)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(notification.timeAgo)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.shopTextMuted)

                    if !notification.isRead {
                        Circle()
                            .fill(Color(red: 99/255, green: 59/255, blue: 238/255))
                            .frame(width: 8, height: 8)
                    }
                }

                // Middle Content Row
                HStack(alignment: .top, spacing: 12) {
                    // Optional Thumbnail Image
                    if let imgUrl = notification.imageUrl, let url = URL(string: imgUrl), !imgUrl.isEmpty {
                        ShopCachedAsyncImage(url: url, maxPixelSize: 150) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 52, height: 52)
                                    .background(Color(red: 246/255, green: 247/255, blue: 250/255))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            case .empty:
                                ShopSkeletonBlock(cornerRadius: 12, width: 52, height: 52)
                            default:
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 245/255, green: 245/255, blue: 248/255))
                                    .frame(width: 52, height: 52)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.system(size: 18))
                                            .foregroundColor(.shopTextMuted)
                                    )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(notification.title)
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundColor(Color.shopDark)
                            .lineLimit(2)

                        if let sub = notification.subtitle {
                            Text(sub)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(Color(red: 50/255, green: 50/255, blue: 60/255))
                                .lineLimit(1)
                        }

                        Text(notification.body)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color(red: 100/255, green: 100/255, blue: 110/255))
                            .lineLimit(3)
                            .lineSpacing(1.5)
                    }
                }

                // Bottom Price Difference Row (if Price Drop)
                if let curr = notification.newPrice {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Nuovo:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                            Text(String(format: "%.2f €", curr).replacingOccurrences(of: ".", with: ","))
                                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                .foregroundColor(Color.shopDark)
                        }

                        if let old = notification.oldPrice, old > curr {
                            HStack(spacing: 4) {
                                Text("Era:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.shopTextMuted)
                                Text(String(format: "%.2f €", old).replacingOccurrences(of: ".", with: ","))
                                    .font(.system(size: 11.5, weight: .regular))
                                    .foregroundColor(.shopTextMuted)
                                    .strikethrough()
                            }
                        }

                        if let savings = notification.savingsAmount {
                            Text("Risparmi €\(String(format: "%.0f", savings))")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 228/255, green: 42/255, blue: 38/255))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Color(red: 228/255, green: 42/255, blue: 38/255).opacity(0.1))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 170/255, green: 170/255, blue: 180/255))
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(notification.isRead ? Color.black.opacity(0.04) : Color(red: 99/255, green: 59/255, blue: 238/255).opacity(0.2), lineWidth: notification.isRead ? 1 : 1.5)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Elimina notifica", systemImage: "trash")
            }
        }
    }
}
