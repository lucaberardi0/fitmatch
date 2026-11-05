import SwiftUI

// MARK: - Shopify "Shop" Skeleton & Shimmer Color Palette

extension Color {
    /// Exact soft neutral gray used for skeleton placeholders in Shopify Shop
    static let shopSkeleton = Color(red: 236/255, green: 238/255, blue: 242/255)
    static let shopSkeletonHighlight = Color(red: 248/255, green: 249/255, blue: 251/255)
}

// MARK: - High-Performance 60/120fps Shimmer Modifier

public struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.2
    var isAnimating: Bool = true
    var duration: Double = 1.35

    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    if isAnimating {
                        let w = geo.size.width
                        let h = geo.size.height
                        let bandWidth = max(w * 1.1, 160)

                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.0), location: 0.0),
                                .init(color: Color.white.opacity(0.55), location: 0.5),
                                .init(color: Color.white.opacity(0.0), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: bandWidth, height: max(h * 1.8, 100))
                        .rotationEffect(.degrees(15))
                        .offset(x: phase * (w + bandWidth) - (bandWidth * 0.4))
                        .blendMode(.screen)
                        .mask(content)
                    }
                }
            )
            .onAppear {
                guard isAnimating else { return }
                withAnimation(
                    .linear(duration: duration)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.3
                }
            }
    }
}

public extension View {
    func shimmering(active: Bool = true, duration: Double = 1.35) -> some View {
        self.modifier(ShimmerModifier(isAnimating: active, duration: duration))
    }
}

// MARK: - Reusable Skeleton Primitives

struct ShopSkeletonBlock: View {
    var cornerRadius: CGFloat = 20
    var width: CGFloat? = nil
    var height: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.shopSkeleton)
            .frame(width: width, height: height)
            .shimmering()
    }
}

struct ShopSkeletonCapsule: View {
    var width: CGFloat? = nil
    var height: CGFloat = 36

    var body: some View {
        Capsule()
            .fill(Color.shopSkeleton)
            .frame(width: width, height: height)
            .shimmering()
    }
}

struct ShopSkeletonCircle: View {
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(Color.shopSkeleton)
            .frame(width: size, height: size)
            .shimmering()
    }
}

struct ShopSkeletonTextLine: View {
    var width: CGFloat? = nil
    var height: CGFloat = 13
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.shopSkeleton)
            .frame(width: width, height: height)
            .shimmering()
    }
}

// MARK: - 1. Home Screen Skeleton (100% Identical to Shopify Shop App Screenshot)

struct ShopHomeSkeletonView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Horizontal Skeleton Pills Bar (Matching Per te, Saldi, Segui già, Salvati)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ShopSkeletonCapsule(width: 74, height: 36)
                    ShopSkeletonCapsule(width: 145, height: 36)
                    ShopSkeletonCapsule(width: 90, height: 36)
                    ShopSkeletonCapsule(width: 80, height: 36)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 12)

            // Scrollable Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 1. Top Carousel Cards Skeleton (with Card 2 peeking on right edge)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            let cardWidth = max(UIScreen.main.bounds.width - 56, 320)
                            ShopSkeletonBlock(cornerRadius: 24, width: cardWidth, height: 180)
                            ShopSkeletonBlock(cornerRadius: 24, width: cardWidth, height: 180)
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 4)

                    // 2. Large Tall Feed Card Skeleton (Store Showcase)
                    ShopSkeletonBlock(
                        cornerRadius: 24,
                        width: UIScreen.main.bounds.width - 32,
                        height: 390
                    )
                    .padding(.horizontal, 16)

                    // 3. Third Bottom Card Peeking
                    ShopSkeletonBlock(
                        cornerRadius: 24,
                        width: UIScreen.main.bounds.width - 32,
                        height: 220
                    )
                    .padding(.horizontal, 16)

                    Spacer(minLength: 120)
                }
            }
        }
    }
}

// MARK: - 2. Product Card Skeleton (for 2-Column Grids)

struct ShopProductCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Product Image Box
            ShopSkeletonBlock(cornerRadius: 16, height: 165)
                .frame(maxWidth: .infinity)

            // Store Tag Line
            ShopSkeletonTextLine(width: 75, height: 10, cornerRadius: 4)

            // Title Line 1 & 2
            ShopSkeletonTextLine(height: 12, cornerRadius: 5)
                .frame(maxWidth: .infinity)

            ShopSkeletonTextLine(width: 105, height: 12, cornerRadius: 5)

            // Price Line
            HStack(spacing: 8) {
                ShopSkeletonTextLine(width: 65, height: 16, cornerRadius: 6)
                ShopSkeletonTextLine(width: 45, height: 12, cornerRadius: 4)
            }
            .padding(.top, 2)
        }
        .padding(6)
        .background(Color.white)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }
}

// MARK: - 3. Deals Screen Skeleton

struct ShopDealsSkeletonView: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Category Pills Skeleton
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { i in
                        ShopSkeletonCapsule(width: i == 0 ? 70 : 85, height: 34)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)

            // Deals Cards Grid
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Store 1 Section Skeleton
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ShopSkeletonCircle(size: 32)
                            ShopSkeletonTextLine(width: 120, height: 16, cornerRadius: 6)
                            Spacer()
                            ShopSkeletonCapsule(width: 75, height: 28)
                        }
                        .padding(.horizontal, 16)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ShopProductCardSkeleton()
                            ShopProductCardSkeleton()
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(24)
                    .padding(.horizontal, 16)

                    // Store 2 Section Skeleton
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ShopSkeletonCircle(size: 32)
                            ShopSkeletonTextLine(width: 140, height: 16, cornerRadius: 6)
                            Spacer()
                            ShopSkeletonCapsule(width: 75, height: 28)
                        }
                        .padding(.horizontal, 16)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ShopProductCardSkeleton()
                            ShopProductCardSkeleton()
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(24)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 120)
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - 4. Search Screen Skeletons (AI Deep Dive & Classic)

struct ShopSearchDeepDiveSkeletonView: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Conversational Header Line
                HStack(spacing: 8) {
                    ShopSkeletonCircle(size: 18)
                    ShopSkeletonTextLine(width: 220, height: 14, cornerRadius: 5)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                // Spotlight Card Skeleton
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ShopSkeletonCapsule(width: 90, height: 22)
                        Spacer()
                    }
                    ShopSkeletonBlock(cornerRadius: 16, height: 140)
                    ShopSkeletonTextLine(height: 14, cornerRadius: 5)
                    ShopSkeletonTextLine(width: 160, height: 12, cornerRadius: 4)
                }
                .padding(16)
                .background(Color.white)
                .cornerRadius(22)
                .padding(.horizontal, 16)

                // Curated Grid Skeleton
                VStack(alignment: .leading, spacing: 10) {
                    ShopSkeletonTextLine(width: 170, height: 15, cornerRadius: 5)
                        .padding(.horizontal, 20)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ShopProductCardSkeleton()
                        ShopProductCardSkeleton()
                        ShopProductCardSkeleton()
                        ShopProductCardSkeleton()
                    }
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 120)
            }
        }
    }
}

struct ShopSearchGridSkeletonView: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                // Filter pills placeholder
                HStack(spacing: 8) {
                    ShopSkeletonCapsule(width: 80, height: 32)
                    ShopSkeletonCapsule(width: 90, height: 32)
                    ShopSkeletonCapsule(width: 75, height: 32)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<6, id: \.self) { _ in
                        ShopProductCardSkeleton()
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 120)
            }
        }
    }
}

// MARK: - 5. Store Detail Screen Skeleton

struct ShopStoreDetailSkeletonView: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Store Banner Placeholder
                ShopSkeletonBlock(cornerRadius: 0, height: 190)

                // Store Avatar + Name + Follow button
                VStack(spacing: 10) {
                    ShopSkeletonCircle(size: 64)
                        .offset(y: -32)
                        .padding(.bottom, -28)

                    ShopSkeletonTextLine(width: 180, height: 20, cornerRadius: 7)
                    ShopSkeletonTextLine(width: 120, height: 13, cornerRadius: 5)

                    HStack(spacing: 12) {
                        ShopSkeletonCapsule(width: 130, height: 40)
                        ShopSkeletonCapsule(width: 50, height: 40)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)

                // Product Grid Skeleton
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<6, id: \.self) { _ in
                        ShopProductCardSkeleton()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer(minLength: 80)
            }
        }
    }
}

// MARK: - 6. Wishlist Screen Skeleton

struct ShopWishlistSkeletonView: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Collections Card Skeleton
                ShopSkeletonBlock(
                    cornerRadius: 22,
                    width: UIScreen.main.bounds.width - 32,
                    height: 120
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)

                // Filter Pills Skeleton
                HStack(spacing: 8) {
                    ShopSkeletonCapsule(width: 70, height: 32)
                    ShopSkeletonCapsule(width: 90, height: 32)
                    ShopSkeletonCapsule(width: 80, height: 32)
                }
                .padding(.horizontal, 16)

                // 2-Column Product Cards
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        ShopProductCardSkeleton()
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 120)
            }
        }
    }
}

// MARK: - 7. Following ("Segui già") Screen Skeleton

struct ShopFollowingSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            // 1. Stories Avatar Row Skeleton
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { _ in
                        ShopSkeletonCircle(size: 62)
                    }
                    ShopSkeletonCircle(size: 62)
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 6)

            // 2. Store 1 Section Skeleton
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 12) {
                    ShopSkeletonCircle(size: 42)
                    VStack(alignment: .leading, spacing: 5) {
                        ShopSkeletonTextLine(width: 140, height: 16, cornerRadius: 6)
                        ShopSkeletonTextLine(width: 190, height: 12, cornerRadius: 4)
                    }
                    Spacer()
                    ShopSkeletonCircle(size: 20)
                }
                .padding(.horizontal, 16)

                // Horizontal Carousel of Products
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(0..<3, id: \.self) { _ in
                            ShopSkeletonBlock(cornerRadius: 18, width: 165, height: 170)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            // 3. Store 2 Section Skeleton
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 12) {
                    ShopSkeletonCircle(size: 42)
                    VStack(alignment: .leading, spacing: 5) {
                        ShopSkeletonTextLine(width: 120, height: 16, cornerRadius: 6)
                        ShopSkeletonTextLine(width: 170, height: 12, cornerRadius: 4)
                    }
                    Spacer()
                    ShopSkeletonCircle(size: 20)
                }
                .padding(.horizontal, 16)

                // Horizontal Carousel of Products
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(0..<3, id: \.self) { _ in
                            ShopSkeletonBlock(cornerRadius: 18, width: 165, height: 170)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}
