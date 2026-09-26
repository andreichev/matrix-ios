import XCTest

@testable import Matrix_Workspace

@MainActor
final class SfuIntegrationTests: XCTestCase {
    func testNativeAndBrowserExchangeAudio() async throws {
        let address = ProcessInfo.processInfo.environment["MATRIX_SFU_TEST_URL"] ?? ""
        guard address == "http://127.0.0.1:38761" else {
            throw XCTSkip("Start test-support/native-sfu.mts and set MATRIX_SFU_TEST_URL.")
        }
        let server = try ServerAddress(address)
        let http = HTTPClient()
        defer { http.session.invalidateAndCancel() }
        func snapshot() async throws -> CallSnapshot {
            try JSONDecoder().decode(CallSnapshot.self, from: await http.send(server: server, path: "state"))
        }
        let call = try await snapshot()
        var failure: String?
        var connected = false
        let media = SfuAudioSession(
            callId: call.id, iceServers: .array([]),
            command: { command in
                let data = try await http.send(server: server, path: "command/native", body: .object(command))
                return try JSONDecoder().decode(JSONValue.self, from: data)
            }, onError: { failure = $0 }, onConnection: { connected = $0 })
        defer { media.close() }
        try await media.start(call, muted: true)
        let muted = try await snapshot()
        XCTAssertTrue(muted.connections.first { $0.peerId == call.myPeerId }?.producer?.paused == true)
        try await media.setMuted(false)
        var browserReceived = false
        var nativeReceived = false
        for _ in 0..<60 {
            let state = try await snapshot()
            await media.sync(state, servers: .array([]))
            let browser = try JSONDecoder().decode(JSONValue.self, from: await http.send(server: server, path: "stats"))
            let native = try await media.receiveStatistics()
            browserReceived = hasPackets(browser)
            nativeReceived = hasPackets(native)
            if connected && browserReceived && nativeReceived { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        XCTAssertNil(failure)
        XCTAssertTrue(connected, "Native DTLS transport did not connect")
        XCTAssertTrue(browserReceived, "Browser did not receive native RTP packets")
        XCTAssertTrue(nativeReceived, "Native client did not receive browser RTP packets")
        try await media.setMuted(true)
        let paused = try await snapshot()
        XCTAssertTrue(paused.connections.first { $0.peerId == call.myPeerId }?.producer?.paused == true)
    }

    private func hasPackets(_ value: JSONValue) -> Bool {
        guard case .array(let stats) = value else { return false }
        return stats.contains { stat in
            guard stat["type"].string == "inbound-rtp", case .number(let bytes) = stat["bytesReceived"] else {
                return false
            }
            return bytes > 0
        }
    }
}
