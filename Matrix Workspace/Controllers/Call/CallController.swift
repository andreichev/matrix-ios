import UIKit

@MainActor
final class CallController: UIViewController {
    private lazy var customView = CallView()
    private let interactor: CallInteractor

    init(target: CallTarget, auth: AuthService) {
        interactor = CallInteractor(target: target, auth: auth)
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func loadView() { view = customView }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Звонок"
        customView.onJoin = { [weak self] in self?.interactor.retry() }
        customView.onMute = { [weak self] in self?.interactor.toggleMute() }
        customView.onLeave = { [weak self] in
            self?.interactor.stop()
            self?.navigationController?.popViewController(animated: true)
        }
        interactor.onChange = { [weak self] state in
            self?.title = state.call?.title ?? "Звонок"
            self?.customView.apply(state)
        }
        customView.apply(CallScreenState())
        interactor.start()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if navigationController?.viewControllers.contains(self) != true { interactor.stop() }
    }
    func refresh() { interactor.sync() }
    func stop() { interactor.stop() }
}
