import SwiftUI

struct HomeView: View {
    @StateObject private var api = APIService.shared
    @State private var searchText = "Nike Pegasus"
    @State private var selectedSize: String? = nil
    @State private var products: [MatchedProduct] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    private let availableSizes = ["Tutte", "40", "41", "42", "42.5", "43", "44", "44.5", "45", "46"]
    private let quickSearches = ["Nike Pegasus", "Hoka Bondi", "Asics Nimbus", "Brooks Ghost", "Trail GTX"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Quick Suggestions
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickSearches, id: \.self) { term in
                                Button(action: {
                                    searchText = term
                                    performSearch()
                                }) {
                                    Text(term)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(searchText == term ? .white : .primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(searchText == term ? Color.blue : Color(.systemGray6))
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Size Filter Bar
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "ruler")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Text("Filtra per Taglia (in stock)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
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

                    // Content State
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Confronto prezzi in corso su Cisalfa, Maxi Sport, Mister Running e Nencini...")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else if let error = errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Riprova") {
                                performSearch()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 40)
                    } else if products.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Nessuna offerta trovata")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Prova a cambiare parola chiave o taglia selezionata.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 60)
                    } else {
                        // Product Cards Grid
                        LazyVStack(spacing: 14) {
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
                .padding(.vertical, 12)
            }
            .navigationTitle("FitMatch 🏃")
            .searchable(text: $searchText, prompt: "Cerca modello (es. Pegasus, Bondi...)")
            .onSubmit(of: .search) {
                performSearch()
            }
            .refreshable {
                performSearch()
            }
            .background(Color(.systemGroupedBackground))
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
                self.errorMessage = "Impossibile contattare il server locale (127.0.0.1:8000). Assicurati che 'python3 api.py' sia attivo."
                self.isLoading = false
            }
        }
    }
}
