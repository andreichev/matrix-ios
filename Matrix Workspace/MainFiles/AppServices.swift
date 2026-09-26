import Foundation

@MainActor
final class AppServices {
    let auth = AuthService(http: HTTPClient())
    let systemCalls = SystemCallService()
    let calls: NativeCallCoordinator
    let push: VoipPushService
    var onInvalidated: (() -> Void)?
    private(set) var restoreError: String?

    init() {
        calls = NativeCallCoordinator(auth: auth, systemCalls: systemCalls)
        push = VoipPushService(auth: auth, calls: calls)
        do { try auth.restore() } catch { restoreError = error.localizedDescription }
        auth.onSessionChanged = { [weak self] in self?.push.synchronize() }
        auth.onInvalidated = { [weak self] in
            self?.calls.stop()
            self?.onInvalidated?()
        }
    }
}
