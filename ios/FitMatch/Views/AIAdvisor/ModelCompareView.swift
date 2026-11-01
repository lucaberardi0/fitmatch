import SwiftUI

struct ModelCompareView: View {
    @StateObject private var api = APIService.shared
    @State private var modelA: String = "Nike Pegasus 41"
    @State private var modelB: String = "Asics Gel Nimbus 26"
    @State private var isLoading: Bool = false
    @State private var comparisonResult: ModelComparisonResponse? = nil
    @State private var errorMessage: String? = nil

    private let quickPresets: [(String, String, String)] = [
        ("Pegasus vs Nimbus", "Nike Pegasus 41", "Asics Gel Nimbus 26"),
        ("Clifton vs Novablast", "Hoka Clifton 9", "Asics Novablast 4"),
        ("Alphafly vs Vaporfly", "Nike Alphafly 3", "Nike Vaporfly 3"),
        ("Garmin 165 vs 265", "Garmin Forerunner 165", "Garmin Forerunner 265")
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // MARK: - Header
                    headerCard

                    // MARK: - Quick Presets
                    presetChips

                    // MARK: - Input Selectors
                    inputSection

                    // MARK: - Compare Button
                    compareButton

                    // MARK: - Loading State
                    if isLoading {
                        loadingSection
                    }

                    // MARK: - Error Message
                    if let err = errorMessage {
                        errorCard(err)
                    }

                    // MARK: - Comparison Content
                    if let comp = comparisonResult {
                        comparisonDetails(comp)
                    }

                    Spacer(minLength: 60)
                }
                .padding(.vertical, 16)
            }
            .background(Color(red: 247/255, green: 247/255, blue: 250/255).ignoresSafeArea())
            .navigationTitle("Confronto Modelli IA")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Subviews

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Text("Confronto Tecnico & Prezzi")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }

            Text("Metti a confronto due modelli di scarpe o smartwatch. L'IA analizza drop, mescola, peso e podista ideale, trovando il prezzo più basso live nei 10 store partner.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.92))
                .lineSpacing(2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.shopPurple, Color(red: 30/255, green: 20/255, blue: 50/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
        .shadow(color: Color.shopPurple.opacity(0.2), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
    }

    private var presetChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONFRONTI POPOLARI:")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.6)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickPresets, id: \.0) { preset in
                        Button(action: {
                            modelA = preset.1
                            modelB = preset.2
                            runComparison()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                                Text(preset.0)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.shopBorder, lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var inputSection: some View {
        VStack(spacing: 12) {
            // Model A Input
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.shopPurple)
                    .frame(width: 24, height: 24)
                    .overlay(Text("A").font(.system(size: 12, weight: .black)).foregroundColor(.white))

                TextField("Modello A (es. Nike Pegasus 41)", text: $modelA)
                    .font(.system(size: 14, weight: .medium))

                if !modelA.isEmpty {
                    Button(action: { modelA = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.shopBorder, lineWidth: 1))

            // Model B Input
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)
                    .overlay(Text("B").font(.system(size: 12, weight: .black)).foregroundColor(.white))

                TextField("Modello B (es. Asics Gel Nimbus 26)", text: $modelB)
                    .font(.system(size: 14, weight: .medium))

                if !modelB.isEmpty {
                    Button(action: { modelB = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.shopBorder, lineWidth: 1))
        }
        .padding(.horizontal, 16)
    }

    private var compareButton: some View {
        Button(action: runComparison) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                    Text("Avvia Confronto Biomeccanico")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(modelA.isEmpty || modelB.isEmpty || isLoading ? Color.gray : Color.shopPurple)
            .cornerRadius(25)
            .shadow(color: Color.shopPurple.opacity(0.3), radius: 8, x: 0, y: 3)
        }
        .disabled(modelA.isEmpty || modelB.isEmpty || isLoading)
        .padding(.horizontal, 16)
    }

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.shopPurple)
                .scaleEffect(1.2)
            Text("Analisi tecnica mescole e ricerca prezzi nei 10 negozi in corso...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 20)
    }

    private func errorCard(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.red)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    // MARK: - Comparison Details

    @ViewBuilder
    private func comparisonDetails(_ comp: ModelComparisonResponse) -> some View {
        VStack(spacing: 18) {
            // 1. Verdict & Value Winner Banner
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                    Text("VERDETTO IA & MIGLIOR VALORE")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.shopPurple)
                        .tracking(0.6)
                }

                if let delta = comp.price_delta, delta > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.shopGreen)
                        Text("Miglior Prezzo: \(comp.winner_for_value)")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(.shopDark)
                    }
                    .padding(10)
                    .background(Color.shopGreenLight)
                    .cornerRadius(10)
                }

                Text(comp.verdict_summary)
                    .font(.system(size: 13.5))
                    .foregroundColor(.shopDark)
                    .lineSpacing(3)

                if !comp.winner_for_performance.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("**Scelta Performance:** \(comp.winner_for_performance)")
                            .font(.system(size: 12.5))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 16)

            // 2. Side-by-Side Key Spec Cards
            HStack(alignment: .top, spacing: 12) {
                modelColumnCard(
                    title: comp.model_a_specs.name,
                    brand: comp.model_a_specs.brand,
                    price: comp.model_a_market.formattedBestPrice,
                    store: comp.model_a_market.best_store,
                    specs: comp.model_a_specs,
                    color: .shopPurple
                )

                modelColumnCard(
                    title: comp.model_b_specs.name,
                    brand: comp.model_b_specs.brand,
                    price: comp.model_b_market.formattedBestPrice,
                    store: comp.model_b_market.best_store,
                    specs: comp.model_b_specs,
                    color: .blue
                )
            }
            .padding(.horizontal, 16)

            // 3. Key Technical Differences
            if !comp.key_differences.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("DIFFERENZE CHIAVE IN SINTESI")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.secondary)
                        .tracking(0.6)

                    ForEach(comp.key_differences, id: \.self) { diff in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.shopPurple)
                                .padding(.top, 2)
                            Text(diff)
                                .font(.system(size: 13))
                                .foregroundColor(.shopDark)
                                .lineSpacing(2)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .cornerRadius(18)
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
                .padding(.horizontal, 16)
            }

            // 4. Live Store Offers Section for Model A
            if !comp.model_a_market.top_offers.isEmpty {
                offersCard(modelName: comp.model_a_specs.name, offers: comp.model_a_market.top_offers)
            }

            // 5. Live Store Offers Section for Model B
            if !comp.model_b_market.top_offers.isEmpty {
                offersCard(modelName: comp.model_b_specs.name, offers: comp.model_b_market.top_offers)
            }
        }
    }

    private func modelColumnCard(
        title: String,
        brand: String?,
        price: String,
        store: String?,
        specs: ModelSpecs,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let b = brand {
                    Text(b.uppercased())
                        .font(.system(size: 9.5, weight: .black))
                        .foregroundColor(color)
                        .tracking(0.5)
                }
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Pricing Block
            VStack(alignment: .leading, spacing: 2) {
                Text(price)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundColor(.shopDark)
                if let st = store {
                    Text("su \(st)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)

            Divider()

            // Technical Specs Stack
            specRow(label: "Drop", value: specs.drop_mm != nil ? "\(specs.drop_mm!) mm" : "N/D")
            specRow(label: "Peso", value: specs.weight_g != nil ? "\(specs.weight_g!) g" : "N/D")
            specRow(label: "Ammortizzamento", value: specs.cushioning ?? "N/D")
            specRow(label: "Intersuola", value: specs.midsole ?? "N/D")
            specRow(label: "Piastra", value: specs.plate ?? "Nessuna")
            specRow(label: "Utilizzo", value: specs.ideal_use ?? "N/D")

            Divider()

            // Pros
            if !specs.pros.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PRO:")
                        .font(.system(size: 9.5, weight: .black))
                        .foregroundColor(.shopGreen)
                    ForEach(specs.pros.prefix(2), id: \.self) { pro in
                        Text("• " + pro)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(color.opacity(0.2), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    private func specRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .black))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.shopDark)
                .lineLimit(2)
        }
    }

    private func offersCard(modelName: String, offers: [StoreOfferBrief]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OFFERTE NEGOZI PER \(modelName.uppercased())")
                .font(.system(size: 10.5, weight: .black))
                .foregroundColor(.secondary)
                .tracking(0.6)

            ForEach(offers, id: \.url) { off in
                if let u = URL(string: off.url) {
                    Link(destination: u) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(off.store_name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.shopDark)
                                Text(off.is_free_shipping ? "Spedizione gratis" : "Totale \(String(format: "€%.2f", off.total_price))")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(off.is_free_shipping ? .shopGreen : .secondary)
                            }
                            Spacer()
                            Text(off.formattedPrice)
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundColor(.shopDark)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.shopPurple)
                        }
                        .padding(12)
                        .background(Color(red: 248/255, green: 248/255, blue: 251/255))
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    private func runComparison() {
        guard !modelA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !modelB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let res = try await api.compareModels(modelA: modelA, modelB: modelB)
                await MainActor.run {
                    self.comparisonResult = res
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Impossibile completare il confronto: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}
