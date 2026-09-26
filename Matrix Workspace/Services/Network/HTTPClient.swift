import Foundation

struct HTTPResponseError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

final class HTTPClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let userAgent = "Matrix-iOS/1.0 (iPhone; iOS)"
    // Ephemeral storage: credentials and authenticated responses never enter a disk cache.
    private(set) var session: URLSession!

    init(configuration: URLSessionConfiguration = .ephemeral) {
        super.init()
        let config = configuration
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func send(server: ServerAddress, path: String, body: JSONValue? = nil, token: String? = nil, method: String? = nil,
        queryItems: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: server.endpoint(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method ?? (body == nil ? "GET" : "POST")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MatrixError.message("Некорректный ответ сервера.")
        }
        if response.statusCode == 401 { throw MatrixError.unauthorized }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(JSONValue.self, from: data))?["message"].string
            throw HTTPResponseError(status: response.statusCode, message: message ?? "Ошибка сервера: \(response.statusCode).")
        }
        return data
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
