import UIKit
import WebKit

/// Retains each page, including history and forms, until explicitly closed.
final class BrowserTabCoordinator {
    let navigationController = UINavigationController()
    private var tabs: [BrowserViewController] = []
    private weak var picker: BrowserTabsGridViewController?

    private let sessionStore: BrowserSessionStore
    private var restoring = true

    init(sessionStore: BrowserSessionStore = BrowserSessionStore()) {
        self.sessionStore = sessionStore
        if let session = sessionStore.load() {
            for url in session.urls {
                _ = addTab(initialURL: url ?? BrowserPreferences().defaultBank.url, activate: false)
            }
            select(tabs[session.selectedIndex])
        } else {
            _ = addTab()
        }
        restoring = false
        saveSession()
    }

    func saveSession() {
        guard !restoring, !tabs.isEmpty else { return }
        let index = tabs.firstIndex { $0 === navigationController.topViewController } ?? 0
        sessionStore.save(BrowserSession(urls: tabs.map { $0.restorationURL }, selectedIndex: index))
    }

    @discardableResult
    private func addTab(initialURL: URL? = nil, activate: Bool = true, configuration: WKWebViewConfiguration? = nil,
                        rules: WKContentRuleList? = nil, opener: BrowserViewController? = nil) -> BrowserViewController? {
        guard tabs.count < 12 else {
            let alert = UIAlertController(title: "Открыто 12 вкладок", message: "Закройте ненужную вкладку, чтобы открыть новую.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Понятно", style: .default))
            (navigationController.presentedViewController ?? navigationController).present(alert, animated: true)
            return nil
        }
        let browser = BrowserViewController(initialURL: configuration == nil ? (initialURL ?? BrowserPreferences().defaultBank.url) : nil,
                                            configuration: configuration, rules: rules)
        browser.onAddressChanged = { [weak self] in self?.saveSession() }
        browser.opener = opener
        browser.onShowTabs = { [weak self] in self?.showTabs() }
        browser.onCreateWindow = { [weak self, weak browser] config, rules in
            self?.addTab(configuration: config, rules: rules, opener: browser)?.webView
        }
        browser.onCloseWindow = { [weak self, weak browser] in
            if let browser = browser { self?.close(browser) }
        }
        tabs.append(browser)
        if activate { select(browser); browser.loadViewIfNeeded() }
        updateCounts()
        saveSession()
        return browser
    }

    private func select(_ browser: BrowserViewController) {
        navigationController.topViewController?.view.endEditing(true)
        navigationController.setViewControllers([browser], animated: false)
        browser.loadViewIfNeeded()
        saveSession()
    }

    private func close(_ browser: BrowserViewController) {
        guard let index = tabs.firstIndex(where: { $0 === browser }) else { return }
        let wasSelected = navigationController.topViewController === browser
        tabs.remove(at: index)
        browser.closeTab()
        if tabs.isEmpty { _ = addTab() }
        else if wasSelected {
            let parent = browser.opener.flatMap { candidate in tabs.first(where: { $0 === candidate }) }
            select(parent ?? tabs[min(index, tabs.count - 1)])
        }
        updateCounts()
        saveSession()
    }

    private func updateCounts() {
        tabs.forEach { $0.tabCount = tabs.count }
        picker?.reloadData()
    }

    private func showTabs() {
        guard navigationController.presentedViewController == nil else { return }
        let current = navigationController.topViewController as? BrowserViewController
        current?.captureSnapshot { [weak self] _ in
            guard let self = self else { return }
            let grid = BrowserTabsGridViewController()
            grid.getTabs = { [weak self] in self?.tabs ?? [] }
            grid.isSelected = { [weak self] browser in
                self?.navigationController.topViewController === browser
            }
            grid.onSelect = { [weak self, weak grid] browser in
                grid?.dismiss(animated: true) { self?.select(browser) }
            }
            grid.onClose = { [weak self] browser in
                self?.close(browser)
            }
            grid.onNew = { [weak self, weak grid] in
                grid?.dismiss(animated: true) { _ = self?.addTab() }
            }
            self.picker = grid
            let sheet = UINavigationController(rootViewController: grid)
            sheet.modalPresentationStyle = .pageSheet
            sheet.sheetPresentationController?.detents = [.large()]
            sheet.sheetPresentationController?.prefersGrabberVisible = true
            self.navigationController.present(sheet, animated: true)
        }
    }
}

// MARK: - Modern 2-Column Tab Switcher Grid
final class BrowserTabsGridViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var getTabs: () -> [BrowserViewController] = { [] }
    var isSelected: (BrowserViewController) -> Bool = { _ in false }
    var onSelect: ((BrowserViewController) -> Void)?
    var onClose: ((BrowserViewController) -> Void)?
    var onNew: (() -> Void)?

    private var collectionView: UICollectionView!
    private let bottomToolbar = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let tabCountLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Вкладки"
        view.backgroundColor = .systemGroupedBackground
        navigationController?.navigationBar.prefersLargeTitles = true

        setupCollectionView()
        setupBottomToolbar()
    }

    func reloadData() {
        collectionView.reloadData()
        updateTabCountLabel()
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 14
        layout.minimumLineSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 14, left: 16, bottom: 90, right: 16)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(BrowserTabGridCell.self, forCellWithReuseIdentifier: "TabCell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupBottomToolbar() {
        bottomToolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomToolbar)

        let hairline = UIView()
        hairline.backgroundColor = .separator
        hairline.translatesAutoresizingMaskIntoConstraints = false
        bottomToolbar.contentView.addSubview(hairline)

        tabCountLabel.font = .preferredFont(forTextStyle: .subheadline)
        tabCountLabel.textColor = .secondaryLabel
        tabCountLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomToolbar.contentView.addSubview(tabCountLabel)

        let addBtn = UIButton(type: .system)
        let plusConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        addBtn.setImage(UIImage(systemName: "plus", withConfiguration: plusConfig), for: .normal)
        addBtn.tintColor = .systemBlue
        addBtn.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        addBtn.layer.cornerRadius = 20
        addBtn.accessibilityLabel = "Новая вкладка"
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addBtn.addAction(UIAction { [weak self] _ in self?.onNew?() }, for: .touchUpInside)
        bottomToolbar.contentView.addSubview(addBtn)

        let doneBtn = UIButton(type: .system)
        doneBtn.setTitle("Готово", for: .normal)
        doneBtn.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneBtn.tintColor = .systemBlue
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        doneBtn.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        bottomToolbar.contentView.addSubview(doneBtn)

        NSLayoutConstraint.activate([
            bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomToolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),

            hairline.topAnchor.constraint(equalTo: bottomToolbar.topAnchor),
            hairline.leadingAnchor.constraint(equalTo: bottomToolbar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: bottomToolbar.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5),

            tabCountLabel.leadingAnchor.constraint(equalTo: bottomToolbar.leadingAnchor, constant: 18),
            tabCountLabel.centerYAnchor.constraint(equalTo: bottomToolbar.topAnchor, constant: 30),

            addBtn.centerXAnchor.constraint(equalTo: bottomToolbar.centerXAnchor),
            addBtn.centerYAnchor.constraint(equalTo: bottomToolbar.topAnchor, constant: 30),
            addBtn.widthAnchor.constraint(equalToConstant: 40),
            addBtn.heightAnchor.constraint(equalToConstant: 40),

            doneBtn.trailingAnchor.constraint(equalTo: bottomToolbar.trailingAnchor, constant: -18),
            doneBtn.centerYAnchor.constraint(equalTo: bottomToolbar.topAnchor, constant: 30)
        ])

        updateTabCountLabel()
    }

    private func updateTabCountLabel() {
        let count = getTabs().count
        tabCountLabel.text = "\(count) \(tabWord(for: count))"
    }

    private func tabWord(for count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 19 { return "вкладок" }
        if mod10 == 1 { return "вкладка" }
        if mod10 >= 2 && mod10 <= 4 { return "вкладки" }
        return "вкладок"
    }

    // MARK: - UICollectionViewDataSource
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        getTabs().count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TabCell", for: indexPath) as! BrowserTabGridCell
        let tabs = getTabs()
        guard indexPath.item < tabs.count else { return cell }
        let browser = tabs[indexPath.item]
        let active = isSelected(browser)

        cell.configure(browser: browser, isActive: active) { [weak self, weak browser] in
            guard let self = self, let browser = browser else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.onClose?(browser)
            self.reloadData()
        }
        return cell
    }

    // MARK: - UICollectionViewDelegateFlowLayout
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let availableWidth = collectionView.bounds.width - 32 - 14 // left/right insets (32) + spacing (14)
        let width = max(140, floor(availableWidth / 2))
        let height = floor(width * 1.32)
        return CGSize(width: width, height: height)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let tabs = getTabs()
        guard indexPath.item < tabs.count else { return }
        onSelect?(tabs[indexPath.item])
    }
}

// MARK: - Modern Tab Grid Cell
final class BrowserTabGridCell: UICollectionViewCell {
    private let containerView = UIView()
    private let headerBar = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let previewImageView = UIImageView()
    private let placeholderView = UIView()
    private let placeholderLabel = UILabel()

    private var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupViews() {
        contentView.backgroundColor = .clear

        containerView.layer.cornerRadius = 14
        containerView.layer.masksToBounds = true
        containerView.backgroundColor = .secondarySystemGroupedBackground
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        // Header bar
        headerBar.backgroundColor = .tertiarySystemGroupedBackground
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(headerBar)

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .systemBlue
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(iconImageView)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(titleLabel)

        let xConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.backgroundColor = UIColor.label.withAlphaComponent(0.08)
        closeButton.layer.cornerRadius = 12
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        headerBar.addSubview(closeButton)

        // Preview image
        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
        previewImageView.backgroundColor = .systemBackground
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(previewImageView)

        // Placeholder for tabs without snapshot
        placeholderView.backgroundColor = .systemBackground
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        let globeConfig = UIImage.SymbolConfiguration(pointSize: 32, weight: .light)
        let placeholderIcon = UIImageView(image: UIImage(systemName: "globe", withConfiguration: globeConfig))
        placeholderIcon.tintColor = .tertiaryLabel
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.addSubview(placeholderIcon)

        placeholderLabel.font = .preferredFont(forTextStyle: .caption2)
        placeholderLabel.textColor = .secondaryLabel
        placeholderLabel.textAlignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.addSubview(placeholderLabel)

        containerView.addSubview(placeholderView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            headerBar.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 34),

            iconImageView.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 8),
            iconImageView.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 16),
            iconImageView.heightAnchor.constraint(equalToConstant: 16),

            closeButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
            titleLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            previewImageView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            placeholderView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            placeholderIcon.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: placeholderView.centerYAnchor, constant: -10),

            placeholderLabel.topAnchor.constraint(equalTo: placeholderIcon.bottomAnchor, constant: 8),
            placeholderLabel.leadingAnchor.constraint(equalTo: placeholderView.leadingAnchor, constant: 8),
            placeholderLabel.trailingAnchor.constraint(equalTo: placeholderView.trailingAnchor, constant: -8)
        ])
    }

    func configure(browser: BrowserViewController, isActive: Bool, onClose: @escaping () -> Void) {
        self.onClose = onClose

        titleLabel.text = browser.tabTitle.isEmpty ? browser.tabHost : browser.tabTitle
        closeButton.accessibilityLabel = "Закрыть вкладку \(browser.tabTitle)"

        let host = browser.tabHost
        placeholderLabel.text = host

        // Determine icon based on matching bank or default globe
        if let bank = Bank.matching(URL(string: "https://" + host)) {
            iconImageView.image = UIImage(systemName: bank.displayIconName)
            iconImageView.tintColor = bank.tintColor
        } else {
            iconImageView.image = UIImage(systemName: "globe")
            iconImageView.tintColor = .systemBlue
        }

        // Active border
        if isActive {
            containerView.layer.borderWidth = 2.5
            containerView.layer.borderColor = UIColor.systemBlue.cgColor
        } else {
            containerView.layer.borderWidth = 1
            containerView.layer.borderColor = UIColor.separator.cgColor
        }

        // Snapshot preview or placeholder
        if let snapshot = browser.currentSnapshot {
            previewImageView.image = snapshot
            previewImageView.isHidden = false
            placeholderView.isHidden = true
        } else {
            previewImageView.isHidden = true
            placeholderView.isHidden = false
        }
    }
}

