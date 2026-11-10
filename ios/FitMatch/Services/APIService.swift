import Foundation

@MainActor
class APIService: ObservableObject {
    static let shared = APIService()

    // Production Cloud Backend hosted on Render (Frankfurt, Docker)
    @Published var baseURL = "https://fitmatch-backend-klhv.onrender.com"
    @Published var isCloudOnline: Bool = true

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        // 60-second timeout to handle Render cold-start spins gracefully
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)

        #if targetEnvironment(simulator)
        // Auto-switch to local server if running locally during active simulator development
        Task {
            if let localUrl = URL(string: "http://127.0.0.1:8000/health") {
                if let (_, response) = try? await URLSession.shared.data(from: localUrl),
                   (response as? HTTPURLResponse)?.statusCode == 200 {
                    await MainActor.run {
                        self.baseURL = "http://127.0.0.1:8000"
                        self.isCloudOnline = true
                    }
                }
            }
        }
        #endif
    }

    /// Verifies live connectivity with the Render cloud backend
    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                self.isCloudOnline = true
                return true
            }
        } catch {
            self.isCloudOnline = false
        }
        return false
    }

    /// Robust HTTP fetch with automatic retry to gracefully handle Render cold-starts or redeploy cutovers
    private func fetchDataWithRetry(url: URL, maxRetries: Int = 2) async throws -> Data {
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse {
                    if (200...299).contains(http.statusCode) {
                        return data
                    } else if [502, 503, 504].contains(http.statusCode) && attempt < maxRetries {
                        // Render waking up or deploying: wait and retry
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        continue
                    }
                }
                throw URLError(.badServerResponse)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                }
            }
        }

        #if targetEnvironment(simulator)
        if (lastError as? URLError)?.code == .badServerResponse && !url.absoluteString.contains("127.0.0.1") {
            let localString = url.absoluteString.replacingOccurrences(of: baseURL, with: "http://127.0.0.1:8000")
            if let localUrl = URL(string: localString),
               let (data, response) = try? await session.data(from: localUrl),
               let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return data
            }
        }
        #endif

        throw lastError ?? URLError(.unknown)
    }

    func search(query: String, size: String? = nil) async throws -> [MatchedProduct] {
        var components = URLComponents(string: "\(baseURL)/api/search")!
        var queryItems = [URLQueryItem(name: "q", value: query)]
        if let size = size, !size.isEmpty {
            queryItems.append(URLQueryItem(name: "size", value: size))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw URLError(.badURL) }

        do {
            let data = try await fetchDataWithRetry(url: url)
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            return decoded.matched_products
        } catch {
            let direct = await SupabaseManager.shared.fetchSmartProductsDirect(
                category: nil,
                keywords: [query],
                size: size,
                limit: 30
            )
            if !direct.isEmpty {
                return direct
            }
            throw error
        }
    }

    func fetchPriceHistory(canonicalName: String, productId: String? = nil, days: Int = 90) async throws -> PriceHistoryResponse {
        var components = URLComponents(string: "\(baseURL)/api/products/price-history")!
        var queryItems = [
            URLQueryItem(name: "canonical_name", value: canonicalName),
            URLQueryItem(name: "days", value: "\(days)")
        ]
        if let pid = productId, !pid.isEmpty {
            queryItems.append(URLQueryItem(name: "product_id", value: pid))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }

        let data = try await fetchDataWithRetry(url: url)
        return try JSONDecoder().decode(PriceHistoryResponse.self, from: data)
    }

    func smartSearch(
        query: String,
        mode: String? = nil,
        maxPrice: Double? = nil,
        size: String? = nil,
        category: String? = nil,
        store: String? = nil,
        contextQuery: String? = nil
    ) async throws -> SmartSearchResponse {
        var components = URLComponents(string: "\(baseURL)/api/search/smart")!
        var queryItems = [URLQueryItem(name: "q", value: query)]
        if let mode = mode {
            queryItems.append(URLQueryItem(name: "mode", value: mode))
        }
        if let maxPrice = maxPrice {
            queryItems.append(URLQueryItem(name: "max_price", value: "\(maxPrice)"))
        }
        if let size = size, !size.isEmpty && size != "Tutte" {
            queryItems.append(URLQueryItem(name: "size", value: size))
        }
        if let category = category, !category.isEmpty && category != "all" && category != "tutti" {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        if let store = store, !store.isEmpty && store != "Tutti" {
            queryItems.append(URLQueryItem(name: "store", value: store))
        }
        if let contextQuery = contextQuery, !contextQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "context_query", value: contextQuery))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }

        do {
            let data = try await fetchDataWithRetry(url: url)
            let decoded = try JSONDecoder().decode(SmartSearchResponse.self, from: data)
            return await validateAndEnrichSmartSearchResponse(
                decoded,
                query: query,
                contextQuery: contextQuery,
                maxPrice: maxPrice,
                size: size,
                store: store
            )
        } catch {
            // High-Availability Fallback: if Render backend is sleeping (cold start), deploying, or experiencing high load,
            // query Supabase Cloud directly so user gets instantaneous real products instead of an error view!
            if let directFallback = await buildDirectSmartSearchFallback(
                query: query,
                category: category,
                maxPrice: maxPrice,
                size: size,
                store: store
            ) {
                return directFallback
            }
            throw error
        }
    }

    /// Autonomous client-side fallback building a rich SmartSearchResponse directly from Supabase Cloud
    func buildDirectSmartSearchFallback(
        query: String,
        category: String? = nil,
        maxPrice: Double? = nil,
        size: String? = nil,
        store: String? = nil
    ) async -> SmartSearchResponse? {
        let prods = await SupabaseManager.shared.fetchSmartProductsDirect(
            category: category,
            keywords: [query],
            brand: nil,
            maxPrice: maxPrice,
            size: size,
            store: store,
            limit: 35
        )
        guard !prods.isEmpty else { return nil }

        let topProd = prods.first!
        let sections = [
            CuratedProductSection(
                id: "sec_cloud_results",
                title: "Migliori Risultati Trovati",
                subtitle: "Offerte e disponibilità verificate in tempo reale sul catalogo FitMatch Cloud.",
                products: prods
            )
        ]

        var compCards: [ComparativeSpecCard] = []
        for p in prods.prefix(3) {
            let strength: String
            if p.offers.count > 1, let sav = p.cross_store_savings, sav > 0 {
                strength = "Confrontato in \(p.offers.count) store (risparmi € \(Int(sav)))"
            } else {
                strength = String(format: "Miglior prezzo verificato a € %.2f", p.best_price ?? 0)
            }
            compCards.append(ComparativeSpecCard(
                product: p,
                model_name: p.canonical_name,
                ideal_for: compCards.isEmpty ? "Miglior rapporto qualità/prezzo" : "Alternativa tecnica \(p.brand ?? "")".trimmingCharacters(in: .whitespaces),
                strengths: strength,
                section_title: "Confronto rapido"
            ))
        }

        let spotlight = SpotlightRecommendation(
            product: topProd,
            badge_text: (topProd.cross_store_savings ?? 0) > 10 ? "Miglior Risparmio" : "Miglior Scelta",
            highlights: [
                String(format: "Miglior offerta a partire da € %.2f", topProd.best_price ?? 0),
                topProd.offers.count > 1 ? "Confrontato tra \(topProd.offers.count) negozi specializzati" : "Disponibilità immediata verificata",
                "Spedizione e prezzi aggiornati in tempo reale"
            ]
        )

        return SmartSearchResponse(
            search_mode: "deep_dive",
            is_deep_dive: true,
            conversational_header: "Ho cercato \(query)",
            conversational_summary: "Ecco i modelli trovati per la tua ricerca:",
            curated_sections: sections,
            comparative_cards: compCards,
            spotlight: spotlight,
            follow_up_suggestions: [
                "Mostrami solo le offerte con spedizione gratuita",
                "Filtra per prezzo più basso"
            ],
            intent: SmartSearchIntent(
                raw_query: query,
                search_mode: "deep_dive",
                is_deep_dive: true,
                target_keywords: [query],
                brand: topProd.brand,
                category: category ?? "shoes",
                gender: nil,
                max_price: maxPrice,
                min_price: nil,
                size: size,
                features: nil,
                explanation: nil,
                source: "supabase_direct",
                is_off_topic: false,
                is_unsafe: false
            ),
            chips: [],
            total_found: prods.count,
            results: prods,
            is_off_topic: false,
            is_unsafe: false
        )
    }

    // MARK: - Client-Side Intent Alignment & Product Relevance Guardrail

    private enum DetectedQueryKind {
        case gpsWatch
        case bikeComputer
        case eyewear
        case hydration
        case padelRacket
        case socks
        case jacket
        case pants
        case top
        case shoes
    }

    private func detectExpectedQueryKind(query: String, contextQuery: String?, summary: String?) -> DetectedQueryKind? {
        let q = "\(query) \(contextQuery ?? "")".lowercased()
        if q.range(of: #"\b(ciclocomputer|bike\s*computer|contachilometri|contatore\s*bici|garmin\s*edge|wahoo\s*elemnt|bryton|igpsport)\b"#, options: .regularExpression) != nil {
            return .bikeComputer
        }
        if q.range(of: #"\b(orologi[o]?|smartwatch|sportwatch|forerunner|fenix|instinct|epix|venu|vivoactive|coros|suunto|polar\s*(?:vantage|pacer|grit)|garmin)\b"#, options: .regularExpression) != nil {
            return .gpsWatch
        }
        if q.range(of: #"\b(occhial[ie]|oakley|sutro|radar\s*ev|jawbreaker)\b"#, options: .regularExpression) != nil {
            return .eyewear
        }
        if q.range(of: #"\b(zain[oi]|gilet\s*(?:idratazione|trail)|active\s*skin|adv\s*skin|borracc(?:ia|e)|soft\s*flask|camelbak)\b"#, options: .regularExpression) != nil {
            return .hydration
        }
        if q.range(of: #"\b(racchett[ae]|pala\s*padel|bullpadel|nox\s*at10|padel)\b"#, options: .regularExpression) != nil && !q.contains("scarp") {
            return .padelRacket
        }
        if q.range(of: #"\b(calz[ae]|calzin[oi]|calzetton[ei]|socks?)\b"#, options: .regularExpression) != nil {
            return .socks
        }
        if q.range(of: #"\b(giacc(?:a|he)|antivento|windbreaker|k[\s-]*way)\b"#, options: .regularExpression) != nil {
            return .jacket
        }
        if q.range(of: #"\b(pantaloncin[oi]|shorts?|leggings?|tights?|pantalon[ie])\b"#, options: .regularExpression) != nil {
            return .pants
        }
        if q.range(of: #"\b(magli[ae]|t[\s-]*shirt|long\s*sleeve|manic(?:a|he)|canott[ae]|singlet)\b"#, options: .regularExpression) != nil {
            return .top
        }
        if q.range(of: #"\b(scarp[ae]|sneakers?|running|corsa|maratona|trail|palestra|hyrox|ammortizzat[ae]|pegasus|vomero|vaporfly|alphafly|nimbus|clifton|bondi|ghost|glycerin|adizero|dropset|metcon)\b"#, options: .regularExpression) != nil {
            return .shoes
        }
        return nil
    }

    private func isProductCompatible(_ product: MatchedProduct, with kind: DetectedQueryKind) -> Bool {
        let name = product.canonical_name.lowercased()
        let brand = (product.brand ?? "").lowercased()
        let offerTitles = product.offers.prefix(3).map { $0.title.lowercased() }.joined(separator: " ")
        let fullText = "\(name) \(brand) \(offerTitles)"
        let bestPrice = product.best_price ?? product.offers.first?.price ?? 0.0

        // Global junk filter (screen protectors, used items)
        if fullText.range(of: #"\b(panzerglass|vetro\s*temp[ea]?rato|pellicol[ae]|idrogel|hydrogel|screen\s*protector|sportenzia|second\s*hand)\b"#, options: .regularExpression) != nil {
            return false
        }

        switch kind {
        case .gpsWatch:
            if fullText.range(of: #"\b(igpsport|bsc100|bsc200|bsc300|igs\d+|ciclocomputer|bike\s*computer|contachilometri|contatore|garmin\s*edge|\bedge\s*(?:530|540|830|840|1030|1040|explore)\b|bryton|wahoo\s*elemnt|supporto|staff[ae]|mount|cinturin[oi]|strap|bracelet|quickfit|custodi[ae]|cover|felp[ae]|pile\b|cardigan|polo\b|scarp[ae])\b"#, options: .regularExpression) != nil {
                return false
            }
            if bestPrice > 0 && bestPrice < 55 { return false }
            return fullText.range(of: #"\b(garmin|forerunner|fenix|instinct|epix|venu|vivoactive|polar|vantage|pacer|grit|ignite|suunto|coros|pace|apex|vertix|amazfit|orologi[o]?|smartwatch)\b"#, options: .regularExpression) != nil

        case .bikeComputer:
            if fullText.range(of: #"\b(supporto|staff[ae]|mount|custodi[ae]|cover|cinturin[oi]|forerunner|fenix|instinct|venu|scarp[ae])\b"#, options: .regularExpression) != nil {
                return false
            }
            if bestPrice > 0 && bestPrice < 38 { return false }
            return fullText.range(of: #"\b(edge|ciclocomputer|bike\s*computer|contachilometri|contatore|igpsport|bsc|bryton|wahoo\s*elemnt)\b"#, options: .regularExpression) != nil

        case .eyewear:
            if name.hasPrefix("oakley lenti ") || name.hasPrefix("rudy project lenti ") || fullText.range(of: #"\b(lenti\s*occhiali|lente\s*di\s*ricambio|replacement\s*lens|custodi[ae]|scarp[ae])\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(occhial[ie]|oakley|sutro|radar|jawbreaker|bliz|rudy|smith|sunglasses)\b"#, options: .regularExpression) != nil

        case .hydration:
            if fullText.range(of: #"\b(scarp[ae]|magli[ae]|pantaloncin[oi]|orologi[o]?)\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(zain[oi]|gilet|active\s*skin|adv\s*skin|sense\s*pro|borracc|flask|camelbak|idratazione)\b"#, options: .regularExpression) != nil

        case .padelRacket:
            if fullText.range(of: #"\b(scarp[ae]|magli[ae]|pantaloncin[oi]|pallin[ae]|tubo|overgrip|\bgrip\b|hesacore|ammortizzator|vibe\b|bors[ae]|zain[oi]|occhial[ie]|pit\s*viper|skysurfer)\b"#, options: .regularExpression) != nil {
                return false
            }
            if bestPrice > 0 && bestPrice < 38 { return false }
            return fullText.range(of: #"\b(bullpadel|nox|babolat|head|siux|starvie|kuikma|metalbone|adipower|racchett[ae]|pala|vertex|hack|at10)\b"#, options: .regularExpression) != nil

        case .socks:
            if fullText.range(of: #"\b(scarp[ae]|ghost|pegasus|nimbus|clifton|bondi|magli[ae]|pantaloncin[oi]|orologi[o]?)\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(calz[ae]|calzin[oi]|calzetton[ei]|socks?)\b"#, options: .regularExpression) != nil

        case .jacket:
            return fullText.range(of: #"\b(giacc(?:a|he)|jacket|antivento|windbreaker|k[\s-]*way|gilet|guscio|impermeabil[ei])\b"#, options: .regularExpression) != nil

        case .pants:
            return fullText.range(of: #"\b(pantaloncin[oi]|shorts?|leggings?|tights?|pantalon[ie]|fuseaux|sprinter)\b"#, options: .regularExpression) != nil

        case .top:
            if fullText.range(of: #"\b(scarp[ae]|pantaloncin[oi]|shorts?|leggings|calz[ae]|orologi[o]?|zain[oi])\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(magli[ae]|magliett[ae]|t[\s-]*shirt|long\s*sleeve|manic(?:a|he)|canott[ae]|singlet|top|half\s*zip)\b"#, options: .regularExpression) != nil

        case .shoes:
            if fullText.range(of: #"\b(orologi[o]?|smartwatch|garmin|polar|suunto|coros|igpsport|bsc100|bsc200|ciclocomputer|bike\s*computer|contatore|magli[ae]|t[\s-]*shirt|long\s*sleeve|manic(?:a|he)|pantaloncin[oi]|shorts?|giacc(?:a|he)|calz[ae]|calzin[oi]|zain[oi]|borracc|occhial[ie]|racchett[ae])\b"#, options: .regularExpression) != nil {
                return false
            }
            return true
        }
    }

    private func validateAndEnrichSmartSearchResponse(
        _ response: SmartSearchResponse,
        query: String,
        contextQuery: String?,
        maxPrice: Double?,
        size: String?,
        store: String?
    ) async -> SmartSearchResponse {
        if response.is_off_topic == true || response.is_unsafe == true {
            return response
        }

        guard let kind = detectExpectedQueryKind(query: query, contextQuery: contextQuery, summary: response.conversational_summary) else {
            return response
        }

        let validResults = response.results.filter { isProductCompatible($0, with: kind) }
        let needsDirectEnrichment = validResults.count < 5 || (response.results.count > 0 && Double(validResults.count) / Double(response.results.count) < 0.6)

        var finalResults = validResults
        if needsDirectEnrichment {
            let fallbackCategory: String
            let fallbackKeywords: [String]
            switch kind {
            case .gpsWatch:
                fallbackCategory = "gps_watch"
                fallbackKeywords = ["forerunner 265", "forerunner 165", "forerunner 965", "coros pace", "suunto race", "polar vantage", "garmin fenix", "garmin instinct"]
            case .bikeComputer:
                fallbackCategory = "cycling"
                fallbackKeywords = ["edge 540", "edge 840", "edge 1040", "edge explore", "garmin edge", "igpsport bsc200", "bryton"]
            case .eyewear:
                fallbackCategory = "eyewear"
                fallbackKeywords = ["oakley sutro", "oakley radar", "oakley jawbreaker", "rudy project", "bliz"]
            case .hydration:
                fallbackCategory = "hydration"
                fallbackKeywords = ["active skin", "adv skin", "salomon", "camelbak"]
            case .padelRacket:
                fallbackCategory = "padel"
                fallbackKeywords = ["bullpadel vertex", "bullpadel hack", "nox at10", "head extreme", "babolat viper", "adidas metalbone"]
            case .socks:
                fallbackCategory = "socks"
                fallbackKeywords = ["asics calze", "nike", "salomon", "compressport", "uyn"]
            case .jacket:
                fallbackCategory = "jacket"
                fallbackKeywords = ["giacca antivento", "salomon bonatti", "nike stride", "adizero", "odlo"]
            case .pants:
                fallbackCategory = "pants"
                fallbackKeywords = ["nike stride", "nike challenger", "adizero", "salomon", "odlo"]
            case .top:
                fallbackCategory = "top"
                fallbackKeywords = ["adizero", "odlo", "kiprun", "nike stride", "salomon"]
            case .shoes:
                fallbackCategory = "running_shoes"
                fallbackKeywords = ["nike pegasus", "asics nimbus", "asics novablast", "hoka clifton", "brooks ghost", "new balance 1080", "adidas adizero", "saucony"]
            }

            let directProds = await SupabaseManager.shared.fetchSmartProductsDirect(
                category: fallbackCategory,
                keywords: fallbackKeywords,
                brand: response.intent?.brand,
                maxPrice: maxPrice ?? response.intent?.max_price,
                size: size ?? response.intent?.size,
                store: store,
                limit: 35
            ).filter { isProductCompatible($0, with: kind) }

            var seenNames = Set(finalResults.map { $0.canonical_name.lowercased() })
            for dp in directProds where !seenNames.contains(dp.canonical_name.lowercased()) {
                seenNames.insert(dp.canonical_name.lowercased())
                finalResults.append(dp)
            }
        }

        guard !finalResults.isEmpty else { return response }

        // Clean curated sections so no incompatible product remains
        var cleanedSections: [CuratedProductSection] = []
        var usedIds = Set<String>()
        for sec in (response.curated_sections ?? []) {
            let validSecProds = sec.products.filter { isProductCompatible($0, with: kind) }
            if !validSecProds.isEmpty {
                for p in validSecProds { usedIds.insert(p.id) }
                cleanedSections.append(CuratedProductSection(
                    id: sec.id,
                    title: sec.title,
                    subtitle: sec.subtitle,
                    products: validSecProds
                ))
            }
        }
        if cleanedSections.isEmpty {
            cleanedSections.append(CuratedProductSection(
                id: "sec_selected",
                title: "I Modelli Selezionati",
                subtitle: "I migliori prodotti trovati in base alla tua ricerca.",
                products: Array(finalResults.prefix(10))
            ))
        }

        // Clean comparative cards
        var cleanedComps = (response.comparative_cards ?? []).filter { isProductCompatible($0.product, with: kind) }
        if cleanedComps.count < 2 && finalResults.count >= 2 {
            var compIds = Set(cleanedComps.map { $0.product.id })
            for p in finalResults where !compIds.contains(p.id) {
                compIds.insert(p.id)
                let ideal = cleanedComps.isEmpty ? "Scelta principale per rapporto qualità/prezzo" : "Alternativa tecnica \(p.brand ?? "")".trimmingCharacters(in: .whitespaces)
                let strength: String
                if p.offers.count > 1, let sav = p.cross_store_savings, sav > 0 {
                    strength = "Confrontato in \(p.offers.count) store (risparmi € \(Int(sav)))"
                } else {
                    strength = String(format: "Miglior prezzo verificato a € %.2f", p.best_price ?? 0)
                }
                cleanedComps.append(ComparativeSpecCard(
                    product: p,
                    model_name: p.canonical_name,
                    ideal_for: ideal,
                    strengths: strength,
                    section_title: "Confronto rapido"
                ))
                if cleanedComps.count >= 3 { break }
            }
        }

        // Clean spotlight
        var cleanedSpotlight = response.spotlight
        if let spot = cleanedSpotlight, !isProductCompatible(spot.product, with: kind) {
            let bestP = finalResults[0]
            let numStores = max(1, bestP.offers.count)
            let hl3 = numStores > 1
                ? "Prezzo più basso confrontato tra \(numStores) negozi ufficiali"
                : String(format: "Miglior offerta verificata a € %.2f", bestP.best_price ?? 0)
            cleanedSpotlight = SpotlightRecommendation(
                product: bestP,
                badge_text: "Miglior Scelta",
                highlights: [
                    "Selezionato per prestazioni e affidabilità nella categoria",
                    "Disponibilità immediata verificata nei negozi partner",
                    hl3
                ]
            )
        }

        return SmartSearchResponse(
            search_mode: response.search_mode,
            is_deep_dive: response.is_deep_dive,
            conversational_header: response.conversational_header,
            conversational_summary: response.conversational_summary,
            curated_sections: cleanedSections,
            comparative_cards: cleanedComps,
            spotlight: cleanedSpotlight,
            follow_up_suggestions: response.follow_up_suggestions,
            intent: response.intent,
            chips: response.chips,
            total_found: finalResults.count,
            results: finalResults,
            is_off_topic: response.is_off_topic,
            is_unsafe: response.is_unsafe
        )
    }

    func getAIAdvice(prompt: String) async throws -> AIAdviceResponse {
        var components = URLComponents(string: "\(baseURL)/api/ai/advise")!
        components.queryItems = [URLQueryItem(name: "prompt", value: prompt)]

        guard let url = components.url else { throw URLError(.badURL) }

        let data = try await fetchDataWithRetry(url: url)
        return try JSONDecoder().decode(AIAdviceResponse.self, from: data)
    }

    func compareModels(modelA: String, modelB: String) async throws -> ModelComparisonResponse {
        var components = URLComponents(string: "\(baseURL)/api/ai/compare")!
        components.queryItems = [
            URLQueryItem(name: "model_a", value: modelA),
            URLQueryItem(name: "model_b", value: modelB)
        ]

        guard let url = components.url else { throw URLError(.badURL) }

        let data = try await fetchDataWithRetry(url: url)
        return try JSONDecoder().decode(ModelComparisonResponse.self, from: data)
    }

    func searchCatalog(query: String = "", category: String? = nil, limit: Int = 40) async throws -> [MatchedProduct] {
        var components = URLComponents(string: "\(baseURL)/api/catalog")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: trimmed))
        }
        if let cat = category, !cat.isEmpty, cat != "all", cat != "tutti" {
            queryItems.append(URLQueryItem(name: "category", value: cat))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw URLError(.badURL) }
        do {
            let data = try await fetchDataWithRetry(url: url)
            struct CatalogResultResponse: Decodable {
                let results: [MatchedProduct]
            }
            let decoded = try JSONDecoder().decode(CatalogResultResponse.self, from: data)
            return decoded.results
        } catch {
            let direct = await SupabaseManager.shared.fetchSmartProductsDirect(
                category: category,
                keywords: trimmed.isEmpty ? [] : [trimmed],
                limit: limit
            )
            if !direct.isEmpty {
                return direct
            }
            throw error
        }
    }

    func getStats() async throws -> CatalogStatsResponse {
        guard let url = URL(string: "\(baseURL)/api/stats") else { throw URLError(.badURL) }
        let data = try await fetchDataWithRetry(url: url)
        return try JSONDecoder().decode(CatalogStatsResponse.self, from: data)
    }

    func getStoreShowcases() async throws -> [StoreShowcase] {
        // 1. Direct Supabase Cloud database query (100% real products, stores and live offer counts)
        do {
            let direct = try await SupabaseManager.shared.fetchStoreShowcasesDirect()
            if !direct.isEmpty {
                return direct
            }
        } catch {
            print("APIService Supabase direct note: \(error), falling back to API...")
        }

        // 2. Cloud API fallback
        if let url = URL(string: "\(baseURL)/api/stores/showcase") {
            let data = try await fetchDataWithRetry(url: url, maxRetries: 1)
            let decoded = try JSONDecoder().decode(StoreShowcaseResponse.self, from: data)
            if !decoded.showcases.isEmpty {
                return decoded.showcases
            }
        }
        return []
    }

    func getSizeDeals(size: String, minDiscount: Double = 15, limit: Int = 12) async -> [StoreShowcaseProduct] {
        // 1. Direct Supabase query
        let direct = await SupabaseManager.shared.fetchSizeDealsDirect(size: size, minDiscount: minDiscount, limit: limit)
        if !direct.isEmpty {
            return direct
        }

        // 2. Fallback to backend API
        struct SizeDealsResponse: Codable {
            let size: String
            let deals: [StoreShowcaseProduct]
            let count: Int
        }
        if let encoded = size.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "\(baseURL)/api/feed/size-deals?size=\(encoded)&min_discount=\(Int(minDiscount))&limit=\(limit)") {
            if let data = try? await fetchDataWithRetry(url: url, maxRetries: 1),
               let decoded = try? JSONDecoder().decode(SizeDealsResponse.self, from: data) {
                return decoded.deals
            }
        }
        return []
    }

    func getDealsShowcases(category: String? = nil) async throws -> [StoreShowcase] {
        do {
            let direct = try await SupabaseManager.shared.fetchDealsShowcasesDirect(category: category)
            if !direct.isEmpty {
                return direct
            }
        } catch {
            print("APIService fetchDealsShowcasesDirect error: \(error)")
        }

        // If category is nil or "tutti", fallback to general store showcases
        guard let cat = category?.lowercased(), !cat.isEmpty && cat != "tutti" else {
            return try await getStoreShowcases()
        }

        // If a specific category was requested, filter fallback products so unrelated items (e.g. shoes for smartwatch) are NEVER shown
        let allStores = try await getStoreShowcases()
        return filterShowcasesByCategory(allStores, category: cat)
    }

    private func filterShowcasesByCategory(_ showcases: [StoreShowcase], category: String) -> [StoreShowcase] {
        let cat = category.lowercased()
        guard cat != "tutti" && !cat.isEmpty else { return showcases }

        var filtered: [StoreShowcase] = []
        for sc in showcases {
            let matched = sc.products.filter { CategoryFilterMatcher.matches(title: $0.title, category: cat) }
            if !matched.isEmpty {
                filtered.append(StoreShowcase(
                    store_id: sc.store_id,
                    store_name: sc.store_name,
                    total_offers: matched.count,
                    avg_discount: sc.avg_discount,
                    rating: sc.rating,
                    review_count: sc.review_count,
                    card_theme: sc.card_theme,
                    accent_color: sc.accent_color,
                    logo_url: sc.logo_url,
                    products: matched
                ))
            }
        }
        return filtered
    }

    func getStoreDetails(storeId: String, query: String = "", sort: String = "discount") async throws -> StoreDetailResponse {
        var components = URLComponents(string: "\(baseURL)/api/stores/\(storeId)")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "limit", value: "100")
        ]
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw URLError(.badURL) }
        let data = try await fetchDataWithRetry(url: url)
        return try JSONDecoder().decode(StoreDetailResponse.self, from: data)
    }

    // MARK: - Wishlist & Collections (Database Connected)

    func getWishlist(collection: String? = nil) async throws -> [WishlistItem] {
        var components = URLComponents(string: "\(baseURL)/api/wishlist")!
        if let col = collection, !col.isEmpty && col.lowercased() != "tutti" {
            components.queryItems = [URLQueryItem(name: "collection", value: col)]
        }
        guard let url = components.url else { throw URLError(.badURL) }
        let data = try await fetchDataWithRetry(url: url)
        let decoded = try JSONDecoder().decode(WishlistResponse.self, from: data)
        return decoded.items
    }

    func addToWishlist(item: WishlistItem) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/wishlist") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "canonical_name": item.canonical_name,
            "brand": item.brand ?? "",
            "store_name": item.bestStore ?? "",
            "current_price": item.currentBestPrice,
            "original_price": item.initialPrice,
            "discount_pct": item.discountPct ?? 0.0,
            "image_url": item.image_url ?? "",
            "product_url": item.bestStoreUrl ?? "",
            "selected_size": item.selectedSize ?? "Standard",
            "collection_name": item.collectionName ?? "Tutti"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func removeFromWishlist(canonicalName: String) async throws -> Bool {
        let encoded = canonicalName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? canonicalName
        guard let url = URL(string: "\(baseURL)/api/wishlist/\(encoded)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func getCollections() async throws -> [WishlistCollection] {
        guard let url = URL(string: "\(baseURL)/api/collections") else { throw URLError(.badURL) }
        let data = try await fetchDataWithRetry(url: url)
        let decoded = try JSONDecoder().decode(CollectionsResponse.self, from: data)
        return decoded.collections
    }

    func createCollection(name: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/collections") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["name": name]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func updateItemCollection(canonicalName: String, collectionName: String) async throws -> Bool {
        let encoded = canonicalName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? canonicalName
        guard let url = URL(string: "\(baseURL)/api/wishlist/\(encoded)/collection") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["collection_name": collectionName]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func deleteCollection(name: String) async throws -> Bool {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = URL(string: "\(baseURL)/api/collections/\(encoded)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Followed Stores API

    func getFollowedStores() async throws -> [FollowedStoreItem] {
        guard let url = URL(string: "\(baseURL)/api/followed_stores") else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        struct StoresResp: Codable {
            let stores: [FollowedStoreItem]
        }
        return (try? JSONDecoder().decode(StoresResp.self, from: data))?.stores ?? []
    }

    func followStore(storeId: String, storeName: String, storeLogo: String? = nil) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/followed_stores") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["store_id": storeId, "store_name": storeName]
        if let logo = storeLogo { body["store_logo"] = logo }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func unfollowStore(storeId: String) async throws -> Bool {
        let encoded = storeId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? storeId
        guard let url = URL(string: "\(baseURL)/api/followed_stores/\(encoded)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Store Reviews API

    func submitStoreReview(storeId: String, authorName: String, rating: Int, reviewText: String) async throws -> Bool {
        let encoded = storeId.lowercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? storeId
        guard let url = URL(string: "\(baseURL)/api/stores/\(encoded)/reviews") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "author_name": authorName,
            "rating": rating,
            "review_text": reviewText,
            "device_id": "default_device"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Admin Control Center Actions

    func triggerDiscovery(limitPerStore: Int = 200) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/scheduler/run-discovery?limit_per_store=\(limitPerStore)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func triggerRefresh(limit: Int = 50) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/scheduler/run-refresh?limit=\(limit)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func triggerSizeEnrichment(limitPerStore: Int = 50) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/scheduler/run-enrichment?limit_per_store=\(limitPerStore)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func triggerRecluster() async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/catalog/recluster") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func crawlStore(storeId: String, limit: Int = 100) async throws -> Bool {
        let encoded = storeId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? storeId
        guard let url = URL(string: "\(baseURL)/api/crawl?store=\(encoded)&limit_per_store=\(limit)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func submitSearchFeedback(
        query: String,
        feedbackType: String,
        comment: String? = nil,
        productEvaluations: [[String: Any]]? = nil
    ) async {
        // 1. Send to Supabase directly
        _ = try? await SupabaseManager.shared.submitSearchFeedback(
            query: query,
            feedbackType: feedbackType,
            comment: comment,
            productEvaluations: productEvaluations
        )

        // 2. Also send to FastAPI backend endpoint if available
        guard let url = URL(string: "\(baseURL)/api/search/feedback") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "query": query,
            "feedback_type": feedbackType,
            "device_id": SupabaseManager.shared.deviceId
        ]
        if let c = comment { payload["comment"] = c }
        if let evals = productEvaluations { payload["product_evaluations"] = evals }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await session.data(for: request)
    }

    // MARK: - Outbound Affiliate Monetization

    func outboundRedirectURL(
        targetUrl: String,
        storeId: String? = nil,
        offerId: String? = nil,
        source: String = "app"
    ) -> URL {
        let clean = targetUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: "\(baseURL)/api/outbound/redirect") else {
            return URL(string: clean) ?? URL(string: "https://fitmatch.it")!
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "url", value: clean),
            URLQueryItem(name: "source", value: source),
            URLQueryItem(name: "device_id", value: SupabaseManager.shared.deviceId)
        ]
        if let s = storeId, !s.isEmpty {
            queryItems.append(URLQueryItem(name: "store_id", value: s))
        }
        if let o = offerId, !o.isEmpty {
            queryItems.append(URLQueryItem(name: "offer_id", value: o))
        }
        components.queryItems = queryItems
        return components.url ?? (URL(string: clean) ?? URL(string: "https://fitmatch.it")!)
    }
}
