import UIKit

@MainActor
final class AppCoordinator {
    let navigationController = UINavigationController()
    private let services: AppServices
    private var auth: AuthService { services.auth }

    init(services: AppServices) { self.services = services }

    func start() {
        services.onInvalidated = { [weak self] in self?.showLogin() }
        services.calls.onOpen = { [weak self] call in self?.showCall(call) }
        if auth.current == nil { showLogin(error: services.restoreError) } else { showCalls() }
    }

    func suspend() { (navigationController.topViewController as? CallsListController)?.suspend() }
    func resume() {
        services.push.synchronize()
        (navigationController.topViewController as? CallsListController)?.resume()
        (navigationController.topViewController as? CallController)?.refresh()
    }
    func stop() {
        services.calls.stop()
        suspend()
    }

    private func showLogin(error: String? = nil) {
        stop()
        let controller = LoginController(auth: auth)
        controller.onLogin = { [weak self] in self?.showCalls() }
        navigationController.setViewControllers([controller], animated: false)
        if let error { controller.showError(error) }
    }

    private func showCalls() {
        let controller = CallsListController(auth: auth)
        controller.onSelect = { [weak self] target in
            self?.services.calls.open(target)
        }
        controller.onLogoutError = { [weak self] error in
            guard let self else { return }
            if let login = self.navigationController.topViewController as? LoginController {
                login.showError(error)
            } else {
                let alert = UIAlertController(title: "Не удалось выйти", message: error, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Закрыть", style: .default))
                self.navigationController.present(alert, animated: true)
            }
        }
        navigationController.setViewControllers([controller], animated: false)
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
