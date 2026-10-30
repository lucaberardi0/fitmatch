import SwiftUI

struct DealsView: View {
    @StateObject private var api = APIService.shared
    @State private var stats: CatalogStatsResponse? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        ProgressView()
                            .padding(.vertical, 40)
                    } else if let stats = stats {
                        // Quick Stats Overview Grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            statCard(title: "Prodotti a Catalogo", value: "\(stats.total_products)", icon: "tshirt.fill", color: .blue)
                            statCard(title: "Offerte a Confronto", value: "\(stats.total_offers)", icon: "tag.fill", color: .purple)
                            statCard(title: "Multi-Store Match", value: "\(stats.multi_store_products)", icon: "arrow.triangle.2.circlepath", color: .green)
                            statCard(title: "Brand Sportivi", value: "\(stats.brands_count)", icon: "sparkles", color: .orange)
                        }
                        .padding(.horizontal, 16)

                        // Top Cross-Store Savings Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(.red)
                                Text("Maggiori Risparmi tra Negozi")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .padding(.horizontal, 16)

                            VStack(spacing: 12) {
                                ForEach(Array(stats.top_savings.enumerated()), id: \.offset) { index, saving in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("#\(index + 1)")
                                                .font(.system(size: 14, weight: .black))
                                                .foregroundColor(.blue)

                                            VStack(alignment: .leading, spacing: 2) {
                                                if let brand = saving.brand {
                                                    Text(brand.uppercased())
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(.secondary)
                                                }
                                                Text(saving.canonical_name)
                                                    .font(.system(size: 15, weight: .bold))
                                            }

                                            Spacer()

                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text("Risparmio")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.secondary)
                                                Text(String(format: "€%.2f", saving.savings))
                                                    .font(.system(size: 16, weight: .heavy))
                                                    .foregroundColor(.green)
                                            }
                                        }

                                        Divider()

                                        HStack {
                                            Text("Prezzo min: \(String(format: "€%.2f", saving.min_price))")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.green)

                                            Spacer()

                                            Text("Prezzo max: \(String(format: "€%.2f", saving.max_price))")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)

                                            Text("(\(saving.store_count) negozi)")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(14)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(14)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    } else if let error = errorMessage {
                        VStack(spacing: 12) {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Button("Riprova") {
                                loadStats()
                            }
                        }
                        .padding(.vertical, 40)
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Top Risparmi 🔥")
            .background(Color(.systemGroupedBackground))
            .onAppear {
                loadStats()
            }
            .refreshable {
                loadStats()
            }
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 22, weight: .heavy))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    private func loadStats() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let res = try await api.getStats()
                self.stats = res
                self.isLoading = false
            } catch {
                self.errorMessage = "Impossibile caricare le statistiche. Assicurati che l'API sia in esecuzione su http://127.0.0.1:8000."
                self.isLoading = false
            }
        }
    }
}
