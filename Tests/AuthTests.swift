import XCTest

@testable import Matrix_Workspace

private final class MockHTTP: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    static var refreshStatus = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let status = Self.refreshStatus
        Self.lock.unlock()
        let isRefresh = request.url!.path.hasSuffix("refresh")
        let json =
            isRefresh
            ? """
            {"accessToken":"fresh","expiresAt":"2099-01-01T00:00:00Z","refreshToken":"rotated","refreshExpiresAt":"2099-02-01T00:00:00Z"}
            """ : "{}"
        client?.urlProtocol(
            self,
            didReceive: HTTPURLResponse(
                url: request.url!, statusCode: isRefresh ? status : 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class AuthTests: XCTestCase {
    private func setupSession(server: ServerAddress = .configured) throws -> (AuthService, KeychainStore) {
        MockHTTP.requests = []
        MockHTTP.refreshStatus = 200
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHTTP.self]
        let store = KeychainStore(service: "matrix.tests.\(UUID())")
        let old = AuthSession(
            server: server, username: "tester",
            tokens: AuthTokens(
                accessToken: "old", expiresAt: "2000-01-01T00:00:00Z", refreshToken: "original",
                refreshExpiresAt: "2099-02-01T00:00:00Z"))
        try store.write(JSONEncoder().encode(old))
        let auth = AuthService(http: HTTPClient(configuration: config), store: store)
        try auth.restore()
        return (auth, store)
    }

    func testRestoreKeepsSelectedOrganizationAndRefreshesOnlyThere() async throws {
        let (auth, store) = try setupSession(server: ServerAddress("https://other.example.org"))
        defer {
            try? store.clear()
            auth.http.session.invalidateAndCancel()
        }
        XCTAssertEqual(auth.current?.server.url.host, "other.example.org")
        XCTAssertNotNil(try store.read())
        XCTAssertTrue(MockHTTP.requests.isEmpty)
        _ = try await auth.accessToken()
        XCTAssertEqual(MockHTTP.requests.count, 1)
        XCTAssertEqual(MockHTTP.requests.first?.url?.host, "other.example.org")
    }

    func testConcurrentRefreshUsesOneRequestAndPersistsRotation() async throws {
        let (auth, store) = try setupSession()
        defer {
            try? store.clear()
            auth.http.session.invalidateAndCancel()
        }
        async let a = auth.accessToken()
        async let b = auth.accessToken()
        let tokens = try await [a, b]
        XCTAssertEqual(tokens, ["fresh", "fresh"])
        XCTAssertEqual(MockHTTP.requests.filter { $0.url?.path.hasSuffix("refresh") == true }.count, 1)
        let persisted = try JSONDecoder().decode(AuthSession.self, from: XCTUnwrap(store.read()))
        XCTAssertEqual(persisted.tokens.refreshToken, "rotated")
    }

    func testRejectedRefreshClearsSession() async throws {
        let (auth, store) = try setupSession()
        defer {
            try? store.clear()
            auth.http.session.invalidateAndCancel()
        }
        MockHTTP.refreshStatus = 401
        var invalidated = false
        auth.onInvalidated = { invalidated = true }
        do {
            _ = try await auth.accessToken()
            XCTFail("Expected revoked session")
        } catch {}
        XCTAssertNil(auth.current)
        XCTAssertNil(try store.read())
        XCTAssertTrue(invalidated)
    }

    func testLogoutClearsKeychainAndCallsServer() async throws {
        let (auth, store) = try setupSession()
        defer {
            try? store.clear()
            auth.http.session.invalidateAndCancel()
        }
        try await auth.logout()
        XCTAssertNil(auth.current)
        XCTAssertNil(try store.read())
        XCTAssertEqual(MockHTTP.requests.last?.url?.path, "/api/v1/auth/logout")
    }
}
