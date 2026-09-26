import UIKit
import WebKit

@MainActor
final class WorkspaceView: UIView {
    private let configuration: WKWebViewConfiguration
    lazy var webView: WKWebView = {
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = HTTPClient.userAgent
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.allowsBackForwardNavigationGestures = true
        return view
    }()
    private lazy var errorLabel: UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        view.textAlignment = .center
        view.font = .preferredFont(forTextStyle: .body)
        return view
    }()
    private lazy var retryButton: UIButton = {
        let view = UIButton(configuration: .tinted())
        view.setTitle("Повторить", for: .normal)
        view.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
        return view
    }()
    private lazy var errorPanel: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.spacing = 16
        view.isHidden = true
        return view
    }()
    var onRetry: (() -> Void)?

    init(configuration: WKWebViewConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        setupStyle(); addSubviews(); makeConstraints()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func showError(_ text: String?) {
        errorLabel.text = text
        errorPanel.isHidden = text == nil
        webView.isHidden = text != nil
    }
    private func setupStyle() { backgroundColor = .systemBackground }
    private func addSubviews() {
        addSubview(webView); addSubview(errorPanel)
        errorPanel.addArrangedSubview(errorLabel); errorPanel.addArrangedSubview(retryButton)
    }
    private func makeConstraints() {
        [webView, errorPanel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor), webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            errorPanel.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorPanel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 24),
            errorPanel.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])
    }
}
