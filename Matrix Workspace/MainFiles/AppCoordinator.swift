import UIKit

@MainActor
final class AppCoordinator {
    let navigationController = UINavigationController()
    private let auth = AuthService(http: HTTPClient())

    func start() {
        auth.onInvalidated = { [weak self] in self?.showLogin() }
        do {
            try auth.restore()
            if auth.current == nil { showLogin() } else { showCalls() }
        } catch { showLogin(error: error.localizedDescription) }
    }

    func suspend() { (navigationController.topViewController as? CallsListController)?.suspend() }
    func resume() {
        (navigationController.topViewController as? CallsListController)?.resume()
        (navigationController.topViewController as? CallController)?.refresh()
    }
    func stop() {
        (navigationController.topViewController as? CallController)?.stop()
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
            guard let self else { return }
            self.navigationController.pushViewController(
                CallController(target: target, auth: self.auth), animated: true)
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
    }
}
