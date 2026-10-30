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

    func getStats() async throws -> CatalogStatsResponse {
        guard let url = URL(string: "\(baseURL)/api/stats") else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(CatalogStatsResponse.self, from: data)
    }
}
