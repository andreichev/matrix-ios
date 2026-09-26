import AVFoundation
import OSLog
import PushKit
import UIKit

@MainActor
final class VoipPushService: NSObject, @preconcurrency PKPushRegistryDelegate {
    private let auth: AuthService
    private let calls: NativeCallCoordinator
    private let hub: HubPushService
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Matrix", category: "PushKit")
    private var registry: PKPushRegistry?
    private var token: String?
    private var registered: String?
    private var registration: Task<Void, Never>?

    init(auth: AuthService, calls: NativeCallCoordinator, hub: HubPushService) {
        self.auth = auth
        self.calls = calls
        self.hub = hub
        super.init()
    }

    func start() {
        #if !targetEnvironment(simulator)
            guard registry == nil else { return }
            let registry = PKPushRegistry(queue: .main)
            registry.delegate = self
            self.registry = registry
            synchronize()
        #endif
    }

    func synchronize() {
        registry?.desiredPushTypes = auth.current == nil ? [] : [.voIP]
        guard let session = auth.current, let id = session.id, let token else {
            registration?.cancel()
            registration = nil
            registered = nil
            return
        }
        let key = "\(session.server.url.absoluteString)|\(id)|\(token)"
        guard registration == nil else { return }
        guard let environment = Bundle.main.object(forInfoDictionaryKey: "APNSEnvironment") as? String,
            environment == "development" || environment == "production" else {
            logger.error("Missing APNSEnvironment build setting")
            return
        }
        registration = Task { [weak self, auth] in
            do {
                if UIApplication.shared.applicationState == .active,
                    AVAudioApplication.shared.recordPermission == .undetermined {
                    _ = await AVAudioApplication.requestRecordPermission()
                }
                try Task.checkCancellation()
                if try await self?.hub.updateVoip(token: token) == true {
                    self?.registered = nil
                    self?.registration = nil
                    if self?.token != token || auth.current?.id != id { self?.synchronize() }
                    return
                }
                if self?.registered == key { self?.registration = nil; return }
                let data = try await auth.send("api/v1/calls/push/device", body: .object([
                    "token": .string(token),
                    "environment": .string(environment == "development" ? "SANDBOX" : "PRODUCTION"),
                ]))
                try Task.checkCancellation()
                let result = try JSONDecoder().decode(JSONValue.self, from: data)
                if auth.current?.id == id { self?.registered = key }
                if result["enabled"].bool != true { self?.logger.warning("APNs delivery is disabled on the backend") }
            } catch {
                if !Task.isCancelled { self?.logger.error("VoIP registration failed: \(error.localizedDescription, privacy: .public)") }
            }
            guard !Task.isCancelled else { return }
            self?.registration = nil
            if self?.token != token || auth.current?.id != id { self?.synchronize() }
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        synchronize()
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        let oldToken = token
        let sessionId = auth.current?.id
        let environment = Bundle.main.object(forInfoDictionaryKey: "APNSEnvironment") as? String
        token = nil
        registered = nil
        registration?.cancel()
        registration = nil
        Task { [auth, logger, hub] in
            guard let oldToken, let sessionId, auth.current?.id == sessionId,
                environment == "development" || environment == "production" else { return }
            do {
                if try await hub.updateVoip(token: nil) { return }
                _ = try await auth.send("api/v1/calls/push/device", body: .object([
                    "token": .string(oldToken),
                    "environment": .string(environment == "development" ? "SANDBOX" : "PRODUCTION"),
                ]), method: "DELETE")
            }
            catch { logger.error("VoIP unregistration failed") }
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP else { completion(); return }
        calls.receive(IncomingCall(payload: payload.dictionaryPayload), completion: completion)
    }
}
