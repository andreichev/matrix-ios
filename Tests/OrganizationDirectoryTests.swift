import XCTest

@testable import Matrix_Workspace

private final class DirectoryHTTP: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        Self.lock.unlock()
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        let json = """
        {"protocolVersion":\(query == "unsupported" ? 2 : 1),"organizations":[
          {"id":"00000000-0000-0000-0000-000000000001","name":"Организация","baseUrl":"https://example.org"}
        ]}
        """
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class OrganizationDirectoryTests: XCTestCase {
    func testDirectorySearchDoesNotSendCredentialsAndEncodesQuery() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectoryHTTP.self]
        let http = HTTPClient(configuration: configuration)
        defer { http.session.invalidateAndCancel() }
        DirectoryHTTP.requests = []
        let directory = OrganizationDirectoryService(http: http)
        let query = "Матрица & партнёры"
        let organizations = try await directory.organizations(query: query)
        XCTAssertEqual(organizations.first?.baseUrl, "https://example.org")
        let request = try XCTUnwrap(DirectoryHTTP.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/v1/directory")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems,
            [URLQueryItem(name: "q", value: query)])
    }

    func testUnknownProtocolIsRejected() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectoryHTTP.self]
        let http = HTTPClient(configuration: configuration)
        defer { http.session.invalidateAndCancel() }
        do {
            _ = try await OrganizationDirectoryService(http: http).organizations(query: "unsupported")
            XCTFail("Expected an unsupported directory protocol error")
        } catch MatrixError.message { }
    }

    func testLastOrganizationIsAvailableWithoutDirectoryAndRejectsInvalidAddress() {
        let suite = "matrix.directory.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let http = HTTPClient()
        defer {
            defaults.removePersistentDomain(forName: suite)
            http.session.invalidateAndCancel()
        }
        let directory = OrganizationDirectoryService(http: http, defaults: defaults)
        XCTAssertNil(directory.lastSelection)
        directory.remember(OrganizationSelection(name: "Организация", baseUrl: "https://example.org"))
        let restored = OrganizationDirectoryService(http: http, defaults: defaults)
        XCTAssertEqual(restored.lastSelection?.baseUrl, "https://example.org")
        XCTAssertEqual(restored.lastSelection?.name, "Организация")
        directory.remember(OrganizationSelection(name: nil, baseUrl: "https://example.org"))
        XCTAssertEqual(restored.lastSelection?.title, "Другая организация")
        directory.remember(OrganizationSelection(name: nil, baseUrl: "https://example.org/api"))
        XCTAssertNil(restored.lastSelection)
    }
}
