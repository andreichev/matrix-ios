import XCTest

@testable import Matrix_Workspace

@MainActor
final class NativeMediaTests: XCTestCase {
    func testCompletedTransportRemainsConnected() {
        XCTAssertEqual(MediaConnectionState(.connected), .connected)
        XCTAssertEqual(MediaConnectionState(.completed), .connected)
        XCTAssertEqual(MediaConnectionState(.disconnected), .disconnected)
        XCTAssertEqual(MediaConnectionState(.failed), .failed)
    }

    func testNativeDeviceLoadsOpusAndReleasesSession() async throws {
        let capabilities = try JSONValue.parse(
            """
            {"codecs":[{"kind":"audio","mimeType":"audio/opus","preferredPayloadType":100,"clockRate":48000,"channels":2,"parameters":{"useinbandfec":1},"rtcpFeedback":[{"type":"transport-cc","parameter":""}]}],"headerExtensions":[{"kind":"audio","uri":"urn:ietf:params:rtp-hdrext:sdes:mid","preferredId":1,"preferredEncrypt":false,"direction":"sendrecv"}]}
            """)
        let worker = MediaWorker(
            connect: { _, _ in }, produce: { _, _, callback in callback(nil) }, stateChanged: { _, _ in })
        defer { worker.close() }
        let actual = try await worker.load(capabilities: capabilities)
        if case .array(let codecs) = actual["codecs"] {
            XCTAssertTrue(codecs.contains { $0["mimeType"].string?.lowercased() == "audio/opus" })
        } else {
            XCTFail("Missing native RTP capabilities")
        }
    }
}
