import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let coordinator = AppCoordinator(services: appDelegate.services)
        self.coordinator = coordinator
        window.rootViewController = coordinator.navigationController
        coordinator.start()
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidEnterBackground(_ scene: UIScene) { coordinator?.suspend() }
    func sceneWillResignActive(_ scene: UIScene) { coordinator?.suspend() }
    func sceneDidBecomeActive(_ scene: UIScene) { coordinator?.resume() }
    func sceneDidDisconnect(_ scene: UIScene) { coordinator?.suspend() }
}
