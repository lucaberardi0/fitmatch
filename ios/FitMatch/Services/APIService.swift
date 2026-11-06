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

        let data = try await fetchDataWithRetry(url: url)
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.matched_products
    }

    func smartSearch(
        query: String,
        mode: String? = nil,
        maxPrice: Double? = nil,
        size: String? = nil,
        category: String? = nil,
        store: String? = nil
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
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }

        let data = try await fetchDataWithRetry(url: url)
        return try JSONDecoder().decode(SmartSearchResponse.self, from: data)
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
}
