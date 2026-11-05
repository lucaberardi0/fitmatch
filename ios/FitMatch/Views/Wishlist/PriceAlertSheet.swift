import SwiftUI

struct PriceAlertSheet: View {
    let product: MatchedProduct
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var notifications = NotificationManager.shared

    @State private var isAlertEnabled: Bool = true
    @State private var targetPrice: Double = 0.0
    @State private var selectedSize: String = "Tutte"
    @State private var selectedPreset: AlertPreset = .tenPercent
    @State private var showSuccessBanner = false

    enum AlertPreset: String, CaseIterable {
        case any = "Qualsiasi calo"
        case tenPercent = "-10%"
        case twentyPercent = "-20%"
        case custom = "Personalizzato"
    }

    private let availableSizes = ["Tutte", "40", "41", "42", "42.5", "43", "44", "44.5", "45", "46"]

    private var currentPrice: Double {
        product.best_price ?? product.bestOffer?.price ?? 100.0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Product Summary Card
                    HStack(spacing: 14) {
                        if let imageUrl = product.image_url ?? product.bestOffer?.image_url, let url = URL(string: imageUrl) {
                            ShopCachedAsyncImage(url: url, maxPixelSize: 200) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFit()
                                } else {
                                    ShopSkeletonBlock(cornerRadius: 12)
                                }
                            }
                            .frame(width: 64, height: 64)
                            .cornerRadius(12)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            if let brand = product.brand {
                                Text(brand.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            Text(product.canonical_name)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(2)

                            HStack(spacing: 6) {
                                Text(product.formattedBestPrice)
                                    .font(.system(size: 15, weight: .black))
                                    .foregroundColor(.shopPurple)
                                if let store = product.bestOffer?.store_name {
                                    Text("su \(store)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(.systemGray6).opacity(0.6))
                    .cornerRadius(16)

                    // Notification Permission Warning if not authorized
                    if !notifications.isAuthorized {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.badge.slash.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notifiche non attive")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Abilita le notifiche per ricevere gli alert sui prezzi.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Attiva") {
                                notifications.requestAuthorization()
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.shopPurple)
                            .cornerRadius(8)
                        }
                        .padding(14)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(14)
                    }

                    // Alert Toggle Section
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: $isAlertEnabled) {
                            HStack(spacing: 10) {
                                Image(systemName: "bell.fill")
                                    .foregroundColor(.shopPurple)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Monitora Calo Prezzo")
                                        .font(.system(size: 15, weight: .bold))
                                    Text("Ricevi una notifica istantanea appena il prezzo scende")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .tint(.shopPurple)

                        if isAlertEnabled {
                            Divider()

                            // Presets
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SOGLIA DI PREZZO DESIDERATA:")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)

                                HStack(spacing: 8) {
                                    ForEach(AlertPreset.allCases, id: \.self) { preset in
                                        Button(action: {
                                            selectedPreset = preset
                                            applyPreset(preset)
                                        }) {
                                            Text(preset.rawValue)
                                                .font(.system(size: 12, weight: selectedPreset == preset ? .bold : .medium))
                                                .foregroundColor(selectedPreset == preset ? .white : .primary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .background(selectedPreset == preset ? Color.shopDark : Color(.systemGray6))
                                                .cornerRadius(10)
                                        }
                                    }
                                }
                            }

                            // Target Price Box
                            HStack {
                                Text("Avvisami se scende sotto:")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("€\(String(format: "%.2f", targetPrice))")
                                    .font(.system(size: 20, weight: .black))
                                    .foregroundColor(.shopPurple)
                            }
                            .padding(12)
                            .background(Color.shopPurpleLight.opacity(0.4))
                            .cornerRadius(12)

                            // Stepper for custom adjustments
                            Stepper("Regola soglia: €\(String(format: "%.0f", targetPrice))", value: $targetPrice, in: 10...500, step: 5)
                                .font(.system(size: 13, weight: .medium))

                            Divider()

                            // Size filter
                            VStack(alignment: .leading, spacing: 8) {
                                Text("TAGLIA DA MONITORARE:")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(availableSizes, id: \.self) { sz in
                                            Button(action: { selectedSize = sz }) {
                                                Text(sz)
                                                    .font(.system(size: 12, weight: selectedSize == sz ? .bold : .medium))
                                                    .foregroundColor(selectedSize == sz ? .white : .primary)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(selectedSize == sz ? Color.shopDark : Color(.systemGray6))
                                                    .cornerRadius(14)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color(.systemGray5), lineWidth: 1)
                    )

                    // Simulation Test Button
                    VStack(alignment: .leading, spacing: 8) {
                        Text("COLLAUDO NOTIFICA:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)

                        Button(action: {
                            // Ensure in wishlist first
                            if !wishlist.isFavorite(product.canonical_name) {
                                wishlist.addToWishlist(product: product, selectedSize: selectedSize == "Tutte" ? nil : selectedSize, targetPrice: targetPrice)
                            }
                            wishlist.simulatePriceDrop(for: product.canonical_name, dropAmount: 25.0)
                            showSuccessBanner = true
                        }) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.yellow)
                                Text("Simula Calo Prezzo Subito (Test)")
                                    .font(.system(size: 13, weight: .bold))
                                Spacer()
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.primary)
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }

                        if showSuccessBanner {
                            Text("✓ Notifica inviata! Controlla la tendina delle notifiche.")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.top, 4)

                    // Save Button
                    Button(action: saveSettings) {
                        Text("Salva Notifica Prezzo")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.shopPurple)
                            .cornerRadius(25)
                    }
                    .padding(.top, 10)
                }
                .padding(16)
            }
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

    private func applyPreset(_ preset: AlertPreset) {
        switch preset {
        case .any:
            targetPrice = max(10, currentPrice - 1.0)
        case .tenPercent:
            targetPrice = (currentPrice * 0.90).rounded()
        case .twentyPercent:
            targetPrice = (currentPrice * 0.80).rounded()
        case .custom:
            break
        }
    }

    private func loadCurrentSettings() {
        if let existing = wishlist.getItem(product.canonical_name) {
            isAlertEnabled = existing.isAlertEnabled
            if let tp = existing.targetAlertPrice {
                targetPrice = tp
            } else {
                applyPreset(.tenPercent)
            }
            selectedSize = existing.selectedSize ?? "Tutte"
        } else {
            applyPreset(.tenPercent)
        }
    }

    private func saveSettings() {
        let sizeToSave = selectedSize == "Tutte" ? nil : selectedSize

        if wishlist.isFavorite(product.canonical_name) {
            wishlist.updateAlertSettings(
                canonicalName: product.canonical_name,
                isEnabled: isAlertEnabled,
                targetPrice: targetPrice,
                selectedSize: sizeToSave
            )
        } else {
            wishlist.addToWishlist(
                product: product,
                selectedSize: sizeToSave,
                targetPrice: targetPrice
            )
        }

        dismiss()
    }
}
