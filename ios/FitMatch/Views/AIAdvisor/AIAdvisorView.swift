import SwiftUI

struct AIAdvisorView: View {
    @StateObject private var api = APIService.shared
    @State private var promptText = ""
    @State private var isLoading = false
    @State private var currentAdvice: AIAdviceResponse? = nil
    @State private var errorMessage: String? = nil

    private let samplePrompts = [
        "Peso 85kg corro su asfalto cerco scarpe ammortizzate sotto i 140€",
        "Porto il 43, scarpe veloci e reattive per mezza maratona sotto i 130€",
        "Scarpe da trail running impermeabili per sentieri bagnati da donna"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.yellow)
                            Text("Coach IA di Shopping")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }

                        Text("Descrivi come corri, il tuo peso, i tuoi obiettivi o il tuo budget. L'IA analizzerà il tuo profilo biomeccanico e troverà le offerte migliori tra tutti i negozi.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(16)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
                    .padding(.horizontal, 16)

                    // Sample Quick Prompts
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PROVA UNO DI QUESTI ESEMPI:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(samplePrompts, id: \.self) { sample in
                                    Button(action: {
                                        promptText = sample
                                        askAdvisor()
                                    }) {
                                        Text(sample)
                                            .font(.system(size: 12))
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color(.secondarySystemGroupedBackground))
                                            .cornerRadius(12)
                                            .shadow(color: Color.black.opacity(0.04), radius: 3)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // Loading State
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Analisi biomeccanica e scansione negozi in corso...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 40)
                    }

                    // Error Message
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .padding()
                    }

                    // Advice Content
                    if let advice = currentAdvice {
                        VStack(alignment: .leading, spacing: 16) {
                            // Category & Biomechanics Card
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "figure.run.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)
                                    Text(advice.category_name)
                                        .font(.system(size: 16, weight: .bold))
                                }

                                Text(advice.biomechanical_reasoning)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                    .lineSpacing(4)
                            }
                            .padding(16)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(14)

                            // Recommended Models Cards
                            Text("I Modelli Consigliati al Miglior Prezzo:")
                                .font(.system(size: 16, weight: .bold))

                            ForEach(advice.recommendations) { rec in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            if let b = rec.brand {
                                                Text(b.uppercased())
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.secondary)
                                            }
                                            Text(rec.product_name)
                                                .font(.system(size: 16, weight: .bold))
                                        }
                                        Spacer()
                                        if let store = rec.best_store {
                                            StoreBadge(storeName: store)
                                        }
                                    }

                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        if let price = rec.best_price {
                                            Text(String(format: "€%.2f", price))
                                                .font(.system(size: 20, weight: .heavy))
                                                .foregroundColor(.green)
                                        }
                                        if let orig = rec.original_price, let p = rec.best_price, orig > p {
                                            Text(String(format: "€%.2f", orig))
                                                .font(.system(size: 13))
                                                .strikethrough()
                                                .foregroundColor(.secondary)
                                        }
                                        if let disc = rec.discount_pct, disc > 0 {
                                            DiscountBadge(discountText: String(format: "-%.0f%%", disc))
                                        }
                                    }

                                    if let savings = rec.cross_store_savings, savings > 1.0 {
                                        Text("✓ Risparmi fino a \(String(format: "€%.2f", savings)) confrontando i negozi!")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.green)
                                    }

                                    if let link = rec.link, let url = URL(string: link) {
                                        Link(destination: url) {
                                            HStack {
                                                Text("Vedi offerta su \(rec.best_store ?? "Store")")
                                                    .font(.system(size: 13, weight: .bold))
                                                Spacer()
                                                Image(systemName: "arrow.up.right.square")
                                            }
                                            .foregroundColor(.white)
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 12)
                                            .background(Color.green)
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                                .padding(14)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(14)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Assistente IA 🤖")
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                // Input Bar
                HStack(spacing: 8) {
                    TextField("Descrivi cosa cerchi (es. peso, budget, taglia)...", text: $promptText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(20)

                    Button(action: askAdvisor) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(promptText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
                    }
                    .disabled(promptText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func askAdvisor() {
        guard !promptText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let advice = try await api.getAIAdvice(prompt: promptText)
                self.currentAdvice = advice
                self.isLoading = false
            } catch {
                self.errorMessage = "Errore di connessione. Assicurati che 'python3 api.py' sia attivo."
                self.isLoading = false
            }
        }
    }
}
