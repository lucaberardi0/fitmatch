import Foundation

@MainActor
class APIService: ObservableObject {
    static let shared = APIService()

    // Default to localhost for iOS Simulator; can be changed to LAN IP for physical device
    var baseURL = "http://127.0.0.1:8000"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        self.session = URLSession(configuration: config)
    }

    func search(query: String, size: String? = nil) async throws -> [MatchedProduct] {
        var components = URLComponents(string: "\(baseURL)/api/search")!
        var queryItems = [URLQueryItem(name: "q", value: query)]
        if let size = size, !size.isEmpty {
            queryItems.append(URLQueryItem(name: "size", value: size))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.matched_products
    }

    func smartSearch(
        query: String,
        maxPrice: Double? = nil,
        size: String? = nil,
        category: String? = nil,
        store: String? = nil
    ) async throws -> SmartSearchResponse {
        var components = URLComponents(string: "\(baseURL)/api/search/smart")!
        var queryItems = [URLQueryItem(name: "q", value: query)]
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

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(SmartSearchResponse.self, from: data)
    }

    func getAIAdvice(prompt: String) async throws -> AIAdviceResponse {
        var components = URLComponents(string: "\(baseURL)/api/ai/advise")!
        components.queryItems = [URLQueryItem(name: "prompt", value: prompt)]

        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(AIAdviceResponse.self, from: data)
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
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct CatalogResultResponse: Decodable {
            let results: [MatchedProduct]
        }
        let decoded = try JSONDecoder().decode(CatalogResultResponse.self, from: data)
        return decoded.results
    }

    func getStats() async throws -> CatalogStatsResponse {
        guard let url = URL(string: "\(baseURL)/api/stats") else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(CatalogStatsResponse.self, from: data)
    }

    func getStoreShowcases() async throws -> [StoreShowcase] {
        guard let url = URL(string: "\(baseURL)/api/stores/showcase") else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(StoreShowcaseResponse.self, from: data)
        return decoded.showcases
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
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(StoreDetailResponse.self, from: data)
    }

    // MARK: - Wishlist & Collections (Database Connected)

    func getWishlist(collection: String? = nil) async throws -> [WishlistItem] {
        var components = URLComponents(string: "\(baseURL)/api/wishlist")!
        if let col = collection, !col.isEmpty && col.lowercased() != "tutti" {
            components.queryItems = [URLQueryItem(name: "collection", value: col)]
        }
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
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
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
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
}
