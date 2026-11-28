import SwiftUI

// MARK: - Sub-Page: Notifiche

struct AccountNotificationsSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var prefs = UserPreferencesManager.shared
    @ObservedObject private var notifManager = NotificationManager.shared
    @State private var showingNotificationsSheet = false
    @State private var showingSystemSettingsAlert = false

    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Notifiche")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // System permission warning when explicitly denied in iOS Settings
                    if notifManager.authorizationStatus == .denied {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.shopOrange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Permessi iOS disattivati")
                                    .font(.system(size: 13.5, weight: .bold))
                                    .foregroundColor(.shopDark)
                                Text("Per ricevere avvisi push sui ribassi, abilita le notifiche di FitMatch nelle Impostazioni di iOS.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.shopTextMuted)
                            }

                            Spacer()

                            Button("Apri") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.shopPurple)
                            .clipShape(Capsule())
                        }
                        .padding(14)
                        .background(Color.shopOrange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    // Open Notifications Center Card
                    Button(action: {
                        ShopHaptics.impact(.light)
                        showingNotificationsSheet = true
                    }) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.shopPurpleLight)
                                    .frame(width: 42, height: 42)
                                Image(systemName: "bell.badge.fill")
                                    .font(.system(size: 17))
                                    .foregroundColor(.shopPurple)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Centro Notifiche")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.shopDark)
                                Text(notifManager.unreadCount > 0 ? "\(notifManager.unreadCount) non lette" : "Visualizza avvisi e cali di prezzo")
                                    .font(.system(size: 12.5))
                                    .foregroundColor(.shopTextMuted)
                            }

                            Spacer()

                            if notifManager.unreadCount > 0 {
                                Text("\(min(notifManager.unreadCount, 99))")
                                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.shopPurple)
                                    .clipShape(Capsule())
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.shopTextMuted)
                        }
                        .shopCard()
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.98))

                    // Notification Preferences (synced server-side to user_preferences + device_tokens)
                    VStack(spacing: 14) {
                        Toggle(isOn: $prefs.preferences.isPushNotificationEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notifiche Push Ribassi")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Text("Avvisa quando un prodotto della wishlist scende di prezzo")
                                    .font(.system(size: 12))
                                    .foregroundColor(.shopTextMuted)
                            }
                        }
                        .tint(.shopPurple)
                        .onChange(of: prefs.preferences.isPushNotificationEnabled) { enabled in
                            if enabled {
                                if notifManager.authorizationStatus == .denied {
                                    showingSystemSettingsAlert = true
                                } else if !notifManager.isAuthorized {
                                    notifManager.requestAuthorization { granted in
                                        if !granted {
                                            prefs.preferences.isPushNotificationEnabled = false
                                        }
                                    }
                                }
                            }
                        }

                        Divider()

                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Soglia Minima di Sconto")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Text("Per gli alert automatici senza prezzo target personalizzato")
                                    .font(.system(size: 12))
                                    .foregroundColor(.shopTextMuted)
                            }
                            Spacer()
                            Stepper(
                                "\(prefs.preferences.minDiscountThreshold)%",
                                value: $prefs.preferences.minDiscountThreshold,
                                in: 5...60,
                                step: 5
                            )
                            .labelsHidden()
                            Text("-\(prefs.preferences.minDiscountThreshold)%")
                                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                .foregroundColor(.shopPurple)
                                .frame(minWidth: 42, alignment: .trailing)
                        }
                        .opacity(prefs.preferences.isPushNotificationEnabled ? 1.0 : 0.5)
                        .disabled(!prefs.preferences.isPushNotificationEnabled)

                        Divider()

                        Toggle(isOn: $prefs.preferences.isHapticFeedbackEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Feedback Aptico")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Text("Vibrazione al tocco su filtri, tab e salvataggi")
                                    .font(.system(size: 12))
                                    .foregroundColor(.shopTextMuted)
                            }
                        }
                        .tint(.shopPurple)
                    }
                    .shopCard()

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 6)
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            notifManager.checkAuthorization()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                notifManager.checkAuthorization()
            }
        }
        .sheet(isPresented: $showingNotificationsSheet) {
            NotificationsView()
        }
        .alert("Notifiche disattivate su iOS", isPresented: $showingSystemSettingsAlert) {
            Button("Annulla", role: .cancel) {
                prefs.preferences.isPushNotificationEnabled = false
            }
            Button("Apri Impostazioni") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Hai precedentemente negato i permessi di notifica per FitMatch. Abilitali nelle Impostazioni di sistema per ricevere gli avvisi di calo prezzo.")
        }
    }
}

// MARK: - Sub-Page: Dati e Privacy

struct AccountPrivacyDataView: View {
    let storeCount: Int

    @ObservedObject private var supabase = SupabaseManager.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var prefs = UserPreferencesManager.shared
    @ObservedObject private var followedManager = FollowedStoresManager.shared
    @ObservedObject private var recentManager = RecentActivityManager.shared
    @ObservedObject private var notifManager = NotificationManager.shared

    @State private var isRefreshingCloud = false
    @State private var isExportingData = false
    @State private var isClearingChats = false
    @State private var isDeletingData = false
    @State private var cacheSizeText: String = "0 MB"

    @State private var showingClearCacheAlert = false
    @State private var showingClearChatsAlert = false
    @State private var showingChatsClearedAlert = false
    @State private var showingDeleteAccountAlert = false
    @State private var showingDeletedDoneAlert = false
    @State private var deletionErrorMessage: String? = nil

    @State private var exportFileURL: URL? = nil
    @State private var showingExportShareSheet = false

    private var lastSyncFormatted: String? {
        guard let date = supabase.lastSyncDate else { return nil }
        let df = RelativeDateTimeFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.unitsStyle = .short
        return "Aggiornato \(df.localizedString(for: date, relativeTo: Date()))"
    }

    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Dati e privacy")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 1. Supabase Cloud Sync & Identità Account
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(supabase.isCloudConnected ? Color.shopGreenLight : Color.shopOrange.opacity(0.16))
                                    .frame(width: 36, height: 36)
                                Circle()
                                    .fill(supabase.isCloudConnected ? Color.shopGreen : Color.shopOrange)
                                    .frame(width: 11, height: 11)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("FitMatch Cloud Sync")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.shopDark)
                                Text(supabase.syncStatusMessage)
                                    .font(.system(size: 12))
                                    .foregroundColor(.shopTextMuted)
                                if let syncTime = lastSyncFormatted {
                                    Text(syncTime)
                                        .font(.system(size: 11))
                                        .foregroundColor(.shopTextMuted.opacity(0.85))
                                }
                            }

                            Spacer()

                            Button(action: {
                                Task { await refreshAllCloudData() }
                            }) {
                                Group {
                                    if isRefreshingCloud {
                                        ProgressView()
                                            .scaleEffect(0.75)
                                            .tint(.shopPurple)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.shopPurple)
                                    }
                                }
                                .frame(width: 34, height: 34)
                                .background(Color.shopPurpleLight)
                                .clipShape(Circle())
                            }
                            .disabled(isRefreshingCloud)
                            .accessibilityLabel("Sincronizza ora")
                        }

                        Text("In modalità ospite i tuoi dati sono isolati tramite una sessione anonima cifrata; effettuando l'accesso vengono uniti al tuo profilo e sincronizzati su tutti i dispositivi.")
                            .font(.system(size: 12))
                            .foregroundColor(.shopTextMuted)
                            .lineSpacing(2)
                    }
                    .shopCard()

                    // 2. Permessi e Consensi
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Permessi di sistema e consensi")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notifiche Push (Art. 6.1.a GDPR)")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                Text(
                                    notifManager.isAuthorized && prefs.preferences.isPushNotificationEnabled
                                        ? "Attive · Consenso revocabile in qualsiasi momento"
                                        : "Disattivate sul dispositivo o nelle impostazioni app"
                                )
                                .font(.system(size: 11.5))
                                .foregroundColor(.shopTextMuted)
                            }
                            Spacer()
                            Button("Impostazioni") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.shopPurple)
                        }
                    }
                    .shopCard()

                    // 3. Documenti Legali Obbligatori (GDPR, Termini, Omnibus/Affiliazioni, Licenze)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Documenti Legali")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                            .padding(.bottom, 8)

                        legalNavigationRow(
                            icon: "hand.raised.fill",
                            title: "Informativa sulla Privacy (GDPR)",
                            subtitle: "Reg. UE 2016/679 · Dati trattati, contatti e diritti",
                            type: .privacy
                        )
                        Divider()

                        legalNavigationRow(
                            icon: "doc.text.fill",
                            title: "Termini e Condizioni d'Uso",
                            subtitle: "Natura del servizio, prezzi e responsabilità",
                            type: .terms
                        )
                        Divider()

                        legalNavigationRow(
                            icon: "arrow.up.right.square.fill",
                            title: "Trasparenza Comparazione & Affiliazioni",
                            subtitle: "Criteri di ranking e link affiliati (Dir. Omnibus)",
                            type: .affiliate
                        )
                        Divider()

                        legalNavigationRow(
                            icon: "checkmark.seal.fill",
                            title: "Licenze Software & Attribuzioni",
                            subtitle: "Framework, servizi cloud e marchi terzi",
                            type: .licenses
                        )
                    }
                    .shopCard(padding: 16)

                    // 4. Diritti dell'Interessato (Portabilità, Gestione Cronologia, Cache, Cancellazione - Artt. 15-20 GDPR)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("I Tuoi Dati e Diritti (GDPR)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)
                            .padding(.bottom, 6)

                        // Clear AI Chat History
                        Button(action: {
                            showingClearChatsAlert = true
                        }) {
                            HStack(spacing: 12) {
                                if isClearingChats {
                                    ProgressView().frame(width: 22)
                                } else {
                                    Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                        .frame(width: 22)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Cancella Cronologia Chat AI")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                    let chatCount = prefs.accountMonitorStats?.chat_sessions_count ?? 0
                                    Text(chatCount > 0 ? "\(chatCount) conversazioni salvate nell'Assistente" : "Rimuove le conversazioni dell'Assistente AI")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.shopTextMuted)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(isClearingChats)

                        Divider()

                        // Complete Art. 20 GDPR Export
                        Button(action: {
                            Task { await exportUserDataJSON() }
                        }) {
                            HStack(spacing: 12) {
                                if isExportingData {
                                    ProgressView().frame(width: 22)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                        .frame(width: 22)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Esporta i tuoi dati (JSON)")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                    Text("Diritto alla portabilità completo · Art. 20 GDPR")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.shopTextMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(.shopTextMuted)
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(isExportingData)

                        Divider()

                        // Clear RAM + Disk Image Cache & URLCache
                        Button(action: {
                            ImageCacheManager.shared.clearAllCaches()
                            ShopHaptics.notification(.success)
                            cacheSizeText = ImageCacheManager.shared.formattedDiskCacheSize()
                            showingClearCacheAlert = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "trash")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.shopDark)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Svuota Cache Locale")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                    Text("Memoria e disco: \(cacheSizeText) occupati")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.shopTextMuted)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        // Permanent Account & Data Deletion (GDPR Art. 17 & App Store 5.1.1(v))
                        Button(action: {
                            showingDeleteAccountAlert = true
                        }) {
                            HStack(spacing: 12) {
                                if isDeletingData {
                                    ProgressView()
                                        .frame(width: 22)
                                } else {
                                    Image(systemName: "person.crop.circle.badge.xmark")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.shopRed)
                                        .frame(width: 22)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Elimina Account & Tutti i Dati")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundColor(.shopRed)
                                    Text("Rimozione permanente account e cloud · Art. 17 GDPR")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.shopTextMuted)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeletingData)
                    }
                    .shopCard(padding: 16)

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 6)
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            notifManager.checkAuthorization()
            cacheSizeText = ImageCacheManager.shared.formattedDiskCacheSize()
        }
        .task {
            await prefs.fetchAccountMonitorStats()
        }
        .sheet(isPresented: $showingExportShareSheet) {
            if let url = exportFileURL {
                AccountShareSheet(items: [url])
            }
        }
        .alert("Cache Svuotata", isPresented: $showingClearCacheAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("La cache locale in memoria e su disco (immagini e risposte di rete) è stata svuotata.")
        }
        .alert("Cancella Cronologia Chat AI", isPresented: $showingClearChatsAlert) {
            Button("Annulla", role: .cancel) { }
            Button("Cancella", role: .destructive) {
                Task { await performClearChatHistory() }
            }
        } message: {
            Text("Vuoi rimuovere tutte le conversazioni salvate nell'Assistente AI? L'operazione non può essere annullata.")
        }
        .alert("Cronologia Chat Rimossa", isPresented: $showingChatsClearedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Tutte le conversazioni dell'Assistente AI sono state rimosse.")
        }
        .alert("Elimina Account e Tutti i Dati", isPresented: $showingDeleteAccountAlert) {
            Button("Annulla", role: .cancel) { }
            Button("Elimina Definitivamente", role: .destructive) {
                Task { await performFullAccountAndDataDeletion() }
            }
        } message: {
            Text("Questa azione irreversibile eliminerà definitivamente il tuo account di autenticazione, i salvati, le collezioni, le preferenze, i negozi seguiti/nascosti, le chat AI, le recensioni e la cronologia dal dispositivo e dal cloud (Art. 17 GDPR).")
        }
        .alert("Account e Dati Eliminati", isPresented: $showingDeletedDoneAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Il tuo account e tutti i dati personali associati sono stati eliminati definitivamente dal dispositivo e dal cloud.")
        }
        .alert(
            "Impossibile eliminare l'account",
            isPresented: Binding(
                get: { deletionErrorMessage != nil },
                set: { if !$0 { deletionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { deletionErrorMessage = nil }
        } message: {
            Text(deletionErrorMessage ?? "Errore sconosciuto. Riprova più tardi.")
        }
    }

    private func legalNavigationRow(icon: String, title: String, subtitle: String, type: AccountLegalType) -> some View {
        NavigationLink(destination: AccountLegalDocumentPage(type: type, storeCount: storeCount)) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.shopPurple)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.shopDark)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(.shopTextMuted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.shopTextMuted)
            }
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    private func refreshAllCloudData() async {
        isRefreshingCloud = true
        defer { isRefreshingCloud = false }
        ShopHaptics.impact(.light)
        _ = await supabase.checkCloudHealth()
        async let w: Void = wishlist.syncWithDatabase(force: true)
        async let p: Void = prefs.syncFromDatabase(force: true)
        async let f: Void = followedManager.fetchFollowedStores()
        async let h: Void = followedManager.fetchHiddenStores()
        async let r: Void = recentManager.syncFromDatabase(force: true)
        async let s: Void = prefs.fetchAccountMonitorStats()
        _ = await (w, p, f, h, r, s)
    }

    private func performClearChatHistory() async {
        isClearingChats = true
        defer { isClearingChats = false }
        let ok = await supabase.archiveUserChatSessions()
        if ok {
            ShopHaptics.notification(.success)
            NotificationCenter.default.post(name: NSNotification.Name("FitMatchChatHistoryCleared"), object: nil)
            await prefs.fetchAccountMonitorStats()
            showingChatsClearedAlert = true
        }
    }

    private func exportUserDataJSON() async {
        isExportingData = true
        defer { isExportingData = false }

        let chatSessions = await supabase.fetchChatSessionsDirect(
            deviceId: supabase.deviceId,
            userId: supabase.validCurrentUserId,
            limit: 100
        )

        let iso = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "exported_at": iso.string(from: Date()),
            "app": "FitMatch",
            "gdpr_article": "Art. 20 - Data Portability",
            "account": [
                "is_authenticated": supabase.isAuthenticated,
                "user_id": supabase.validCurrentUserId ?? NSNull(),
                "email": supabase.currentUserEmail ?? NSNull(),
                "pseudonymous_device_id": supabase.deviceId
            ],
            "preferences": [
                "user_name": prefs.preferences.userName,
                "preferred_shoe_size": prefs.preferences.preferredShoeSize,
                "preferred_apparel_size": prefs.preferences.preferredApparelSize,
                "selected_sports": prefs.preferences.selectedSports,
                "favorite_brands": prefs.preferences.favoriteBrands,
                "min_discount_threshold": prefs.preferences.minDiscountThreshold,
                "push_notifications_enabled": prefs.preferences.isPushNotificationEnabled,
                "haptic_feedback_enabled": prefs.preferences.isHapticFeedbackEnabled
            ],
            "wishlist_items": wishlist.items.map { item -> [String: Any] in
                [
                    "canonical_name": item.canonical_name,
                    "product_id": item.productId ?? NSNull(),
                    "brand": item.brand ?? "",
                    "best_store": item.bestStore ?? "",
                    "current_best_price": item.currentBestPrice,
                    "saved_price": item.savedPrice,
                    "initial_price": item.initialPrice,
                    "selected_size": item.selectedSize ?? NSNull(),
                    "collection_names": item.collectionNames,
                    "target_alert_price": item.targetAlertPrice ?? NSNull(),
                    "alert_enabled": item.isAlertEnabled,
                    "date_added": iso.string(from: item.dateAdded)
                ]
            },
            "collections": wishlist.collections.map(\.name),
            "followed_stores": followedManager.followedStores.map {
                ["store_id": $0.store_id, "store_name": $0.store_name]
            },
            "hidden_stores": Array(followedManager.hiddenStoreIds).sorted(),
            "recent_activities": recentManager.activities.map { act -> [String: Any] in
                [
                    "type": act.type.rawValue,
                    "title": act.title,
                    "subtitle": act.subtitle ?? NSNull(),
                    "store_id": act.storeId ?? NSNull(),
                    "timestamp": iso.string(from: act.timestamp)
                ]
            },
            "notifications": notifManager.notifications.map { n -> [String: Any] in
                [
                    "id": n.id,
                    "type": n.type.rawValue,
                    "title": n.title,
                    "body": n.body,
                    "product": n.productCanonicalName ?? NSNull(),
                    "store_name": n.storeName ?? NSNull(),
                    "is_read": n.isRead,
                    "timestamp": iso.string(from: n.timestamp)
                ]
            },
            "ai_chat_sessions": chatSessions.map { s -> [String: Any] in
                [
                    "id": s.id,
                    "title": s.title,
                    "subtitle": s.subtitle ?? NSNull(),
                    "turn_count": s.turn_count,
                    "updated_at": s.updated_at ?? NSNull()
                ]
            }
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("fitmatch_dati_personali.json")
        do {
            try data.write(to: tempURL, options: .atomic)
            self.exportFileURL = tempURL
            self.showingExportShareSheet = true
        } catch {
            print("Export error: \(error)")
        }
    }

    private func performFullAccountAndDataDeletion() async {
        isDeletingData = true
        defer { isDeletingData = false }

        do {
            // 1. Server-side verified deletion of ALL cloud tables + auth.users
            try await supabase.deleteAccount()

            // 2. Wipe ALL local caches & state cleanly without firing network mutations
            wishlist.resetLocalOnly()
            followedManager.resetLocalOnly()
            recentManager.resetLocalOnly()
            notifManager.resetLocalOnly()
            prefs.resetLocalOnly()
            ImageCacheManager.shared.clearAllCaches()
            cacheSizeText = ImageCacheManager.shared.formattedDiskCacheSize()

            // 3. Spin up a brand new isolated guest session
            await supabase.startFreshAnonymousSessionAfterDeletion()

            ShopHaptics.notification(.success)
            showingDeletedDoneAlert = true
        } catch {
            ShopHaptics.notification(.error)
            deletionErrorMessage = error.localizedDescription
        }
    }
}

private struct AccountShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Sub-Page: Assistenza

struct AccountSupportView: View {
    let storeCount: Int
    @State private var copiedEmailToast = false

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: "Assistenza")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            FitMatchBrandEmblem(size: 30)
                            Text("Come funziona FitMatch")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                        }

                        Text("FitMatch confronta prezzi, sconti, spese di spedizione e disponibilità delle taglie su \(storeCount) store sportivi verificati.")
                            .font(.system(size: 13.5))
                            .foregroundColor(.shopTextMuted)
                            .lineSpacing(3)
                    }
                    .shopCard()

                    // Direct Support Contact Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hai bisogno di aiuto?")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        Button(action: {
                            openSupportEmail(subject: "Supporto FitMatch iOS v\(appVersion)")
                        }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.shopPurpleLight)
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 15))
                                        .foregroundColor(.shopPurple)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Scrivi al supporto")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                    Text(FitMatchContactInfo.supportEmail)
                                        .font(.system(size: 12))
                                        .foregroundColor(.shopTextMuted)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.shopPurple)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Button(action: {
                            openSupportEmail(subject: "Segnalazione prezzo o bug — FitMatch iOS v\(appVersion)")
                        }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.shopSurfaceElevated)
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "exclamationmark.bubble.fill")
                                        .font(.system(size: 15))
                                        .foregroundColor(.shopDark)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Segnala un problema o un prezzo")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.shopDark)
                                    Text("Aiutaci a mantenere il catalogo sempre preciso")
                                        .font(.system(size: 12))
                                        .foregroundColor(.shopTextMuted)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.shopTextMuted)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)

                        if copiedEmailToast {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.shopGreen)
                                Text("Indirizzo \(FitMatchContactInfo.supportEmail) copiato negli appunti.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.shopGreen)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .shopCard()

                    // FAQ Card
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Domande frequenti")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.shopDark)

                        faqRow(
                            question: "Come funzionano gli avvisi di prezzo?",
                            answer: "Salva un prodotto nella wishlist e tocca la campanella per impostare una soglia target o ricevere avvisi automatici quando il prezzo scende."
                        )
                        Divider()
                        faqRow(
                            question: "I prezzi includono la disponibilità taglia?",
                            answer: "Sì! Impostando la tua taglia scarpe o abbigliamento in \"Misure e preferenze\", FitMatch evidenzia subito gli store che hanno la tua misura in stock."
                        )
                        Divider()
                        faqRow(
                            question: "Dove concludo l'acquisto?",
                            answer: "FitMatch ti reindirizza sempre al sito ufficiale del negozio partner selezionato al miglior prezzo. Non effettua vendite dirette."
                        )
                        Divider()
                        faqRow(
                            question: "FitMatch è davvero gratuito?",
                            answer: "Sì, completamente gratuito. Per alcuni link verso i negozi partner possiamo ricevere una piccola commissione di affiliazione senza alcun costo aggiuntivo per te."
                        )
                    }
                    .shopCard()

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, ShopLayout.screenPadding)
                .padding(.top, 6)
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }

    private func openSupportEmail(subject: String) {
        ShopHaptics.impact(.light)
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Supporto"
        if let url = URL(string: "mailto:\(FitMatchContactInfo.supportEmail)?subject=\(encodedSubject)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            UIPasteboard.general.string = FitMatchContactInfo.supportEmail
            withAnimation {
                copiedEmailToast = true
            }
        }
    }

    private func faqRow(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.shopDark)
            Text(answer)
                .font(.system(size: 13))
                .foregroundColor(.shopTextMuted)
                .lineSpacing(2)
        }
    }
}
