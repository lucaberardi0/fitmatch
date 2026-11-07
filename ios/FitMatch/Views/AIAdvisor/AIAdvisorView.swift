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
                    // Header Card in Shop Purple style
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                            Text("Coach IA Biomeccanico")
                                .font(.system(size: 18, weight: .black))
                                .foregroundColor(.white)
                        }

                        Text("Spiegaci le tue esigenze di corsa (peso, terreno, budget, taglia). L'IA deduce i modelli ideali e trova il prezzo più basso tra tutti i negozi partner.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.92))
                    }
                    .padding(18)
                    .background(
                        LinearGradient(
                            colors: [Color.shopPurple, Color.shopDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(20)
                    .padding(.horizontal, 16)

                    // Versus Mode Navigation Card
                    NavigationLink(destination: ModelCompareView()) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.shopPurpleLight)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.shopPurple)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Confronto Modelli (Versus Mode)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.shopDark)
                                Text("Metti a confronto 2 scarpe: drop, peso, mescola e prezzi live.")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .background(Color.white)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.shopBorder, lineWidth: 1))
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)

                    // Sample Quick Prompts
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ESEMPI RAPIDI DI RICHIESTA:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(0.5)
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(samplePrompts, id: \.self) { sample in
                                    Button(action: {
                                        promptText = sample
                                        askAdvisor()
                                    }) {
                                        Text(sample)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 9)
                                            .background(Color(.secondarySystemGroupedBackground))
                                            .cornerRadius(16)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(Color.shopBorder, lineWidth: 1)
                                            )
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
                                .tint(.shopPurple)
                                .scaleEffect(1.2)
                            Text("Analisi biomeccanica e verifica taglie in corso...")
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
                                        .foregroundColor(.shopPurple)
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
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.shopBorder, lineWidth: 1)
                            )

                            // Recommended Models Cards
                            Text("I MODELLI CONSIGLIATI AL MIGLIOR PREZZO:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .tracking(0.5)

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
                                            ShopStoreLogo(storeName: store)
                                        }
                                    }

                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        if let price = rec.best_price {
                                            Text(String(format: "€%.2f", price))
                                                .font(.system(size: 20, weight: .black))
                                                .foregroundColor(.primary)
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
                                            .foregroundColor(.shopPurple)
                                    }

                                    if let link = rec.link, !link.isEmpty {
                                        let outboundUrl = APIService.shared.outboundRedirectURL(
                                            targetUrl: link,
                                            storeId: rec.best_store,
                                            source: "ai_advisor"
                                        )
                                        Link(destination: outboundUrl) {
                                            HStack {
                                                Text("Acquista su \(rec.best_store ?? "Store")")
                                                    .font(.system(size: 13, weight: .bold))
                                                Spacer()
                                                Image(systemName: "arrow.up.right.square")
                                            }
                                            .foregroundColor(.white)
                                            .padding(.vertical, 10)
                                            .padding(.horizontal, 14)
                                            .background(Color.shopPurple)
                                            .cornerRadius(12)
                                        }
                                    }
                                }
                                .padding(16)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.shopBorder, lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Coach IA 🤖")
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom) {
                // Input Bar
                HStack(spacing: 10) {
                    TextField("Chiedi al Coach (es. peso, asfalto, budget)...", text: $promptText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(24)

                    Button(action: askAdvisor) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(promptText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .shopPurple)
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
