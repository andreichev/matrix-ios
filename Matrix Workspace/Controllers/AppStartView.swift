import UIKit

@MainActor
final class AppStartView: UIView {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let contentStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStyle()
        addSubviews()
        makeConstraints()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    private func setupStyle() {
        backgroundColor = .systemBackground

        titleLabel.text = L10n.text("app_start.title")
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.textColor = .label
        titleLabel.accessibilityTraits.insert(.header)

        detailLabel.text = L10n.text("app_start.detail")
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.textColor = .secondaryLabel

        for label in [titleLabel, detailLabel] {
            label.numberOfLines = 0
            label.textAlignment = .center
            label.adjustsFontForContentSizeCategory = true
        }

        contentStack.axis = .vertical
        contentStack.spacing = 16
    }

    private func addSubviews() {
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(detailLabel)
        addSubview(contentStack)
    }

    private func makeConstraints() {
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        let preferredWidth = contentStack.widthAnchor.constraint(equalToConstant: 440)
        preferredWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -24),
            preferredWidth,
        ])
    }
}
