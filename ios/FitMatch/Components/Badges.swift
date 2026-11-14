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
    var accentColor: Color = .shopPurple
    var badgeText: String? = nil
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

    var body: some View {
        let content = VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.08))
                    .frame(width: 84, height: 84)

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.16), accentColor.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(accentColor.opacity(0.18), lineWidth: 1)
                    )

                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(accentColor)
            }

            VStack(spacing: 8) {
                if let badge = badgeText, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(accentColor.opacity(0.10))
                        .clipShape(Capsule())
                }

                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundColor(.shopTextMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }

            if !suggestions.isEmpty, let onSuggestionTap {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { item in
                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.impactOccurred()
                            onSuggestionTap(item)
                        }) {
                            Text(item)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.shopDark)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.shopCardBg)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.shopBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }

            if (primaryTitle != nil && onPrimaryTap != nil) || (secondaryTitle != nil && onSecondaryTap != nil) {
                VStack(spacing: 10) {
                    if let pTitle = primaryTitle, let pAction = onPrimaryTap {
                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .medium)
                            gen.impactOccurred()
                            pAction()
                        }) {
                            HStack(spacing: 7) {
                                if let pIcon = primaryIcon {
                                    Image(systemName: pIcon)
                                        .font(.system(size: 13.5, weight: .bold))
                                }
                                Text(pTitle)
                                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(primaryColor)
                            .clipShape(Capsule())
                            .shadow(color: primaryColor.opacity(0.22), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                    }

                    if let sTitle = secondaryTitle, let sAction = onSecondaryTap {
                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.impactOccurred()
                            sAction()
                        }) {
                            HStack(spacing: 5) {
                                if let sIcon = secondaryIcon {
                                    Image(systemName: sIcon)
                                        .font(.system(size: 12.5, weight: .semibold))
                                }
                                Text(sTitle)
                                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(accentColor)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, showsCardBackground ? 20 : 12)
        .padding(.vertical, showsCardBackground ? 26 : 16)
        .frame(maxWidth: .infinity)

        if showsCardBackground {
            content
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.shopBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
        } else {
            content
        }
    }
}

struct FitMatchInlineEmptyRow: View {
    let icon: String
    var accentColor: Color = .shopPurple
    let title: String
    let subtitle: String
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accentColor.opacity(0.10))
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(accentColor.opacity(0.14), lineWidth: 1)
                    )

                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.shopTextMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.shopCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.shopBorder, lineWidth: 1)
        )
    }
}
