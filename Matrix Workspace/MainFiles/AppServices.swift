import Foundation

@MainActor
final class AppServices {
    let auth = AuthService(http: HTTPClient())
    let systemCalls = SystemCallService()
    let calls: NativeCallCoordinator
    let push: VoipPushService
    let notifications: NativeNotificationService
    var onInvalidated: (() -> Void)?
    private(set) var restoreError: String?

    init() {
        calls = NativeCallCoordinator(auth: auth, systemCalls: systemCalls)
        push = VoipPushService(auth: auth, calls: calls)
        notifications = NativeNotificationService(auth: auth)
        do { try auth.restore() } catch { restoreError = error.localizedDescription }
        auth.onSessionChanged = { [weak self] in
            self?.push.synchronize()
            self?.notifications.synchronize()
        }
        auth.onInvalidated = { [weak self] in
            self?.calls.stop()
            self?.onInvalidated?()
        }
    }
}
