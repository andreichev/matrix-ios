import Foundation

struct AuthTokens: Codable {
    let accessToken: String
    let expiresAt: String
    let refreshToken: String
    let refreshExpiresAt: String

    var needsRefresh: Bool { (Self.date(expiresAt)?.timeIntervalSinceNow ?? 0) < 60 }
    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct AuthSession: Codable {
    let server: ServerAddress
    let username: String
    let tokens: AuthTokens

    // Identity hint only; authorization is always verified by the backend.
    var id: UUID? {
        let parts = tokens.accessToken.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let json = try? JSONDecoder().decode(JSONValue.self, from: data),
            let id = json["sid"].string else { return nil }
        return UUID(uuidString: id)
    }
}

@MainActor
final class AuthService {
    private(set) var current: AuthSession?
    private let store: KeychainStore
    let http: HTTPClient
    private var refreshTask: Task<AuthTokens, Error>?
    private var generation = 0
    var onInvalidated: (() -> Void)?
    var onSessionChanged: (() -> Void)?

    init(http: HTTPClient, store: KeychainStore = KeychainStore()) {
        self.http = http
        self.store = store
    }

    func restore() throws {
        guard let data = try store.read() else { return }
        let session = try JSONDecoder().decode(AuthSession.self, from: data)
        // Never reuse credentials from another environment.
        guard session.server.url.standardized == ServerAddress.configured.url.standardized else {
            try store.clear()
            return
        }
        current = session
    }

    func login(server: ServerAddress, username: String, password: String) async throws {
        let data = try await http.send(
            server: server, path: "api/v1/auth/token",
            body: .object([
                "username": .string(username), "password": .string(password),
            ]))
        let tokens = try JSONDecoder().decode(AuthTokens.self, from: data)
        try save(AuthSession(server: server, username: username, tokens: tokens))
    }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let session = current else { throw MatrixError.unauthorized }
        if let refreshTask { return try await refreshTask.value.accessToken }
        if !forceRefresh && !session.tokens.needsRefresh { return session.tokens.accessToken }
        let epoch = generation
        let task = Task { [self] in
            do {
                let data = try await http.send(
                    server: session.server, path: "api/v1/auth/refresh",
                    body: .object([
                        "refreshToken": .string(session.tokens.refreshToken)
                    ]))
                let tokens = try JSONDecoder().decode(AuthTokens.self, from: data)
                guard epoch == generation else { throw CancellationError() }
                // Persist rotation before any waiter gets the new access token.
                try save(AuthSession(server: session.server, username: session.username, tokens: tokens))
                return tokens
            } catch MatrixError.unauthorized {
                if epoch == generation { try invalidate() }
                throw MatrixError.unauthorized
            }
        }
        refreshTask = task
        defer { if epoch == generation { refreshTask = nil } }
        return try await task.value.accessToken
    }

    func logout() async throws {
        // Serialize logout with rotation; the server also accepts a recently rotated token for logout.
        if let refreshTask { _ = try? await refreshTask.value }
        let session = current
        try invalidate()
        if let session {
            _ = try await http.send(
                server: session.server, path: "api/v1/auth/logout",
                body: .object([
                    "refreshToken": .string(session.tokens.refreshToken)
                ]))
        }
    }

    func send(_ path: String, body: JSONValue? = nil, method: String = "POST") async throws -> Data {
        guard let server = current?.server else { throw MatrixError.unauthorized }
        let epoch = generation
        let token = try await accessToken()
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
        do {
            return try await http.send(server: server, path: path, body: body, token: token, method: method)
        } catch MatrixError.unauthorized {
            guard generation == epoch else { throw CancellationError() }
            let fresh = try await accessToken(forceRefresh: true)
            try Task.checkCancellation()
            guard generation == epoch else { throw CancellationError() }
            return try await http.send(server: server, path: path, body: body, token: fresh, method: method)
        }
    }

    private func save(_ session: AuthSession) throws {
        try store.write(JSONEncoder().encode(session))
        current = session
        onSessionChanged?()
    }

    private func invalidate() throws {
        try store.clear()
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        current = nil
        onSessionChanged?()
        onInvalidated?()
    }
}
