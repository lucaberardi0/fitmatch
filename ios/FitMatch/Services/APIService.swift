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
    // Client-side deals cache (5-minute validity) & in-flight deduplication
    private var dealsShowcasesCache: [String: (showcases: [StoreShowcase], expiry: Date)] = [:]
    private var inFlightDealsTasks: [String: Task<[StoreShowcase], Error>] = [:]
    private var topDealsCrossStoreCache: [String: (deals: [StoreShowcaseProduct], total: Int, expiry: Date)] = [:]
    private var inFlightTopDealsTasks: [String: Task<(deals: [StoreShowcaseProduct], totalMatching: Int), Error>] = [:]
    // Client-side home showcases cache (memory + disk for instant cold-start render) & deduplication
    private var homeShowcasesCache: (showcases: [StoreShowcase], expiry: Date)? = nil
    private var inFlightHomeShowcasesTask: Task<[StoreShowcase], Error>? = nil
    private let homeCacheFileURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("fitmatch_home_showcases_v2.json")
    }()
    // Client-side home comparator & personalized highlights cache (memory + disk SWR)
    private var homeHighlightsCache: [String: (bundle: HomeHighlightsBundle, expiry: Date)] = [:]
    private var inFlightHomeHighlightsTasks: [String: Task<HomeHighlightsBundle, Error>] = [:]
    private let homeHighlightsCacheFileURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("fitmatch_home_highlights_v2.json")
    }()
    // Client-side "Segui già" feed cache (memory + disk SWR) & in-flight deduplication
    private var followingFeedCache: [String: (bundle: FollowingFeedBundle, expiry: Date)] = [:]
    private var inFlightFollowingTasks: [String: Task<FollowingFeedBundle, Error>] = [:]
    private let followingFeedCacheFileURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("fitmatch_following_feed_v2.json")
    }()

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

        // 1. Direct Supabase Cloud catalog query (avoids waking Render for indexed products)
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

        // 2. Fallback to live federated search backend only if nothing is indexed in Supabase
        var components = URLComponents(string: "\(baseURL)/api/search")!
        var queryItems = [URLQueryItem(name: "q", value: query)]
        if let size = size, !size.isEmpty {
            queryItems.append(URLQueryItem(name: "size", value: size))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw URLError(.badURL) }

        let data = try await fetchFastData(url: url, timeout: 6.0)
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        liveSearchCache[cacheKey] = (decoded.matched_products, Date().addingTimeInterval(600))
        return decoded.matched_products
    }

    func fetchPriceHistory(canonicalName: String, productId: String? = nil, days: Int = 90) async throws -> PriceHistoryResponse {
        return try await SupabaseManager.shared.fetchPriceHistoryDirect(
            canonicalName: canonicalName,
            productId: productId,
            days: days
        )
    }

    private func isMoreExamplesQuery(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.range(
            of: #"\b(pi[uù]\s*esempi|altri\s*esempi|altri\s*modelli|altr[ae]\s*(?:alternative|opzioni|scarp[ae]|prodott[oi])|mostramene\s*altr[ioe]|fammi\s*vedere\s*(?:pi[uù]\s*esempi|altr[ioe]|di\s*pi[uù])|vederne\s*altr[ioe]|ancora\s*(?:qualche|altri))\b"#,
            options: .regularExpression
        ) != nil
    }

    private func detectGenderConstraint(query: String, contextQuery: String?, intentGender: String? = nil) -> String? {
        if let ig = intentGender?.trimmingCharacters(in: .whitespacesAndNewlines),
           ig == "Uomo" || ig == "Donna" {
            return ig
        }
        let turns = ((contextQuery ?? "").components(separatedBy: ">>").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }) + [query]
        var resolved: String? = nil
        for turn in turns {
            let t = turn.lowercased()
            if t.range(of: #"\b(unisex|uomo\s+e\s+donna|tutti\s+i\s+generi)\b"#, options: .regularExpression) != nil {
                resolved = nil
            } else if t.range(of: #"\b(donna|donne|ragazza|femmin[eia]|wmns?|women|woman)\b"#, options: .regularExpression) != nil {
                resolved = "Donna"
            } else if t.range(of: #"\b(uomo|uomini|ragazzo|maschil[eia]|mens?|men)\b"#, options: .regularExpression) != nil {
                resolved = "Uomo"
            }
        }
        return resolved
    }

    private func matchesGenderConstraint(_ product: MatchedProduct, gender: String?) -> Bool {
        guard let req = gender?.lowercased(), req == "uomo" || req == "donna" else { return true }
        let pg = (product.gender ?? "Unisex").lowercased()
        let isDual = pg.contains("uomo") && pg.contains("donna")
        if pg != "unisex" && !pg.isEmpty && !isDual && !pg.contains(req) && !req.contains(pg) {
            return false
        }
        let offerMeta = product.offers.prefix(4).map { "\($0.title) \($0.url)" }.joined(separator: " ")
        let probe = "\(product.canonical_name) \(offerMeta)".lowercased()
        let hasF = probe.range(of: #"(?:\b(?:donna|donne|wmns|woman|women|womens|femme|lady|ladies|damen|mujer)\b|/(?:donna|woman|women|womens|wmns|femme)/)"#, options: .regularExpression) != nil
        let hasM = probe.range(of: #"(?:\b(?:uomo|uomini|men|mens|homme|herren|hombre)\b|/(?:uomo|men|mens|homme)/)"#, options: .regularExpression) != nil
        if req == "uomo" && hasF && !hasM { return false }
        if req == "donna" && hasM && !hasF { return false }
        return true
    }

    private func smartSearchCacheKey(
        query: String,
        mode: String?,
        maxPrice: Double?,
        size: String?,
        category: String?,
        store: String?,
        contextQuery: String?,
        preferredSize: String?
    ) -> String {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(cleanQuery)_\(mode ?? "")_\(maxPrice ?? 0)_\(size ?? "")_\(category ?? "")_\(store ?? "")_\(contextQuery ?? "")_\(preferredSize ?? "")"
    }

    private var edgeFunctionsBaseURL: String {
        "\(SupabaseManager.shared.projectURL)/functions/v1"
    }

    private func makeEdgeRequest(url: URL, method: String = "GET", timeout: TimeInterval = 25.0) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        let key = SupabaseManager.shared.anonKey
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func fetchEdgeDataWithRetry(url: URL, maxRetries: Int = 1) async throws -> Data {
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                let req = makeEdgeRequest(url: url, method: "GET", timeout: 25.0)
                let (data, response) = try await session.data(for: req)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    return data
                }
                throw URLError(.badServerResponse)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    private func buildSmartSearchURL(
        path: String,
        query: String,
        mode: String?,
        maxPrice: Double?,
        size: String?,
        category: String?,
        store: String?,
        contextQuery: String?,
        sessionId: String?,
        deviceId: String?,
        userId: String?,
        preferredSize: String?,
        userImageURL: String? = nil,
        stream: Bool = false
    ) throws -> URL {
        var components = URLComponents(string: "\(edgeFunctionsBaseURL)\(path)")!
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "stream", value: stream ? "1" : "0")
        ]
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
        if let sessionId = sessionId, !sessionId.isEmpty {
            queryItems.append(URLQueryItem(name: "session_id", value: sessionId))
        }
        if let deviceId = deviceId, !deviceId.isEmpty {
            queryItems.append(URLQueryItem(name: "device_id", value: deviceId))
        }
        if let userId = userId, !userId.isEmpty {
            queryItems.append(URLQueryItem(name: "user_id", value: userId))
        }
        if let preferredSize = preferredSize, !preferredSize.isEmpty {
            queryItems.append(URLQueryItem(name: "preferred_size", value: preferredSize))
        }
        if let userImageURL = userImageURL, !userImageURL.isEmpty {
            queryItems.append(URLQueryItem(name: "user_image_url", value: userImageURL))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private func resolveUserId(_ explicitUserId: String?) async -> String? {
        if let explicit = explicitUserId?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return explicit
        }
        return await MainActor.run { SupabaseManager.shared.validCurrentUserId }
    }

    func smartSearch(
        query: String,
        mode: String? = nil,
        maxPrice: Double? = nil,
        size: String? = nil,
        category: String? = nil,
        store: String? = nil,
        contextQuery: String? = nil,
        sessionId: String? = nil,
        deviceId: String? = nil,
        userId: String? = nil,
        preferredSize: String? = nil,
        userImageURL: String? = nil
    ) async throws -> SmartSearchResponse {
        let resolvedUserId = await resolveUserId(userId)
        let cacheKey = smartSearchCacheKey(
            query: query,
            mode: mode,
            maxPrice: maxPrice,
            size: size,
            category: category,
            store: store,
            contextQuery: contextQuery,
            preferredSize: preferredSize
        )
        let hasUserImg = userImageURL != nil && !(userImageURL?.isEmpty ?? true)
        let skipClientCache = isMoreExamplesQuery(query) || hasUserImg
        if !skipClientCache, let cached = smartSearchCache[cacheKey], cached.expiry > Date() {
            if let sid = sessionId, !sid.isEmpty, let did = deviceId, !did.isEmpty {
                Task {
                    await SupabaseManager.shared.saveChatTurnDirect(
                        sessionId: sid,
                        deviceId: did,
                        query: query,
                        isFollowUp: contextQuery != nil && !(contextQuery?.isEmpty ?? true),
                        response: cached.response,
                        userImageURL: userImageURL
                    )
                }
            }
            return cached.response
        }

        let url = try buildSmartSearchURL(
            path: "/smart-search",
            query: query,
            mode: mode,
            maxPrice: maxPrice,
            size: size,
            category: category,
            store: store,
            contextQuery: contextQuery,
            sessionId: sessionId,
            deviceId: deviceId,
            userId: resolvedUserId,
            preferredSize: preferredSize,
            userImageURL: userImageURL,
            stream: false
        )

        do {
            let edgeReq = makeEdgeRequest(url: url, method: "GET", timeout: 25.0)
            let (data, response) = try await session.data(for: edgeReq)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(SmartSearchResponse.self, from: data)
            let enriched = await validateAndEnrichSmartSearchResponse(
                decoded,
                query: query,
                contextQuery: contextQuery,
                maxPrice: maxPrice,
                size: size,
                store: store
            )
            if !skipClientCache {
                smartSearchCache[cacheKey] = (enriched, Date().addingTimeInterval(600))
            }
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
                contextQuery: contextQuery,
                sessionId: sessionId
            ) {
                if let sid = sessionId, !sid.isEmpty, let did = deviceId, !did.isEmpty {
                    Task {
                        await SupabaseManager.shared.saveChatTurnDirect(
                            sessionId: sid,
                            deviceId: did,
                            query: query,
                            isFollowUp: contextQuery != nil && !(contextQuery?.isEmpty ?? true),
                            response: directFallback,
                            userImageURL: userImageURL
                        )
                    }
                }
                smartSearchCache[cacheKey] = (directFallback, Date().addingTimeInterval(600))
                return directFallback
            }
            throw error
        }
    }

    /// Fast-path pagination for Classic Mode ("Carica altri prodotti"):
    /// Fetches the next slice of matching products excluding already-loaded IDs without re-running LLM planning.
    func loadMoreSmartSearch(
        query: String,
        excludeIds: [String],
        sessionId: String? = nil,
        contextState: ChatSessionContextState? = nil,
        maxPrice: Double? = nil,
        size: String? = nil,
        store: String? = nil,
        preferredSize: String? = nil,
        limit: Int = 30
    ) async throws -> SmartSearchLoadMoreResponse {
        guard let url = URL(string: "\(SupabaseManager.shared.projectURL)/functions/v1/smart-search") else {
            throw URLError(.badURL)
        }
        var payload: [String: Any] = [
            "q": query,
            "mode": "classic",
            "load_more": true,
            "exclude_ids": Array(excludeIds.prefix(300)),
            "limit": limit
        ]
        if let sid = sessionId, !sid.isEmpty { payload["session_id"] = sid }
        if let mp = maxPrice { payload["max_price"] = mp }
        if let sz = size, !sz.isEmpty { payload["size"] = sz }
        if let st = store, !st.isEmpty { payload["store"] = st }
        if let ps = preferredSize, !ps.isEmpty { payload["preferred_size"] = ps }
        if let ctx = contextState,
           let ctxData = try? JSONEncoder().encode(ctx),
           let ctxObj = try? JSONSerialization.jsonObject(with: ctxData) as? [String: Any] {
            payload["context_state"] = ctxObj
        }

        var req = makeEdgeRequest(url: url, method: "POST", timeout: 20.0)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(SmartSearchLoadMoreResponse.self, from: data)
    }

    /// Streams real-time backend thinking steps via SSE from `/api/search/smart/stream`,
    /// falling back seamlessly to `smartSearch(...)` if streaming is unavailable.
    func smartSearchStream(
        query: String,
        mode: String? = nil,
        maxPrice: Double? = nil,
        size: String? = nil,
        category: String? = nil,
        store: String? = nil,
        contextQuery: String? = nil,
        sessionId: String? = nil,
        deviceId: String? = nil,
        userId: String? = nil,
        preferredSize: String? = nil,
        userImageURL: String? = nil,
        onStep: @escaping @MainActor (SearchThinkingStep) -> Void,
        onPartialResults: (@MainActor (SmartSearchPartialPayload) -> Void)? = nil
    ) async throws -> SmartSearchResponse {
        let resolvedUserId = await resolveUserId(userId)
        let cacheKey = smartSearchCacheKey(
            query: query,
            mode: mode,
            maxPrice: maxPrice,
            size: size,
            category: category,
            store: store,
            contextQuery: contextQuery,
            preferredSize: preferredSize
        )
        let hasUserImg = userImageURL != nil && !(userImageURL?.isEmpty ?? true)
        let skipClientCache = isMoreExamplesQuery(query) || hasUserImg
        if !skipClientCache, let cached = smartSearchCache[cacheKey], cached.expiry > Date() {
            await onStep(SearchThinkingStep(
                id: "cache",
                status: .done,
                title: "Risultati già pronti in memoria",
                detail: "\(cached.response.results.count) modelli verificati",
                elapsedMs: 1
            ))
            if let sid = sessionId, !sid.isEmpty, let did = deviceId, !did.isEmpty {
                Task {
                    await SupabaseManager.shared.saveChatTurnDirect(
                        sessionId: sid,
                        deviceId: did,
                        query: query,
                        isFollowUp: contextQuery != nil && !(contextQuery?.isEmpty ?? true),
                        response: cached.response,
                        userImageURL: userImageURL
                    )
                }
            }
            return cached.response
        }

        let streamURL = try buildSmartSearchURL(
            path: "/smart-search",
            query: query,
            mode: mode,
            maxPrice: maxPrice,
            size: size,
            category: category,
            store: store,
            contextQuery: contextQuery,
            sessionId: sessionId,
            deviceId: deviceId,
            userId: resolvedUserId,
            preferredSize: preferredSize,
            userImageURL: userImageURL,
            stream: true
        )

        var request = makeEdgeRequest(url: streamURL, method: "GET", timeout: 30.0)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                await onStep(SearchThinkingStep(
                    id: "catalog",
                    status: .running,
                    title: "Interrogo il catalogo multi-store…",
                    detail: "Ricerca standard in corso",
                    elapsedMs: nil
                ))
                return try await smartSearch(
                    query: query,
                    mode: mode,
                    maxPrice: maxPrice,
                    size: size,
                    category: category,
                    store: store,
                    contextQuery: contextQuery,
                    sessionId: sessionId,
                    deviceId: deviceId,
                    userId: resolvedUserId,
                    preferredSize: preferredSize,
                    userImageURL: userImageURL
                )
            }

            let decoder = JSONDecoder()
            for try await line in bytes.lines {
                if Task.isCancelled { throw CancellationError() }
                guard line.hasPrefix("data: ") else { continue }
                let jsonStr = String(line.dropFirst(6))
                guard let payloadData = jsonStr.data(using: .utf8),
                      let event = try? decoder.decode(SmartSearchStreamEvent.self, from: payloadData) else {
                    continue
                }

                if event.type == "step", let stepId = event.id, let title = event.title {
                    let mappedStatus = SearchThinkingStep.Status(rawValue: event.status ?? "running") ?? .running
                    let step = SearchThinkingStep(
                        id: stepId,
                        status: mappedStatus,
                        title: title,
                        detail: event.detail,
                        elapsedMs: event.elapsed_ms
                    )
                    await onStep(step)
                } else if event.type == "products", let partial = event.partial {
                    await onPartialResults?(partial)
                } else if event.type == "result", let decoded = event.data {
                    let enriched = await validateAndEnrichSmartSearchResponse(
                        decoded,
                        query: query,
                        contextQuery: contextQuery,
                        maxPrice: maxPrice,
                        size: size,
                        store: store
                    )
                    if !skipClientCache {
                        smartSearchCache[cacheKey] = (enriched, Date().addingTimeInterval(600))
                    }
                    return enriched
                } else if event.type == "error" {
                    break
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Fall through to standard smartSearch / Supabase cloud fallback
        }

        await onStep(SearchThinkingStep(
            id: "catalog",
            status: .running,
            title: "Recupero risultati dal catalogo…",
            detail: "Connessione al database prodotti",
            elapsedMs: nil
        ))
        return try await smartSearch(
            query: query,
            mode: mode,
            maxPrice: maxPrice,
            size: size,
            category: category,
            store: store,
            contextQuery: contextQuery,
            sessionId: sessionId,
            deviceId: deviceId,
            userId: resolvedUserId,
            preferredSize: preferredSize,
            userImageURL: userImageURL
        )
    }

    /// Autonomous client-side fallback building a rich SmartSearchResponse directly from Supabase Cloud
    func buildDirectSmartSearchFallback(
        query: String,
        category: String? = nil,
        maxPrice: Double? = nil,
        size: String? = nil,
        store: String? = nil,
        contextQuery: String? = nil,
        sessionId: String? = nil
    ) async -> SmartSearchResponse? {
        // Extract price constraint if embedded in query (handles "sotto i 150€", "sotto ai 150 euro", "sotto €150", "< 150", "entro 150", "budget 150")
        var effectiveMaxPrice = maxPrice
        let qLower = query.lowercased()
        if effectiveMaxPrice == nil {
            let pricePattern = #"(?:al\s+di\s+sotto\s*(?:di|dei|degli)?|sotto\s*(?:i|ai|gli|le|di|dei)?|a\s+meno\s+di|meno\s*di|non\s+(?:oltre|pi[uù]\s*di)|fino\s*a(?:i|gli|lle)?|entro\s*(?:i|ai|gli)?|(?:prezzo|budget)\s*(?:massimo|max)?\s*(?:di)?|al\s+massimo|massimo|max|under|below|<=|<)\s*(?:€\s*)?(\d+(?:[.,]\d+)?)(?!\s*(?:kg|g\b|gr\b|grammi|km|mm|cm|ore|minuti|%))"#
            if let regex = try? NSRegularExpression(pattern: pricePattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: qLower, options: [], range: NSRange(location: 0, length: qLower.utf16.count)),
               let range = Range(match.range(at: 1), in: qLower) {
                let numStr = String(qLower[range]).replacingOccurrences(of: ",", with: ".")
                if let parsed = Double(numStr), parsed >= 15 || qLower.contains("€") || qLower.contains("euro") {
                    effectiveMaxPrice = parsed
                }
            }
        }

        // Extract size constraint if embedded in query (e.g. "44,5", "taglia 42.5")
        var effectiveSize = size
        let combined = "\(qLower) \(contextQuery?.lowercased() ?? "")"
        if effectiveSize == nil {
            if let regex = try? NSRegularExpression(pattern: #"\b(?:tagli[ae]|misur[ae]|size|numero|num|eu)\s*(\d{2}(?:[.,]5)?|\b(?:xs|s|m|l|xl|xxl)\b)"#, options: .caseInsensitive),
               let match = regex.firstMatch(in: combined, options: [], range: NSRange(location: 0, length: combined.utf16.count)),
               let range = Range(match.range(at: 1), in: combined) {
                effectiveSize = String(combined[range]).replacingOccurrences(of: ",", with: ".").uppercased()
            } else if let regex = try? NSRegularExpression(pattern: #"(?<![\d.,])\b(3[5-9]|4[0-9])[.,](5)\b(?![\d.,])"#, options: .caseInsensitive),
                      let match = regex.firstMatch(in: combined, options: [], range: NSRange(location: 0, length: combined.utf16.count)),
                      let r1 = Range(match.range(at: 1), in: combined) {
                effectiveSize = "\(combined[r1]).5"
            }
        }

        // Determine effective category & keywords (respecting follow-up context before bare brand defaults!)
        let expectedKind = detectExpectedQueryKind(query: query, contextQuery: contextQuery, summary: nil)
        var effectiveCategory = category
        let isShortSleeveCombined = combined.range(of: #"\b(short[\s-]*sleeve|manic(?:a|he)\s*cort[ae])\b"#, options: .regularExpression) != nil

        if effectiveCategory == nil || effectiveCategory == "all" || effectiveCategory == "tutti" {
            if let expectedKind = expectedKind {
                switch expectedKind {
                case .heartRateMonitor: effectiveCategory = "sensor"
                case .gpsWatch: effectiveCategory = "gps_watch"
                case .bikeComputer: effectiveCategory = "cycling"
                case .eyewear: effectiveCategory = "eyewear"
                case .hydration: effectiveCategory = "hydration"
                case .padelRacket: effectiveCategory = "padel"
                case .padelShoes: effectiveCategory = "shoes"
                case .footballBoots: effectiveCategory = "football_boots"
                case .basketballShoes: effectiveCategory = "basketball"
                case .tennisShoes: effectiveCategory = "tennis"
                case .volleyballShoes, .shoes: effectiveCategory = "running_shoes"
                case .headwear: effectiveCategory = "apparel"
                case .swim: effectiveCategory = "swim"
                case .socks: effectiveCategory = "socks"
                case .jacket: effectiveCategory = "jacket"
                case .leggings, .pants: effectiveCategory = "pants"
                case .top: effectiveCategory = "top"
                }
            } else if combined.range(of: #"\b(fasc(?:ia|e|ie)\s*card(?:io|o)(?:frequenzimetr[oi])?|cardiofrequenzimetr[oi]|fasc(?:ia|e|ie)\s*toracic[ae]|sensore\s*(?:cardio|frequenza\s*cardiaca|hr)|heart\s*rate\s*(?:monitor|strap|sensor)|\bhrm\b|polar\s*h(?:9|10)|verity\s*sense|wahoo\s*tickr|trackr\s*hr|coros\s*heart\s*rate)\b"#, options: .regularExpression) != nil {
                effectiveCategory = "sensor"
            } else if combined.range(of: #"\b(occhialin[oi]|occhial[ie]\s*(?:da\s*)?nuoto|nuot[ao]|nuotare|piscina|cuffi[ae]\s*nuoto|costum[ei]\s*(?:nuoto|bagno))\b"#, options: .regularExpression) != nil {
                effectiveCategory = "swim"
            } else if combined.range(of: #"\b(scarpin[oi]|scarp[ae]\s*(?:da\s*)?calcio|calcetto|calcio\s*a\s*[57]|mercurial|predator|tiempo|phantom|copa\s*pure|top\s*sala|top\s*flex|magnetico)\b"#, options: .regularExpression) != nil {
                effectiveCategory = "football_boots"
            } else if combined.range(of: #"\b(garmin|forerunner|fenix|smartwatch|orologi|suunto|coros|polar)\b"#, options: .regularExpression) != nil {
                effectiveCategory = "gps_watch"
            } else if combined.range(of: #"\b(padel|racchett[ae]|pala\s*padel|bullpadel|nox\s*at10)\b"#, options: .regularExpression) != nil && !combined.contains("scarp") {
                effectiveCategory = "padel"
            } else if combined.range(of: #"\b(zain[oi]|gilet\s*(?:idratazione|trail)|active\s*skin|adv\s*skin|borracc(?:ia|e)|soft\s*flask|camelbak|idratazione)\b"#, options: .regularExpression) != nil {
                effectiveCategory = "hydration"
            } else if combined.range(of: #"\b(occhial[ie]|oakley|sutro|radar\s*ev|jawbreaker)\b"#, options: .regularExpression) != nil {
                effectiveCategory = "eyewear"
            } else if combined.range(of: #"\b(calz[ae]|calzin[oi]|calzetton[ei]|socks?)\b"#, options: .regularExpression) != nil {
                effectiveCategory = "socks"
            } else if !isShortSleeveCombined && combined.range(of: #"\b(pantaloncin[oi]|shorts?\b(?!\s*[-]?\s*sleeve)|leggings?|leggins|legins|tights?|tight|calzamagli[ae]|fuseaux|pantacollant|collant|pantalon[ie]|ciclisti|sprinter|bermuda)\b"#, options: .regularExpression) != nil {
                effectiveCategory = "pants"
            } else if isShortSleeveCombined || combined.range(of: #"\b(magli[ae]|t[\s-]*shirt|long\s*sleeve|canott[ae]|singlet)\b"#, options: .regularExpression) != nil {
                effectiveCategory = "top"
            } else if combined.range(of: #"\b(giacc(?:a|he)|antivento|k[\s-]*way)\b"#, options: .regularExpression) != nil {
                effectiveCategory = "jacket"
            } else if combined.range(of: #"\b(corr|running|scarpa|scarpe|hyrox|dropset|metcon|nano|tribase|palestra|basket|pallacanestro|tennis|terra\s*battuta|pallavolo|volley|pegasus|novablast|nimbus|clifton|bondi|ghost|adizero|endorphin|zoom\s*fly)\b"#, options: .regularExpression) != nil {
                effectiveCategory = "running_shoes"
            }
        }

        // Clean query terms for database text search (strip conversational filler words and numeric price/size filters)
        let stopwords: Set<String> = [
            "alternative", "modelli", "funzionalità", "funzionalita", "avanzate",
            "per", "la", "il", "lo", "i", "gli", "le", "un", "una", "uno", "di",
            "del", "dello", "della", "dei", "degli", "delle", "al", "allo", "alla", "ai", "agli", "alle",
            "dal", "dallo", "dalla", "dai", "dagli", "dalle", "nel", "nello", "nella", "nei", "negli", "nelle",
            "sul", "sullo", "sulla", "sui", "sugli", "sulle", "a", "da", "in", "con", "su", "sotto", "meno", "euro", "eur", "corsa", "running",
            "analisi", "prestazioni", "confronta", "miglior", "migliori", "prezzo", "prezzi",
            "minore", "minori", "maggiore", "maggiori", "inferiore", "superiore", "basso", "bassi", "alto", "alti",
            "elevato", "elevati", "economico", "economica", "economici", "economiche", "costa", "costano", "spendere",
            "marca", "marche", "brand", "brands", "genere", "generi", "colore", "colori", "esclusione", "esclusioni",
            "ordine", "consigliato", "consigliati", "rimuovi", "tutti", "tutte", "filtro", "filtri", "limite", "limiti",
            "smartwatch", "orologi", "uomo", "donna", "men", "man", "women", "woman", "wmns",
            "ragazzo", "ragazza", "scarpe", "scarpa", "taglia", "taglie", "misura", "size", "numero", "mia", "mio",
            "sono", "vanno", "bene", "buone", "buoni", "buon", "comodi", "comodo", "comode",
            "valide", "valido", "adatte", "adatto", "adatti", "usare", "scegliere", "differenza",
            "vs", "alta", "alte", "livello", "intermedio", "principiante", "principianti",
            "come", "quanto", "quanti", "quante", "ha", "hanno", "ci", "sta", "posso", "puoi",
            "meglio", "cosa", "quale", "quali", "quelle", "quelli", "queste", "questi", "perche", "perché", "è", "e", "tu", "consigli",
            "mi", "consigliami", "iniziare", "correre", "nuotare", "nuoto", "piscina",
            "fammi", "vedere", "più", "piu", "esempi", "altri", "altre", "opzioni", "scarpini",
            "quindi", "allora", "mentre", "mente", "solo", "sconto", "sconti", "mostrami", "mostrane", "mostramele", "mostrameli"
        ]
        let genericBrandTokens: Set<String> = [
            "nike", "adidas", "asics", "hoka", "brooks", "saucony", "new", "balance", "under", "armour",
            "salomon", "mizuno", "puma", "on", "garmin", "polar", "suunto", "coros", "wahoo", "bryton",
            "igpsport", "oakley", "bullpadel", "nox", "arena", "speedo", "camelbak", "enervit"
        ]

        let wantsPriceAsc = qLower.range(
            of: #"\b(pi[uù]\s+(?:economic[hoaie]+|convenient[ei]|accessibil[ei])|prezz[oi]\s+(?:pi[uù]\s+)?(?:bass[oi]|minor[ei]|inferior[ei]|ridott[oi])|costa(?:no)?\s+(?:di\s+)?meno|meno\s+(?:car[aeio]|costos[aeio])|dal\s+meno\s+caro)\b"#,
            options: .regularExpression
        ) != nil
        let explicitBrandInQuery: String? = {
            let knownBrands = ["Under Armour", "New Balance", "The North Face", "La Sportiva", "Rudy Project", "Garmin", "Polar", "Suunto", "Coros", "Wahoo", "Bryton", "iGPSPORT", "Nike", "Adidas", "Asics", "Hoka", "Brooks", "Saucony", "Salomon", "Mizuno", "Puma", "Oakley", "Bullpadel", "Nox", "Arena", "Speedo", "CamelBak", "Enervit"]
            for b in knownBrands {
                if qLower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: b.lowercased()))\\b", options: .regularExpression) != nil {
                    return b
                }
            }
            return nil
        }()

        let isMetaNudge = qLower.range(of: #"^\s*(?:e\s+)?(?:quindi|allora|dunque|ebbene|e\s+allora|quali\s+sono|me\s+l[eio]\s+mostri|mostramel[eio]|fammel[eio]\s+vedere|prodotti|modelli|offerte)\s*[?!.]*\s*$"#, options: .regularExpression) != nil
        let isMoreExamples = isMetaNudge || qLower.range(of: #"\b(pi[uù]\s*esempi|altri\s*modelli|altri\s*esempi|altr[ae]\s*(?:alternative|opzioni)|mostramene\s*altr[ioe]|mostrane\s*altr[ioe])\b"#, options: .regularExpression) != nil
        let isQuestion = !isMoreExamples && !isMetaNudge && !wantsPriceAsc && explicitBrandInQuery == nil && (qLower.contains("?") || qLower.hasPrefix("sono ") || qLower.hasPrefix("vanno ") || qLower.hasPrefix("come ") || qLower.hasPrefix("quanto ") || qLower.hasPrefix("per che ") || qLower.contains("differenza") || qLower.contains("comodi") || qLower.contains("tasche") || qLower.contains("palestra"))

        let qWithoutDecimalSizes = qLower.replacingOccurrences(of: #"(?<![\d.,])\b(3[5-9]|4[0-9])[.,]5\b(?![\d.,])"#, with: " ", options: .regularExpression)
        // Prioritize explicit model/product tokens in the current query before falling back to context
        let rawCurrentTokens = qWithoutDecimalSizes.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                guard token.count > 1 && !stopwords.contains(token) else { return false }
                if let num = Double(token), let emp = effectiveMaxPrice, (num == emp || num == Double(Int(emp))) {
                    return false
                }
                if let es = effectiveSize, token == es.components(separatedBy: ".").first {
                    return false
                }
                return true
            }
        let nonBrandCurrentTokens = rawCurrentTokens.filter { !genericBrandTokens.contains($0) }

        var tokens = nonBrandCurrentTokens.isEmpty ? rawCurrentTokens : nonBrandCurrentTokens
        if tokens.isEmpty || ((isQuestion || isMoreExamples) && nonBrandCurrentTokens.isEmpty), let ctx = contextQuery?.lowercased() {
            let ctxTokens = ctx.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { token in
                    guard token.count > 1 && !stopwords.contains(token) else { return false }
                    if let num = Double(token), let emp = effectiveMaxPrice, (num == emp || num == Double(Int(emp))) {
                        return false
                    }
                    return true
                }
            if !ctxTokens.isEmpty {
                tokens = ctxTokens
            }
        }

        var keywordsToSearch: [String] = []
        if nonBrandCurrentTokens.count >= 2 {
            // Compound phrase first (e.g. "adizero dropset") + individual specific tokens, avoiding bare brand ("adidas") alone
            keywordsToSearch.append(nonBrandCurrentTokens.prefix(2).joined(separator: " "))
        }
        for tok in tokens where !keywordsToSearch.contains(tok) {
            keywordsToSearch.append(tok)
        }
        if keywordsToSearch.isEmpty {
            if effectiveCategory == "sensor" {
                keywordsToSearch = ["polar h10", "polar h9", "hrm 200", "hrm 600", "fascia cardio"]
            } else if effectiveCategory == "gps_watch" {
                keywordsToSearch = ["garmin", "forerunner"]
            } else if effectiveCategory == "pants" {
                if combined.range(of: #"\b(leggings?|leggins|legins|tights?|tight|calzamagli[ae]|fuseaux|pantacollant|collant)\b"#, options: .regularExpression) != nil {
                    keywordsToSearch = ["leggings", "tights", "calzamaglia", "fuseaux"]
                } else {
                    keywordsToSearch = ["shorts", "pantaloncini"]
                }
            } else if effectiveCategory == "football_boots" {
                keywordsToSearch = ["mercurial", "predator", "phantom", "tiempo", "top sala", "calcio"]
            } else if effectiveCategory == "swim" {
                keywordsToSearch = ["occhialini", "arena", "speedo", "biofuse", "nuoto"]
            } else if effectiveCategory == "padel" {
                keywordsToSearch = ["bullpadel", "nox", "vertex", "at10", "head"]
            } else if effectiveCategory == "hydration" {
                keywordsToSearch = ["active skin", "adv skin", "salomon", "camelbak"]
            } else if effectiveCategory == "eyewear" {
                keywordsToSearch = ["oakley", "sutro", "radar"]
            } else if effectiveCategory == "socks" {
                keywordsToSearch = ["calze", "compressport", "asics"]
            } else if effectiveCategory == "running_shoes" || effectiveCategory == "shoes" {
                keywordsToSearch = ["pegasus", "novablast", "ghost", "clifton", "nimbus"]
            } else {
                keywordsToSearch = [query]
            }
        }

        let effectiveGender = detectGenderConstraint(query: query, contextQuery: contextQuery)

        var prods = await SupabaseManager.shared.fetchSmartProductsDirect(
            category: effectiveCategory,
            keywords: keywordsToSearch,
            brand: explicitBrandInQuery,
            gender: effectiveGender,
            maxPrice: effectiveMaxPrice,
            size: effectiveSize,
            store: store,
            limit: 35
        )

        if let expectedKind = expectedKind {
            prods = prods.filter { isProductCompatible($0, with: expectedKind) }
        }
        // Rank direct fallback matches by price if requested, else by overlap with specific query/model tokens
        if wantsPriceAsc && !prods.isEmpty {
            prods.sort { ($0.best_price ?? 99999) < ($1.best_price ?? 99999) }
        } else if !tokens.isEmpty && !prods.isEmpty {
            let hyroxBoostModels = ["dropset", "deviate nitro", "velocity nitro", "metcon", "hyrox"]
            let wantsHyrox = combined.contains("hyrox")
            prods.sort { lhs, rhs in
                func scoreProd(_ p: MatchedProduct) -> Int {
                    let pname = p.canonical_name.lowercased()
                    var sc = 0
                    for tok in tokens where pname.contains(tok) {
                        sc += (tok.count >= 5 ? 40 : 25)
                    }
                    if wantsHyrox && hyroxBoostModels.contains(where: { pname.contains($0) }) {
                        sc += 80
                    }
                    return sc
                }
                return scoreProd(lhs) > scoreProd(rhs)
            }
        }
        if isMoreExamples && prods.count > 4 {
            prods = Array(prods.dropFirst(min(3, prods.count - 3)))
        }

        // Resilient fallback: if exact keywords returned 0 products, fetch general category products
        if prods.isEmpty && (isQuestion || isMoreExamples || !tokens.isEmpty || explicitBrandInQuery != nil) {
            let fbKws: [String]
            switch expectedKind {
            case .heartRateMonitor:
                fbKws = explicitBrandInQuery != nil
                    ? ["\(explicitBrandInQuery!) hrm", "\(explicitBrandInQuery!) fascia cardio", "fascia cardio", "hrm"]
                    : ["polar h10", "polar h9", "hrm 200", "hrm 600", "fascia cardio"]
            case .basketballShoes: fbKws = ["basket", "luka", "caitlin", "lebron", "jordan"]
            case .tennisShoes: fbKws = ["tennis", "terra battuta", "resolution", "dedicate", "nikecourt"]
            case .padelShoes: fbKws = ["padel", "bullpadel", "asics padel", "babolat padel", "head padel"]
            case .volleyballShoes: fbKws = ["pallavolo", "volley", "sky elite", "wave lightning", "spike"]
            case .padelRacket: fbKws = ["bullpadel", "nox", "vertex", "hack", "at10"]
            case .hydration: fbKws = ["adv skin", "active skin", "salomon", "camelbak"]
            case .eyewear: fbKws = ["oakley", "sutro", "radar"]
            case .socks: fbKws = ["calze", "compressport", "uyn", "asics"]
            default:
                switch effectiveCategory {
                case "sensor":
                    fbKws = explicitBrandInQuery != nil
                        ? ["\(explicitBrandInQuery!) hrm", "\(explicitBrandInQuery!) fascia cardio", "fascia cardio", "hrm"]
                        : ["polar h10", "polar h9", "hrm 200", "hrm 600", "fascia cardio"]
                case "pants": fbKws = ["shorts"]
                case "top": fbKws = ["long sleeve", "manica lunga", "adizero", "odlo", "kiprun"]
                case "football_boots": fbKws = ["predator", "mercurial", "calcio"]
                case "swim": fbKws = ["occhialini", "arena", "speedo"]
                default: fbKws = combined.contains("hyrox") ? ["dropset", "deviate nitro", "metcon"] : ["pegasus", "novablast", "ghost", "clifton"]
                }
            }
            prods = await SupabaseManager.shared.fetchSmartProductsDirect(
                category: effectiveCategory,
                keywords: fbKws,
                brand: explicitBrandInQuery,
                gender: effectiveGender,
                maxPrice: effectiveMaxPrice,
                size: effectiveSize,
                store: store,
                limit: 20
            )
            if let expectedKind = expectedKind {
                prods = prods.filter { isProductCompatible($0, with: expectedKind) }
            }
            if wantsPriceAsc && !prods.isEmpty {
                prods.sort { ($0.best_price ?? 99999) < ($1.best_price ?? 99999) }
            }
        }

        guard !prods.isEmpty else { return nil }

        let topProd = prods.first!

        var headerTitle = "Ho cercato \(query)"
        var summaryText = "Ecco i modelli trovati per la tua ricerca:"
        var sectionTitle = "Migliori Risultati Trovati"

        if effectiveCategory == "sensor" {
            headerTitle = "Ho cercato Fasce Cardio & Sensori HR"
            summaryText = "Per rilevare i battiti al secondo con precisione ECG durante ripetute, soglia e palestra, ecco le **migliori fasce cardio toraciche e sensori HR** confrontati tra i negozi partner:"
            sectionTitle = "Fasce Cardio & Sensori Selezionati"
        } else if let exactMatch = qLower.range(of: #"\b(zoom\s*fly\s*\d*|endorphin\s*\w*|pegasus\s*\w*|nimbus\s*\d*|clifton\s*\d*|bondi\s*\d*|ghost\s*\d*|adizero\s*\w*|forerunner\s*\d*|fenix\s*\d*)\b"#, options: .regularExpression) {
            let matchedStr = String(qLower[exactMatch]).capitalized
            headerTitle = "Ho cercato \(matchedStr)"
            summaryText = "Ecco i migliori prezzi e offerte per **\(matchedStr)**, confrontati in tempo reale:"
            sectionTitle = "Offerte \(matchedStr)"
        } else if effectiveCategory == "pants" {
            headerTitle = "Shorts & Pantaloncini da Corsa"
            summaryText = "Ecco i migliori **shorts e pantaloncini da corsa** trovati al miglior prezzo verificato:"
            sectionTitle = "Shorts & Pantaloncini Selezionati"
        } else if effectiveCategory == "top" && (combined.contains("manica lunga") || combined.contains("long sleeve")) {
            headerTitle = "Maglie a Manica Lunga da Corsa"
            summaryText = "Ecco le migliori **maglie a manica lunga da corsa** disponibili in catalogo:"
            sectionTitle = "Maglie a Manica Lunga Selezionate"
        }
        if effectiveGender != nil || effectiveMaxPrice != nil || effectiveSize != nil {
            var qParts: [String] = []
            if let eg = effectiveGender { qParts.append(eg) }
            if let es = effectiveSize { qParts.append("Taglia \(es)") }
            if let emp = effectiveMaxPrice { qParts.append("fino a €\(Int(emp))") }
            if !qParts.isEmpty {
                headerTitle = "\(headerTitle) — \(qParts.joined(separator: " · "))"
            }
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
                summaryText = "Per la tua richiesta, **\(sub)** è tra le opzioni più equilibrate disponibili in catalogo (a partire da **€ \(String(format: "%.2f", topProd.best_price ?? 0))**). Puoi confrontare qui sotto le alternative migliori per prezzo e utilizzo."
                followUps = ["Alternative sotto i 120 euro", "Fammi vedere più esempi", "Come scelgo il modello giusto?"]
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
            searched_queries: keywordsToSearch,
            curated_sections: sections,
            comparative_cards: compCards,
            featured_cards: [spotlight],
            spotlight: spotlight,
            follow_up_suggestions: followUps,
            intent: SmartSearchIntent(
                raw_query: query,
                search_mode: "deep_dive",
                is_deep_dive: true,
                target_keywords: [query],
                brand: topProd.brand,
                category: effectiveCategory ?? "shoes",
                gender: effectiveGender,
                max_price: effectiveMaxPrice,
                min_price: nil,
                size: effectiveSize,
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
            is_unsafe: false,
            session_id: sessionId,
            turn_id: nil,
            user_image_url: nil
        )
    }

    // MARK: - Client-Side Intent Alignment & Product Relevance Guardrail

    private enum DetectedQueryKind {
        case heartRateMonitor
        case gpsWatch
        case bikeComputer
        case eyewear
        case hydration
        case padelRacket
        case padelShoes
        case footballBoots
        case basketballShoes
        case tennisShoes
        case volleyballShoes
        case headwear
        case swim
        case socks
        case jacket
        case leggings
        case pants
        case top
        case shoes
    }

    /// Detects ONLY explicit product nouns or unmistakable model lines — NEVER bare multi-category brands
    /// ("garmin", "coros", "oakley", "bullpadel", "bryton", "camelbak") or standalone activity words!
    private func detectExplicitQueryKind(_ q: String) -> DetectedQueryKind? {
        if q.range(of: #"\b(fasc(?:ia|e|ie)\s*card(?:io|o)(?:frequenzimetr[oi])?|fasc(?:ia|e|ie)\s*hrm|fasc(?:ia|e|ie)\s*toracic[ae]|sensore\s*(?:cardio|cardiaco|frequenza\s*cardiaca|hr)|heart\s*rate\s*(?:monitor|strap|sensor)|chest\s*strap|\bhrm\b|polar\s*h(?:9|10)|verity\s*sense|oh1|wahoo\s*(?:tickr|trackr\s*hr)|coros\s*(?:heart\s*rate|fasc(?:ia|e)\s*cardio))\b"#, options: .regularExpression) != nil {
            return .heartRateMonitor
        }
        if q.range(of: #"\b(occhialin[oi]|occhial[ie]\s*(?:da\s*)?nuoto|cuffi[ae]\s*(?:da\s*)?nuoto|costum[ei]\s*(?:da\s*)?(?:nuoto|bagno)|pinn[ae]\s*(?:da\s*)?nuoto)\b"#, options: .regularExpression) != nil {
            return .swim
        }
        if q.range(of: #"\b(scarpin[oi]|scarp[ae]\s*(?:da\s*)?(?:calcio|calcetto)|mercurial|predator|tiempo|phantom|copa\s*pure|top\s*sala|top\s*flex|magnetico)\b"#, options: .regularExpression) != nil {
            return .footballBoots
        }
        if q.range(of: #"\b(ciclocomputer|bike\s*computer|contachilometri|contatore\s*bici|garmin\s*edge|\bedge\s*(?:130|530|540|830|840|1030|1040|1050|explore|mtb)\b|wahoo\s*elemnt|bryton\s*rider|igpsport\s*(?:bsc|igs)|coros\s*dura)\b"#, options: .regularExpression) != nil {
            return .bikeComputer
        }
        if q.range(of: #"\b(orologi[o]?|smartwatch|sportwatch|cardiofrequenzimetr[oi]|forerunner|fenix|instinct|epix|venu|vivoactive|garmin\s*enduro|coros\s*(?:pace|apex|vertix)|suunto\s*(?:race|vertical|run|9\s*peak)|polar\s*(?:vantage|pacer|grit|ignite|unite)|amazfit\s*(?:t[\s-]*rex|cheetah|balance))\b"#, options: .regularExpression) != nil {
            return .gpsWatch
        }
        if q.range(of: #"\b(occhial[ie]|sunglasses|eyewear|oakley\s*(?:sutro|radar|jawbreaker|encoder|holbrook)|sutro|radar\s*ev|jawbreaker)\b"#, options: .regularExpression) != nil {
            return .eyewear
        }
        if q.range(of: #"\b(zain[oi]|gilet\s*(?:idratazione|trail)|active\s*skin|adv\s*skin|borracc(?:ia|e|ie)|soft\s*flask|idratazione)\b"#, options: .regularExpression) != nil {
            return .hydration
        }
        if q.range(of: #"\b(racchett[ae]|pala\s*padel|bullpadel\s*(?:vertex|hack|neuron|xplo|flow|elite)|nox\s*(?:at10|ml10))\b"#, options: .regularExpression) != nil && !q.contains("scarp") {
            return .padelRacket
        }
        if q.range(of: #"\b(cappellin[oi]|cappell[oi]|visier[ae]|berrett[oi]|scaldacollo|fascia\s*(?:da\s*)?testa)\b"#, options: .regularExpression) != nil && !q.contains("scarp") {
            return .headwear
        }
        if q.range(of: #"\b(calz[ae]|calzin[oi]|calzetton[ei]|socks?)\b"#, options: .regularExpression) != nil {
            return .socks
        }
        if q.range(of: #"\b(scarp[ae]\s*(?:da\s*)?basket|lebron|kobe|giannis|luka|caitlin|sabrina|kd\s*\d+|harden|dame)\b"#, options: .regularExpression) != nil &&
           q.range(of: #"\b(magli[ae]|canott[ae]|pantaloncin[oi]|calz[ae]|pallon[ei])\b"#, options: .regularExpression) == nil {
            return .basketballShoes
        }
        if q.range(of: #"\b(scarp[ae]\s*(?:da\s*)?padel|padel\s*(?:shoes?|scarp[ae])|bullpadel\s*(?:hack|vertex|next|pearl|elite)\s*(?:hybrid|vibram|knit|pro)|babolat\s*(?:jet\s*premura|movea|sensa)|nox\s*(?:at10|ml10|nerbo)\s*lux)\b"#, options: .regularExpression) != nil &&
           q.range(of: #"\b(racchett[ae]|pala\s*padel|pallin[ae]|bors[ae]|borson[ei]|zain[oi]|overgrip)\b"#, options: .regularExpression) == nil {
            return .padelShoes
        }
        if q.range(of: #"\b(scarp[ae]\s*(?:da\s*)?tennis|gel[\s-]*resolution|court\s*ff|dedicate|nikecourt|barricade)\b"#, options: .regularExpression) != nil &&
           q.range(of: #"\b(racchett[ae]|pallin[ae]|pantaloncin[oi]|magli[ae])\b"#, options: .regularExpression) == nil {
            return .tennisShoes
        }
        if q.range(of: #"\b(scarp[ae]\s*(?:da\s*)?(?:pallavolo|volley)|sky\s*elite|metarise|wave\s*lightning|wave\s*momentum|netburner)\b"#, options: .regularExpression) != nil &&
           q.range(of: #"\b(ginocchier[ae]|manicotti|pallon[ei]|magli[ae]|pantaloncin[oi])\b"#, options: .regularExpression) == nil {
            return .volleyballShoes
        }
        let isShortSleeve = q.range(of: #"\b(short[\s-]*sleeve|manic(?:a|he)\s*cort[ae])\b"#, options: .regularExpression) != nil
        if q.range(of: #"\b(giacc(?:a|he)|jacket|antivento|anti\s+vento|windbreaker|k[\s-]*way)\b"#, options: .regularExpression) != nil {
            return .jacket
        }
        if q.range(of: #"\b(leggings?|leggins|legins|tights?|tight|calzamagli[ae]|fuseaux|pantacollant|collant)\b"#, options: .regularExpression) != nil {
            return .leggings
        }
        if !isShortSleeve && q.range(of: #"\b(pantaloncin[oi]|shorts?\b(?!\s*[-]?\s*sleeve)|pantalon[ie]|sprinter|ciclisti|bermuda)\b"#, options: .regularExpression) != nil {
            return .pants
        }
        if isShortSleeve || q.range(of: #"\b(magli[ae]|magliett[ae]|t[\s-]*shirt|long\s*sleeve|longsleeve|manic(?:a|he)|canott[ae]|singlet|half\s*zip|1/4\s*zip|quarter\s*zip|intimo\s*termic|felp[ae]|hoodie|fleece|pile\b)\b"#, options: .regularExpression) != nil {
            return .top
        }
        if q.range(of: #"\b(scarp[ae]|shoes?|sneakers?|pegasus|vomero|vaporfly|alphafly|nimbus|novablast|superblast|cumulus|kayano|clifton|bondi|ghost|glycerin|adizero|dropset|metcon|nano|deviate|velocity|tribase|zoom\s*fly|endorphin)\b"#, options: .regularExpression) != nil {
            return .shoes
        }
        return nil
    }

    private func detectSingleQueryKind(_ q: String) -> DetectedQueryKind? {
        if let explicit = detectExplicitQueryKind(q) {
            return explicit
        }
        if q.range(of: #"\b(nuot[ao]|nuotare|piscina)\b"#, options: .regularExpression) != nil { return .swim }
        if q.range(of: #"\b(calcetto|futsal|calcio\s*a\s*[57])\b"#, options: .regularExpression) != nil { return .footballBoots }
        if q.range(of: #"\bpadel\b"#, options: .regularExpression) != nil && !q.contains("scarp") { return .padelRacket }
        if q.range(of: #"\b(basket|pallacanestro)\b"#, options: .regularExpression) != nil && q.range(of: #"\b(magli[ae]|canott[ae]|pantaloncin[oi]|calz[ae]|pallon[ei])\b"#, options: .regularExpression) == nil { return .basketballShoes }
        if q.range(of: #"\b(tennis|terra\s*battuta)\b"#, options: .regularExpression) != nil && q.range(of: #"\b(racchett[ae]|pallin[ae]|pantaloncin[oi]|magli[ae])\b"#, options: .regularExpression) == nil { return .tennisShoes }
        if q.range(of: #"\b(pallavolo|volley)\b"#, options: .regularExpression) != nil && q.range(of: #"\b(ginocchier[ae]|manicotti|pallon[ei]|magli[ae]|pantaloncin[oi])\b"#, options: .regularExpression) == nil { return .volleyballShoes }
        if q.range(of: #"\b(running|corsa|maratona|trail|palestra|hyrox|ammortizzat[ae])\b"#, options: .regularExpression) != nil { return .shoes }
        // Bare primary-brand fallback defaults ONLY for fresh standalone queries
        if q.range(of: #"\b(garmin|coros|suunto|amazfit)\b"#, options: .regularExpression) != nil { return .gpsWatch }
        if q.range(of: #"\b(bryton|igpsport)\b"#, options: .regularExpression) != nil { return .bikeComputer }
        if q.range(of: #"\b(oakley|rudy\s*project|bliz)\b"#, options: .regularExpression) != nil { return .eyewear }
        if q.range(of: #"\bcamelbak\b"#, options: .regularExpression) != nil { return .hydration }
        if q.range(of: #"\bbullpadel\b"#, options: .regularExpression) != nil { return .padelRacket }
        return nil
    }

    private func detectExpectedQueryKind(query: String, contextQuery: String?, summary: String?) -> DetectedQueryKind? {
        let qLow = query.lowercased()
        if let explicitCurrent = detectExplicitQueryKind(qLow) {
            return explicitCurrent
        }
        if let ctx = contextQuery, !ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let turns = ctx.components(separatedBy: ">>")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
                .reversed()
            for turn in turns {
                if let pt = detectExplicitQueryKind(turn) { return pt }
            }
            for turn in turns {
                if let pt = detectSingleQueryKind(turn) { return pt }
            }
        }
        return detectSingleQueryKind(qLow)
    }

    private func isProductCompatible(_ product: MatchedProduct, with kind: DetectedQueryKind) -> Bool {
        let name = product.canonical_name.lowercased()
        let brand = (product.brand ?? "").lowercased()
        let offerTitles = product.offers.prefix(3).map { $0.title.lowercased() }.joined(separator: " ")
        let fullText = "\(name) \(brand) \(offerTitles)"
        let bestPrice = product.best_price ?? product.offers.first?.price ?? 0.0

        // Global junk filter (screen protectors, non-sport moto/marine/foosball items, used items)
        if fullText.range(of: #"\b(furygan|dainese|alpinestars|d3o\s*ghost|protezion[ei]\s+gomit|vetus|scambiatore\s+calore|garlando|calciobalilla|barbie|panzerglass|vetro\s*temp[ea]?rato|pellicol[ae]|idrogel|hydrogel|screen\s*protector|sportenzia|second\s*hand|iphone\s*\d+|birkenstock)\b"#, options: .regularExpression) != nil {
            return false
        }

        switch kind {
        case .heartRateMonitor:
            if bestPrice > 0 && bestPrice < 18 { return false }
            if fullText.range(of: #"\b(ricambi[oi]|replacement|cinghi[ae]|cavo\b|ricarica|caricabatteri|usb|speed\s*sensor|cadence|cadense|cadenza|zbike|smart\s*bike|bryton\s*rider|fanale|luce\b|radar\b|scarp[ae]|shoe|magli[ae]|pantaloncin[oi]|shorts?|giacc(?:a|he)|calz[ae]|zain[oi]|occhial[ie]|forerunner|fenix|instinct|epix|venu|vivoactive|enduro|coros\s*(?:pace|apex|vertix|nomad)|suunto\s*(?:race|vertical|9\s*peak|run)|polar\s*(?:vantage|pacer|grit|ignite|unite))\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(hrm|polar\s*h(?:9|10)|verity\s*sense|oh1|fasc(?:ia|e|ie)\s*cardio|cardiofrequenzimetr|heart\s*rate|heartrate|sensore\s*(?:cardio|cardiaco|frequenza\s*cardiaca|hr)|trackr\s*hr|tickr|fasc(?:ia|e|ie)\s*toracic[ae]|chest\s*strap)\b"#, options: .regularExpression) != nil

        case .gpsWatch:
            if fullText.range(of: #"\b(igpsport|bsc100|bsc200|bsc300|igs\d+|ciclocomputer|bike\s*computer|contachilometri|contatore|garmin\s*edge|\bedge\s*(?:530|540|830|840|1030|1040|explore)\b|bryton|wahoo\s*elemnt|supporto|staff[ae]|mount|cinturin[oi]|strap|bracelet|quickfit|custodi[ae]|cover|felp[ae]|pile\b|cardigan|polo\b|scarp[ae])\b"#, options: .regularExpression) != nil {
                return false
            }
            if bestPrice > 0 && bestPrice < 55 { return false }
            return fullText.range(of: #"\b(garmin|forerunner|fenix|instinct|epix|venu|vivoactive|polar|vantage|pacer|grit|ignite|suunto|coros|pace|apex|vertix|amazfit|orologi[o]?|smartwatch)\b"#, options: .regularExpression) != nil

        case .bikeComputer:
            if fullText.range(of: #"\b(supporto|sostegno|staff[ae]|manubrio|mount(?:ing|s)?|closethegap|cockpit|out[\s-]*front|k[\s-]*edge|cassette|vitesses?|pacco\s*pignoni|adattatore|adapter|custodi[ae]|cover|cinturin[oi]|forerunner|fenix|instinct|venu|scarp[ae])\b"#, options: .regularExpression) != nil {
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
            if fullText.range(of: #"\b(scarp[ae]|magli[ae]|pantaloncin[oi]|pallin[ae]|tub[oi]|overgrip|\bgrip\b|hesacore|ammortizzator|vibe\b|bors[ae]|borson[ei]|zain[oi]|marsupi[oi]|cube\b|sacc[ae]|portaracchett[ae]|telo\b|occhial[ie]|pit\s*viper|skysurfer)\b"#, options: .regularExpression) != nil {
                return false
            }
            if bestPrice > 0 && bestPrice < 38 { return false }
            return fullText.range(of: #"\b(bullpadel|nox|babolat|head|siux|starvie|kuikma|metalbone|adipower|racchett[ae]|pala|vertex|hack|at10)\b"#, options: .regularExpression) != nil

        case .headwear:
            if fullText.range(of: #"\b(scarp[ae]|magli[ae]|pantaloncin[oi]|orologi[o]?)\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(cappellin[oi]|visier[ae]|berrett[oi]|cap\b|beanie|visor|headband)\b"#, options: .regularExpression) != nil

        case .socks:
            if fullText.range(of: #"\b(scarp[ae]|ghost|pegasus|nimbus|clifton|bondi|magli[ae]|pantaloncin[oi]|orologi[o]?)\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(calz[ae]|calzin[oi]|calzetton[ei]|socks?)\b"#, options: .regularExpression) != nil

        case .jacket:
            return fullText.range(of: #"\b(giacc(?:a|he)|jacket|antivento|windbreaker|k[\s-]*way|gilet|guscio|impermeabil[ei])\b"#, options: .regularExpression) != nil

        case .leggings:
            if fullText.range(of: #"\b(scarp[ae]|shoe|shoes|sneakers?|magli[ae]|t[\s-]*shirt|shirt\b|tee\b|top\b|jsy\b|jersey|short[\s-]*sleeve|manic(?:a|he)|canott[ae]|singlet|giacc(?:a|he)|jacket|calz[ae]|calzin[oi]|socks?|orologi[o]?|zain[oi]|cappellin[oi]|reggisen[oi]|\bbra\b)\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(leggings?|leggins|tights?|tight|calzamagli[ae]|fuseaux|pantacollant|collant)\b"#, options: .regularExpression) != nil

        case .pants:
            if fullText.range(of: #"\b(scarp[ae]|shoe|shoes|sneakers?|magli[ae]|t[\s-]*shirt|shirt\b|tee\b|top\b|jsy\b|jersey|short[\s-]*sleeve|manic(?:a|he)|canott[ae]|singlet|giacc(?:a|he)|jacket|calz[ae]|calzin[oi]|socks?|orologi[o]?|zain[oi]|cappellin[oi])\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(pantaloncin[oi]|shorts?\b(?!\s*[-]?\s*sleeve)|leggings?|leggins|tights?|tight|calzamagli[ae]|pantalon[ie]|fuseaux|pantacollant|sprinter|ciclisti|bermuda)\b"#, options: .regularExpression) != nil

        case .top:
            if fullText.range(of: #"\b(scarp[ae]|pantaloncin[oi]|shorts?\b(?!\s*[-]?\s*sleeve)|leggings|calz[ae]|orologi[o]?|zain[oi]|cappellin[oi]|cappell[oi]|visier[ae]|balaclava|scaldacollo)\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(magli[ae]|magliett[ae]|t[\s-]*shirt|shirt|tee\b|long\s*sleeve|longsleeve|\bls\b|short\s*sleeve|manic(?:a|he)|canott[ae]|singlet|tank|top|half\s*zip|1/4\s*zip|quarter\s*zip|zip\s*top|zip\s*met[aà]|cloudspun|felp[ae]|hoodie|sweatshirt|pullover|midlayer|base\s*layer|intimo\s*termic|termic[ao]|therma[\s-]*fit|fleece|pile\b|polar\b|girocollo|wolf\s*grid|wolf\s*tree|wolf\s*lichen|chinati|wildsee)\b"#, options: .regularExpression) != nil

        case .basketballShoes:
            if fullText.range(of: #"\b(nimbus|bondi|clifton|novablast|cumulus|kayano|ghost|glycerin|speedgoat|trabuco|magli[ae]|canott[ae]|pantaloncin[oi]|calz[ae]|cappellin[oi]|zain[oi]|orologi[o]?|pallon[ei])\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(basket|pallacanestro|lebron|kobe|giannis|luka|caitlin|sabrina|kd\s*\d+|harden|dame|jordan|curry|kyrie)\b"#, options: .regularExpression) != nil

        case .tennisShoes:
            if fullText.range(of: #"\b(nimbus|bondi|clifton|novablast|cumulus|kayano|ghost|glycerin|pegasus|speedgoat|magli[ae]|pantaloncin[oi]|calz[ae]|cappellin[oi]|zain[oi]|orologi[o]?|racchett[ae]|pallin[ae]|cord[ae])\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(tennis|terra\s*battuta|clay|resolution|court\s*ff|dedicate|nikecourt|barricade|vapor|challenger|rush\s*pro|jet\s*mach)\b"#, options: .regularExpression) != nil

        case .padelShoes:
            if fullText.range(of: #"\b(racchett[ae]|pala\s*padel|pallin[ae]|overgrip|hesacore|bors[ae]|borson[ei]|paletero|zain[oi]|magli[ae]|pantaloncin[oi]|shorts?|calz[ae]|cappellin[oi]|orologi[o]?|nimbus|bondi|clifton|novablast|cumulus|kayano|ghost|glycerin|pegasus|speedgoat|trail|calcio|calcetto)\b"#, options: .regularExpression) != nil {
                return false
            }
            if bestPrice > 0 && bestPrice < 30 { return false }
            return fullText.range(of: #"\b(padel|premura|movea|sensa|hack\s*vibram|vertex\s*vibram|next\s*pro|hybrid\s*fly|sonicsmash|challenger\s*\d*\s*padel|dedicate\s*\d*\s*padel|resolution\s*\d*\s*padel|crazyquick\s*boost|at10\s*lux|ml10\s*lux|nerbo\s*lux|motion\s*pro|sprint\s*pro|revolt\s*pro|hurakn|bela\s*pro|kuikma\s*ps)\b"#, options: .regularExpression) != nil

        case .volleyballShoes:
            if fullText.range(of: #"\b(nimbus|bondi|clifton|novablast|cumulus|kayano|ghost|glycerin|pegasus|speedgoat|magli[ae]|pantaloncin[oi]|calz[ae]|cappellin[oi]|zain[oi]|orologi[o]?|pallon[ei]|ginocchier[ae])\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(pallavolo|volley|spike|sky\s*elite|metarise|wave\s*lightning|wave\s*momentum|netburner|upcourt|gel[\s-]*task)\b"#, options: .regularExpression) != nil

        case .shoes:
            if fullText.range(of: #"\b(orologi[o]?|smartwatch|garmin|polar|suunto|coros|igpsport|bsc100|bsc200|ciclocomputer|bike\s*computer|contatore|magli[ae]|magliett[ae]|t[\s-]*shirt|shirt|tee\b|jsy\b|jersey\b|top\s*ss\b|crew\s*top\b|trk\s*jkt\b|pant\s*kp\b|dry\s*park\d*|park\s*20\b|woven\b|long\s*sleeve|longsleeve|manic(?:a|he)|canott[ae]|canottier[ae]|singlet|snglt|tank|crop|reggisen[oi]|bra\b|pantaloncin[oi]|shorts?|leggings?|leggins|tights?|calzamagli[ae]|fuseaux|coscial[ei]|pacer|2in1|3inch|giacc(?:a|he)|jacket|jkt|felp[ae]|hoodie|pantalon[ie]|pants\b|costum[ei]|mut[ae]|calz[ae]|calzin[oi]|socks?|cappellin[oi]|visier[ae]|berrett[oi]|cappell[oi]|zain[oi]|marsupi[oi]|bors[ae]|borracc|guant[oi]|casch?[oi]|ciabatt[ae]|sandal[oi]|adilette|birkenstock|rull[oi]|bike\s*trainer|occhial[ie]|racchett[ae]|crankbrothers|scarpin[oi]|calcio|calcetto|futsal|mercurial|predator|\bxcs\b|avanti\s*tyo|ambition|finesse|prime\s*sp|distancestar|sprintstar|throwstar|chiodat[ae])\b"#, options: .regularExpression) != nil {
                return false
            }
            return true

        case .footballBoots:
            if fullText.range(of: #"\b(magli[ae]|jersey|t[\s-]*shirt|pantaloncin[oi]|shorts?|calz[ae]|calzetton[ei]|socks?|parastinchi|guant[oi]|pallon[ei]|borson[ei]|zain[oi])\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(scarpin[oi]|calcio|calcetto|futsal|mercurial|superfly|vapor|tiempo|phantom|predator|copa|future|magnetico|f50|top\s*sala|top\s*flex|\bfg\b|\bag\b|\btf\b|\bmg\b|\bsg\b)\b"#, options: .regularExpression) != nil

        case .swim:
            if fullText.range(of: #"\b(scarp[ae]|oakley|sutro|radar|jawbreaker|magli[ae]|pantaloncin[oi]|calz[ae]|orologi[o]?|ciclocomputer)\b"#, options: .regularExpression) != nil {
                return false
            }
            return fullText.range(of: #"\b(occhialin[oi]|goggles|nuot[ao]|piscina|arena|speedo|biofuse|futura|cobra\s*ultra|swipe|tyr|nabaiji|costum[ei]\s*(?:bagno|nuoto)|cuffi[ae])\b"#, options: .regularExpression) != nil
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
        let effGender = detectGenderConstraint(query: query, contextQuery: contextQuery, intentGender: response.intent?.gender)
        var validResults = response.results.filter { isProductCompatible($0, with: kind) && matchesGenderConstraint($0, gender: effGender) }

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

        let serverSource = response.intent?.source ?? ""
        let isPrecisionServerV2 = serverSource.hasPrefix("supabase_edge_v2") || serverSource.hasPrefix("supabase_edge_v3")
        // For v3 Shop-grade server responses, the server already ran strict product-type, brand, price, size, color, store & gender gating
        // and built disjoint thematic sections + grounded featured cards — preserve them cleanly, with a defensive price ceiling check.
        if serverSource.hasPrefix("supabase_edge_v3") {
            let ceiling = maxPrice ?? response.intent?.max_price
            guard let maxP = ceiling, maxP > 0 else {
                return response
            }
            let floorP = response.intent?.min_price
            let filterProduct: (MatchedProduct) -> MatchedProduct? = { prod in
                let okOffers = prod.offers.filter { o in
                    o.price <= maxP + 0.01 && (floorP == nil || o.price >= floorP! - 0.01)
                }
                guard !okOffers.isEmpty else { return nil }
                let minPriceVal = okOffers.map(\.price).min() ?? prod.best_price
                let maxPriceVal = okOffers.map(\.price).max() ?? prod.highest_price
                return MatchedProduct(
                    id_val: prod.id,
                    canonical_name: prod.canonical_name,
                    brand: prod.brand,
                    image_url: prod.image_url,
                    gallery_images: prod.gallery_images,
                    gender: prod.gender,
                    offers: okOffers,
                    best_price: minPriceVal,
                    highest_price: maxPriceVal,
                    cross_store_savings: prod.cross_store_savings
                )
            }
            let filteredResults = response.results.compactMap(filterProduct)
            if filteredResults.count == response.results.count {
                return response
            }
            let filteredSections = response.curated_sections?.compactMap { sec -> CuratedProductSection? in
                let prods = sec.products.compactMap(filterProduct)
                guard !prods.isEmpty else { return nil }
                return CuratedProductSection(id: sec.id, title: sec.title, subtitle: sec.subtitle, products: prods)
            }
            return SmartSearchResponse(
                search_mode: response.search_mode,
                is_deep_dive: response.is_deep_dive,
                is_conversational_advice: response.is_conversational_advice,
                conversational_header: response.conversational_header,
                conversational_summary: response.conversational_summary,
                searched_queries: response.searched_queries,
                curated_sections: filteredSections,
                comparative_cards: response.comparative_cards,
                featured_cards: response.featured_cards,
                spotlight: response.spotlight,
                follow_up_suggestions: response.follow_up_suggestions,
                intent: response.intent,
                chips: response.chips,
                total_found: filteredResults.count,
                has_more: response.has_more,
                context_state: response.context_state,
                results: filteredResults,
                is_off_topic: response.is_off_topic,
                is_unsafe: response.is_unsafe,
                session_id: response.session_id,
                turn_id: response.turn_id,
                user_image_url: response.user_image_url
            )
        }
        // Never pollute clean exact-model results (e.g. 1-4 exact model variants) with generic category fallbacks!
        // Only run direct fallback enrichment if the server returned 0 valid products (and wasn't an intentional empty v2 response)
        // or if a legacy server returned mostly incompatible items.
        let needsDirectEnrichment = !isPrecisionServerV2 && (
            validResults.isEmpty ||
            (response.results.count >= 5 && Double(validResults.count) / Double(response.results.count) < 0.5)
        )

        var finalResults = validResults
        if needsDirectEnrichment {
            let fallbackCategory: String
            var fallbackKeywords: [String]
            switch kind {
            case .heartRateMonitor:
                fallbackCategory = "sensor"
                fallbackKeywords = ["polar h10", "polar h9", "hrm 200", "hrm 600", "fascia cardio"]
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
            case .headwear:
                fallbackCategory = "accessories"
                fallbackKeywords = ["cappellino", "visiera", "running cap"]
            case .socks:
                fallbackCategory = "socks"
                fallbackKeywords = ["asics calze", "nike", "salomon", "compressport", "uyn"]
            case .jacket:
                fallbackCategory = "jacket"
                fallbackKeywords = ["giacca antivento", "salomon bonatti", "nike stride", "adizero", "odlo"]
            case .leggings:
                fallbackCategory = "pants"
                fallbackKeywords = ["leggings", "tights", "calzamaglia", "fuseaux"]
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
            case .footballBoots:
                fallbackCategory = "football_boots"
                fallbackKeywords = ["mercurial", "predator", "phantom", "tiempo", "top sala", "top flex", "calcio"]
            case .basketballShoes:
                fallbackCategory = "running_shoes"
                fallbackKeywords = ["basket", "luka", "caitlin", "lebron", "jordan", "kobe"]
            case .tennisShoes:
                fallbackCategory = "running_shoes"
                fallbackKeywords = ["tennis", "terra battuta", "resolution", "dedicate", "nikecourt"]
            case .padelShoes:
                fallbackCategory = "shoes"
                fallbackKeywords = ["padel", "bullpadel", "asics padel", "babolat padel", "head padel"]
            case .volleyballShoes:
                fallbackCategory = "running_shoes"
                fallbackKeywords = ["pallavolo", "volley", "sky elite", "wave lightning", "spike"]
            case .swim:
                fallbackCategory = "swim"
                fallbackKeywords = ["occhialini", "arena", "speedo", "biofuse", "cobra", "nuoto"]
            case .shoes:
                fallbackCategory = "running_shoes"
                let qLow = query.lowercased()
                if qLow.contains("dropset") || qLow.contains("hyrox") {
                    fallbackKeywords = ["dropset", "deviate nitro", "velocity nitro", "metcon", "hyrox"]
                } else if qLow.contains("zoom fly") {
                    fallbackKeywords = ["nike zoom fly", "zoom fly 6", "zoom fly"]
                } else if qLow.contains("endorphin") {
                    fallbackKeywords = ["saucony endorphin", "endorphin pro", "endorphin speed"]
                } else {
                    fallbackKeywords = ["nike pegasus", "asics nimbus", "asics novablast", "hoka clifton", "brooks ghost", "new balance 1080", "adidas adizero", "saucony"]
                }
            }

            var directProds = await SupabaseManager.shared.fetchSmartProductsDirect(
                category: fallbackCategory,
                keywords: fallbackKeywords,
                brand: response.intent?.brand,
                gender: effGender,
                maxPrice: effMaxPrice,
                size: size ?? response.intent?.size,
                store: store,
                limit: 35
            ).filter { isProductCompatible($0, with: kind) && matchesGenderConstraint($0, gender: effGender) }

            // If brand-specific direct enrichment yielded < 3 total items, supplement with multi-brand alternatives
            if finalResults.count + directProds.count < 3 && response.intent?.brand != nil {
                let altProds = await SupabaseManager.shared.fetchSmartProductsDirect(
                    category: fallbackCategory,
                    keywords: fallbackKeywords,
                    brand: nil,
                    gender: effGender,
                    maxPrice: effMaxPrice,
                    size: size ?? response.intent?.size,
                    store: store,
                    limit: 20
                ).filter { isProductCompatible($0, with: kind) && matchesGenderConstraint($0, gender: effGender) }
                directProds.append(contentsOf: altProds)
            }

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
            var validSecProds = sec.products.filter { isProductCompatible($0, with: kind) && matchesGenderConstraint($0, gender: effGender) }
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

        // Clean featured cards
        let cleanedFeatured = (response.featured_cards ?? []).filter { isProductCompatible($0.product, with: kind) }

        return SmartSearchResponse(
            search_mode: response.search_mode,
            is_deep_dive: response.is_deep_dive,
            is_conversational_advice: response.is_conversational_advice,
            conversational_header: response.conversational_header,
            conversational_summary: response.conversational_summary,
            searched_queries: response.searched_queries,
            curated_sections: cleanedSections,
            comparative_cards: isPrecisionServerV2 ? (response.comparative_cards ?? []) : cleanedComps,
            featured_cards: cleanedFeatured.isEmpty ? (cleanedSpotlight.map { [$0] } ?? []) : cleanedFeatured,
            spotlight: cleanedSpotlight,
            follow_up_suggestions: response.follow_up_suggestions,
            intent: response.intent,
            chips: response.chips,
            total_found: finalResults.count,
            results: finalResults,
            is_off_topic: response.is_off_topic,
            is_unsafe: response.is_unsafe,
            session_id: response.session_id,
            turn_id: response.turn_id,
            user_image_url: response.user_image_url
        )
    }

    func getAIAdvice(
        prompt: String,
        sessionId: String? = nil,
        deviceId: String? = nil,
        userId: String? = nil
    ) async throws -> AIAdviceResponse {
        var components = URLComponents(string: "\(edgeFunctionsBaseURL)/ai-advise")!
        var items = [URLQueryItem(name: "prompt", value: prompt)]
        if let sid = sessionId, !sid.isEmpty {
            items.append(URLQueryItem(name: "session_id", value: sid))
        }
        if let did = deviceId, !did.isEmpty {
            items.append(URLQueryItem(name: "device_id", value: did))
        }
        let resolvedUid = await resolveUserId(userId)
        if let uid = resolvedUid, !uid.isEmpty {
            items.append(URLQueryItem(name: "user_id", value: uid))
        }
        components.queryItems = items

        guard let url = components.url else { throw URLError(.badURL) }

        let data = try await fetchEdgeDataWithRetry(url: url)
        return try JSONDecoder().decode(AIAdviceResponse.self, from: data)
    }

    // MARK: - Persistent Chat History API

    func fetchChatSessions(deviceId: String, userId: String? = nil, limit: Int = 20) async -> [ChatSessionSummary] {
        let resolvedUid = await resolveUserId(userId)
        return await SupabaseManager.shared.fetchChatSessionsDirect(deviceId: deviceId, userId: resolvedUid, limit: limit)
    }

    func fetchChatSessionDetail(sessionId: String) async -> ChatSessionDetail? {
        return await SupabaseManager.shared.fetchChatSessionDetailDirect(sessionId: sessionId)
    }

    func deleteChatSession(sessionId: String, deviceId: String) async -> Bool {
        return await SupabaseManager.shared.deleteChatSessionDirect(sessionId: sessionId, deviceId: deviceId)
    }

    func submitChatTurnFeedback(sessionId: String, turnId: String, feedback: Int) async {
        _ = await SupabaseManager.shared.updateChatMessageFeedbackDirect(
            sessionId: sessionId,
            turnId: turnId,
            feedback: feedback
        )
    }

    func compareModels(modelA: String, modelB: String) async throws -> ModelComparisonResponse {
        var components = URLComponents(string: "\(edgeFunctionsBaseURL)/ai-compare")!
        components.queryItems = [
            URLQueryItem(name: "model_a", value: modelA),
            URLQueryItem(name: "model_b", value: modelB)
        ]

        guard let url = components.url else { throw URLError(.badURL) }

        let data = try await fetchEdgeDataWithRetry(url: url)
        return try JSONDecoder().decode(ModelComparisonResponse.self, from: data)
    }

    func searchCatalog(query: String = "", category: String? = nil, limit: Int = 40) async throws -> [MatchedProduct] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let effCat = (category != nil && category != "all" && category != "tutti") ? category : nil
        let direct = await SupabaseManager.shared.fetchSmartProductsDirect(
            category: effCat,
            keywords: trimmed.isEmpty ? [] : [trimmed],
            limit: limit
        )
        if !direct.isEmpty {
            return direct
        }

        var components = URLComponents(string: "\(baseURL)/api/catalog")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if !trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: trimmed))
        }
        if let cat = effCat, !cat.isEmpty {
            queryItems.append(URLQueryItem(name: "category", value: cat))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw URLError(.badURL) }
        let data = try await fetchDataWithRetry(url: url)
        struct CatalogResultResponse: Decodable {
            let results: [MatchedProduct]
        }
        let decoded = try JSONDecoder().decode(CatalogResultResponse.self, from: data)
        return decoded.results
    }

    func getStats() async throws -> CatalogStatsResponse {
        guard let url = URL(string: "\(baseURL)/api/stats") else { throw URLError(.badURL) }
        let data = try await fetchDataWithRetry(url: url)
        return try JSONDecoder().decode(CatalogStatsResponse.self, from: data)
    }

    /// Returns memory-cached or disk-cached home showcases synchronously for zero-skeleton cold starts.
    func cachedHomeShowcases() -> [StoreShowcase]? {
        if let mem = homeShowcasesCache, !mem.showcases.isEmpty {
            return mem.showcases
        }
        guard let data = try? Data(contentsOf: homeCacheFileURL),
              let decoded = try? JSONDecoder().decode([StoreShowcase].self, from: data),
              !decoded.isEmpty else {
            return nil
        }
        // Populate memory cache with a short 2-minute TTL so background SWR refresh still runs when stale
        homeShowcasesCache = (decoded, Date().addingTimeInterval(120))
        return decoded
    }

    func isHomeCacheFresh() -> Bool {
        if let mem = homeShowcasesCache, !mem.showcases.isEmpty {
            return Date() < mem.expiry
        }
        return false
    }

    private func persistHomeShowcasesToDisk(_ showcases: [StoreShowcase]) {
        guard !showcases.isEmpty else { return }
        let targetURL = homeCacheFileURL
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(showcases) {
                try? data.write(to: targetURL, options: .atomic)
            }
        }
    }

    func getStoreShowcases(forceRefresh: Bool = false) async throws -> [StoreShowcase] {
        if !forceRefresh, let mem = homeShowcasesCache, !mem.showcases.isEmpty, Date() < mem.expiry {
            return mem.showcases
        }

        if let existingTask = inFlightHomeShowcasesTask {
            return try await existingTask.value
        }

        let task = Task<[StoreShowcase], Error> {
            // 1. Direct Supabase Cloud database query (single fast RPC + parallel fallback)
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

        inFlightHomeShowcasesTask = task
        defer { inFlightHomeShowcasesTask = nil }

        let result = try await task.value
        if !result.isEmpty {
            homeShowcasesCache = (result, Date().addingTimeInterval(300))
            persistHomeShowcasesToDisk(result)
        }
        return result
    }

    // MARK: - Home Personalized & Comparator Highlights Cache (Memory + Disk SWR)

    private struct DiskHomeHighlightsEnvelope: Codable {
        let key: String
        let bundle: HomeHighlightsBundle
    }

    func homeHighlightsCacheKey(
        shoeSize: String?,
        apparelSize: String?,
        sports: [String],
        brands: [String],
        hiddenStores: [String]
    ) -> String {
        let s = (shoeSize ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let a = (apparelSize ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sp = sports.map { $0.lowercased() }.sorted().joined(separator: ",")
        let br = brands.map { $0.lowercased() }.sorted().joined(separator: ",")
        let hd = hiddenStores.map { $0.lowercased() }.sorted().joined(separator: ",")
        return "\(s)|\(a)|\(sp)|\(br)|\(hd)"
    }

    func cachedHomeHighlights(for key: String) -> HomeHighlightsBundle? {
        if let mem = homeHighlightsCache[key], !mem.bundle.isEmpty {
            return mem.bundle
        }
        guard let data = try? Data(contentsOf: homeHighlightsCacheFileURL),
              let envelope = try? JSONDecoder().decode(DiskHomeHighlightsEnvelope.self, from: data),
              envelope.key == key,
              !envelope.bundle.isEmpty else {
            return nil
        }
        homeHighlightsCache[key] = (envelope.bundle, Date().addingTimeInterval(120))
        return envelope.bundle
    }

    func isHomeHighlightsCacheFresh(for key: String) -> Bool {
        if let mem = homeHighlightsCache[key], !mem.bundle.isEmpty {
            return Date() < mem.expiry
        }
        return false
    }

    private func persistHomeHighlightsToDisk(key: String, bundle: HomeHighlightsBundle) {
        guard !bundle.isEmpty else { return }
        let targetURL = homeHighlightsCacheFileURL
        let envelope = DiskHomeHighlightsEnvelope(key: key, bundle: bundle)
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(envelope) {
                try? data.write(to: targetURL, options: .atomic)
            }
        }
    }

    func getHomeHighlights(
        shoeSize: String?,
        apparelSize: String?,
        sports: [String],
        brands: [String],
        hiddenStores: [String],
        limitPerSection: Int = 10,
        forceRefresh: Bool = false
    ) async throws -> HomeHighlightsBundle {
        let key = homeHighlightsCacheKey(
            shoeSize: shoeSize,
            apparelSize: apparelSize,
            sports: sports,
            brands: brands,
            hiddenStores: hiddenStores
        )
        if !forceRefresh, let mem = homeHighlightsCache[key], !mem.bundle.isEmpty, Date() < mem.expiry {
            return mem.bundle
        }
        if !forceRefresh, let existing = inFlightHomeHighlightsTasks[key] {
            return try await existing.value
        }

        let task = Task<HomeHighlightsBundle, Error> {
            try await SupabaseManager.shared.fetchHomeHighlightsDirect(
                shoeSize: shoeSize,
                apparelSize: apparelSize,
                sports: sports,
                brands: brands,
                hiddenStores: hiddenStores,
                limitPerSection: limitPerSection
            )
        }
        inFlightHomeHighlightsTasks[key] = task
        defer { inFlightHomeHighlightsTasks[key] = nil }

        let result = try await task.value
        if !result.isEmpty {
            homeHighlightsCache[key] = (result, Date().addingTimeInterval(300))
            persistHomeHighlightsToDisk(key: key, bundle: result)
        }
        return result
    }

    // MARK: - Following Feed ("Segui già") Cache (Memory + Disk SWR)

    private struct DiskFollowingFeedEnvelope: Codable {
        let key: String
        let bundle: FollowingFeedBundle
    }

    func followingFeedCacheKey(
        storeIds: [String],
        mode: FollowingFeedMode,
        onlyMySize: Bool,
        shoeSize: String?,
        apparelSize: String?,
        sports: [String],
        brands: [String]
    ) -> String {
        let st = storeIds.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ",")
        let s = (shoeSize ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let a = (apparelSize ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sp = sports.map { $0.lowercased() }.sorted().joined(separator: ",")
        let br = brands.map { $0.lowercased() }.sorted().joined(separator: ",")
        return "\(st)|\(mode.rawValue)|\(onlyMySize ? "1" : "0")|\(s)|\(a)|\(sp)|\(br)"
    }

    func cachedFollowingFeed(for key: String) -> FollowingFeedBundle? {
        if let mem = followingFeedCache[key], !mem.bundle.isEmpty {
            return mem.bundle
        }
        guard let data = try? Data(contentsOf: followingFeedCacheFileURL),
              let envelope = try? JSONDecoder().decode(DiskFollowingFeedEnvelope.self, from: data),
              envelope.key == key,
              !envelope.bundle.isEmpty else {
            return nil
        }
        followingFeedCache[key] = (envelope.bundle, Date().addingTimeInterval(120))
        return envelope.bundle
    }

    func isFollowingFeedCacheFresh(for key: String) -> Bool {
        if let mem = followingFeedCache[key], !mem.bundle.isEmpty {
            return Date() < mem.expiry
        }
        return false
    }

    private func persistFollowingFeedToDisk(key: String, bundle: FollowingFeedBundle) {
        guard !bundle.isEmpty else { return }
        let targetURL = followingFeedCacheFileURL
        let envelope = DiskFollowingFeedEnvelope(key: key, bundle: bundle)
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(envelope) {
                try? data.write(to: targetURL, options: .atomic)
            }
        }
    }

    func getFollowingFeed(
        storeIds: [String],
        mode: FollowingFeedMode = .all,
        onlyMySize: Bool = false,
        shoeSize: String? = nil,
        apparelSize: String? = nil,
        sports: [String] = [],
        brands: [String] = [],
        perStore: Int = 12,
        highlightsLimit: Int = 12,
        forceRefresh: Bool = false
    ) async throws -> FollowingFeedBundle {
        let key = followingFeedCacheKey(
            storeIds: storeIds,
            mode: mode,
            onlyMySize: onlyMySize,
            shoeSize: shoeSize,
            apparelSize: apparelSize,
            sports: sports,
            brands: brands
        )
        if !forceRefresh, let mem = followingFeedCache[key], !mem.bundle.isEmpty, Date() < mem.expiry {
            return mem.bundle
        }
        if !forceRefresh, let existing = inFlightFollowingTasks[key] {
            return try await existing.value
        }

        let task = Task<FollowingFeedBundle, Error> {
            try await SupabaseManager.shared.fetchFollowingFeedDirect(
                storeIds: storeIds,
                mode: mode,
                onlyMySize: onlyMySize,
                shoeSize: shoeSize,
                apparelSize: apparelSize,
                sports: sports,
                brands: brands,
                perStore: perStore,
                highlightsLimit: highlightsLimit
            )
        }
        inFlightFollowingTasks[key] = task
        defer { inFlightFollowingTasks[key] = nil }

        let result = try await task.value
        if !result.isEmpty {
            followingFeedCache[key] = (result, Date().addingTimeInterval(240))
            if mode == .all && !onlyMySize {
                persistFollowingFeedToDisk(key: key, bundle: result)
            }
        }
        return result
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

    func cachedDealsShowcases(for category: String?, filters: DealsFilterOptions = DealsFilterOptions()) -> [StoreShowcase]? {
        let catKey = (category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "tutti"
        let key = "\(catKey)_\(filters.cacheKeySuffix)"
        guard let cached = dealsShowcasesCache[key], Date() < cached.expiry else {
            return nil
        }
        return cached.showcases
    }

    func cachedTopDealsCrossStore(for category: String?, filters: DealsFilterOptions = DealsFilterOptions()) -> (deals: [StoreShowcaseProduct], total: Int)? {
        let catKey = (category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "tutti"
        let key = "\(catKey)_\(filters.cacheKeySuffix)"
        guard let cached = topDealsCrossStoreCache[key], Date() < cached.expiry else {
            return nil
        }
        return (cached.deals, cached.total)
    }

    func prefetchDefaultDealsIfNeeded() async {
        let needShowcases = cachedDealsShowcases(for: "tutti") == nil
        let needTopDeals = cachedTopDealsCrossStore(for: "tutti") == nil
        guard needShowcases || needTopDeals else { return }
        async let showcasesPrefetch: Void = {
            if needShowcases {
                _ = try? await self.getDealsShowcases(category: nil, filters: DealsFilterOptions(), forceRefresh: false)
            }
        }()
        async let topDealsPrefetch: Void = {
            if needTopDeals {
                _ = try? await self.getTopDealsCrossStore(category: nil, filters: DealsFilterOptions(), limit: 40, forceRefresh: false)
            }
        }()
        _ = await (showcasesPrefetch, topDealsPrefetch)
    }

    func getTopDealsCrossStore(
        category: String? = nil,
        filters: DealsFilterOptions = DealsFilterOptions(),
        limit: Int = 40,
        offset: Int = 0,
        forceRefresh: Bool = false
    ) async throws -> (deals: [StoreShowcaseProduct], totalMatching: Int) {
        let catKey = (category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "tutti"
        let cacheKey = "\(catKey)_\(filters.cacheKeySuffix)"

        // Paginated subsequent pages bypass first-page cache and fetch directly by offset
        if offset > 0 {
            let page = try await SupabaseManager.shared.fetchTopDealsCrossStoreDirect(
                category: category,
                filters: filters,
                limit: limit,
                offset: offset
            )
            if let existing = topDealsCrossStoreCache[cacheKey], !page.deals.isEmpty {
                var existingIds = Set(existing.deals.map(\.id))
                let appended = page.deals.filter { existingIds.insert($0.id).inserted }
                if !appended.isEmpty {
                    let merged = existing.deals + appended
                    topDealsCrossStoreCache[cacheKey] = (merged, max(existing.total, page.totalMatching), Date().addingTimeInterval(300))
                }
            }
            return page
        }

        if !forceRefresh, let cached = topDealsCrossStoreCache[cacheKey], Date() < cached.expiry {
            return (cached.deals, cached.total)
        }
        if !forceRefresh, let existing = inFlightTopDealsTasks[cacheKey] {
            return try await existing.value
        }

        let task = Task<(deals: [StoreShowcaseProduct], totalMatching: Int), Error> {
            try await SupabaseManager.shared.fetchTopDealsCrossStoreDirect(
                category: category,
                filters: filters,
                limit: limit,
                offset: 0
            )
        }
        inFlightTopDealsTasks[cacheKey] = task
        defer { inFlightTopDealsTasks[cacheKey] = nil }

        let result = try await task.value
        topDealsCrossStoreCache[cacheKey] = (result.deals, result.totalMatching, Date().addingTimeInterval(300))
        return result
    }

    func getDealsShowcases(
        category: String? = nil,
        filters: DealsFilterOptions = DealsFilterOptions(),
        forceRefresh: Bool = false
    ) async throws -> [StoreShowcase] {
        let catKey = (category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "tutti"
        let cacheKey = "\(catKey)_\(filters.cacheKeySuffix)"

        if !forceRefresh, let cached = dealsShowcasesCache[cacheKey], Date() < cached.expiry {
            return cached.showcases
        }

        if !forceRefresh, let existingTask = inFlightDealsTasks[cacheKey] {
            return try await existingTask.value
        }

        let task = Task<[StoreShowcase], Error> {
            do {
                let direct = try await SupabaseManager.shared.fetchDealsShowcasesDirect(
                    category: category,
                    filters: filters
                )
                // Only fall back to general store showcases for default "tutti" if direct returned empty;
                // for filtered or specific categories, the RPC evaluates the entire catalog authoritatively.
                if !direct.isEmpty || catKey != "tutti" || !filters.isDefault {
                    return direct
                }
            } catch {
                print("APIService fetchDealsShowcasesDirect error: \(error)")
                if !filters.isDefault {
                    throw error
                }
            }

            // Fallback when RPC/Supabase direct failed (default filters only)
            guard catKey != "tutti" else {
                return try await getStoreShowcases()
            }

            let allStores = try await getStoreShowcases()
            return filterShowcasesByCategory(allStores, category: catKey)
        }

        inFlightDealsTasks[cacheKey] = task
        defer { inFlightDealsTasks[cacheKey] = nil }

        let result = try await task.value
        dealsShowcasesCache[cacheKey] = (result, Date().addingTimeInterval(300))
        return result
    }

    private func filterShowcasesByCategory(_ showcases: [StoreShowcase], category: String) -> [StoreShowcase] {
        let cat = category.lowercased()
        guard cat != "tutti" && !cat.isEmpty else { return showcases }

        var filtered: [StoreShowcase] = []
        for sc in showcases {
            let matched = sc.products.filter {
                CategoryFilterMatcher.matches(title: $0.title, category: cat, brand: $0.brand)
            }
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

    func getStoreDetails(
        storeId: String,
        query: String = "",
        sort: String = "recommended",
        preferredSize: String? = nil
    ) async throws -> StoreDetailResponse {
        return try await SupabaseManager.shared.fetchStoreDetailsDirect(
            storeId: storeId,
            query: query,
            sort: sort,
            preferredSize: preferredSize,
            limit: 40
        )
    }

    func getStoreCatalogPage(
        storeId: String,
        query: String = "",
        category: String = "tutti",
        brand: String? = nil,
        size: String? = nil,
        onlyDiscounted: Bool = false,
        maxPrice: Double? = nil,
        sort: String = "recommended",
        preferredSize: String? = nil,
        limit: Int = 40,
        offset: Int = 0
    ) async throws -> StoreCatalogPageResponse {
        return try await SupabaseManager.shared.fetchStoreCatalogPageDirect(
            storeId: storeId,
            query: query,
            category: category,
            brand: brand,
            size: size,
            onlyDiscounted: onlyDiscounted,
            maxPrice: maxPrice,
            sort: sort,
            preferredSize: preferredSize,
            limit: limit,
            offset: offset
        )
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
        var components = URLComponents(string: "\(baseURL)/api/followed_stores")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "device_id", value: SupabaseManager.shared.deviceId)
        ]
        if let uid = SupabaseManager.shared.validCurrentUserId {
            items.append(URLQueryItem(name: "user_id", value: uid))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw URLError(.badURL) }
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
        var body: [String: Any] = [
            "store_id": storeId.lowercased(),
            "store_name": storeName,
            "device_id": SupabaseManager.shared.deviceId
        ]
        if let uid = SupabaseManager.shared.validCurrentUserId {
            body["user_id"] = uid
        }
        if let logo = storeLogo { body["store_logo"] = logo }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func unfollowStore(storeId: String) async throws -> Bool {
        let encoded = storeId.lowercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? storeId.lowercased()
        var components = URLComponents(string: "\(baseURL)/api/followed_stores/\(encoded)")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "device_id", value: SupabaseManager.shared.deviceId)
        ]
        if let uid = SupabaseManager.shared.validCurrentUserId {
            items.append(URLQueryItem(name: "user_id", value: uid))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw URLError(.badURL) }
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
        // Persist directly to Supabase Cloud (no Render call needed)
        _ = try? await SupabaseManager.shared.submitSearchFeedback(
            query: query,
            feedbackType: feedbackType,
            comment: comment,
            productEvaluations: productEvaluations
        )
    }

    // MARK: - Outbound Affiliate Monetization

    func outboundRedirectURL(
        targetUrl: String,
        storeId: String? = nil,
        offerId: String? = nil,
        source: String = "app"
    ) -> URL {
        let clean = targetUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return URL(string: "https://fitmatch.it")!
        }

        let sovrnKey = "bc9e0db8eb869194e60dcb42219bf689"
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")

        if !sovrnKey.isEmpty, let encodedTarget = clean.addingPercentEncoding(withAllowedCharacters: allowed) {
            let cleanStore = (storeId ?? "gen").lowercased().filter { $0.isLetter || $0.isNumber }
            let cleanSource = source.lowercased().filter { $0.isLetter || $0.isNumber }
            let randomHash = UUID().uuidString.prefix(6).lowercased()
            let cuid = "fm_\(cleanStore.prefix(8))_\(cleanSource.prefix(6))_\(randomHash)"
            let viglinkString = "https://redirect.viglink.com?key=\(sovrnKey)&u=\(encodedTarget)&cuid=\(cuid)"
            if let vigUrl = URL(string: viglinkString) {
                return vigUrl
            }
        }

        return URL(string: clean) ?? URL(string: "https://fitmatch.it")!
    }

    // MARK: - Affiliate Link Generator for Sharing

    func affiliateShareURL(
        targetUrl: String,
        storeId: String? = nil,
        offerId: String? = nil
    ) -> URL {
        let clean = targetUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return URL(string: "https://fitmatch.it")!
        }

        // Sovrn //Commerce (VigLink) API Key configured in FitMatch
        let sovrnKey = "bc9e0db8eb869194e60dcb42219bf689"

        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")

        if !sovrnKey.isEmpty, let encodedTarget = clean.addingPercentEncoding(withAllowedCharacters: allowed) {
            let cleanStore = (storeId ?? "gen").lowercased().filter { $0.isLetter || $0.isNumber }
            let randomHash = UUID().uuidString.prefix(8).lowercased()
            let cuid = "fm_\(cleanStore.prefix(10))_\(randomHash)"
            let viglinkString = "https://redirect.viglink.com?key=\(sovrnKey)&u=\(encodedTarget)&cuid=\(cuid)"
            if let vigUrl = URL(string: viglinkString) {
                return vigUrl
            }
        }

        // Fallback to FitMatch Outbound Redirect Gateway
        return outboundRedirectURL(
            targetUrl: clean,
            storeId: storeId,
            offerId: offerId,
            source: "product_share"
        )
    }

    // MARK: - Visual Search (Camera & Gallery Photo Recognition)

    func analyzeVisualSearchImage(imageData: Data, mimeType: String = "image/jpeg", description: String? = nil) async throws -> VisualSearchResponse {
        guard let url = URL(string: "\(edgeFunctionsBaseURL)/visual-search") else {
            throw URLError(.badURL)
        }

        var payload: [String: String] = [
            "image_base64": imageData.base64EncodedString(),
            "mime_type": mimeType,
            "device_id": SupabaseManager.shared.deviceId
        ]
        if let cleanDesc = description?.trimmingCharacters(in: .whitespacesAndNewlines), !cleanDesc.isEmpty {
            payload["description"] = cleanDesc
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)

        let maxRetries = 2
        var lastError: Error?

        for attempt in 0...maxRetries {
            var request = makeEdgeRequest(url: url, method: "POST", timeout: 35)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if (200...299).contains(http.statusCode) {
                    return try JSONDecoder().decode(VisualSearchResponse.self, from: data)
                }

                if [502, 503, 504].contains(http.statusCode) && attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    continue
                }

                if http.statusCode == 404 {
                    throw NSError(
                        domain: "FitMatchVisualSearch",
                        code: 404,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Servizio di ricerca visiva non ancora attivo su Supabase (404)."
                        ]
                    )
                }

                if let errObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = errObj["detail"] as? String,
                   !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw NSError(domain: "FitMatchVisualSearch", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
                }

                throw NSError(
                    domain: "FitMatchVisualSearch",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Errore durante l'analisi della foto (\(http.statusCode))."]
                )
            } catch {
                lastError = error
                let nsErr = error as NSError
                if nsErr.domain == "FitMatchVisualSearch" {
                    throw error
                }
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    continue
                }
            }
        }

        throw lastError ?? NSError(
            domain: "FitMatchVisualSearch",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Connessione al servizio di analisi visiva non riuscita. Riprova tra poco."]
        )
    }
}

struct VisualSearchResponse: Codable {
    let is_sport_product: Bool
    let recognized_model: String
    let brand: String?
    let category: String?
    let color: String?
    let search_query: String
    let confidence: String
    let alternatives: [String]
    let note: String?
    let catalog_matches_count: Int
    let uploaded_image_url: String?
}
