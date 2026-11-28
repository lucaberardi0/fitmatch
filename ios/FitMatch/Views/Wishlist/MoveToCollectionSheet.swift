import SwiftUI

struct MoveToCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var wishlist = WishlistManager.shared

    let item: WishlistItem

    @State private var newCollectionName: String = ""
    @State private var isCreatingNew: Bool = false

    /// Live view of this wishlist item so multi-collection toggles update instantaneously.
    private var liveItem: WishlistItem {
        wishlist.getItem(item.canonical_name) ?? item
    }

    private var currentSummary: String {
        if liveItem.collectionNames.isEmpty {
            return "Nessuna collezione"
        }
        return liveItem.collectionNames.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                productHeader
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.vertical, ShopLayout.compactCardPadding)
                    .background(Color.shopSurface)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("SELEZIONA UNA O PIÙ COLLEZIONI")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.shopTextMuted)
                                .tracking(0.8)

                            Spacer()

                            if !liveItem.collectionNames.isEmpty {
                                Button("Rimuovi tutte") {
                                    withAnimation(.spring(response: 0.25)) {
                                        wishlist.setCollections([], for: item.canonical_name)
                                    }
                                }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.shopTextMuted)
                            }
                        }
                        .padding(.horizontal, ShopLayout.screenPadding)
                        .padding(.top, ShopLayout.cardPadding)

                        VStack(spacing: ShopLayout.tightSpacing) {
                            let available = wishlist.getAvailableCollections()
                            if available.isEmpty {
                                FitMatchInlineEmptyRow(
                                    icon: "folder.badge.plus",
                                    title: "Nessuna collezione",
                                    subtitle: "Creane una qui sotto per organizzare i salvati"
                                )
                                .padding(.vertical, 4)
                            } else {
                                ForEach(available, id: \.name) { col in
                                    collectionRow(col)
                                }
                            }
                        }
                        .padding(.horizontal, ShopLayout.screenPadding)

                        // Inline New Collection Creator
                        VStack(spacing: 12) {
                            if isCreatingNew {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.shopPurple)

                                    TextField("Nome collezione (es. Maratona)...", text: $newCollectionName)
                                        .font(.system(size: 15))
                                        .textInputAutocapitalization(.words)
                                        .submitLabel(.done)
                                        .onSubmit {
                                            createNewAndAssign()
                                        }

                                    let clean = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !clean.isEmpty && !WishlistManager.isReservedCollectionName(clean) {
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
                                .clipShape(RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                                        .stroke(Color.shopPurple.opacity(0.35), lineWidth: 1)
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
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundColor(.shopPurple)

                                        Spacer()
                                    }
                                    .padding(.horizontal, ShopLayout.cardPadding)
                                    .padding(.vertical, 12)
                                    .background(Color.shopPurpleLight)
                                    .clipShape(RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous))
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
            .navigationTitle("Organizza in Collezioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fatto") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.shopPurple)
                }
            }
        }
        .presentationDetents([.medium, .fraction(0.85)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Product Header Preview

    private var productHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.shopBorder, lineWidth: 1)
                    )

                if let urlStr = liveItem.image_url, let url = URL(string: urlStr), !urlStr.isEmpty {
                    ShopCachedAsyncImage(url: url, maxPixelSize: 160) { phase in
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
                        .foregroundColor(.shopTextMuted.opacity(0.5))
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(liveItem.canonical_name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(liveItem.formattedCurrentPrice)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.shopPurple)

                    if let store = liveItem.bestStore, !store.isEmpty {
                        Text("· \(store)")
                            .font(.system(size: 12))
                            .foregroundColor(.shopTextMuted)
                            .lineLimit(1)
                    }
                }

                Text(currentSummary)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.shopTextMuted)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    // MARK: - Collection Row (Multi-Select Toggle)

    private func collectionRow(_ col: WishlistCollection) -> some View {
        let isSelected = liveItem.belongsToCollection(col.name)

        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                wishlist.toggleCollection(col.name, for: liveItem.canonical_name)
            }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.shopPurple.opacity(0.15) : Color.shopSurfaceElevated)
                        .frame(width: 36, height: 36)

                    Image(systemName: isSelected ? "folder.fill" : "folder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isSelected ? .shopPurple : .shopDark)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(col.name)
                        .font(.system(size: 15, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundColor(.shopDark)

                    Text(col.item_count == 1 ? "1 articolo" : "\(col.item_count) articoli")
                        .font(.system(size: 12))
                        .foregroundColor(.shopTextMuted)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(.shopPurple)
                } else {
                    Circle()
                        .stroke(Color.shopBorder, lineWidth: 1.5)
                        .frame(width: 21, height: 21)
                }
            }
            .padding(.horizontal, ShopLayout.compactCardPadding)
            .padding(.vertical, 10)
            .background(isSelected ? Color.shopPurpleLight.opacity(0.65) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                    .stroke(isSelected ? Color.shopPurple.opacity(0.45) : Color.shopBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func createNewAndAssign() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !WishlistManager.isReservedCollectionName(trimmed) else { return }
        wishlist.createCollection(name: trimmed)
        if !liveItem.belongsToCollection(trimmed) {
            wishlist.toggleCollection(trimmed, for: liveItem.canonical_name)
        }
        newCollectionName = ""
        withAnimation(.spring(response: 0.25)) {
            isCreatingNew = false
        }
    }
}
