import Foundation

struct ServerAddress: Codable, Equatable, Sendable {
    let url: URL

    init(_ input: String) throws {
        guard let parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
            let host = parts.host, !host.isEmpty,
            parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
            parts.path.isEmpty || parts.path == "/", let url = parts.url
        else {
            throw MatrixError.message("Укажите адрес сервера без пути, например https://matrix.example.ru.")
        }
        var allowed = parts.scheme == "https"
        #if DEBUG
            allowed = allowed || (parts.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host))
        #endif
        guard allowed else {
            throw MatrixError.message("Для подключения нужен HTTPS. В Debug разрешён HTTP только для localhost.")
        }
        self.url = url
    }

    func endpoint(_ path: String) -> URL { url.appendingPathComponent(path) }

    func socketRequest(token: String) -> URLRequest {
        var parts = URLComponents(url: endpoint("api/v1/ws/chat"), resolvingAgainstBaseURL: false)!
        parts.scheme = url.scheme == "https" ? "wss" : "ws"
        var request = URLRequest(url: parts.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}

enum MatrixError: LocalizedError {
    case message(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .unauthorized: return "Сессия завершена. Войдите заново."
        }
    }
}
