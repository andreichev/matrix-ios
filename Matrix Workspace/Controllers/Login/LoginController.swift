import UIKit

@MainActor
final class LoginController: UIViewController {
    private lazy var customView = LoginView()
    private let interactor: LoginInteractor
    private var task: Task<Void, Never>?
    private var organization: OrganizationSelection?
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
        customView.onChooseOrganization = { [weak self] in self?.chooseOrganization() }
        organization = interactor.directory.lastSelection
        customView.apply(organization: organization)
    }

    private func chooseOrganization() {
        guard task == nil else { return }
        customView.endEditing(true)
        let controller = OrganizationPickerController(directory: interactor.directory)
        controller.onSelect = { [weak self] selection in
            guard let self else { return }
            organization = selection
            customView.clearCredentials()
            customView.apply(organization: selection)
            customView.apply(busy: false)
            navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func submit() {
        guard task == nil else { return }
        guard let organization else {
            customView.apply(busy: false, error: "Выберите организацию.")
            return
        }
        let input = customView.credentials
        let selection: OrganizationSelection
        if organization.name == nil {
            let address = customView.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else {
                customView.apply(busy: false, error: "Укажите адрес сервера организации.")
                return
            }
            selection = OrganizationSelection(name: nil, baseUrl: address.contains("://") ? address : "https://" + address)
        } else {
            selection = organization
        }
        customView.endEditing(true)
        customView.apply(busy: true)
        task = Task { [weak self, interactor] in
            do {
                try await interactor.login(organization: selection, username: input.username, password: input.password)
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
