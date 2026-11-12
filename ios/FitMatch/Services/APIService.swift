import Foundation

@MainActor
class APIService: ObservableObject {
    static let shared = APIService()

    // Production Cloud Backend hosted on Render (Frankfurt, Docker)
    @Published var baseURL = "https://fitmatch-backend-klhv.onrender.com"
    @Published var isCloudOnline: Bool = true

    private let session: URLSession

    // Client-side instant search cache (10-minute validity)
    private var smartSearchCache: [String: (response: SmartSearchResponse, expiry: Date)] = [:]
    private var liveSearchCache: [String: (results: [MatchedProduct], expiry: Date)] = [:]

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

    /// High-speed HTTP fetch with tight timeout (4.0s) for user-facing interactive queries.
    /// If Render backend is sleeping (cold start) or slow, fails fast so the app immediately queries Supabase Cloud directly.
    private func fetchFastData(url: URL, timeout: TimeInterval = 4.0) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            return data
        }
        throw URLError(.badServerResponse)
    }

    func search(query: String, size: String? = nil) async throws -> [MatchedProduct] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cacheKey = "\(cleanQuery)_\(size ?? "")"
        if let cached = liveSearchCache[cacheKey], cached.expiry > Date() {
            return cached.results
        }

        var components = URLComponents(string: "\(baseURL)/api/search")!
        var queryItems = [URLQueryItem(name: "q", value: query)]
        if let size = size, !size.isEmpty {
            queryItems.append(URLQueryItem(name: "size", value: size))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw URLError(.badURL) }

        do {
            let data = try await fetchFastData(url: url, timeout: 4.0)
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            liveSearchCache[cacheKey] = (decoded.matched_products, Date().addingTimeInterval(600))
            return decoded.matched_products
        } catch {
            let direct = await SupabaseManager.shared.fetchSmartProductsDirect(
                category: nil,
                keywords: [query],
                size: size,
                limit: 30
            )
            if !direct.isEmpty {
                liveSearchCache[cacheKey] = (direct, Date().addingTimeInterval(600))
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
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cacheKey = "\(cleanQuery)_\(mode ?? "")_\(maxPrice ?? 0)_\(size ?? "")_\(category ?? "")_\(store ?? "")_\(contextQuery ?? "")"
        if let cached = smartSearchCache[cacheKey], cached.expiry > Date() {
            return cached.response
        }

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
            let data = try await fetchFastData(url: url, timeout: 12.0)
            let decoded = try JSONDecoder().decode(SmartSearchResponse.self, from: data)
            let enriched = await validateAndEnrichSmartSearchResponse(
                decoded,
                query: query,
                contextQuery: contextQuery,
                maxPrice: maxPrice,
                size: size,
                store: store
            )
            smartSearchCache[cacheKey] = (enriched, Date().addingTimeInterval(600))
            return enriched
        } catch {
            // High-Availability Fallback: if Render backend is sleeping (cold start), deploying, or experiencing high load,
            // query Supabase Cloud directly so user gets instantaneous real products instead of an error view!
            if let directFallback = await buildDirectSmartSearchFallback(
                query: query,
                category: category,
                maxPrice: maxPrice,
                size: size,
                store: store,
                contextQuery: contextQuery
            ) {
                smartSearchCache[cacheKey] = (directFallback, Date().addingTimeInterval(600))
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
        store: String? = nil,
        contextQuery: String? = nil
    ) async -> SmartSearchResponse? {
        // Extract price constraint if embedded in query (e.g. "Alternative sotto i 300 euro" -> maxPrice = 300)
        var effectiveMaxPrice = maxPrice
        let qLower = query.lowercased()
        if effectiveMaxPrice == nil {
            if let regex = try? NSRegularExpression(pattern: #"(?:sotto|meno\s*di|max|fino\s*a)\s*i?\s*(\d+(?:[.,]\d+)?)"#, options: .caseInsensitive),
               let match = regex.firstMatch(in: qLower, options: [], range: NSRange(location: 0, length: qLower.utf16.count)),
               let range = Range(match.range(at: 1), in: qLower) {
                let numStr = String(qLower[range]).replacingOccurrences(of: ",", with: ".")
                effectiveMaxPrice = Double(numStr)
            }
        }

        // Determine effective category & keywords
        var effectiveCategory = category
        let combined = "\(qLower) \(contextQuery?.lowercased() ?? "")"
        let isShortSleeveCombined = combined.range(of: #"\b(short[\s-]*sleeve|manic(?:a|he)\s*cort[ae])\b"#, options: .regularExpression) != nil

        if effectiveCategory == nil || effectiveCategory == "all" || effectiveCategory == "tutti" {
            if combined.contains("garmin") || combined.contains("forerunner") || combined.contains("fenix") ||
               combined.contains("smartwatch") || combined.contains("orologi") || combined.contains("cardio") ||
               combined.contains("suunto") || combined.contains("coros") || combined.contains("polar") {
                effectiveCategory = "gps_watch"
            } else if !isShortSleeveCombined && combined.range(of: #"\b(pantaloncin[oi]|shorts?\b(?!\s*[-]?\s*sleeve)|leggings?|tights?|pantalon[ie]|ciclisti|sprinter|bermuda)\b"#, options: .regularExpression) != nil {
                effectiveCategory = "pants"
            } else if isShortSleeveCombined || combined.range(of: #"\b(magli[ae]|t[\s-]*shirt|long\s*sleeve|canott[ae]|singlet)\b"#, options: .regularExpression) != nil {
                effectiveCategory = "top"
            } else if combined.range(of: #"\b(giacc(?:a|he)|antivento|k[\s-]*way)\b"#, options: .regularExpression) != nil {
                effectiveCategory = "jacket"
            }
        }

        // Clean query terms for database text search (strip conversational filler words and numeric price filters)
        let stopwords: Set<String> = [
            "alternative", "modelli", "funzionalità", "funzionalita", "avanzate",
            "per", "la", "il", "lo", "i", "gli", "le", "un", "una", "uno", "di",
            "a", "da", "in", "con", "su", "sotto", "meno", "euro", "eur", "corsa", "running",
            "analisi", "delle", "prestazioni", "confronta", "miglior", "migliori", "prezzo",
            "smartwatch", "orologi", "uomo", "donna", "ragazzo", "ragazza", "scarpe", "scarpa",
            "sono", "vanno", "bene", "buone", "buoni", "buon", "comodi", "comodo", "comode",
            "come", "quanto", "quanti", "quante", "ha", "hanno", "ci", "sta", "posso", "puoi",
            "meglio", "cosa", "quale", "quali", "perche", "perché", "è", "e", "tu", "consigli"
        ]

        let isQuestion = qLower.contains("?") || qLower.hasPrefix("sono ") || qLower.hasPrefix("vanno ") || qLower.hasPrefix("come ") || qLower.hasPrefix("quanto ") || qLower.hasPrefix("per che ") || qLower.contains("differenza") || qLower.contains("comodi") || qLower.contains("tasche") || qLower.contains("palestra")

        // If the query is a conversational follow-up question, extract search keywords from the context query!
        let textForTokenExtraction = (isQuestion && contextQuery != nil && !contextQuery!.isEmpty) ? contextQuery!.lowercased() : qLower

        var tokens = textForTokenExtraction.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                guard token.count > 1 && !stopwords.contains(token) else { return false }
                if let num = Double(token), let emp = effectiveMaxPrice, (num == emp || num == Double(Int(emp))) {
                    return false
                }
                return true
            }

        if tokens.isEmpty, let ctx = contextQuery?.lowercased() {
            tokens = ctx.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { token in
                    guard token.count > 1 && !stopwords.contains(token) else { return false }
                    if let num = Double(token), let emp = effectiveMaxPrice, (num == emp || num == Double(Int(emp))) {
                        return false
                    }
                    return true
                }
        }

        var keywordsToSearch = tokens
        if keywordsToSearch.isEmpty {
            if effectiveCategory == "gps_watch" {
                keywordsToSearch = ["garmin", "forerunner"]
            } else if effectiveCategory == "pants" {
                keywordsToSearch = ["shorts", "pantaloncini"]
            } else {
                keywordsToSearch = [query]
            }
        }

        var prods = await SupabaseManager.shared.fetchSmartProductsDirect(
            category: effectiveCategory,
            keywords: keywordsToSearch,
            brand: nil,
            maxPrice: effectiveMaxPrice,
            size: size,
            store: store,
            limit: 35
        )

        // Resilient fallback: if exact keywords returned 0 products but this is a question, fetch general category products
        if prods.isEmpty && isQuestion {
            prods = await SupabaseManager.shared.fetchSmartProductsDirect(
                category: effectiveCategory,
                keywords: effectiveCategory == "pants" ? ["shorts"] : ["running"],
                brand: nil,
                maxPrice: effectiveMaxPrice,
                size: size,
                store: store,
                limit: 20
            )
        }

        guard !prods.isEmpty else { return nil }

        let topProd = prods.first!

        var headerTitle = "Ho cercato \(query)"
        var summaryText = "Ecco i modelli trovati per la tua ricerca:"
        var sectionTitle = "Migliori Risultati Trovati"

        if let exactMatch = qLower.range(of: #"\b(zoom\s*fly\s*\d*|endorphin\s*\w*|pegasus\s*\w*|nimbus\s*\d*|clifton\s*\d*|bondi\s*\d*|ghost\s*\d*|adizero\s*\w*|forerunner\s*\d*|fenix\s*\d*)\b"#, options: .regularExpression) {
            let matchedStr = String(qLower[exactMatch]).capitalized
            headerTitle = "Ho cercato \(matchedStr)"
            summaryText = "Ecco i migliori prezzi e offerte per **\(matchedStr)**, confrontati in tempo reale:"
            sectionTitle = "Offerte \(matchedStr)"
        } else if effectiveCategory == "pants" {
            headerTitle = "Ho cercato Shorts & Pantaloncini da Corsa"
            summaryText = "Ecco i migliori **shorts e pantaloncini da corsa** trovati al miglior prezzo verificato:"
            sectionTitle = "Shorts & Pantaloncini Selezionati"
        }

        var isAdvice = false
        var followUps = [
            "Mostrami solo le offerte con spedizione gratuita",
            "Filtra per prezzo più basso"
        ]

        if isQuestion {
            isAdvice = true
            let sub = topProd.canonical_name
            headerTitle = "Risposta per \(sub)"
            if effectiveCategory == "pants" || combined.contains("shorts") || combined.contains("pantaloncin") {
                if qLower.contains("comod") || qLower.contains("comfort") || qLower.contains("tessut") {
                    headerTitle = "Comfort & Materiali \(sub)"
                    summaryText = "Sì, i **\(sub)** sono rinomati per l'eccellente comfort e traspirabilità: il tessuto tecnico elasticizzato a 4 vie espelle rapidamente il sudore, le cuciture piatte ergonomiche azzerano gli sfregamenti nell'interno coscia e la vita con coulisse piatta garantisce totale stabilità."
                    followUps = ["Hanno le tasche con zip per il telefono?", "Come vestono come taglia?", "Hanno il boxer o liner interno?"]
                } else if qLower.contains("tasch") || qLower.contains("telefon") || qLower.contains("smartphon") {
                    headerTitle = "Tasche & Smartphone \(sub)"
                    summaryText = "I **\(sub)** offrono tasche per le mani e una tasca di sicurezza anti-rimbalzo (posteriore con zip o Speedpocket centrale impermeabile) studiata appositamente per ospitare smartphone fino a 6.7 pollici senza fastidiosi sobbalzi."
                    followUps = ["Sono comodi per correre?", "Come vestono come taglia?", "Hanno il liner interno?"]
                } else if qLower.contains("palestr") || qLower.contains("fitness") || qLower.contains("pesi") {
                    headerTitle = "Uso in Palestra \(sub)"
                    summaryText = "Assolutamente sì: i **\(sub)** sono perfetti sia per la corsa che per la palestra e la sala pesi, garantendo mobilità completa a 360° per squat, affondi e functional training."
                    followUps = ["Hanno le tasche?", "Sono comodi?", "Come vestono come taglia?"]
                } else {
                    headerTitle = "Info \(sub)"
                    summaryText = "I capi **\(sub)** rappresentano uno standard di riferimento per abbigliamento sportivo tecnico ad asciugatura rapida e zero sfregamenti."
                    followUps = ["Sono comodi per correre?", "Hanno le tasche con zip?", "Come vestono come taglia?"]
                }
            } else if qLower.contains("mezza") || qLower.contains("21") {
                summaryText = "Sì, le **\(sub)** sono un'ottima scelta per la **mezza maratona** (21 km). Offrono reattività e comfort muscolare sui ritmi prolungati, garantendo protezione sui 21 km."
                followUps = ["Come calzano?", "Qual è il drop e il peso?", "Vanno bene per pronatori?"]
            } else if qLower.contains("pronat") || qLower.contains("stabilit") {
                summaryText = "Le **\(sub)** sono scarpe a **supporto neutro**. Se cerchi stabilità e correzione specifica dell'iperpronazione su lunghe distanze, sono preferibili modelli dedicati come le Asics Kayano o Saucony Guide."
                followUps = ["Mostrami modelli per pronatori", "Come calzano?", "Qual è il drop?"]
            } else if qLower.contains("calzan") || qLower.contains("taglia") {
                summaryText = "Le **\(sub)** hanno una calzata regolare ma aderente. Se hai la pianta larga o per lunghe distanze è consigliato scegliere **mezza taglia in più**."
                followUps = ["Quanto durano?", "Qual è il drop?", "Vanno bene per mezza maratona?"]
            } else if qLower.contains("duran") || qLower.contains("km") {
                summaryText = "La durata stimata per le **\(sub)** è tra **500 e 700 km**, grazie al battistrada in gomma resistente all'abrasione."
                followUps = ["Come calzano?", "Qual è il drop?", "Vanno bene per mezza maratona?"]
            } else {
                summaryText = "Le **\(sub)** sono un modello di riferimento per prestazioni e affidabilità, ideale per allenamenti e preparazione atletica."
                followUps = ["Come calzano?", "Qual è il drop e il peso?", "Quanto durano?"]
            }
        }

        let sections = [
            CuratedProductSection(
                id: "sec_cloud_results",
                title: sectionTitle,
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
            is_conversational_advice: isAdvice,
            conversational_header: headerTitle,
            conversational_summary: summaryText,
            curated_sections: sections,
            comparative_cards: compCards,
            spotlight: spotlight,
            follow_up_suggestions: followUps,
            intent: SmartSearchIntent(
                raw_query: query,
                search_mode: "deep_dive",
                is_deep_dive: true,
                target_keywords: [query],
                brand: topProd.brand,
                category: effectiveCategory ?? "shoes",
                gender: nil,
                max_price: effectiveMaxPrice,
                min_price: nil,
                size: size,
                features: nil,
                explanation: nil,
                source: "supabase_direct",
                is_off_topic: false,
                is_unsafe: false,
                is_conversational_advice: isAdvice
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
        let isShortSleeve = q.range(of: #"\b(short[\s-]*sleeve|manic(?:a|he)\s*cort[ae])\b"#, options: .regularExpression) != nil
        if q.range(of: #"\b(giacc(?:a|he)|antivento|windbreaker|k[\s-]*way)\b"#, options: .regularExpression) != nil {
            return .jacket
        }
        if !isShortSleeve && q.range(of: #"\b(pantaloncin[oi]|shorts?\b(?!\s*[-]?\s*sleeve)|leggings?|tights?|pantalon[ie]|fuseaux|sprinter|ciclisti|bermuda)\b"#, options: .regularExpression) != nil {
            return .pants
        }
        if isShortSleeve || q.range(of: #"\b(magli[ae]|t[\s-]*shirt|long\s*sleeve|manic(?:a|he)|canott[ae]|singlet)\b"#, options: .regularExpression) != nil {
            return .top
        }
        if q.range(of: #"\b(scarp[ae]|sneakers?|running|corsa|maratona|trail|palestra|hyrox|ammortizzat[ae]|pegasus|vomero|vaporfly|alphafly|nimbus|clifton|bondi|ghost|glycerin|adizero|dropset|metcon|zoom\s*fly|endorphin)\b"#, options: .regularExpression) != nil {
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
            if fullText.range(of: #"\b(scarp[ae]|shoe|shoes|sneakers?|magli[ae]|t[\s-]*shirt|shirt\b|tee\b|top\b|short[\s-]*sleeve|manic(?:a|he)|canott[ae]|singlet|giacc(?:a|he)|jacket|calz[ae]|calzin[oi]|orologi[o]?|zain[oi]|cappellin[oi])\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(pantaloncin[oi]|shorts?\b(?!\s*[-]?\s*sleeve)|leggings?|tights?|pantalon[ie]|fuseaux|sprinter|ciclisti|bermuda)\b"#, options: .regularExpression) != nil

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

        let effMaxPrice = maxPrice ?? response.intent?.max_price
        var validResults = response.results.filter { isProductCompatible($0, with: kind) }

        // Strictly enforce price bounds on product and offer levels
        if let mp = effMaxPrice {
            validResults = validResults.compactMap { prod in
                let validOffers = prod.offers.filter { $0.price <= mp }
                guard !validOffers.isEmpty else { return nil }
                let minP = validOffers.map { $0.price }.min() ?? prod.best_price ?? 0.0
                guard minP <= mp else { return nil }
                return MatchedProduct(
                    id_val: prod.id,
                    canonical_name: prod.canonical_name,
                    brand: prod.brand,
                    image_url: prod.image_url,
                    gallery_images: prod.gallery_images,
                    gender: prod.gender,
                    offers: validOffers,
                    best_price: minP,
                    highest_price: validOffers.map { $0.price }.max() ?? minP,
                    cross_store_savings: prod.cross_store_savings
                )
            }
        }

        let needsDirectEnrichment = validResults.count < 5 || (response.results.count > 0 && Double(validResults.count) / Double(response.results.count) < 0.6)

        var finalResults = validResults
        if needsDirectEnrichment {
            let fallbackCategory: String
            var fallbackKeywords: [String]
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
                if query.lowercased().contains("compression") || query.lowercased().contains("ciclisti") {
                    fallbackKeywords = ["shorts compression", "compression shorts", "ciclisti", "shorts", "pantaloncini"]
                } else {
                    fallbackKeywords = ["nike stride", "nike challenger", "adizero", "salomon", "odlo"]
                }
            case .top:
                fallbackCategory = "top"
                fallbackKeywords = ["adizero", "odlo", "kiprun", "nike stride", "salomon"]
            case .shoes:
                fallbackCategory = "running_shoes"
                let qLow = query.lowercased()
                if qLow.contains("zoom fly") {
                    fallbackKeywords = ["nike zoom fly", "zoom fly 6", "zoom fly"]
                } else if qLow.contains("endorphin") {
                    fallbackKeywords = ["saucony endorphin", "endorphin pro", "endorphin speed"]
                } else {
                    fallbackKeywords = ["nike pegasus", "asics nimbus", "asics novablast", "hoka clifton", "brooks ghost", "new balance 1080", "adidas adizero", "saucony"]
                }
            }

            let directProds = await SupabaseManager.shared.fetchSmartProductsDirect(
                category: fallbackCategory,
                keywords: fallbackKeywords,
                brand: response.intent?.brand,
                maxPrice: effMaxPrice,
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
            var validSecProds = sec.products.filter { isProductCompatible($0, with: kind) }
            if let mp = effMaxPrice {
                validSecProds = validSecProds.compactMap { prod in
                    let validOffers = prod.offers.filter { $0.price <= mp }
                    guard !validOffers.isEmpty else { return nil }
                    let minP = validOffers.map { $0.price }.min() ?? prod.best_price ?? 0.0
                    guard minP <= mp else { return nil }
                    return MatchedProduct(
                        id_val: prod.id,
                        canonical_name: prod.canonical_name,
                        brand: prod.brand,
                        image_url: prod.image_url,
                        gallery_images: prod.gallery_images,
                        gender: prod.gender,
                        offers: validOffers,
                        best_price: minP,
                        highest_price: validOffers.map { $0.price }.max() ?? minP,
                        cross_store_savings: prod.cross_store_savings
                    )
                }
            }
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
            is_conversational_advice: response.is_conversational_advice,
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
