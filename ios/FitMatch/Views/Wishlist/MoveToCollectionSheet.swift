import SwiftUI

struct MoveToCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var wishlist = WishlistManager.shared

    let item: WishlistItem

    @State private var newCollectionName: String = ""
    @State private var isCreatingNew: Bool = false

    private var currentCollection: String {
        item.collectionName ?? "Nessuna collezione"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Product Summary
                productHeader
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.vertical, ShopLayout.cardPadding)
                    .background(Color.shopSurface)

                Divider()

                // Collections List
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("SELEZIONA COLLEZIONE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.shopTextMuted)
                            .tracking(0.8)
                            .padding(.horizontal, ShopLayout.screenPadding)
                            .padding(.top, ShopLayout.cardPadding)

                        VStack(spacing: ShopLayout.tightSpacing) {
                            if wishlist.getAvailableCollections().isEmpty {
                                FitMatchInlineEmptyRow(
                                    icon: "folder.badge.plus",
                                    title: "Nessuna collezione",
                                    subtitle: "Creane una qui sotto per organizzare i salvati"
                                )
                                .padding(.vertical, 4)
                            } else {
                                ForEach(wishlist.getAvailableCollections(), id: \.name) { col in
                                    collectionRow(col)
                                }
                            }

                            if item.collectionName != nil {
                                Button(action: {
                                    wishlist.moveItem(canonicalName: item.canonical_name, toCollection: nil)
                                    dismiss()
                                }) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color.shopSurfaceElevated)
                                                .frame(width: 36, height: 36)

                                            Image(systemName: "folder.badge.minus")
                                                .font(.system(size: 15))
                                                .foregroundColor(.shopTextMuted)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Nessuna collezione")
                                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                                .foregroundColor(.shopDark)

                                            Text("Rimuovi dalla collezione attuale")
                                                .font(.system(size: 12))
                                                .foregroundColor(.shopTextMuted)
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal, ShopLayout.compactCardPadding)
                                    .padding(.vertical, 10)
                                    .background(Color.white)
                                    .cornerRadius(ShopLayout.mediumRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                                            .stroke(Color.shopBorder, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, ShopLayout.screenPadding)

                        // New Collection Creator
                        VStack(spacing: 12) {
                            if isCreatingNew {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.shopPurple)

                                    TextField("Nome collezione (es. Maratona)...", text: $newCollectionName)
                                        .font(.system(size: 15))
                                        .textInputAutocapitalization(.words)

                                    if !newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Button("Aggiungi") {
                                            createNewAndAssign()
                                        }
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.shopPurple)
                                    }
                                }
                                .padding(.horizontal, ShopLayout.cardPadding)
                                .padding(.vertical, 12)
                                .background(Color.shopSurface)
                                .cornerRadius(ShopLayout.mediumRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                                        .stroke(Color.shopPurple.opacity(0.3), lineWidth: 1)
                                )
                            } else {
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        isCreatingNew = true
                                    }
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.shopPurple)

                                        Text("Nuova collezione...")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.shopPurple)

                                        Spacer()
                                    }
                                    .padding(.horizontal, ShopLayout.cardPadding)
                                    .padding(.vertical, 12)
                                    .background(Color.shopPurpleLight)
                                    .cornerRadius(ShopLayout.mediumRadius)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, ShopLayout.screenPadding)
                        .padding(.top, 4)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Organizza in Collezione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(red: 180/255, green: 180/255, blue: 190/255))
                    }
                }
            }
        }
        .presentationDetents([.medium, .fraction(0.85)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Product Header Preview

    private var productHeader: some View {
        HStack(spacing: 14) {
            // Product image
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 230/255, green: 230/255, blue: 235/255), lineWidth: 1)
                    )

                if let urlStr = item.image_url, let url = URL(string: urlStr) {
                    ShopCachedAsyncImage(url: url, maxPixelSize: 150) { phase in
                        if let img = phase.image {
                            img.resizable()
                                .scaledToFit()
                                .padding(4)
                        } else {
                            ShopSkeletonBlock(cornerRadius: 10)
                        }
                    }
                } else {
                    Image(systemName: "shoe.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(red: 180/255, green: 180/255, blue: 190/255))
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.canonical_name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(item.formattedCurrentPrice)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 92/255, green: 60/255, blue: 245/255))

                    if let store = item.bestStore {
                        Text("•  \(store)")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 120/255, green: 120/255, blue: 130/255))
                    }
                }

                Text("Collezione attuale: \(currentCollection)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 130/255, green: 130/255, blue: 140/255))
            }

            Spacer()
        }
    }

    // MARK: - Collection Row

    private func collectionRow(_ col: WishlistCollection) -> some View {
        let isSelected = col.name.caseInsensitiveCompare(currentCollection) == .orderedSame

        return Button(action: {
            if isSelected {
                // Tapping active collection unassigns item
                wishlist.moveItem(canonicalName: item.canonical_name, toCollection: nil)
            } else {
                wishlist.moveItem(canonicalName: item.canonical_name, toCollection: col.name)
            }
            dismiss()
        }) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconBackgroundColor(for: col.name))
                        .frame(width: 36, height: 36)

                    Image(systemName: iconName(for: col.name))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(iconColor(for: col.name))
                }

                // Name & count
                VStack(alignment: .leading, spacing: 2) {
                    Text(col.name)
                        .font(.system(size: 15, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundColor(Color(red: 25/255, green: 25/255, blue: 30/255))

                    Text("\(col.item_count) \(col.item_count == 1 ? "articolo" : "articoli")")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 130/255, green: 130/255, blue: 140/255))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.shopPurple)
                } else {
                    Circle()
                        .stroke(Color(red: 220/255, green: 220/255, blue: 225/255), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, ShopLayout.compactCardPadding)
            .padding(.vertical, 10)
            .background(isSelected ? Color.shopPurpleLight : Color.white)
            .cornerRadius(ShopLayout.mediumRadius)
            .overlay(
                RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                    .stroke(isSelected ? Color.shopPurple.opacity(0.4) : Color.shopBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func createNewAndAssign() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        wishlist.createCollection(name: trimmed)
        wishlist.moveItem(canonicalName: item.canonical_name, toCollection: trimmed)
        dismiss()
    }

    private func iconName(for name: String) -> String {
        switch name.lowercased() {
        case "tutti": return "star.fill"
        case "scarpe da corsa": return "figure.run"
        case "smartwatch & gps": return "applewatch"
        case "trail & outdoor": return "mountain.2.fill"
        case "offerte speciali": return "tag.fill"
        default: return "folder.fill"
        }
    }

    private func iconColor(for name: String) -> Color {
        switch name.lowercased() {
        case "tutti": return .shopPurple
        case "scarpe da corsa": return Color(red: 245/255, green: 110/255, blue: 40/255)
        case "smartwatch & gps": return Color(red: 40/255, green: 130/255, blue: 245/255)
        case "trail & outdoor": return Color(red: 34/255, green: 160/255, blue: 95/255)
        case "offerte speciali": return Color(red: 230/255, green: 50/255, blue: 80/255)
        default: return Color(red: 120/255, green: 70/255, blue: 240/255)
        }
    }

    private func iconBackgroundColor(for name: String) -> Color {
        iconColor(for: name).opacity(0.12)
    }
}
