import UIKit

@MainActor
final class CallsListController: UIViewController {
    private lazy var customView = CallsListView()
    private let interactor: CallsListInteractor
    var onSelect: ((CallTarget) -> Void)?
    var onLogoutError: ((String) -> Void)?

    init(auth: AuthService) {
        interactor = CallsListInteractor(auth: auth)
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func loadView() { view = customView }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Звонки"
        navigationItem.backButtonTitle = "Назад"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Выйти", primaryAction: UIAction { [weak self] _ in self?.logout() })
        customView.onSelect = { [weak self] target in self?.onSelect?(target) }
        customView.onRefresh = { [weak self] in self?.interactor.refresh() }
        interactor.onChange = { [weak self] state in self?.customView.apply(state) }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Returning from a system-ended call can reveal this screen while the phone is locked.
        if UIApplication.shared.applicationState != .background { interactor.start() }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        interactor.stop()
    }
    func suspend() { interactor.stop() }
    func resume() { interactor.start() }
    private func logout() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        let reportError = onLogoutError
        Task { [weak self, interactor] in
            do { try await interactor.logout() } catch {
                reportError?("Не удалось подтвердить выход на сервере: \(error.localizedDescription)")
            }
            self?.navigationItem.rightBarButtonItem?.isEnabled = true
        }
    }
}
