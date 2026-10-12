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
        current?.captureSnapshot(completion: { _ in })

        let grid = BrowserTabsGridViewController()
        grid.getTabs = { [weak self] in self?.tabs ?? [] }
        grid.isSelected = { [weak self] browser in
            self?.navigationController.topViewController === browser
        }
        grid.onSelect = { [weak self, weak grid] browser in
            self?.select(browser)
            grid?.dismiss(animated: true)
        }
        grid.onClose = { [weak self] browser in
            self?.close(browser)
        }
        grid.onNew = { [weak self, weak grid] in
            let _ = self?.addTab()
            grid?.dismiss(animated: true)
        }
        self.picker = grid
        grid.modalPresentationStyle = .fullScreen
        grid.modalTransitionStyle = .coverVertical
        navigationController.present(grid, animated: true)
    }
}

// MARK: - Chrome-Grade Mobile Tab Switcher Grid
final class BrowserTabsGridViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var getTabs: () -> [BrowserViewController] = { [] }
    var isSelected: (BrowserViewController) -> Bool = { _ in false }
    var onSelect: ((BrowserViewController) -> Void)?
    var onClose: ((BrowserViewController) -> Void)?
    var onNew: (() -> Void)?

    private var collectionView: UICollectionView!
    private let topBar = UIView()
    private let bottomToolbar = UIView()
    private let tabCountBadgeLabel = UILabel()

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)

        setupTopBar()
        setupCollectionView()
        setupBottomToolbar()
    }

    func reloadData() {
        collectionView.reloadData()
        updateTabCountBadge()
    }

    private func setupTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        // Center Pill (Chrome style)
        let pill = UIView()
        pill.backgroundColor = UIColor(white: 0.18, alpha: 1.0)
        pill.layer.cornerRadius = 18
        pill.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(pill)

        let maskIcon = UIImageView(image: UIImage(systemName: "eyeglasses"))
        maskIcon.tintColor = UIColor.white.withAlphaComponent(0.7)
        maskIcon.contentMode = .scaleAspectFit
        maskIcon.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(maskIcon)

        let badgeContainer = UIView()
        badgeContainer.layer.borderWidth = 1.5
        badgeContainer.layer.borderColor = UIColor.white.cgColor
        badgeContainer.layer.cornerRadius = 5
        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(badgeContainer)

        tabCountBadgeLabel.font = .systemFont(ofSize: 11, weight: .bold)
        tabCountBadgeLabel.textColor = .white
        tabCountBadgeLabel.textAlignment = .center
        tabCountBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.addSubview(tabCountBadgeLabel)

        let gridIcon = UIImageView(image: UIImage(systemName: "square.grid.2x2"))
        gridIcon.tintColor = UIColor.white.withAlphaComponent(0.7)
        gridIcon.contentMode = .scaleAspectFit
        gridIcon.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(gridIcon)

        // Left Search Icon
        let searchBtn = UIButton(type: .system)
        let searchConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        searchBtn.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: searchConfig), for: .normal)
        searchBtn.tintColor = .white
        searchBtn.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(searchBtn)

        // Right Overflow Icon
        let dotsBtn = UIButton(type: .system)
        let dotsConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        dotsBtn.setImage(UIImage(systemName: "ellipsis", withConfiguration: dotsConfig), for: .normal)
        dotsBtn.tintColor = .white
        dotsBtn.showsMenuAsPrimaryAction = true
        dotsBtn.menu = UIMenu(children: [
            UIAction(title: "Новая вкладка", image: UIImage(systemName: "plus")) { [weak self] _ in
                self?.onNew?()
            },
            UIAction(title: "Закрыть все вкладки", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { [weak self] _ in
                guard let self = self else { return }
                let tabs = self.getTabs()
                for tab in tabs {
                    self.onClose?(tab)
                }
                self.reloadData()
            }
        ])
        dotsBtn.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(dotsBtn)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 48),

            searchBtn.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            searchBtn.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            searchBtn.widthAnchor.constraint(equalToConstant: 36),
            searchBtn.heightAnchor.constraint(equalToConstant: 36),

            dotsBtn.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            dotsBtn.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            dotsBtn.widthAnchor.constraint(equalToConstant: 36),
            dotsBtn.heightAnchor.constraint(equalToConstant: 36),

            pill.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 36),
            pill.widthAnchor.constraint(equalToConstant: 130),

            maskIcon.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14),
            maskIcon.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            maskIcon.widthAnchor.constraint(equalToConstant: 20),
            maskIcon.heightAnchor.constraint(equalToConstant: 20),

            badgeContainer.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            badgeContainer.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            badgeContainer.widthAnchor.constraint(equalToConstant: 20),
            badgeContainer.heightAnchor.constraint(equalToConstant: 20),

            tabCountBadgeLabel.centerXAnchor.constraint(equalTo: badgeContainer.centerXAnchor),
            tabCountBadgeLabel.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),

            gridIcon.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14),
            gridIcon.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            gridIcon.widthAnchor.constraint(equalToConstant: 18),
            gridIcon.heightAnchor.constraint(equalToConstant: 18)
        ])

        updateTabCountBadge()
    }

    private func updateTabCountBadge() {
        tabCountBadgeLabel.text = "\(getTabs().count)"
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 14
        layout.sectionInset = UIEdgeInsets(top: 8, left: 14, bottom: 90, right: 14)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(BrowserTabGridCell.self, forCellWithReuseIdentifier: "TabCell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupBottomToolbar() {
        bottomToolbar.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 0.95)
        bottomToolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomToolbar)

        let addBtn = UIButton(type: .system)
        let plusConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        addBtn.setImage(UIImage(systemName: "plus", withConfiguration: plusConfig), for: .normal)
        addBtn.tintColor = UIColor(red: 0.08, green: 0.11, blue: 0.18, alpha: 1.0)
        addBtn.backgroundColor = UIColor(red: 0.54, green: 0.73, blue: 0.98, alpha: 1.0) // Chrome Accent Light Blue
        addBtn.layer.cornerRadius = 24
        addBtn.layer.shadowColor = UIColor.black.cgColor
        addBtn.layer.shadowOpacity = 0.3
        addBtn.layer.shadowRadius = 8
        addBtn.layer.shadowOffset = CGSize(width: 0, height: 4)
        addBtn.accessibilityLabel = "Новая вкладка"
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addBtn.addAction(UIAction { [weak self] _ in self?.onNew?() }, for: .touchUpInside)
        bottomToolbar.addSubview(addBtn)

        let doneBtn = UIButton(type: .system)
        doneBtn.setTitle("Готово", for: .normal)
        doneBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        doneBtn.setTitleColor(.white, for: .normal)
        doneBtn.backgroundColor = UIColor(white: 0.22, alpha: 1.0)
        doneBtn.layer.cornerRadius = 18
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        doneBtn.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        bottomToolbar.addSubview(doneBtn)

        NSLayoutConstraint.activate([
            bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomToolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -64),

            addBtn.centerXAnchor.constraint(equalTo: bottomToolbar.centerXAnchor),
            addBtn.topAnchor.constraint(equalTo: bottomToolbar.topAnchor, constant: 8),
            addBtn.widthAnchor.constraint(equalToConstant: 48),
            addBtn.heightAnchor.constraint(equalToConstant: 48),

            doneBtn.trailingAnchor.constraint(equalTo: bottomToolbar.trailingAnchor, constant: -16),
            doneBtn.centerYAnchor.constraint(equalTo: addBtn.centerYAnchor),
            doneBtn.widthAnchor.constraint(equalToConstant: 80),
            doneBtn.heightAnchor.constraint(equalToConstant: 36)
        ])
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
        let availableWidth = collectionView.bounds.width - 28 - 12
        let width = max(140, floor(availableWidth / 2))
        let height = floor(width * 1.34)
        return CGSize(width: width, height: height)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let tabs = getTabs()
        guard indexPath.item < tabs.count else { return }
        onSelect?(tabs[indexPath.item])
    }
}

// MARK: - Chrome-Style Tab Grid Cell
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

        containerView.layer.cornerRadius = 16
        containerView.layer.masksToBounds = true
        containerView.backgroundColor = UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1.0)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        // Header bar
        headerBar.backgroundColor = UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1.0)
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(headerBar)

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .white
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(iconImageView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(titleLabel)

        let xConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.75)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        headerBar.addSubview(closeButton)

        // Preview image
        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
        previewImageView.backgroundColor = UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(previewImageView)

        // Placeholder for tabs without snapshot
        placeholderView.backgroundColor = UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        let globeConfig = UIImage.SymbolConfiguration(pointSize: 32, weight: .light)
        let placeholderIcon = UIImageView(image: UIImage(systemName: "globe", withConfiguration: globeConfig))
        placeholderIcon.tintColor = UIColor.white.withAlphaComponent(0.25)
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.addSubview(placeholderIcon)

        placeholderLabel.font = .systemFont(ofSize: 12, weight: .medium)
        placeholderLabel.textColor = UIColor.white.withAlphaComponent(0.6)
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
            headerBar.heightAnchor.constraint(equalToConstant: 38),

            iconImageView.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 10),
            iconImageView.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 16),
            iconImageView.heightAnchor.constraint(equalToConstant: 16),

            closeButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
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
            iconImageView.tintColor = .white
        }

        // Active border (Chrome signature blue border)
        if isActive {
            containerView.layer.borderWidth = 3.0
            containerView.layer.borderColor = UIColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 1.0).cgColor
        } else {
            containerView.layer.borderWidth = 0.5
            containerView.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
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


