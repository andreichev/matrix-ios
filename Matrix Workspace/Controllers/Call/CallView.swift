import UIKit

@MainActor
final class CallView: UIView, UICollectionViewDataSource {
    var onJoin: (() -> Void)?
    var onMute: (() -> Void)?
    var onSpeaker: (() -> Void)?
    var onLeave: (() -> Void)?
    private var participants: [ParticipantDisplayModel] = []

    private lazy var statusLabel: UILabel = {
        let view = UILabel()
        view.textAlignment = .center
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.numberOfLines = 0
        view.textColor = .secondaryLabel
        return view
    }()
    private lazy var errorLabel: UILabel = {
        let view = UILabel()
        view.textAlignment = .center
        view.font = .preferredFont(forTextStyle: .subheadline)
        view.adjustsFontForContentSizeCategory = true
        view.numberOfLines = 0
        view.textColor = .systemRed
        return view
    }()
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { [weak self] _, _ in
            let item = NSCollectionLayoutItem(
                layoutSize: .init(widthDimension: .fractionalWidth(0.5), heightDimension: .fractionalHeight(1)))
            item.contentInsets = .init(top: 6, leading: 6, bottom: 6, trailing: 6)
            let row = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(0.5)),
                subitems: [item])
            let page = NSCollectionLayoutGroup.vertical(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(1)),
                subitems: [row, row])
            let section = NSCollectionLayoutSection(group: page)
            section.orthogonalScrollingBehavior = .groupPaging
            section.visibleItemsInvalidationHandler = { [weak self] _, offset, environment in
                let width = environment.container.effectiveContentSize.width
                if width > 0 { self?.pageControl.currentPage = Int((offset.x / width).rounded()) }
            }
            return section
        }
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.dataSource = self
        view.register(ParticipantCell.self, forCellWithReuseIdentifier: "participant")
        view.alwaysBounceVertical = false
        return view
    }()
    private lazy var pageControl: UIPageControl = {
        let view = UIPageControl()
        view.hidesForSinglePage = true
        view.currentPageIndicatorTintColor = .label
        view.pageIndicatorTintColor = .tertiaryLabel
        view.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                let index = self.pageControl.currentPage * 4
                if index < self.participants.count {
                    self.collectionView.scrollToItem(
                        at: IndexPath(item: index, section: 0), at: .centeredHorizontally, animated: true)
                }
            }, for: .valueChanged)
        return view
    }()
    private lazy var joinButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Присоединиться"
        config.buttonSize = .large
        let view = UIButton(configuration: config)
        view.addAction(UIAction { [weak self] _ in self?.onJoin?() }, for: .touchUpInside)
        return view
    }()
    private lazy var muteButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.image = UIImage(systemName: "mic.fill")
        config.buttonSize = .large
        config.cornerStyle = .capsule
        let view = UIButton(configuration: config)
        view.addAction(UIAction { [weak self] _ in self?.onMute?() }, for: .touchUpInside)
        return view
    }()
    private lazy var speakerButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "speaker.wave.3.fill")
        config.buttonSize = .large
        config.cornerStyle = .capsule
        let view = UIButton(configuration: config)
        view.addAction(UIAction { [weak self] _ in self?.onSpeaker?() }, for: .touchUpInside)
        return view
    }()
    private lazy var leaveButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "phone.down.fill")
        config.baseBackgroundColor = .systemRed
        config.buttonSize = .large
        config.cornerStyle = .capsule
        let view = UIButton(configuration: config)
        view.accessibilityLabel = "Выйти из звонка"
        view.addAction(UIAction { [weak self] _ in self?.onLeave?() }, for: .touchUpInside)
        return view
    }()
    private lazy var buttons: UIStackView = {
        let view = UIStackView()
        view.axis = .horizontal
        view.spacing = 24
        view.alignment = .center
        return view
    }()
    private lazy var footer: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.spacing = 12
        view.alignment = .center
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStyle()
        addSubviews()
        makeConstraints()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func apply(_ state: CallScreenState) {
        switch state.phase {
        case .ready: statusLabel.text = state.online ? "Готовы присоединиться?" : "Подключение к серверу…"
        case .joining: statusLabel.text = "Подключение к звонку…"
        case .active: statusLabel.text = state.connected ? "В звонке" : "Подключение звука…"
        case .reconnecting: statusLabel.text = "Восстановление связи…"
        case .ended: statusLabel.text = "Звонок завершён"
        }
        errorLabel.text = state.error
        errorLabel.isHidden = state.error == nil
        joinButton.isHidden = state.phase != .ready && !(state.phase == .active && state.error != nil)
        joinButton.configuration?.title = state.phase == .active ? "Переподключиться" : "Присоединиться"
        joinButton.isEnabled = state.online
        muteButton.isEnabled = state.phase == .active && !state.changingMute
        muteButton.configuration?.image = UIImage(systemName: state.muted ? "mic.slash.fill" : "mic.fill")
        muteButton.accessibilityLabel = state.muted ? "Включить микрофон" : "Выключить микрофон"
        speakerButton.isEnabled = state.phase == .active
        speakerButton.isSelected = state.speakerEnabled
        speakerButton.configuration?.baseBackgroundColor = state.speakerEnabled ? .systemBlue : .secondarySystemFill
        speakerButton.configuration?.baseForegroundColor = state.speakerEnabled ? .white : .label
        speakerButton.accessibilityLabel = state.speakerEnabled ? "Выключить громкую связь" : "Включить громкую связь"
        speakerButton.accessibilityValue = state.speakerEnabled ? "Включена" : "Выключена"
        participants =
            state.call?.participants.flatMap { person in
                person.connections.map { connection in
                    ParticipantDisplayModel(
                        name: person.name,
                        muted: connection.peerId == state.call?.myPeerId
                            ? state.muted : (connection.producer?.paused ?? true),
                        isCurrent: connection.peerId == state.call?.myPeerId)
                }
            } ?? []
        pageControl.numberOfPages = (participants.count + 3) / 4
        pageControl.currentPage = min(pageControl.currentPage, max(0, pageControl.numberOfPages - 1))
        collectionView.reloadData()
    }
    private func setupStyle() { backgroundColor = .systemGroupedBackground }
    private func addSubviews() {
        addSubview(statusLabel)
        addSubview(collectionView)
        addSubview(footer)
        buttons.addArrangedSubview(muteButton)
        buttons.addArrangedSubview(speakerButton)
        buttons.addArrangedSubview(leaveButton)
        [pageControl, errorLabel, joinButton, buttons].forEach(footer.addArrangedSubview)
    }
    private func makeConstraints() {
        [statusLabel, collectionView, footer].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            collectionView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            collectionView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            collectionView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            collectionView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
            errorLabel.widthAnchor.constraint(equalTo: footer.widthAnchor),
            muteButton.widthAnchor.constraint(equalToConstant: 64),
            muteButton.heightAnchor.constraint(equalToConstant: 56),
            speakerButton.widthAnchor.constraint(equalToConstant: 64),
            speakerButton.heightAnchor.constraint(equalToConstant: 56),
            leaveButton.widthAnchor.constraint(equalToConstant: 64),
            leaveButton.heightAnchor.constraint(equalToConstant: 56),
        ])
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        participants.count
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
    {
        let cell =
            collectionView.dequeueReusableCell(withReuseIdentifier: "participant", for: indexPath) as! ParticipantCell
        cell.apply(participants[indexPath.item])
        return cell
    }
}
