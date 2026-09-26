import UIKit

@MainActor
final class OrganizationPickerController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private lazy var customView = OrganizationPickerView()
    private let directory: OrganizationDirectoryService
    private var organizations: [DirectoryOrganization] = []
    private var query = ""
    private var task: Task<Void, Never>?
    var onSelect: ((OrganizationSelection) -> Void)?

    init(directory: OrganizationDirectoryService) {
        self.directory = directory
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { task?.cancel() }
    override func loadView() { view = customView }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Организация"
        customView.tableView.dataSource = self
        customView.tableView.delegate = self
        customView.onSearch = { [weak self] text in
            self?.query = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self?.loadOrganizations(debounce: true)
        }
        customView.onRetry = { [weak self] in self?.loadOrganizations() }
        loadOrganizations()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent { task?.cancel() }
    }

    private func loadOrganizations(debounce: Bool = false) {
        task?.cancel()
        organizations = []
        customView.tableView.reloadData()
        customView.apply(status: "Загрузка организаций…")
        let query = query
        task = Task { [weak self, directory] in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(300)) }
                let organizations = try await directory.organizations(query: query)
                try Task.checkCancellation()
                guard let self else { return }
                self.organizations = organizations
                customView.tableView.reloadData()
                customView.apply(status: organizations.isEmpty
                    ? "Организации не найдены. Можно указать адрес вручную."
                    : "Выберите организацию. Если её нет в списке, уточните поиск или укажите адрес вручную.")
            } catch {
                guard !Task.isCancelled else { return }
                self?.customView.apply(status: "Не удалось загрузить список. Можно повторить попытку или указать адрес вручную.",
                    canRetry: true)
            }
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { 2 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : organizations.count
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "organization", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            content.text = "Другая организация"
            content.secondaryText = "Указать адрес сервера вручную"
            content.image = UIImage(systemName: "globe")
        } else {
            let organization = organizations[indexPath.row]
            content.text = organization.name
            content.secondaryText = organization.baseUrl
            content.image = UIImage(systemName: "building.2")
        }
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            onSelect?(OrganizationSelection(name: nil, baseUrl: ""))
            return
        }
        let organization = organizations[indexPath.row]
        do {
            let server = try ServerAddress(organization.baseUrl)
            onSelect?(OrganizationSelection(name: organization.name, baseUrl: server.url.absoluteString))
        } catch {
            customView.apply(status: "У организации указан некорректный адрес сервера. Обратитесь к администратору.")
        }
    }
}
