import XCTest
@testable import Matrix_Workspace

@MainActor
final class WebBridgeTests: XCTestCase {
    func testBridgeOnlyTrustsApplicationPagesAndOwnBlobs() throws {
        let auth = AuthService(http: HTTPClient())
        let calls = NativeCallCoordinator(auth: auth, systemCalls: SystemCallService())
        let bridge = MatrixWebBridge(server: try ServerAddress("https://example.org"), auth: auth, calls: calls)
        XCTAssertTrue(bridge.isApplication(bridge.applicationURL()))
        XCTAssertTrue(bridge.isApplication(URL(string: "https://example.org/matrix-mobile")))
        XCTAssertTrue(bridge.isApplication(URL(string: "https://example.org/matrix-mobile/")))
        XCTAssertTrue(bridge.isApplication(URL(string: "https://example.org/matrix-mobile/?from=push")))
        XCTAssertTrue(bridge.isApplication(URL(string: "https://example.org/matrix-mobile/messages")))
        for value in ["https://other.org/matrix-mobile/", "http://example.org/matrix-mobile/", "https://example.org/api/v1/files/test", "https://example.org/matrix-mobile-evil/", "https://example.org/matrix-mobile/../api/v1/files/test"] {
            XCTAssertFalse(bridge.isApplication(URL(string: value)))
        }
        XCTAssertTrue(bridge.isLocalBlob(try XCTUnwrap(URL(string: "blob:https://example.org/id"))))
        XCTAssertFalse(bridge.isLocalBlob(try XCTUnwrap(URL(string: "blob:https://other.org/id"))))
        XCTAssertEqual(bridge.applicationURL(route: "/messages/chat").path, "/matrix-mobile/messages/chat")
        XCTAssertEqual(bridge.applicationURL(route: "https://other.org").absoluteString, "https://example.org/matrix-mobile/")
        XCTAssertEqual(bridge.applicationURL(route: "//other.org").absoluteString, "https://example.org/matrix-mobile/")
        XCTAssertEqual(bridge.applicationURL(route: "/../api/v1/files/test").absoluteString, "https://example.org/matrix-mobile/")
    }
}
