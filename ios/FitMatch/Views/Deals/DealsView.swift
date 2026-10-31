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
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Radar Sconti & Offerte")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.shopDark)
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(.orange)
                                Text("LIVE")
                                    .font(.system(size: 10, weight: .black, design: .rounded))
                                    .foregroundColor(.shopPurple)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.shopPurpleLight)
                            .cornerRadius(8)
                        }

                        Text("Maggiori gap di prezzo e risparmi rilevati confrontando i negozi sportivi")
                            .font(.system(size: 13))
                            .foregroundColor(.shopTextMuted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.shopPurple)
                            Text("Analisi sconti in corso...")
                                .font(.system(size: 13))
                                .foregroundColor(.shopTextMuted)
                        }
                        .padding(.vertical, 50)
                    } else if let stats = stats {
                        // Quick Stats Overview Grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            statCard(title: "Prodotti a Catalogo", value: "\(stats.total_products)", icon: "tshirt.fill", color: .shopPurple)
                            statCard(title: "Offerte a Confronto", value: "\(stats.total_offers)", icon: "tag.fill", color: .orange)
                            statCard(title: "Multi-Store Match", value: "\(stats.multi_store_products)", icon: "arrow.triangle.2.circlepath", color: .shopGreen)
                            statCard(title: "Brand Sportivi", value: "\(stats.brands_count)", icon: "sparkles", color: .blue)
                        }
                        .padding(.horizontal, 16)

                        // Top Cross-Store Savings Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(.orange)
                                Text("MAGGIORI RISPARMI TRA NEGOZI")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(.shopTextMuted)
                                    .tracking(0.6)
                            }
                            .padding(.horizontal, 16)

                            VStack(spacing: 12) {
                                ForEach(Array(stats.top_savings.enumerated()), id: \.offset) { index, saving in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text("#\(index + 1)")
                                                .font(.system(size: 13, weight: .black, design: .rounded))
                                                .foregroundColor(.shopPurple)
                                                .frame(width: 28, height: 28)
                                                .background(Color.shopPurpleLight)
                                                .clipShape(Circle())

                                            VStack(alignment: .leading, spacing: 2) {
                                                if let brand = saving.brand {
                                                    Text(brand.uppercased())
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(.shopTextMuted)
                                                }
                                                Text(saving.canonical_name)
                                                    .font(.system(size: 14.5, weight: .bold))
                                                    .foregroundColor(.shopDark)
                                            }

                                            Spacer()

                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text("Risparmio")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.shopTextMuted)
                                                SavingsPill(amountText: "€\(String(format: "%.0f", saving.savings))")
                                            }
                                        }

                                        Divider()

                                        HStack {
                                            Text("Prezzo min: **\(String(format: "€%.2f", saving.min_price))**")
                                                .font(.system(size: 12))
                                                .foregroundColor(.shopGreen)

                                            Spacer()

                                            Text("Max: \(String(format: "€%.2f", saving.max_price))")
                                                .font(.system(size: 12))
                                                .foregroundColor(.shopTextMuted)

                                            Text("(\(saving.store_count) negozi)")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.shopPurple)
                                        }
                                    }
                                    .padding(14)
                                    .background(Color.white)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.shopBorder, lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    } else if let error = errorMessage {
                        VStack(spacing: 12) {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(.shopTextMuted)
                            Button("Riprova") {
                                loadStats()
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.shopPurple)
                        }
                        .padding(.vertical, 40)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.vertical, 8)
            }
            .background(Color.shopSurface.ignoresSafeArea())
            .navigationBarHidden(true)
            .onAppear {
                loadStats()
            }
            .refreshable {
                loadStats()
            }
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                }
                Spacer()
            }
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(.shopDark)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.shopTextMuted)
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.shopBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
    }

    private func loadStats() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let res = try await api.getStats()
                await MainActor.run {
                    self.stats = res
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Impossibile caricare le statistiche. Assicurati che l'API sia in esecuzione su http://127.0.0.1:8000."
                    self.isLoading = false
                }
            }
        }
    }
}
