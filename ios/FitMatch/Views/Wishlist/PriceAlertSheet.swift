import SwiftUI

struct PriceAlertSheet: View {
    let product: MatchedProduct
    var existingWishlistItem: WishlistItem? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var notifications = NotificationManager.shared
    @ObservedObject private var prefs = UserPreferencesManager.shared

    @State private var isAlertEnabled: Bool = true
    @State private var targetPrice: Double = 0.0
    @State private var targetPriceText: String = ""
    @State private var selectedSize: String = "Tutte"
    @State private var selectedPreset: AlertPreset = .tenPercent
    @FocusState private var isPriceFieldFocused: Bool

    enum AlertPreset: String, CaseIterable {
        case any = "Qualsiasi calo"
        case tenPercent = "-10%"
        case twentyPercent = "-20%"
        case custom = "Soglia"
    }

    private var currentWishlistItem: WishlistItem? {
        wishlist.getItem(product.canonical_name) ?? existingWishlistItem
    }

    private var currentPrice: Double {
        let p = product.best_price ?? product.bestOffer?.price ?? currentWishlistItem?.currentBestPrice ?? 100.0
        return max(1.0, p)
    }

    private var minThresholdPrice: Double {
        max(1.0, (currentPrice * 0.20).rounded(.down))
    }

    private var maxThresholdPrice: Double {
        max(currentPrice + 20.0, (currentPrice * 1.15).rounded(.up))
    }

    private var priceStep: Double {
        if currentPrice < 30 { return 1.0 }
        if currentPrice < 250 { return 5.0 }
        return 10.0
    }

    private var isGearWithoutSizes: Bool {
        if let item = currentWishlistItem {
            return item.isGearCategory && item.availableSizes.isEmpty && product.allAvailableSizes.isEmpty
        }
        let cat = (product.category ?? "").lowercased()
        let gearCats = ["gps_watch", "smartwatch", "electronics", "accessories", "nutrition", "cycling", "racket", "ski"]
        if gearCats.contains(cat) && product.allAvailableSizes.isEmpty {
            return true
        }
        return false
    }

    private var availableSizes: [String] {
        // 1. Prefer real product sizes from live offers or hydrated wishlist item
        let realSizes: [String] = {
            if !product.allAvailableSizes.isEmpty {
                return product.allAvailableSizes
            }
            if let itemSizes = currentWishlistItem?.availableSizes, !itemSizes.isEmpty {
                return itemSizes
            }
            return []
        }()

        var result: [String] = ["Tutte"]
        if !realSizes.isEmpty {
            var seen = Set<String>(["tutte"])
            for sz in realSizes {
                let clean = sz.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty, seen.insert(clean.lowercased()).inserted {
                    result.append(clean)
                }
            }
            return result
        }

        // 2. Category-appropriate fallback sizes (including women's shoe sizes & apparel)
        if let item = currentWishlistItem, item.isApparelCategory {
            return result + UserPreferencesManager.apparelSizes
        }
        let cat = (product.category ?? "").lowercased()
        if ["top", "pants", "jacket", "apparel", "swim", "fitness"].contains(cat) {
            return result + UserPreferencesManager.apparelSizes
        }
        return result + [
            "36", "36.5", "37", "37.5", "38", "38.5", "39", "39.5",
            "40", "40.5", "41", "42", "42.5", "43", "43.5", "44", "44.5", "45", "46", "47"
        ]
    }

    private var savingsVsCurrent: Double {
        max(0, currentPrice - targetPrice)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Product Summary Card
                    HStack(spacing: 14) {
                        if let imageUrl = product.image_url ?? product.bestOffer?.image_url, let url = URL(string: imageUrl) {
                            ShopCachedAsyncImage(url: url, maxPixelSize: 200) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFit().padding(4)
                                } else {
                                    ShopSkeletonBlock(cornerRadius: 12)
                                }
                            }
                            .frame(width: 64, height: 64)
                            .background(Color.shopSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            if let brand = product.brand, !brand.isEmpty {
                                Text(brand.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.shopTextMuted)
                            }
                            Text(product.canonical_name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.shopDark)
                                .lineLimit(2)

                            HStack(spacing: 6) {
                                Text(WishlistItem.formatEuro(currentPrice))
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundColor(.shopPurple)
                                if let store = product.bestOffer?.store_name ?? currentWishlistItem?.bestStore {
                                    Text("su \(store)")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.shopTextMuted)
                                        .lineLimit(1)
                                }
                            }

                            if let histMin = currentWishlistItem?.histMinPrice, histMin > 0 {
                                Text("Minimo storico registrato: \(WishlistItem.formatEuro(histMin))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.shopGreen)
                            }
                        }
                    }
                    .padding(ShopLayout.compactCardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                            .stroke(Color.shopBorder, lineWidth: 1)
                    )

                    // Notification Permission Warning if not authorized
                    if !notifications.isAuthorized {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.badge.slash.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.shopOrange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notifiche non attive")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.shopDark)
                                Text("Abilita le notifiche per ricevere gli alert sui cali di prezzo.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.shopTextMuted)
                            }

                            Spacer()

                            Button("Attiva") {
                                notifications.requestAuthorization()
                            }
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.shopPurple)
                            .clipShape(Capsule())
                        }
                        .padding(14)
                        .background(Color.shopOrange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // Alert Configuration Card
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: $isAlertEnabled) {
                            HStack(spacing: 10) {
                                Image(systemName: "bell.fill")
                                    .foregroundColor(.shopPurple)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Monitora Calo Prezzo")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopDark)
                                    Text("Ricevi una notifica appena il prezzo raggiunge la soglia")
                                        .font(.system(size: 12))
                                        .foregroundColor(.shopTextMuted)
                                }
                            }
                        }
                        .tint(.shopPurple)

                        if isAlertEnabled {
                            Divider()

                            // Quick Presets
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SOGLIA DI PREZZO DESIDERATA")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.shopTextMuted)
                                    .tracking(0.5)

                                HStack(spacing: 7) {
                                    ForEach(AlertPreset.allCases, id: \.self) { preset in
                                        Button(action: {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            selectedPreset = preset
                                            applyPreset(preset)
                                        }) {
                                            Text(preset.rawValue)
                                                .font(.system(size: 12, weight: selectedPreset == preset ? .bold : .medium, design: .rounded))
                                                .foregroundColor(selectedPreset == preset ? .white : .shopDark)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .frame(maxWidth: .infinity)
                                                .background(selectedPreset == preset ? Color.shopDark : Color.shopSurfaceElevated)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            // Editable Target Price Box
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Avvisami se scende sotto")
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundColor(.shopDark)

                                    if savingsVsCurrent >= 1.0 {
                                        let pct = Int(((savingsVsCurrent / currentPrice) * 100.0).rounded())
                                        Text("Risparmio di \(WishlistItem.formatEuro(savingsVsCurrent)) (-\(pct)%)")
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundColor(.shopGreen)
                                    }
                                }

                                Spacer()

                                HStack(spacing: 3) {
                                    Text("€")
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundColor(.shopPurple)

                                    TextField("0", text: $targetPriceText)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                        .foregroundColor(.shopPurple)
                                        .frame(width: 78)
                                        .focused($isPriceFieldFocused)
                                        .onChange(of: targetPriceText) { raw in
                                            let normalized = raw.replacingOccurrences(of: ",", with: ".")
                                            if let val = Double(normalized), val > 0 {
                                                targetPrice = val
                                                if isPriceFieldFocused {
                                                    selectedPreset = .custom
                                                }
                                            }
                                        }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.shopPurple.opacity(0.35), lineWidth: 1)
                                )
                            }
                            .padding(12)
                            .background(Color.shopPurpleLight.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            // Dynamic Stepper
                            Stepper(
                                value: Binding(
                                    get: { min(max(targetPrice, minThresholdPrice), maxThresholdPrice) },
                                    set: { newVal in
                                        targetPrice = newVal
                                        targetPriceText = formatEditablePrice(newVal)
                                        selectedPreset = .custom
                                    }
                                ),
                                in: minThresholdPrice...maxThresholdPrice,
                                step: priceStep
                            ) {
                                Text("Regola a passi di €\(Int(priceStep))")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.shopTextMuted)
                            }

                            if !isGearWithoutSizes {
                                Divider()

                                // Dynamic Size Filter
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("TAGLIA DA MONITORARE")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.shopTextMuted)
                                        .tracking(0.5)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(availableSizes, id: \.self) { sz in
                                                Button(action: {
                                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                    selectedSize = sz
                                                }) {
                                                    Text(sz)
                                                        .font(.system(size: 12.5, weight: selectedSize == sz ? .bold : .medium, design: .rounded))
                                                        .foregroundColor(selectedSize == sz ? .white : .shopDark)
                                                        .padding(.horizontal, 13)
                                                        .padding(.vertical, 6.5)
                                                        .background(selectedSize == sz ? Color.shopDark : Color.shopSurfaceElevated)
                                                        .clipShape(Capsule())
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(ShopLayout.cardPadding)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: ShopLayout.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ShopLayout.cardRadius, style: .continuous)
                            .stroke(Color.shopBorder, lineWidth: 1)
                    )

                    // Save CTA
                    Button(action: saveSettings) {
                        Text(isAlertEnabled ? "Salva Alert Prezzo" : "Disattiva Alert")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(isAlertEnabled ? Color.shopPurple : Color.shopDark)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.98, pressedOpacity: 0.92))
                    .padding(.top, 4)
                }
                .padding(ShopLayout.screenPadding)
            }
            .background(Color.shopSurface.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Alert Prezzo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .onAppear(perform: loadCurrentSettings)
        }
    }

    private func formatEditablePrice(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) < 0.01 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    private func applyPreset(_ preset: AlertPreset) {
        switch preset {
        case .any:
            targetPrice = max(1.0, (currentPrice - 1.0).rounded())
        case .tenPercent:
            targetPrice = max(1.0, (currentPrice * 0.90).rounded())
        case .twentyPercent:
            targetPrice = max(1.0, (currentPrice * 0.80).rounded())
        case .custom:
            isPriceFieldFocused = true
            return
        }
        targetPriceText = formatEditablePrice(targetPrice)
    }

    private func loadCurrentSettings() {
        if let existing = currentWishlistItem {
            isAlertEnabled = existing.isAlertEnabled
            if let tp = existing.targetAlertPrice, tp > 0 {
                targetPrice = tp
                targetPriceText = formatEditablePrice(tp)
                if abs(tp - (currentPrice * 0.90).rounded()) <= 1.0 {
                    selectedPreset = .tenPercent
                } else if abs(tp - (currentPrice * 0.80).rounded()) <= 1.0 {
                    selectedPreset = .twentyPercent
                } else if abs(tp - max(1.0, (currentPrice - 1.0).rounded())) <= 1.0 {
                    selectedPreset = .any
                } else {
                    selectedPreset = .custom
                }
            } else {
                selectedPreset = .tenPercent
                applyPreset(.tenPercent)
            }
            if let sz = existing.selectedSize, !sz.isEmpty {
                selectedSize = sz
            } else {
                selectedSize = "Tutte"
            }
        } else {
            selectedPreset = .tenPercent
            applyPreset(.tenPercent)
            let pref = product.isComparable ? prefs.preferences.preferredShoeSize : prefs.preferences.preferredApparelSize
            if !pref.isEmpty && availableSizes.contains(pref) {
                selectedSize = pref
            }
        }
    }

    private func saveSettings() {
        let sizeToSave = (selectedSize == "Tutte" || isGearWithoutSizes) ? nil : selectedSize
        let finalTarget: Double? = isAlertEnabled ? max(1.0, targetPrice) : currentWishlistItem?.targetAlertPrice

        if wishlist.isFavorite(product.canonical_name) {
            wishlist.updateAlertSettings(
                canonicalName: product.canonical_name,
                isEnabled: isAlertEnabled,
                targetPrice: finalTarget,
                selectedSize: sizeToSave
            )
        } else {
            wishlist.addToWishlist(
                product: product,
                selectedSize: sizeToSave,
                targetPrice: finalTarget,
                isAlertEnabled: isAlertEnabled
            )
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }
}
