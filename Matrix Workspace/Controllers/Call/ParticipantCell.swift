import UIKit

struct ParticipantDisplayModel {
    let name: String
    let muted: Bool
    let isCurrent: Bool
}

@MainActor
final class ParticipantCell: UICollectionViewCell {
    private lazy var initialsLabel: UILabel = {
        let view = UILabel()
        view.font = .preferredFont(forTextStyle: .largeTitle)
        view.textAlignment = .center
        view.adjustsFontSizeToFitWidth = true
        view.minimumScaleFactor = 0.5
        return view
    }()
    private lazy var nameLabel: UILabel = {
        let view = UILabel()
        view.font = .preferredFont(forTextStyle: .subheadline)
        view.adjustsFontForContentSizeCategory = true
        view.numberOfLines = 2
        view.textAlignment = .center
        return view
    }()
    private lazy var micImage: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.tintColor = .secondaryLabel
        return view
    }()
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStyle()
        addSubviews()
        makeConstraints()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func apply(_ item: ParticipantDisplayModel) {
        initialsLabel.text = item.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
            .uppercased()
        nameLabel.text = item.name + (item.isCurrent ? " (вы)" : "")
        micImage.image = UIImage(systemName: item.muted ? "mic.slash.fill" : "mic.fill")
        accessibilityLabel = "\(nameLabel.text ?? item.name), \(item.muted ? "микрофон выключен" : "микрофон включён")"
    }
    private func setupStyle() {
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 20
        contentView.clipsToBounds = true
        isAccessibilityElement = true
    }
    private func addSubviews() {
        contentView.addSubview(initialsLabel)
        contentView.addSubview(nameLabel)
        contentView.addSubview(micImage)
    }
    private func makeConstraints() {
        [initialsLabel, nameLabel, micImage].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            initialsLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -12),
            initialsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            nameLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            micImage.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            micImage.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            micImage.widthAnchor.constraint(equalToConstant: 18),
            micImage.heightAnchor.constraint(equalToConstant: 18),
        ])
    }
}
