import SwiftUI

public struct AdminRootView: View {
    @StateObject private var net = AdminNetworkService.shared

    @State private var selectedTab: Int = 0
    @State private var sessions: [SyncSessionItem] = []
    @State private var storeHealth: [StoreHealthMetric] = []
    @State private var feedbacks: [SearchFeedbackItem] = []
    @State private var isLoading: Bool = true
    @State private var selectedSession: SyncSessionItem? = nil
    @State private var statusToast: String? = nil
    @State private var isRunningAction: Bool = false

    // Filters
    @State private var sessionFilter: String = "all"
    @State private var storeSearch: String = ""
    @State private var feedbackFilter: String = "all"
    @State private var feedbackSearch: String = ""
    @State private var feedbackToDelete: SearchFeedbackItem? = nil
    @State private var showDeleteAlert: Bool = false

    private var totalOffersCount: Int {
        storeHealth.reduce(0) { $0 + $1.totalOffers }
    }

    private var totalWithSizesCount: Int {
        storeHealth.reduce(0) { $0 + $1.withSizes }
    }

    private var overallSizeCoveragePct: Double {
        guard totalOffersCount > 0 else { return 0.0 }
        return Double(totalWithSizesCount) / Double(totalOffersCount) * 100.0
    }

    private var failedSessions: [SyncSessionItem] {
        sessions.filter { $0.isFailed }
    }

    private var totalFeedbacksCount: Int {
        feedbacks.count
    }

    private var positiveFeedbacksCount: Int {
        feedbacks.filter { $0.isPositive }.count
    }

    private var negativeFeedbacksCount: Int {
        feedbacks.filter { !$0.isPositive }.count
    }

    private var commentsFeedbacksCount: Int {
        feedbacks.filter { $0.hasComment }.count
    }

    private var positiveSatisfactionPct: Double {
        guard totalFeedbacksCount > 0 else { return 100.0 }
        return (Double(positiveFeedbacksCount) / Double(totalFeedbacksCount)) * 100.0
    }

    private var filteredFeedbacks: [SearchFeedbackItem] {
        var list = feedbacks
        switch feedbackFilter {
        case "positive":
            list = list.filter { $0.isPositive }
        case "negative":
            list = list.filter { !$0.isPositive }
        case "comments":
            list = list.filter { $0.hasComment }
        default:
            break
        }

        if !feedbackSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = feedbackSearch.lowercased()
            list = list.filter { fb in
                fb.query.lowercased().contains(q) ||
                (fb.comment?.lowercased().contains(q) ?? false) ||
                (fb.productEvaluations?.contains(where: { $0.productName?.lowercased().contains(q) ?? false }) ?? false)
            }
        }

        return list
    }

    private var filteredSessions: [SyncSessionItem] {
        switch sessionFilter {
        case "discovery":
            return sessions.filter { $0.sessionType.lowercased() == "discovery" }
        case "price_refresh":
            return sessions.filter { $0.sessionType.lowercased() == "price_refresh" }
        case "size_enrichment":
            return sessions.filter { $0.sessionType.lowercased() == "size_enrichment" }
        case "failed":
            return failedSessions
        default:
            return sessions
        }
    }

    private var filteredStores: [StoreHealthMetric] {
        if storeSearch.isEmpty { return storeHealth }
        return storeHealth.filter {
            $0.displayName.localizedCaseInsensitiveContains(storeSearch) ||
            $0.storeId.localizedCaseInsensitiveContains(storeSearch)
        }
    }

    public init() {
        if ProcessInfo.processInfo.arguments.contains("-testFeedbackTab") {
            _selectedTab = State(initialValue: 1)
        }
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Control Center
            NavigationStack {
                controlCenterTab
                    .navigationTitle("FitMatch Control")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            refreshButton
                        }
                    }
            }
            .tabItem {
                Label("Controllo", systemImage: "slider.horizontal.3")
            }
            .tag(0)

            // Tab 2: Feedback Ricerca
            NavigationStack {
                feedbackTab
                    .navigationTitle("Feedback Ricerca")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            refreshButton
                        }
                    }
            }
            .tabItem {
                Label("Feedback", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            }
            .badge(feedbacks.count > 0 ? feedbacks.count : 0)
            .tag(1)

            // Tab 3: Store Health
            NavigationStack {
                storesTab
                    .navigationTitle("Salute Store")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            refreshButton
                        }
                    }
            }
            .tabItem {
                Label("Negozi (14)", systemImage: "building.2.crop.circle")
            }
            .tag(2)

            // Tab 4: Sessions Audit
            NavigationStack {
                sessionsTab
                    .navigationTitle("Sessioni Sync")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            refreshButton
                        }
                    }
            }
            .tabItem {
                Label("Sessioni", systemImage: "list.clipboard")
            }
            .badge(failedSessions.count > 0 ? failedSessions.count : 0)
            .tag(3)

            // Tab 5: Settings / Server
            NavigationStack {
                serverSettingsTab
                    .navigationTitle("Server & Cloud")
            }
            .tabItem {
                Label("Server", systemImage: "server.rack")
            }
            .tag(4)
        }
        .tint(Color(red: 99/255, green: 102/255, blue: 241/255)) // Indigo accent
        .task {
            await loadData()
            _ = await net.checkBackendHealth()
        }
        .sheet(item: $selectedSession) { session in
            AdminSessionDetailSheet(session: session)
        }
    }

    private var refreshButton: some View {
        Button(action: {
            Task { await loadData() }
        }) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .bold))
        }
    }

    // MARK: - Tab 1: Control Center

    private var controlCenterTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                // Live status banner
                liveEngineStatusBanner

                // Quick actions
                quickActionsSection

                // Toast if present
                if let msg = statusToast {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.indigo)
                        Text(msg)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("✕") { withAnimation { statusToast = nil } }
                    }
                    .padding(12)
                    .background(Color.indigo.opacity(0.12))
                    .cornerRadius(12)
                }

                // Key metrics 2x2 grid
                metricsOverviewSection

                // Search feedback overview card (tappable to jump to Feedback tab)
                feedbackSummaryCardInControl

                // Schedule routines cards
                routinesSection

                // Top 3 recent sessions preview
                recentSessionsPreviewSection

                Spacer().frame(height: 30)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Color(red: 247/255, green: 248/255, blue: 250/255))
        .refreshable {
            await loadData()
        }
    }

    private var liveEngineStatusBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(Color.green)
                    .frame(width: 12, height: 12)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Motore FitMatch 24/7")
                        .font(.system(size: 14, weight: .bold))
                    Text("ONLINE")
                        .font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(6)
                }
                Text("Refresh ogni 2h • Discovery ogni 24h")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isRunningAction {
                ProgressView()
                    .tint(.indigo)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Azioni Rapide di Controllo")
                .font(.system(size: 13, weight: .bold))

            HStack(spacing: 10) {
                actionCard(
                    title: "Discovery",
                    subtitle: "200/store",
                    icon: "sparkles",
                    color: .indigo
                ) {
                    await executeAction("Avvio discovery catalogo...") {
                        try await net.triggerDiscovery(limitPerStore: 200)
                    }
                }

                actionCard(
                    title: "Verifica Prezzi",
                    subtitle: "50 offerte",
                    icon: "tag.fill",
                    color: .green
                ) {
                    await executeAction("Avvio verifica prezzi...") {
                        try await net.triggerPriceRefresh(limit: 50)
                    }
                }

                actionCard(
                    title: "Taglie",
                    subtitle: "Arricchimento",
                    icon: "ruler",
                    color: .orange
                ) {
                    await executeAction("Avvio arricchimento taglie...") {
                        try await net.triggerSizeEnrichment(limitPerStore: 50)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    private func actionCard(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred()
            Task { await action() }
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.08))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isRunningAction)
    }

    private var metricsOverviewSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                metricBox(
                    title: "Offerte Negozi",
                    value: totalOffersCount > 0 ? "\(totalOffersCount)" : "11.152",
                    caption: "14 partner censiti",
                    icon: "shippingbox.fill",
                    color: .indigo
                )

                metricBox(
                    title: "Copertura Taglie",
                    value: String(format: "%.1f%%", overallSizeCoveragePct),
                    caption: "\(totalWithSizesCount) con taglie",
                    icon: "ruler.fill",
                    color: overallSizeCoveragePct >= 50 ? .green : .orange
                )
            }

            HStack(spacing: 12) {
                metricBox(
                    title: "Sessioni Totali",
                    value: "\(sessions.count)",
                    caption: "Audit trail cloud",
                    icon: "list.clipboard.fill",
                    color: .blue
                )

                metricBox(
                    title: "Errori Registrati",
                    value: "\(failedSessions.count)",
                    caption: failedSessions.isEmpty ? "Nessuna anomalia" : "Tocca per vederli",
                    icon: failedSessions.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                    color: failedSessions.isEmpty ? .green : .red
                )
                .onTapGesture {
                    selectedTab = 3
                    sessionFilter = "failed"
                }
            }
        }
    }

    private func metricBox(title: String, value: String, caption: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(color)
            }

            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(.primary)

            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.03), radius: 5, y: 2)
    }

    private var routinesSection: some View {
        VStack(spacing: 12) {
            routineCard(
                title: "Scoperta Catalogo",
                interval: "Ogni 24h",
                desc: "Crawling massivo su tutti i 14 negozi partner con re-clustering e arricchimento taglie.",
                dotColor: .indigo
            )

            routineCard(
                title: "Monitor Prezzi & Notifiche",
                interval: "Ogni 2h",
                desc: "Verifica tempestiva offerte, storico prezzi e invio notifiche push su cali di prezzo.",
                dotColor: .green
            )
        }
    }

    private func routineCard(title: String, interval: String, desc: String, dotColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                Text(title).font(.system(size: 13, weight: .bold))
                Spacer()
                Text(interval)
                    .font(.system(size: 10.5, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(dotColor.opacity(0.12))
                    .foregroundColor(dotColor)
                    .cornerRadius(8)
            }

            Text(desc)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.02), radius: 4, y: 1)
    }

    private var recentSessionsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ultime Sessioni Sincronizzazione")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button("Vedi Tutte") {
                    selectedTab = 2
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.indigo)
            }

            VStack(spacing: 8) {
                ForEach(sessions.prefix(4)) { sess in
                    sessionRow(sess)
                        .onTapGesture {
                            selectedSession = sess
                        }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    // MARK: - Tab 2: Store Health

    private var storesTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Cerca negozio...", text: $storeSearch)
                        .font(.system(size: 14))
                }
                .padding(12)
                .background(Color.white)
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.02), radius: 4, y: 1)

                // Store list
                VStack(spacing: 12) {
                    ForEach(filteredStores) { store in
                        storeHealthCardView(store)
                    }
                }

                Spacer().frame(height: 30)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Color(red: 247/255, green: 248/255, blue: 250/255))
        .refreshable {
            await loadData()
        }
    }

    private func storeHealthCardView(_ store: StoreHealthMetric) -> some View {
        let pct = store.coveragePercentage
        let pctColor: Color = pct >= 70 ? .green : (pct >= 20 ? .orange : .red)

        return VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.displayName)
                        .font(.system(size: 14, weight: .bold))
                    Text("\(store.withSizes) con taglie su \(store.totalOffers) offerte")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f%%", pct))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(pctColor)
                    Text("copertura")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(red: 240/255, green: 242/255, blue: 245/255))
                        .frame(height: 6)

                    Capsule()
                        .fill(pctColor)
                        .frame(width: max(0, min(geo.size.width * CGFloat(pct / 100.0), geo.size.width)), height: 6)
                }
            }
            .frame(height: 6)

            // Metrics row + crawl button
            HStack {
                if let price = store.avgPrice {
                    Text(String(format: "Prezzo medio: €%.2f", price))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    Task {
                        await executeAction("Scansione \(store.displayName)...") {
                            try await net.crawlStore(storeId: store.storeId, limit: 100)
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                        Text("Scansiona")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.indigo.opacity(0.1))
                    .foregroundColor(.indigo)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.02), radius: 4, y: 1)
    }

    // MARK: - Tab 3: Sessions Audit

    private var sessionsTab: some View {
        VStack(spacing: 0) {
            // Filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    sessionFilterPill("Tutte", tag: "all")
                    sessionFilterPill("Discovery", tag: "discovery")
                    sessionFilterPill("Refresh", tag: "price_refresh")
                    sessionFilterPill("Taglie", tag: "size_enrichment")
                    sessionFilterPill("Errori", tag: "failed", badge: failedSessions.count > 0 ? "\(failedSessions.count)" : nil)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color.white)

            Divider()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    if filteredSessions.isEmpty {
                        Text("Nessuna sessione trovata.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    } else {
                        ForEach(filteredSessions) { sess in
                            sessionRow(sess)
                                .onTapGesture {
                                    selectedSession = sess
                                }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(red: 247/255, green: 248/255, blue: 250/255))
            .refreshable {
                await loadData()
            }
        }
    }

    private func sessionFilterPill(_ title: String, tag: String, badge: String? = nil) -> some View {
        let isSel = sessionFilter == tag
        return Button(action: {
            sessionFilter = tag
        }) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: isSel ? .bold : .medium))
                if let b = badge {
                    Text(b)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSel ? Color.indigo : Color(red: 240/255, green: 242/255, blue: 245/255))
            .foregroundColor(isSel ? .white : .primary)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func sessionRow(_ sess: SyncSessionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(sess.isCompleted ? Color.green.opacity(0.12) : (sess.isRunning ? Color.blue.opacity(0.12) : Color.red.opacity(0.12)))
                        .frame(width: 36, height: 36)
                    Image(systemName: sess.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(sess.isCompleted ? .green : (sess.isRunning ? .blue : .red))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(sess.displayTitle)
                            .font(.system(size: 13, weight: .bold))
                        if sess.isFailed {
                            Text("ERRORE")
                                .font(.system(size: 8.5, weight: .black))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red.opacity(0.15))
                                .foregroundColor(.red)
                                .cornerRadius(4)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(sess.displayStartedAt)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(sess.displayDuration)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    }
                }

                Spacer()

                if let drops = sess.totalPriceDrops, drops > 0 {
                    Text("\(drops) cali")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                } else if let items = sess.totalItemsProcessed, items > 0 {
                    Text("\(items) items")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(white: 0.8))
            }

            if sess.isFailed, let err = sess.errorMessage, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.02), radius: 3, y: 1)
    }

    // MARK: - Search Feedback Card in Control Center

    private var feedbackSummaryCardInControl: some View {
        Button(action: {
            selectedTab = 1
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.indigo.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.indigo)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Feedback Ricerca Utenti")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                        Text("\(feedbacks.count)")
                            .font(.system(size: 11, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.15))
                            .foregroundColor(.indigo)
                            .cornerRadius(6)
                    }

                    if feedbacks.isEmpty {
                        Text("Nessun feedback inviato finora")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            Text("👍 \(positiveFeedbacksCount) (\(Int(positiveSatisfactionPct))%)")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.green)
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("👎 \(negativeFeedbacksCount)")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.red)
                            if commentsFeedbacksCount > 0 {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text("💬 \(commentsFeedbacksCount)")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.indigo)
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 2: Feedback Ricerca

    private var feedbackTab: some View {
        VStack(spacing: 0) {
            feedbackSummaryHeader

            VStack(spacing: 8) {
                // Search box
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    TextField("Cerca query, commento o prodotto...", text: $feedbackSearch)
                        .font(.system(size: 13))
                    if !feedbackSearch.isEmpty {
                        Button(action: { feedbackSearch = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(red: 242/255, green: 243/255, blue: 246/255))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.top, 10)

                // Filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        feedbackFilterPill("Tutti", count: feedbacks.count, tag: "all")
                        feedbackFilterPill("Negativi 👎", count: negativeFeedbacksCount, tag: "negative", color: .red)
                        feedbackFilterPill("Positivi 👍", count: positiveFeedbacksCount, tag: "positive", color: .green)
                        feedbackFilterPill("Con commento 💬", count: commentsFeedbacksCount, tag: "comments", color: .indigo)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .background(Color.white)

            Divider()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    if filteredFeedbacks.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                                .font(.system(size: 40))
                                .foregroundColor(Color.secondary.opacity(0.6))
                                .padding(.top, 40)
                            Text(feedbackSearch.isEmpty ? "Nessun feedback registrato" : "Nessun feedback corrisponde ai criteri")
                                .font(.system(size: 14, weight: .bold))
                            Text("I feedback inviati dagli utenti dall'app principale appariranno qui in tempo reale.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        ForEach(filteredFeedbacks) { fb in
                            feedbackCard(fb)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Color(red: 247/255, green: 248/255, blue: 250/255))
            .refreshable {
                await loadData()
            }
        }
        .confirmationDialog(
            "Elimina Feedback",
            isPresented: $showDeleteAlert,
            titleVisibility: .visible,
            presenting: feedbackToDelete
        ) { item in
            Button("Elimina", role: .destructive) {
                Task {
                    await deleteFeedback(item)
                }
            }
            Button("Annulla", role: .cancel) {}
        } message: { item in
            Text("Sei sicuro di voler eliminare il feedback per la ricerca: \"\(item.query)\"?")
        }
    }

    private var feedbackSummaryHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Satisfaction Box
                VStack(alignment: .leading, spacing: 4) {
                    Text("Soddisfazione")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(totalFeedbacksCount > 0 ? String(format: "%.0f%%", positiveSatisfactionPct) : "—")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(positiveSatisfactionPct >= 70 ? .green : (positiveSatisfactionPct >= 40 ? .orange : .red))
                        if totalFeedbacksCount > 0 {
                            Text("positivi")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(red: 247/255, green: 248/255, blue: 250/255))
                .cornerRadius(12)

                // Breakdown Numbers
                HStack(spacing: 6) {
                    VStack(spacing: 2) {
                        Text("Totali")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(totalFeedbacksCount)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 24)

                    VStack(spacing: 2) {
                        Text("👍 Positivi")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.green)
                        Text("\(positiveFeedbacksCount)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 24)

                    VStack(spacing: 2) {
                        Text("👎 Negativi")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red)
                        Text("\(negativeFeedbacksCount)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.red)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color(red: 247/255, green: 248/255, blue: 250/255))
                .cornerRadius(12)
            }

            // Ratio progress bar
            if totalFeedbacksCount > 0 {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.green)
                            .frame(width: max(0, geo.size.width * CGFloat(positiveFeedbacksCount) / CGFloat(totalFeedbacksCount)))

                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.red)
                            .frame(width: max(0, geo.size.width * CGFloat(negativeFeedbacksCount) / CGFloat(totalFeedbacksCount)))
                    }
                }
                .frame(height: 5)
                .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(Color.white)
    }

    private func feedbackCard(_ fb: SearchFeedbackItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Query + Badge + Delete
            HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.indigo)
                    Text(fb.query)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: fb.isPositive ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(fb.isPositive ? "Positivo" : "Negativo")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(fb.isPositive ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                .foregroundColor(fb.isPositive ? .green : .red)
                .cornerRadius(8)

                Button(action: {
                    feedbackToDelete = fb
                    showDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(Color.secondary.opacity(0.7))
                        .padding(4)
                }
                .buttonStyle(.plain)
            }

            // Sub-row: Timestamp & Device
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(fb.displayCreatedAt)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                if let dev = fb.deviceId, !dev.isEmpty {
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Dev: \(dev.prefix(8))…")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Comment quote box
            if let comment = fb.comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.indigo.opacity(0.7))
                        .padding(.top, 1)

                    Text(comment)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(Color(red: 40/255, green: 40/255, blue: 50/255))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(Color.indigo.opacity(0.06))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.indigo.opacity(0.15), lineWidth: 1)
                )
            }

            // Product evaluations list
            if let evals = fb.productEvaluations, !evals.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Valutazione prodotti (\(evals.count)):")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    VStack(spacing: 5) {
                        ForEach(evals) { pEval in
                            HStack(spacing: 8) {
                                Image(systemName: pEval.isThumbUp ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(pEval.isThumbUp ? .green : .red)
                                    .frame(width: 20, height: 20)
                                    .background((pEval.isThumbUp ? Color.green : Color.red).opacity(0.12))
                                    .clipShape(Circle())

                                Text(pEval.productName ?? pEval.productId ?? "Prodotto")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(red: 247/255, green: 248/255, blue: 250/255))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }

    private func feedbackFilterPill(_ title: String, count: Int, tag: String, color: Color = .primary) -> some View {
        let isSel = feedbackFilter == tag
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.18)) {
                feedbackFilter = tag
            }
        }) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: isSel ? .bold : .medium))
                Text("(\(count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSel ? .white : color.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSel ? Color.indigo : Color(red: 242/255, green: 243/255, blue: 246/255))
            .foregroundColor(isSel ? .white : color)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }

    private func deleteFeedback(_ item: SearchFeedbackItem) async {
        let ok = await net.deleteSearchFeedback(id: item.id)
        if ok {
            withAnimation {
                feedbacks.removeAll { $0.id == item.id }
            }
            statusToast = "Feedback eliminato."
        } else {
            statusToast = "Errore durante l'eliminazione."
        }
    }

    // MARK: - Tab 4: Error Center

    private var errorsTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if failedSessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("Nessun Errore Rilevato")
                            .font(.system(size: 16, weight: .bold))
                        Text("Tutti i cicli di scansione e i crawler stanno operando senza anomalie.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .background(Color.white)
                    .cornerRadius(20)
                    .padding(.top, 20)
                } else {
                    HStack {
                        Text("\(failedSessions.count) Errori Registrati")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            Task {
                                let ok = await net.clearFailedSessions()
                                if ok {
                                    withAnimation {
                                        sessions.removeAll { $0.status == "failed" }
                                    }
                                    statusToast = "Errori cancellati con successo."
                                } else {
                                    statusToast = "Errore durante la cancellazione."
                                }
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "trash")
                                Text("Cancella Tutti")
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }

                    ForEach(failedSessions) { sess in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(sess.displayTitle)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.red)
                                Spacer()
                                Text(sess.displayStartedAt)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                                Button(action: {
                                    Task {
                                        let ok = await net.deleteSyncSession(id: sess.id)
                                        if ok {
                                            withAnimation {
                                                sessions.removeAll { $0.id == sess.id }
                                            }
                                        }
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color.secondary.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }

                            if let err = sess.errorMessage, !err.isEmpty {
                                Text(err)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.red)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.red.opacity(0.08))
                                    .cornerRadius(10)
                            } else {
                                Text("Collisione tra cicli paralleli: task saltato perché un aggiornamento era già in corso.")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.orange)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.orange.opacity(0.08))
                                    .cornerRadius(10)
                            }
                        }
                        .padding(14)
                        .background(Color.white)
                        .cornerRadius(16)
                    }
                }

                Spacer().frame(height: 30)
            }
            .padding(16)
        }
        .background(Color(red: 247/255, green: 248/255, blue: 250/255))
        .refreshable {
            await loadData()
        }
    }

    // MARK: - Tab 5: Server Settings

    private var serverSettingsTab: some View {
        Form {
            Section("Connessione Supabase Cloud") {
                HStack {
                    Text("Database PostgreSQL")
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(net.isSupabaseOnline ? Color.green : Color.red).frame(width: 8, height: 8)
                        Text(net.isSupabaseOnline ? "Connesso" : "Non raggiungibile")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(net.isSupabaseOnline ? .green : .red)
                    }
                }

                HStack {
                    Text("Regione")
                    Spacer()
                    Text("Frankfurt (eu-central-1)")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }

                HStack {
                    Text("Progetto Supabase")
                    Spacer()
                    Text("goopfdvnqhdmsoutkldp")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Section("Endpoint API Backend") {
                TextField("URL Backend", text: $net.backendURL)
                    .font(.system(size: 13, design: .monospaced))

                HStack {
                    Text("Stato Server")
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(net.isBackendOnline ? Color.green : Color.orange).frame(width: 8, height: 8)
                        Text(net.isBackendOnline ? "Online" : "Offline / Standby")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(net.isBackendOnline ? .green : .orange)
                    }
                }

                Button("Test Ping Backend") {
                    Task { _ = await net.checkBackendHealth() }
                }
            }

            Section("Manutenzione Catalogo") {
                Button("Forza Re-clustering Entità") {
                    Task {
                        await executeAction("Re-clustering avviato...") {
                            try await net.triggerRecluster()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data & Actions

    private func loadData() async {
        isLoading = true
        async let sessFetch = net.fetchSyncSessions(limit: 50)
        async let healthFetch = net.fetchStoreHealthMetrics()
        async let feedbackFetch = net.fetchSearchFeedbacks(limit: 100)

        let (s, h, fb) = await (sessFetch, healthFetch, feedbackFetch)
        self.sessions = s
        self.storeHealth = h
        self.feedbacks = fb
        self.isLoading = false
    }

    private func executeAction(_ startMsg: String, action: @escaping () async throws -> Bool) async {
        isRunningAction = true
        statusToast = startMsg
        do {
            let ok = try await action()
            if ok {
                statusToast = "Azione avviata con successo in background!"
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await loadData()
            } else {
                statusToast = "Risposta non valida dal backend."
            }
        } catch {
            statusToast = "Errore: \(error.localizedDescription)"
        }
        isRunningAction = false
    }
}

// MARK: - Session Detail Sheet

struct AdminSessionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: SyncSessionItem
    @StateObject private var net = AdminNetworkService.shared
    @State private var crawlLogs: [CrawlLogItem] = []
    @State private var isLoadingLogs: Bool = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header summary
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(session.displayTitle)
                                .font(.system(size: 18, weight: .bold))
                            Spacer()
                            Text(session.status.capitalized)
                                .font(.system(size: 11, weight: .black))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(session.isCompleted ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                                .foregroundColor(session.isCompleted ? .green : .red)
                                .cornerRadius(8)
                        }

                        Text("ID: \(session.id)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(18)

                    // Error Box if failed
                    if session.isFailed {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("Dettaglio Errore")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.red)
                            }
                            if let err = session.errorMessage, !err.isEmpty {
                                Text(err)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.red)
                            } else {
                                Text("Task saltato per prevenire collisione: un ciclo di verifica prezzi era già attivamente in esecuzione.")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(.red.opacity(0.85))
                            }
                        }
                        .padding(14)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(14)
                    }

                    // Key stats pills
                    HStack(spacing: 10) {
                        statPill(title: "Durata", value: session.displayDuration)
                        statPill(title: "Articoli", value: "\(session.totalItemsProcessed ?? 0)")
                        statPill(title: "Aggiornati", value: "\(session.totalItemsUpdated ?? 0)")
                        statPill(title: "Sconti", value: "\(session.totalPriceDrops ?? 0)")
                    }

                    // Store Stats breakdown
                    if let stats = session.storeStats, !stats.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Articoli Trovati per Negozio")
                                .font(.system(size: 14, weight: .bold))

                            VStack(spacing: 8) {
                                ForEach(Array(stats.keys.sorted()), id: \.self) { key in
                                    HStack {
                                        Text(key.capitalized)
                                            .font(.system(size: 12.5, weight: .semibold))
                                        Spacer()
                                        Text(stats[key]?.stringValue ?? "—")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.indigo)
                                    }
                                    .padding(.vertical, 3)
                                    Divider()
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(18)
                    }

                    // Crawler logs
                    if !crawlLogs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Log Crawler Dettagliati (\(crawlLogs.count))")
                                .font(.system(size: 14, weight: .bold))

                            VStack(spacing: 6) {
                                ForEach(crawlLogs) { log in
                                    HStack {
                                        Text(log.storeId.capitalized)
                                            .font(.system(size: 12, weight: .medium))
                                        Spacer()
                                        Text("\(log.itemsFound) items in \(String(format: "%.1fs", log.durationSeconds))")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(18)
                    }

                    Spacer()
                }
                .padding(16)
            }
            .background(Color(red: 247/255, green: 248/255, blue: 250/255))
            .navigationTitle("Dettaglio Sessione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        Task {
                            let ok = await net.deleteSyncSession(id: session.id)
                            if ok {
                                withAnimation {
                                    sessions.removeAll { $0.id == session.id }
                                }
                                statusToast = "Sessione eliminata."
                                dismiss()
                            }
                        }
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.indigo)
                }
            }
            .task {
                let logs = await net.fetchSessionCrawlLogs(sessionId: session.id)
                self.crawlLogs = logs
                self.isLoadingLogs = false
            }
        }
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white)
        .cornerRadius(12)
    }
}
