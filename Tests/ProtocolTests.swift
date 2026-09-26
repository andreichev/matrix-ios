import XCTest

@testable import Matrix_Workspace

final class ProtocolTests: XCTestCase {
    func testRejectsCredentialsPathsAndInsecureServers() throws {
        for value in [
            "http://example.org", "https://name:secret@example.org", "https://example.org/matrix-mobile",
            "https://example.org?token=secret", "https://example.org#fragment", "file:///tmp/test",
        ] {
            XCTAssertThrowsError(try ServerAddress(value), value)
        }
        XCTAssertEqual(
            try ServerAddress(" https://example.org/ ").endpoint("api/v1/auth/token").path, "/api/v1/auth/token")
    }

    func testSocketTokenIsOnlyInHeader() throws {
        let request = try ServerAddress("https://example.org").socketRequest(token: "secret")
        XCTAssertEqual(request.url?.absoluteString, "wss://example.org/api/v1/ws/chat")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testJSONRoundTrip() throws {
        let value = try JSONValue.parse("{\"enabled\":true,\"number\":1,\"nothing\":null,\"array\":[\"udp\",48000]}")
        XCTAssertEqual(value["enabled"], .bool(true))
        XCTAssertEqual(value["number"], .number(1))
        XCTAssertEqual(try JSONValue.parse(value.json()), value)
    }

    func testSnapshotSupportsMultipleDevicesAndNullableUser() throws {
        let json = """
            {"enabled":true,"iceServers":[],"calls":[{"id":"call","chatId":null,"title":"Test","myPeerId":"peer1","myStatus":"JOINED","joinedHere":true,"rtpCapabilities":{},"participants":[{"id":"p","userId":null,"name":"User","connections":[{"peerId":"peer1","producer":{"id":"a","paused":false}},{"peerId":"peer2","producer":null}]}]}]}
            """
        let snapshot = try JSONValue.parse(json).decoded(CallsSnapshot.self)
        XCTAssertEqual(snapshot.calls.first?.connections.count, 2)
        XCTAssertEqual(snapshot.calls.first?.connections.first?.producer?.paused, false)
    }

    func testTokenDates() {
        let future = AuthTokens(
            accessToken: "a", expiresAt: "2099-01-01T00:00:00.123456Z", refreshToken: "r",
            refreshExpiresAt: "2099-02-01T00:00:00Z")
        XCTAssertFalse(future.needsRefresh)
        let old = AuthTokens(
            accessToken: "a", expiresAt: "2000-01-01T00:00:00Z", refreshToken: "r",
            refreshExpiresAt: "2099-02-01T00:00:00Z")
        XCTAssertTrue(old.needsRefresh)
    }
}
