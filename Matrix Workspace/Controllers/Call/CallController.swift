import UIKit

@MainActor
final class CallController: UIViewController {
    private lazy var customView = CallView()
    private let interactor: CallInteractor

    init(target: CallTarget, auth: AuthService, systemCalls: SystemCallService) {
        interactor = CallInteractor(target: target, auth: auth, systemCalls: systemCalls)
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func loadView() { view = customView }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Звонок"
        customView.onJoin = { [weak self] in self?.interactor.retry() }
        customView.onMute = { [weak self] in self?.interactor.toggleMute() }
        customView.onSpeaker = { [weak self] in self?.interactor.toggleSpeaker() }
        customView.onLeave = { [weak self] in self?.interactor.stop() }
        interactor.onChange = { [weak self] state in
            guard let self else { return }
            self.title = state.call?.title ?? "Звонок"
            self.customView.apply(state)
            if state.phase == .ended, state.error == nil { self.closeCallScreen() }
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

    private func closeCallScreen() {
        guard let navigationController, navigationController.topViewController === self else { return }
        let animated = view.window?.windowScene?.activationState == .foregroundActive
        navigationController.popViewController(animated: animated)
    }
}
