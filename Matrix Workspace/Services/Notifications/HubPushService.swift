import CryptoKit
import DeviceCheck
import Foundation
import Security

// Only native notification services supply tokens. Never expose signing to the WebView bridge.
@MainActor
final class HubPushService {
    private struct Configuration: Decodable {
        let enabled: Bool
        let organizationId: UUID?
    }
    private struct Challenge: Decodable {
        let challengeId: UUID
        let nonce: String
        let requiresAttestation: Bool
        let protocolVersion: Int
    }
    private struct DeviceState: Codable {
        var keyId: String?
        var attested = false
        var sessionId: UUID?
        var secret = ""
        var fingerprint: String?
        var renewedAt: Date?
    }
    private let auth: AuthService
    private let attest = DCAppAttestService.shared
    private var alertToken: String?
    private var voipToken: String?
    private var permission = "NOT_DETERMINED"
    private var cached: (session: UUID, date: Date, configuration: Configuration)?
    private var configurationTask: (session: UUID, task: Task<Configuration, Error>)?
    private var registrationTask: (id: UUID, task: Task<Void, Error>)?

    init(auth: AuthService) { self.auth = auth }

    func updateAlert(token: String?, permission: String) async throws -> Bool {
        alertToken = token; self.permission = permission
        return try await registerIfEnabled()
    }

    func updateVoip(token: String?) async throws -> Bool {
        voipToken = token
        return try await registerIfEnabled()
    }

    func sessionChanged() {
        guard auth.current == nil else { return }
        registrationTask?.task.cancel()
        configurationTask?.task.cancel()
        cached = nil
        // Keep the running task until its waiter unwinds: Apple signing must remain serialized.
    }

    private func configuration(session: UUID) async throws -> Configuration {
        if let cached, cached.session == session, Date().timeIntervalSince(cached.date) < 300 { return cached.configuration }
        if let pending = configurationTask, pending.session == session { return try await pending.task.value }
        let task = Task { [auth] in
            do {
                let data = try await auth.send("api/v1/notifications/push/hub", method: "GET")
                return try JSONDecoder().decode(Configuration.self, from: data)
            } catch let error as HTTPResponseError where error.status == 404 {
                // Older customer servers still support the original direct APNs registration.
                return Configuration(enabled: false, organizationId: nil)
            }
        }
        configurationTask = (session, task)
        defer { if configurationTask?.session == session { configurationTask = nil } }
        let value = try await task.value
        try checkSession(session)
        cached = (session, Date(), value)
        return value
    }

    private func registerIfEnabled() async throws -> Bool {
        guard let session = auth.current?.id else { throw MatrixError.unauthorized }
        let config = try await configuration(session: session)
        try checkSession(session)
        guard config.enabled else { return false }
        guard let organization = config.organizationId else { throw MatrixError.message("Не настроена организация Hub.") }
        if let pending = registrationTask {
            // Another token may have arrived while the first registration was in flight.
            _ = try? await pending.task.value
            if registrationTask?.id == pending.id { registrationTask = nil }
            try checkSession(session)
            return try await registerIfEnabled()
        }
        let alert = alertToken, voip = voipToken, permission = permission
        let task = Task { [self] in
            try await register(organization: organization, session: session,
                alert: alert, voip: voip, permission: permission)
        }
        let id = UUID()
        registrationTask = (id, task)
        defer { if registrationTask?.id == id { registrationTask = nil } }
        try await task.value
        return true
    }

    private func register(organization: UUID, session: UUID,
        alert: String?, voip: String?, permission: String) async throws {
        try checkSession(session)
        guard let server = auth.current?.server else { throw MatrixError.unauthorized }
        let store = KeychainStore(service: "com.andreichev.matrix.hub." + Self.hash(server.url.absoluteString + organization.uuidString))
        var state = try store.read().map { try JSONDecoder().decode(DeviceState.self, from: $0) } ?? DeviceState()
        if state.sessionId != session {
            state.sessionId = session; state.secret = try Self.secret(); state.fingerprint = nil; state.renewedAt = nil
        }
        let fingerprint = Self.hash([session.uuidString, alert ?? "", voip ?? "", permission].joined(separator: "\n"))
        if state.fingerprint == fingerprint, let date = state.renewedAt, Date().timeIntervalSince(date) < 86400 { return }
        try checkSession(session)
        if alert == nil && voip == nil {
            _ = try await auth.send("api/v1/notifications/push/hub/tokens", method: "DELETE")
            try checkSession(session)
            state.fingerprint = fingerprint; state.renewedAt = Date()
            try store.write(JSONEncoder().encode(state))
            return
        }
        guard attest.isSupported else { throw MatrixError.message("App Attest недоступен на этом устройстве. Push через Hub не подключены.") }
        for attempt in 0..<2 {
            do {
                if state.keyId == nil {
                    state.keyId = try await attest.generateKey()
                    state.attested = false
                    try checkSession(session)
                    try store.write(JSONEncoder().encode(state))
                }
                guard let keyId = state.keyId else { return }
                try checkSession(session)
                let grantData = try await auth.send("api/v1/notifications/push/hub/grant",
                    body: .object(["deviceSecretHash": .string(Self.hash(state.secret))]))
                let grantJSON = try JSONDecoder().decode(JSONValue.self, from: grantData)
                guard let grant = grantJSON["grant"].string,
                    let org = grantJSON["organizationId"].string, UUID(uuidString: org) == organization else {
                    throw MatrixError.message("Hub не выдал разрешение для этой организации.")
                }
                try checkSession(session)
                let challengeData = try await auth.send("api/v1/notifications/push/hub/challenges", body: .object([
                    "grant": .string(grant), "deviceSecret": .string(state.secret), "keyId": .string(keyId),
                    "alertToken": alert.map(JSONValue.string) ?? .null, "voipToken": voip.map(JSONValue.string) ?? .null,
                ]))
                let challenge = try JSONDecoder().decode(Challenge.self, from: challengeData)
                try checkSession(session)
                guard challenge.protocolVersion == 2 else { throw MatrixError.message("Обновите приложение для подключения Hub.") }
                if challenge.requiresAttestation && state.attested {
                    state.keyId = nil; state.attested = false
                    try store.write(JSONEncoder().encode(state))
                    if attempt == 0 { continue }
                    throw MatrixError.message("Не удалось восстановить ключ Hub. Повторите позже.")
                }
                let payload = ["matrix-hub-registration-v2", grant, challenge.nonce, keyId,
                    alert?.lowercased() ?? "", voip?.lowercased() ?? ""].joined(separator: "\n")
                let hash = Data(SHA256.hash(data: Data(payload.utf8)))
                let proof: Data
                if challenge.requiresAttestation {
                    proof = try await attest.attestKey(keyId, clientDataHash: hash)
                    try checkSession(session)
                    state.attested = true
                    try store.write(JSONEncoder().encode(state))
                } else {
                    proof = try await attest.generateAssertion(keyId, clientDataHash: hash)
                    state.attested = true
                }
                try checkSession(session)
                _ = try await auth.send("api/v1/notifications/push/hub/challenges/\(challenge.challengeId)/confirm", body: .object([
                    "deviceSecret": .string(state.secret), "proof": .string(proof.base64EncodedString()),
                    "attestation": .bool(challenge.requiresAttestation),
                ]))
                try checkSession(session)
                _ = try await auth.send("api/v1/notifications/push/hub/complete", body: .object(["permission": .string(permission)]))
                try checkSession(session)
                state.fingerprint = fingerprint; state.renewedAt = Date()
                try store.write(JSONEncoder().encode(state))
                return
            } catch {
                if let error = error as? DCError, error.code == .invalidKey, attempt == 0 {
                    try checkSession(session)
                    state.keyId = nil; state.attested = false
                    try store.write(JSONEncoder().encode(state))
                    continue
                }
                throw error
            }
        }
    }

    private func checkSession(_ session: UUID) throws {
        try Task.checkCancellation()
        guard auth.current?.id == session else { throw CancellationError() }
    }
    private static func hash(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    private static func secret() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw MatrixError.message("Не удалось создать секрет устройства.")
        }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
