import UIKit

@MainActor
final class LoginView: UIView {
    var onSubmit: (() -> Void)?

    private lazy var scrollView: UIScrollView = {
        let view = UIScrollView()
        view.keyboardDismissMode = .interactive
        return view
    }()
    private lazy var stack: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.spacing = 16
        return view
    }()
    private lazy var heading: UILabel = {
        let view = UILabel()
        view.text = "Матрица"
        view.font = .preferredFont(forTextStyle: .largeTitle)
        view.adjustsFontForContentSizeCategory = true
        view.numberOfLines = 0
        view.accessibilityTraits.insert(.header)
        return view
    }()
    private lazy var descriptionLabel: UILabel = {
        let view = UILabel()
        view.text = "Войдите в свою учётную запись Матрицы."
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .secondaryLabel
        view.numberOfLines = 0
        return view
    }()
    private lazy var usernameField: UITextField = {
        let view = Self.field("Логин")
        view.textContentType = .username
        return view
    }()
    private lazy var passwordField: UITextField = {
        let view = Self.field("Пароль")
        view.textContentType = .password
        view.isSecureTextEntry = true
        view.returnKeyType = .go
        view.addAction(UIAction { [weak self] _ in self?.onSubmit?() }, for: .editingDidEndOnExit)
        return view
    }()
    private lazy var submitButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Войти"
        config.buttonSize = .large
        let view = UIButton(configuration: config)
        view.addAction(UIAction { [weak self] _ in self?.onSubmit?() }, for: .touchUpInside)
        return view
    }()
    private lazy var errorLabel: UILabel = {
        let view = UILabel()
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .systemRed
        view.numberOfLines = 0
        view.isHidden = true
        return view
    }()

    var credentials: (username: String, password: String) {
        (
            (usernameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            passwordField.text ?? ""
        )
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStyle()
        addSubviews()
        makeConstraints()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func apply(busy: Bool, error: String? = nil) {
        usernameField.isEnabled = !busy
        passwordField.isEnabled = !busy
        submitButton.isEnabled = !busy
        submitButton.configuration?.showsActivityIndicator = busy
        errorLabel.text = error
        errorLabel.isHidden = error == nil
    }
    func clearPassword() { passwordField.text = nil }

    private func setupStyle() { backgroundColor = .systemBackground }
    private func addSubviews() {
        addSubview(scrollView)
        scrollView.addSubview(stack)
        [heading, descriptionLabel, usernameField, passwordField, submitButton, errorLabel].forEach(
            stack.addArrangedSubview)
    }
    private func makeConstraints() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        [usernameField, passwordField].forEach {
            $0.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
        ])
    }
    private static func field(_ title: String) -> UITextField {
        let view = UITextField()
        view.placeholder = title
        view.accessibilityLabel = title
        view.borderStyle = .roundedRect
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        return view
    }
}
