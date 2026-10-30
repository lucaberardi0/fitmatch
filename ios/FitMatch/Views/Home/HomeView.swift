import SwiftUI

struct HomeView: View {
    @StateObject private var api = APIService.shared
    @State private var searchText = "Nike Pegasus"
    @State private var selectedSize: String? = nil
    @State private var products: [MatchedProduct] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    private let availableSizes = ["Tutte", "40", "41", "42", "42.5", "43", "44", "44.5", "45", "46"]
    private let quickSearches = ["Tutti", "Nike Pegasus", "Hoka Bondi", "Asics Nimbus", "Brooks Ghost", "Trail GTX"]
    private let partnerStores = [
        ("Cisalfa Sport", Color.red, "CS"),
        ("Maxi Sport", Color.orange, "MS"),
        ("Mister Running", Color.blue, "MR"),
        ("Nencini Sport", Color(red: 0, green: 0.55, blue: 0.3), "NS")
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Top Shop-style Header & Brand Row
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shop")
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundColor(.shopDark)
                            + Text(" by FitMatch")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.shopPurple)
                        }

                        Spacer()

                        Circle()
                            .fill(Color(.systemGray6))
                            .frame(width: 38, height: 38)
                            .overlay(
                                Image(systemName: "bell")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                            )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    // Shop Search Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)

                        TextField("Cerca modelli, brand o sport...", text: $searchText)
                            .font(.system(size: 15))
                            .onSubmit {
                                performSearch()
                            }

                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6).opacity(0.8))
                    .cornerRadius(24)
                    .padding(.horizontal, 16)

                    // Partner Stores Horizontal Carousel
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NEGOZI PARTNER VERIFICATI")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(0.5)
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(partnerStores, id: \.0) { store in
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(store.1)
                                            .frame(width: 26, height: 26)
                                            .overlay(
                                                Text(store.2)
                                                    .font(.system(size: 10, weight: .black))
                                                    .foregroundColor(.white)
                                            )

                                        Text(store.0)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.primary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.shopBorder, lineWidth: 1)
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // Size Filter Bar
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("TAGLIE IN STOCK")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .tracking(0.5)
                            Spacer()
                            if selectedSize != nil {
                                Button("Azzera") {
                                    selectedSize = nil
                                    performSearch()
                                }
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.shopPurple)
                            }
                        }
                        .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(availableSizes, id: \.self) { sz in
                                    let isSelected = (sz == "Tutte" && selectedSize == nil) || (selectedSize == sz)
                                    Button(action: {
                                        selectedSize = (sz == "Tutte") ? nil : sz
                                        performSearch()
                                    }) {
                                        SizeChip(size: sz, isSelected: isSelected)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // Quick Search Category Tags
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickSearches, id: \.self) { term in
                                let isSelected = (term == "Tutti" && searchText.isEmpty) || (searchText == term)
                                Button(action: {
                                    searchText = (term == "Tutti") ? "running" : term
                                    performSearch()
                                }) {
                                    Text(term)
                                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(isSelected ? Color.shopPurple : Color(.systemGray6))
                                        .cornerRadius(18)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Feed Section
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.shopPurple)
                                .scaleEffect(1.2)
                            Text("Cerco il prezzo più basso sui 4 store...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else if let error = errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 36))
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Riprova") {
                                performSearch()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.shopPurple)
                        }
                        .padding(20)
                    } else if products.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("Nessuna offerta trovata")
                                .font(.system(size: 16, weight: .bold))
                            Text("Prova a cercare un altro modello o a cambiare taglia.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        // 2-Column Product Grid (Shopify "Shop" layout)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("\(products.count) PRODOTTI TROVATI")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .tracking(0.5)

                                Spacer()

                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .font(.system(size: 11))
                                    Text("Miglior Prezzo")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundColor(.shopPurple)
                            }
                            .padding(.horizontal, 16)

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(products) { product in
                                    NavigationLink(destination: ProductDetailView(product: product)) {
                                        ProductCardView(product: product)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                performSearch()
            }
            .onAppear {
                if products.isEmpty {
                    performSearch()
                }
            }
        }
    }

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let results = try await api.search(query: searchText, size: selectedSize)
                self.products = results
                self.isLoading = false
            } catch {
                self.errorMessage = "Impossibile collegarsi al backend. Assicurati che api.py sia attivo."
                self.isLoading = false
            }
        }
    }
}
