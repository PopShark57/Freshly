import Foundation

enum ProviderError: LocalizedError {
    case badStatus(Int, URL)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case let .badStatus(code, url): "HTTP \(code) from \(url.host() ?? url.absoluteString)"
        case let .unreadable(what): what
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 90
        config.httpMaximumConnectionsPerHost = 4
        config.httpAdditionalHeaders = ["User-Agent": "Freshly/1.0 Sparkle/2 (macOS update checker)"]
        return URLSession(configuration: config)
    }()

    static func data(from url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ProviderError.badStatus(http.statusCode, url)
        }
        return data
    }

    static func json<T: Decodable>(_ type: T.Type, from url: URL, headers: [String: String] = [:]) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await data(from: url, headers: headers))
    }
}
