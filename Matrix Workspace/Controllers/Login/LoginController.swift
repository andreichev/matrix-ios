import UIKit

@MainActor
final class LoginController: UIViewController {
    private lazy var customView = LoginView()
    private let interactor: LoginInteractor
    private var task: Task<Void, Never>?
    var onLogin: (() -> Void)?

    init(auth: AuthService) {
        interactor = LoginInteractor(auth: auth)
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func loadView() { view = customView }
    override func viewDidLoad() {
        super.viewDidLoad()
        customView.onSubmit = { [weak self] in self?.submit() }
    }

    private func submit() {
        guard task == nil else { return }
        let input = customView.credentials
        customView.endEditing(true)
        customView.apply(busy: true)
        task = Task { [weak self, interactor] in
            do {
                try await interactor.login(username: input.username, password: input.password)
                self?.customView.clearPassword()
                self?.customView.apply(busy: false)
                self?.onLogin?()
            } catch { self?.customView.apply(busy: false, error: error.localizedDescription) }
            self?.task = nil
        }
    }
    func showError(_ message: String) {
        loadViewIfNeeded()
        customView.apply(busy: false, error: message)
    }
}
