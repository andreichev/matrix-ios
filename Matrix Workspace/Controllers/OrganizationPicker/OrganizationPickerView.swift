import UIKit

@MainActor
final class OrganizationPickerView: UIView {
    var onSearch: ((String) -> Void)?
    var onRetry: (() -> Void)?

    private lazy var searchBar: UISearchBar = {
        let view = UISearchBar()
        view.placeholder = "Название организации"
        view.searchBarStyle = .minimal
        view.delegate = self
        return view
    }()
    private lazy var statusStack: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.spacing = 8
        return view
    }()
    private lazy var statusLabel: UILabel = {
        let view = UILabel()
        view.font = .preferredFont(forTextStyle: .subheadline)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .secondaryLabel
        view.numberOfLines = 0
        return view
    }()
    private lazy var retryButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "Повторить"
        let view = UIButton(configuration: config)
        view.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
        return view
    }()
    lazy var tableView: UITableView = {
        let view = UITableView(frame: .zero, style: .insetGrouped)
        view.keyboardDismissMode = .onDrag
        view.register(UITableViewCell.self, forCellReuseIdentifier: "organization")
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStyle()
        addSubviews()
        makeConstraints()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func apply(status: String, canRetry: Bool = false) {
        statusLabel.text = status
        retryButton.isHidden = !canRetry
    }

    private func setupStyle() { backgroundColor = .systemGroupedBackground }
    private func addSubviews() {
        [searchBar, statusStack, tableView].forEach(addSubview)
        [statusLabel, retryButton].forEach(statusStack.addArrangedSubview)
    }
    private func makeConstraints() {
        [searchBar, statusStack, tableView].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            searchBar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            statusStack.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            statusStack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            statusStack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            tableView.topAnchor.constraint(equalTo: statusStack.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])
    }
}

extension OrganizationPickerView: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { onSearch?(searchText) }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
}
