import Foundation

struct IncomingCall {
    let id: UUID
    let sessionId: UUID
    let title: String
    let expiresAt: Date

    init?(payload: [AnyHashable: Any]) {
        guard let rawID = payload["callId"] as? String, let id = UUID(uuidString: rawID),
            let rawSession = payload["sessionId"] as? String, let sessionId = UUID(uuidString: rawSession),
            let expiry = payload["expiresAt"] as? NSNumber else { return nil }
        self.id = id
        self.sessionId = sessionId
        self.title = String((payload["title"] as? String ?? "Матрица").prefix(200))
        self.expiresAt = Date(timeIntervalSince1970: expiry.doubleValue / 1000)
    }
}
