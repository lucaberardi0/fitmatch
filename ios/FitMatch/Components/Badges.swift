import SwiftUI

struct StoreBadge: View {
    let storeName: String

    var body: some View {
        ShopStoreLogo(storeName: storeName)
    }
}

struct DiscountBadge: View {
    let discountText: String

    var body: some View {
        Text(discountText)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.shopPurple)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.shopPurpleLight)
            .cornerRadius(6)
    }
}

struct SavingsPill: View {
    let amountText: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.down.right")
                .font(.system(size: 8.5, weight: .bold))
            Text(amountText)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
        }
        .foregroundColor(.shopGreen)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Color.shopGreenLight)
        .cornerRadius(5)
    }
}

struct BestPriceBadge: View {
    var body: some View {
        HStack(spacing: 3.5) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .bold))
            Text("MIGLIOR PREZZO")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Color.shopPurple)
        .cornerRadius(6)
    }
}

struct StoreCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count) STORE")
            .font(.system(size: 9, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color.shopDark.opacity(0.85))
            .cornerRadius(6)
    }
}

struct SizeChip: View {
    let size: String
    let isSelected: Bool

    var body: some View {
        Text(size)
            .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
            .foregroundColor(isSelected ? .white : .shopDark)
            .padding(.horizontal, 15)
            .padding(.vertical, 7.5)
            .background(isSelected ? Color.shopPurple : Color.white)
            .cornerRadius(20) // Shop signature pill
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.shopPurple : Color.shopBorder, lineWidth: 1)
            )
            .shadow(color: isSelected ? Color.shopPurple.opacity(0.25) : Color.black.opacity(0.02), radius: 3, y: 1)
    }
}

struct WishlistButton: View {
    let product: MatchedProduct
    var size: String? = nil
    @ObservedObject private var wishlist = WishlistManager.shared

    private var isFavorite: Bool {
        wishlist.isFavorite(product.canonical_name)
    }

    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                wishlist.toggleFavorite(product: product, selectedSize: size)
            }
        }) {
            Circle()
                .fill(Color.white)
                .frame(width: 34, height: 34)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                .overlay(
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isFavorite ? Color(red: 235/255, green: 40/255, blue: 60/255) : Color.shopDark)
                        .scaleEffect(isFavorite ? 1.15 : 1.0)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FitMatch Shared Empty State Components

struct FitMatchEmptyStateView: View {
    let icon: String
    var accentColor: Color = .shopDark
    let title: String
    let subtitle: String
    var suggestions: [String] = []
    var onSuggestionTap: ((String) -> Void)? = nil
    var primaryTitle: String? = nil
    var primaryIcon: String? = nil
    var primaryColor: Color = .shopDark
    var onPrimaryTap: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondaryIcon: String? = nil
    var onSecondaryTap: (() -> Void)? = nil
    var showsCardBackground: Bool = true

    private var isErrorAccent: Bool {
        accentColor == .shopRed
    }

    var body: some View {
        let iconForeground: Color = isErrorAccent ? .shopRed : .shopDark
        let iconBackground: Color = isErrorAccent
            ? Color.shopRed.opacity(0.08)
            : (showsCardBackground ? Color.shopSurface : Color.white)
        let iconStroke: Color = isErrorAccent
            ? Color.shopRed.opacity(0.18)
            : Color.shopBorder
        let medallionSize: CGFloat = showsCardBackground ? 56 : 64
        let iconSize: CGFloat = showsCardBackground ? 22 : 24

        let content = VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: medallionSize, height: medallionSize)
                    .overlay(
                        Circle()
                            .stroke(iconStroke, lineWidth: 1)
                    )
                    .shadow(
                        color: showsCardBackground || isErrorAccent ? .clear : Color.black.opacity(0.04),
                        radius: 10,
                        x: 0,
                        y: 3
                    )

                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundColor(iconForeground)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17.5, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundColor(.shopTextMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }

            if !suggestions.isEmpty, let onSuggestionTap {
                EmptyStateCenteredFlowLayout(spacing: 8) {
                    ForEach(suggestions, id: \.self) { item in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onSuggestionTap(item)
                        }) {
                            Text(item)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.shopDark)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7.5)
                                .background(showsCardBackground ? Color.shopSurface : Color.white)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.shopBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.96, pressedOpacity: 0.9))
                    }
                }
                .padding(.top, 2)
            }

            if (primaryTitle != nil && onPrimaryTap != nil) || (secondaryTitle != nil && onSecondaryTap != nil) {
                VStack(spacing: 10) {
                    if let pTitle = primaryTitle, let pAction = onPrimaryTap {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            pAction()
                        }) {
                            HStack(spacing: 7) {
                                if let pIcon = primaryIcon {
                                    Image(systemName: pIcon)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                Text(pTitle)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 22)
                            .frame(height: 44)
                            .background(primaryColor)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(ShopCardPressStyle(scale: 0.97, pressedOpacity: 0.92))
                    }

                    if let sTitle = secondaryTitle, let sAction = onSecondaryTap {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            sAction()
                        }) {
                            HStack(spacing: 5) {
                                if let sIcon = secondaryIcon {
                                    Image(systemName: sIcon)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                Text(sTitle)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.shopTextMuted)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, showsCardBackground ? 20 : 24)
        .padding(.vertical, showsCardBackground ? 24 : 20)
        .frame(maxWidth: .infinity)

        if showsCardBackground {
            content
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: ShopLayout.largeCardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ShopLayout.largeCardRadius, style: .continuous)
                        .stroke(Color.shopBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.025), radius: 10, x: 0, y: 3)
        } else {
            content
        }
    }
}

struct FitMatchInlineEmptyRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var showsChevron: Bool = false
    var isOnSurfaceCanvas: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isOnSurfaceCanvas ? Color.shopSurface : Color.white)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle()
                            .stroke(Color.shopBorder.opacity(0.9), lineWidth: 1)
                    )

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.shopDark)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.shopDark)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.shopTextMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.shopTextMuted.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isOnSurfaceCanvas ? Color.white : Color.shopSurface)
        .clipShape(RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ShopLayout.mediumRadius, style: .continuous)
                .stroke(Color.shopBorder.opacity(isOnSurfaceCanvas ? 1.0 : 0.75), lineWidth: 1)
        )
    }
}

private struct EmptyStateCenteredFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height }
            + max(0, CGFloat(rows.count - 1)) * spacing
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX + max(0, (bounds.width - row.width) / 2)
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct RowItem {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty && needed > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.items.append(RowItem(index: index, size: size))
            current.width = current.items.count == 1 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
