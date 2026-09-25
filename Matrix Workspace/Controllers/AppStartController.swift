import UIKit

@MainActor
final class AppStartController: UIViewController {
    private let customView = AppStartView()

    override func loadView() {
        view = customView
    }
}
