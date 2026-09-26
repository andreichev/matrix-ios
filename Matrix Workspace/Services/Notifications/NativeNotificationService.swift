import OSLog
import UIKit
import UserNotifications

@MainActor
final class NativeNotificationService: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    private let auth: AuthService
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Matrix", category: "Notifications")
    private var token: String?
    private var registered: String?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var permission: UNAuthorizationStatus = .notDetermined
    private var pending: (session: UUID, route: String)?
    var onOpen: ((String) -> Void)? { didSet { openPending() } }

    init(auth: AuthService) {
        self.auth = auth
        super.init()
        center.delegate = self
    }

    func synchronize() {
        guard let session = auth.current?.id else {
            generation += 1
            task?.cancel(); task = nil; registered = nil; pending = nil
            center.removeAllDeliveredNotifications()
            return
        }
        guard task == nil else { return }
        generation += 1
        let epoch = generation
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == epoch { self.task = nil } }
            do {
                var settings = await self.center.notificationSettings()
                if settings.authorizationStatus == .notDetermined, UIApplication.shared.applicationState == .active {
                    _ = try await self.center.requestAuthorization(options: [.alert, .sound, .badge])
                    settings = await self.center.notificationSettings()
                }
                try Task.checkCancellation()
                guard self.auth.current?.id == session else { return }
                self.permission = settings.authorizationStatus
                if self.permission == .authorized || self.permission == .provisional {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                try await self.register(session: session)
            } catch {
                if !Task.isCancelled { self.logger.error("Native push registration failed") }
            }
        }
    }

    func receivedToken(_ data: Data) {
        let value = data.map { String(format: "%02x", $0) }.joined()
        guard value != token else { return }
        token = value
        // Registration may have been started before APNs supplied the token.
        Task { [weak self] in
            guard let self else { return }
            if let task = self.task { await task.value }
            self.synchronize()
        }
    }

    func registrationFailed(_ error: Error) {
        logger.error("APNs registration failed: \((error as NSError).code)")
    }

    private func register(session: UUID) async throws {
        guard let environment = Bundle.main.object(forInfoDictionaryKey: "APNSEnvironment") as? String,
            ["development", "production"].contains(environment) else { return }
        let status: String = switch permission {
        case .authorized, .ephemeral: "AUTHORIZED"
        case .provisional: "PROVISIONAL"
        case .denied: "DENIED"
        default: "NOT_DETERMINED"
        }
        let key = "\(session)|\(token ?? "")|\(status)"
        guard registered != key, auth.current?.id == session else { return }
        _ = try await auth.send("api/v1/notifications/push/ios", body: .object([
            "environment": .string(environment == "development" ? "SANDBOX" : "PRODUCTION"),
            "token": token.map(JSONValue.string) ?? .null, "permission": .string(status),
        ]), method: "PUT")
        try Task.checkCancellation()
        if auth.current?.id == session { registered = key }
    }

    func clearDelivered() { center.removeAllDeliveredNotifications() }

    private func openPending() {
        guard let pending, let onOpen else { return }
        self.pending = nil
        guard auth.current?.id == pending.session else { return }
        onOpen(pending.route)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let id = response.notification.request.content.userInfo["sessionId"] as? String,
            let session = UUID(uuidString: id), auth.current?.id == session,
            let route = response.notification.request.content.userInfo["url"] as? String else { return }
        pending = (session, route)
        openPending()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let value = notification.request.content.userInfo["sessionId"] as? String
        // Foreground notifications already appear in the web interface.
        guard let value, UUID(uuidString: value) == auth.current?.id else { completionHandler([]); return }
        completionHandler([])
    }
}
