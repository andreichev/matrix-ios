import UIKit

@MainActor
final class CallsListView: UIView, UITableViewDataSource, UITableViewDelegate {
    var onSelect: ((CallTarget) -> Void)?
    var onRefresh: (() -> Void)?
    private var state = CallsListState()
    private lazy var statusLabel: UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        view.font = .preferredFont(forTextStyle: .subheadline)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .secondaryLabel
        return view
    }()
    private lazy var refreshControl: UIRefreshControl = {
        let view = UIRefreshControl()
        view.addAction(UIAction { [weak self] _ in self?.onRefresh?() }, for: .valueChanged)
        return view
    }()
    private lazy var tableView: UITableView = {
        let view = UITableView(frame: .zero, style: .insetGrouped)
        view.register(UITableViewCell.self, forCellReuseIdentifier: "chat")
        view.dataSource = self
        view.delegate = self
        view.refreshControl = refreshControl
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStyle()
        addSubviews()
        makeConstraints()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func apply(_ state: CallsListState) {
        self.state = state
        if let error = state.error {
            statusLabel.text = error
        } else if !state.online {
            statusLabel.text = "Подключение…"
        } else if let enabled = state.enabled {
            statusLabel.text = enabled
                ? "Выберите чат для звонка. Микрофон включится только после присоединения."
                : "Звонки отключены. Обратитесь к администратору."
        } else {
            statusLabel.text = "Проверка доступности звонков…"
        }
        refreshControl.endRefreshing()
        tableView.reloadData()
    }
    private func setupStyle() { backgroundColor = .systemGroupedBackground }
    private func addSubviews() {
        addSubview(statusLabel)
        addSubview(tableView)
    }
    private func makeConstraints() {
        [statusLabel, tableView].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    func numberOfSections(in tableView: UITableView) -> Int { 2 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? state.calls.count : state.chats.count
    }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? (state.calls.isEmpty ? nil : "Текущие звонки") : "Мои чаты"
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "chat", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let call = state.calls[indexPath.row]
            content.text = call.title
            content.secondaryText =
                call.myStatus == "INVITED" ? "Входящий звонок" : "Подключений: \(call.connections.count)"
            content.image = UIImage(systemName: "phone.fill")
        } else {
            content.text = state.chats[indexPath.row].displayTitle
            content.image = UIImage(systemName: "bubble.left.and.bubble.right")
        }
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = state.online && state.enabled == true ? .default : .none
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard state.online, state.enabled == true else { return }
        onSelect?(indexPath.section == 0 ? .call(state.calls[indexPath.row].id) : .chat(state.chats[indexPath.row].id))
    }
}
