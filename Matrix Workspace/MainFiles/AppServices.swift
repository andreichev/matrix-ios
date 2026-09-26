import Foundation

@MainActor
final class AppServices {
    let auth = AuthService(http: HTTPClient())
    let systemCalls = SystemCallService()
    let calls: NativeCallCoordinator
    let push: VoipPushService
    let notifications: NativeNotificationService
    let hubPush: HubPushService
    var onInvalidated: (() -> Void)?
    private(set) var restoreError: String?

    init() {
        hubPush = HubPushService(auth: auth)
        calls = NativeCallCoordinator(auth: auth, systemCalls: systemCalls)
        push = VoipPushService(auth: auth, calls: calls, hub: hubPush)
        notifications = NativeNotificationService(auth: auth, hub: hubPush)
        do { try auth.restore() } catch { restoreError = error.localizedDescription }
        if let sessionId = auth.current?.id { WebDataStoreService.remember(sessionId) }
        WebDataStoreService.clearInactiveStores(auth: auth)
        auth.onSessionChanged = { [weak self] in
            self?.hubPush.sessionChanged()
            self?.push.synchronize()
            self?.notifications.synchronize()
        }
        auth.onInvalidated = { [weak self] in
            guard let self else { return }
            self.calls.stop()
            self.onInvalidated?()
            WebDataStoreService.clearInactiveStores(auth: self.auth)
        }
    }
}
