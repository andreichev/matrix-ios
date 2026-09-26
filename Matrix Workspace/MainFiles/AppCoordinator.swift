import UIKit

@MainActor
final class AppCoordinator {
    let navigationController = UINavigationController()
    private let services: AppServices
    private var auth: AuthService { services.auth }
    private weak var workspace: WorkspaceController?

    init(services: AppServices) { self.services = services }

    func start() {
        services.onInvalidated = { [weak self] in self?.showLogin() }
        services.calls.onOpen = { [weak self] call in self?.showCall(call) }
        if auth.current == nil { showLogin(error: services.restoreError) } else { showWorkspace() }
        services.notifications.onOpen = { [weak self] route in self?.workspace?.open(route: route) }
    }

    func suspend() { workspace?.setActive(false) }
    func resume() {
        services.push.synchronize()
        services.notifications.synchronize()
        services.notifications.clearDelivered()
        workspace?.setActive(true)
        (navigationController.topViewController as? CallController)?.refresh()
    }
    func stop() {
        services.calls.stop()
        suspend()
    }

    private func showLogin(error: String? = nil) {
        stop()
        workspace?.stop()
        workspace = nil
        navigationController.setNavigationBarHidden(false, animated: false)
        let controller = LoginController(auth: auth)
        controller.onLogin = { [weak self] in self?.showWorkspace() }
        navigationController.setViewControllers([controller], animated: false)
        if let error { controller.showError(error) }
    }

    private func showWorkspace() {
        guard let server = auth.current?.server else { return }
        guard let sessionId = auth.current?.id else {
            showLogin(error: "Не удалось восстановить сессию. Войдите заново.")
            return
        }
        let controller = WorkspaceController(auth: auth, calls: services.calls, server: server, sessionId: sessionId)
        workspace = controller
        navigationController.setViewControllers([controller], animated: false)
        services.notifications.synchronize()
        if let call = services.calls.active { showCall(call) }
    }

    private func showCall(_ call: CallInteractor) {
        if let current = navigationController.topViewController as? CallController, current.interactor === call { return }
        if navigationController.topViewController is CallController {
            navigationController.popViewController(animated: false)
        }
        navigationController.pushViewController(CallController(interactor: call),
            animated: UIApplication.shared.applicationState == .active)
    }
}
