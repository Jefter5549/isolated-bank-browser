import UIKit
import WebKit

private enum ChromeTheme {
    static let barBackground = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.125, green: 0.129, blue: 0.141, alpha: 1.0)
            : UIColor(red: 0.945, green: 0.949, blue: 0.957, alpha: 1.0)
    }

    static let capsuleBackground = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.176, green: 0.180, blue: 0.192, alpha: 1.0)
            : UIColor.white
    }

    static let separator = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.235, green: 0.251, blue: 0.263, alpha: 1.0)
            : UIColor(red: 0.855, green: 0.863, blue: 0.878, alpha: 1.0)
    }
}

final class BrowserViewController: UIViewController {
    private let preferences = BrowserPreferences()
    private(set) var webView: WKWebView!
    private let topBarView = UIView()
    private let addressBar = UIView()
    private let servicesButton = UIButton(type: .system)
    private let urlTextField = UITextField()
    private let reloadButton = UIButton(type: .system)
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let bottomBarContainer = UIView()
    private let toolbar = UIToolbar()
    private var webViewBottomConstraint: NSLayoutConstraint!
    private let refreshControl = UIRefreshControl()
    private let errorView = UIScrollView()
    private let errorContent = UIStackView()
    private let errorMessage = UILabel()
    private let vpnOverlay = UIView()
    private let vpnModalCard = UIView()
    private let vpnSettingsButton = UIButton(type: .system)
    private let vpnDismissButton = UIButton(type: .system)
    private static var didPerformStartupVPNCheck = false
    private var pendingLaunchURL: URL?
    private var backButton: UIBarButtonItem!
    private var forwardButton: UIBarButtonItem!
    private var homeButton: UIBarButtonItem!
    private var shareButton: UIBarButtonItem!
    private var observations: [NSKeyValueObservation] = []
    private var requestedURL: URL?
    private var activeNavigation: WKNavigation?
    private var contentReady = false
    private var preparingContent = false
    private var isClosed = false

    private let initialURL: URL?
    private let suppliedConfiguration: WKWebViewConfiguration?
    private var secureRules: WKContentRuleList?
    weak var opener: BrowserViewController?
    var onAddressChanged: (() -> Void)?
    var restorationURL: URL? {
        let url = isViewLoaded && !errorView.isHidden
            ? requestedURL
            : (webView?.url ?? requestedURL ?? initialURL)
        return BrowserSession.restorableURL(url)
    }
    var onShowTabs: (() -> Void)?
    var onCreateWindow: ((WKWebViewConfiguration, WKContentRuleList) -> WKWebView?)?
    var onCloseWindow: (() -> Void)?
    private var tabsButton: UIBarButtonItem!
    var tabCount = 1 { didSet { updateTabCount() } }
    var tabTitle: String { webView?.title ?? title ?? "Новая вкладка" }
    var tabHost: String { (webView?.url ?? requestedURL ?? initialURL)?.host ?? "Новая вкладка" }
    var currentSnapshot: UIImage?

    func captureSnapshot(completion: @escaping (UIImage?) -> Void) {
        guard isViewLoaded, let webView = webView, webView.bounds.width > 0, webView.bounds.height > 0 else {
            completion(currentSnapshot)
            return
        }
        let config = WKSnapshotConfiguration()
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            if let image = image {
                self?.currentSnapshot = image
            }
            completion(self?.currentSnapshot)
        }
    }

    init(initialURL: URL? = BrowserPreferences().defaultBank.url,
         configuration: WKWebViewConfiguration? = nil, rules: WKContentRuleList? = nil) {
        self.initialURL = initialURL
        self.suppliedConfiguration = configuration
        self.secureRules = rules
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(initialURL:)") }

    func closeTab() {
        isClosed = true
        observations.removeAll()
        NotificationCenter.default.removeObserver(self, name: .vpnStatusDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func makeTabsIcon(count: Int) -> UIImage {
        let size = CGSize(width: 22, height: 22)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 4.5)
            path.lineWidth = 1.8
            UIColor.label.setStroke()
            path.stroke()

            let text = "\(min(count, 99))"
            let fontSize: CGFloat = count > 9 ? 10 : 11
            let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.label
            ]
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }.withRenderingMode(.alwaysOriginal)
    }

    private func updateTabCount() {
        tabsButton?.image = makeTabsIcon(count: tabCount)
        tabsButton?.accessibilityLabel = "Вкладки: \(tabCount)"
    }

    @objc private func showTabs() { view.endEditing(true); onShowTabs?() }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ChromeTheme.barBackground
        view.tintColor = .label
        setupNavigationBar()
        setupAddressBar()
        setupWebView()
        setupToolbar()
        setupErrorView()
        setupVPNOverlay()
        setupLayout()
        observeWebView()
        NotificationCenter.default.addObserver(self, selector: #selector(handleVPNChange),
                                               name: .vpnStatusDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleVPNChange),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow),
                                               name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
        if let url = initialURL {
            handleInitialLaunch(url: url)
        }
    }

    private func setupNavigationBar() {
        navigationController?.setNavigationBarHidden(true, animated: false)
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сервисы", style: .plain,
                                                           target: self, action: #selector(showBanks))
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Сервисы и стартовая страница"
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "browser.banks"
    }

    private func setupAddressBar() {
        topBarView.backgroundColor = ChromeTheme.barBackground

        let topBarBottomBorder = UIView()
        topBarBottomBorder.backgroundColor = ChromeTheme.separator
        topBarBottomBorder.translatesAutoresizingMaskIntoConstraints = false
        topBarView.addSubview(topBarBottomBorder)

        addressBar.backgroundColor = ChromeTheme.capsuleBackground
        addressBar.layer.cornerRadius = 20
        addressBar.layer.cornerCurve = .continuous

        let servicesConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        servicesButton.setImage(UIImage(systemName: "square.grid.2x2.fill", withConfiguration: servicesConfig), for: .normal)
        servicesButton.tintColor = .label
        servicesButton.accessibilityLabel = "Сервисы и стартовая страница"
        servicesButton.accessibilityIdentifier = "browser.banks"
        servicesButton.addTarget(self, action: #selector(showBanks), for: .touchUpInside)

        urlTextField.placeholder = "Сайт или поисковый запрос"
        urlTextField.font = .systemFont(ofSize: 15, weight: .regular)
        urlTextField.textColor = .label
        urlTextField.textAlignment = .center
        urlTextField.adjustsFontForContentSizeCategory = true
        urlTextField.keyboardType = .webSearch
        urlTextField.autocapitalizationType = .none
        urlTextField.autocorrectionType = .no
        urlTextField.smartQuotesType = .no
        urlTextField.smartDashesType = .no
        urlTextField.clearButtonMode = .whileEditing
        urlTextField.returnKeyType = .go
        urlTextField.delegate = self
        urlTextField.accessibilityLabel = "Адрес сайта или поиск"
        urlTextField.accessibilityIdentifier = "browser.address"

        let reloadConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        reloadButton.setImage(UIImage(systemName: "arrow.clockwise", withConfiguration: reloadConfig), for: .normal)
        reloadButton.tintColor = .secondaryLabel
        reloadButton.accessibilityLabel = "Обновить страницу"
        reloadButton.accessibilityIdentifier = "browser.reload"
        reloadButton.addTarget(self, action: #selector(reloadOrStop), for: .touchUpInside)

        for child in [servicesButton, urlTextField, reloadButton] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addressBar.addSubview(child)
        }
        NSLayoutConstraint.activate([
            servicesButton.leadingAnchor.constraint(equalTo: addressBar.leadingAnchor, constant: 6),
            servicesButton.centerYAnchor.constraint(equalTo: addressBar.centerYAnchor),
            servicesButton.widthAnchor.constraint(equalToConstant: 32),
            servicesButton.heightAnchor.constraint(equalToConstant: 32),

            urlTextField.leadingAnchor.constraint(equalTo: servicesButton.trailingAnchor, constant: 4),
            urlTextField.topAnchor.constraint(equalTo: addressBar.topAnchor, constant: 4),
            urlTextField.bottomAnchor.constraint(equalTo: addressBar.bottomAnchor, constant: -4),
            urlTextField.trailingAnchor.constraint(equalTo: reloadButton.leadingAnchor, constant: -4),

            reloadButton.trailingAnchor.constraint(equalTo: addressBar.trailingAnchor, constant: -6),
            reloadButton.centerYAnchor.constraint(equalTo: addressBar.centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 30),
            reloadButton.heightAnchor.constraint(equalToConstant: 30)
        ])

        addressBar.translatesAutoresizingMaskIntoConstraints = false
        topBarView.addSubview(addressBar)
        NSLayoutConstraint.activate([
            addressBar.leadingAnchor.constraint(equalTo: topBarView.leadingAnchor, constant: 14),
            addressBar.trailingAnchor.constraint(equalTo: topBarView.trailingAnchor, constant: -14),
            addressBar.heightAnchor.constraint(equalToConstant: 40),
            addressBar.bottomAnchor.constraint(equalTo: topBarView.bottomAnchor, constant: -7),

            topBarBottomBorder.leadingAnchor.constraint(equalTo: topBarView.leadingAnchor),
            topBarBottomBorder.trailingAnchor.constraint(equalTo: topBarView.trailingAnchor),
            topBarBottomBorder.bottomAnchor.constraint(equalTo: topBarView.bottomAnchor),
            topBarBottomBorder.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        view.addSubview(topBarView)
        progressView.isHidden = true
        view.addSubview(progressView)
    }

    private func setupWebView() {
        let config = suppliedConfiguration ?? WKWebViewConfiguration()
        if suppliedConfiguration == nil { config.websiteDataStore = .default() }
        if let rules = secureRules {
            config.userContentController.add(rules)
            contentReady = true
        }
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // Сохраняем совместимость существующего банковского клиента.
        config.applicationNameForUserAgent = "Version/17.5 Mobile/15E148 Safari/604.1"
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .onDrag
        refreshControl.addTarget(self, action: #selector(refreshPage), for: .valueChanged)
        webView.scrollView.addSubview(refreshControl)
        view.addSubview(webView)
    }

    private func setupToolbar() {
        backButton = UIBarButtonItem(image: UIImage(systemName: "arrow.left"), style: .plain, target: self, action: #selector(goBack))
        forwardButton = UIBarButtonItem(image: UIImage(systemName: "arrow.right"), style: .plain, target: self, action: #selector(goForward))
        homeButton = UIBarButtonItem(image: UIImage(systemName: "house"), style: .plain, target: self, action: #selector(openDefaultBank))
        shareButton = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(sharePage))
        backButton.accessibilityLabel = "Назад"
        forwardButton.accessibilityLabel = "Вперёд"
        shareButton.accessibilityLabel = "Поделиться страницей"
        homeButton.accessibilityIdentifier = "browser.home"
        updateDefaultBankLabel()

        func flexSpace() -> UIBarButtonItem { UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil) }

        tabsButton = UIBarButtonItem(image: makeTabsIcon(count: tabCount), style: .plain, target: self, action: #selector(showTabs))
        tabsButton.accessibilityIdentifier = "browser.tabs"
        tabsButton.accessibilityLabel = "Вкладки: \(tabCount)"

        toolbar.items = [backButton, flexSpace(), forwardButton, flexSpace(), homeButton, flexSpace(), shareButton, flexSpace(), tabsButton]

        toolbar.backgroundColor = .clear
        toolbar.barTintColor = ChromeTheme.barBackground
        toolbar.tintColor = .label
        toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
        toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)

        bottomBarContainer.backgroundColor = ChromeTheme.barBackground

        let topBorder = UIView()
        topBorder.backgroundColor = ChromeTheme.separator
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        bottomBarContainer.addSubview(topBorder)

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        bottomBarContainer.addSubview(toolbar)

        NSLayoutConstraint.activate([
            topBorder.leadingAnchor.constraint(equalTo: bottomBarContainer.leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: bottomBarContainer.trailingAnchor),
            topBorder.topAnchor.constraint(equalTo: bottomBarContainer.topAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 0.5),

            toolbar.leadingAnchor.constraint(equalTo: bottomBarContainer.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: bottomBarContainer.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: bottomBarContainer.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44)
        ])

        view.addSubview(bottomBarContainer)
    }

    private func setupErrorView() {
        errorContent.axis = .vertical
        errorContent.alignment = .center
        errorContent.spacing = 16
        errorView.isHidden = true
        let icon = UIImageView(image: UIImage(systemName: "wifi.exclamationmark"))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let title = UILabel()
        title.text = "Не удалось открыть страницу"
        title.font = .preferredFont(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center
        title.numberOfLines = 0
        errorMessage.font = .preferredFont(forTextStyle: .body)
        errorMessage.adjustsFontForContentSizeCategory = true
        errorMessage.textColor = .secondaryLabel
        errorMessage.textAlignment = .center
        errorMessage.numberOfLines = 0
        let retry = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Повторить"
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        retry.configuration = configuration
        retry.addTarget(self, action: #selector(retryPage), for: .touchUpInside)
        let banks = UIButton(type: .system)
        banks.setTitle("Выбрать другой сервис", for: .normal)
        banks.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        banks.addTarget(self, action: #selector(showBanks), for: .touchUpInside)
        [icon, title, errorMessage, retry, banks].forEach(errorContent.addArrangedSubview)
        let canvas = UIView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        errorContent.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(canvas)
        canvas.addSubview(errorContent)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: errorView.contentLayoutGuide.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: errorView.contentLayoutGuide.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: errorView.contentLayoutGuide.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: errorView.contentLayoutGuide.bottomAnchor),
            canvas.widthAnchor.constraint(equalTo: errorView.frameLayoutGuide.widthAnchor),
            canvas.heightAnchor.constraint(greaterThanOrEqualTo: errorView.frameLayoutGuide.heightAnchor),
            errorContent.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            errorContent.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            errorContent.leadingAnchor.constraint(greaterThanOrEqualTo: canvas.leadingAnchor, constant: 24),
            errorContent.trailingAnchor.constraint(lessThanOrEqualTo: canvas.trailingAnchor, constant: -24),
            errorContent.topAnchor.constraint(greaterThanOrEqualTo: canvas.topAnchor, constant: 24),
            errorContent.bottomAnchor.constraint(lessThanOrEqualTo: canvas.bottomAnchor, constant: -24),
            errorContent.widthAnchor.constraint(lessThanOrEqualToConstant: 440)
        ])
        view.addSubview(errorView)
    }

    private func setupVPNOverlay() {
        vpnOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        vpnOverlay.isHidden = true
        vpnOverlay.translatesAutoresizingMaskIntoConstraints = false

        vpnModalCard.backgroundColor = .secondarySystemBackground
        vpnModalCard.layer.cornerRadius = 18
        vpnModalCard.layer.cornerCurve = .continuous
        vpnModalCard.layer.shadowColor = UIColor.black.cgColor
        vpnModalCard.layer.shadowOpacity = 0.15
        vpnModalCard.layer.shadowOffset = CGSize(width: 0, height: 8)
        vpnModalCard.layer.shadowRadius = 16
        vpnModalCard.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "network.badge.shield.half.filled") ?? UIImage(systemName: "exclamationmark.triangle.fill"))
        icon.tintColor = .systemOrange
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "Включён VPN"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        let descLabel = UILabel()
        descLabel.text = "Обнаружено активное VPN-соединение. Для корректной работы с сервисами отключите VPN в Настройках iOS или через Пункт управления."
        descLabel.font = .preferredFont(forTextStyle: .subheadline)
        descLabel.textColor = .secondaryLabel
        descLabel.textAlignment = .center
        descLabel.adjustsFontForContentSizeCategory = true
        descLabel.numberOfLines = 0

        var settingsConfig = UIButton.Configuration.filled()
        settingsConfig.title = "Настройки iOS"
        settingsConfig.cornerStyle = .capsule
        settingsConfig.buttonSize = .medium
        vpnSettingsButton.configuration = settingsConfig
        vpnSettingsButton.tintColor = .systemBlue
        vpnSettingsButton.accessibilityLabel = "Открыть системные настройки iOS"
        vpnSettingsButton.accessibilityIdentifier = "browser.vpnSettings"
        vpnSettingsButton.addTarget(self, action: #selector(openVPNSettings), for: .touchUpInside)

        var dismissConfig = UIButton.Configuration.gray()
        dismissConfig.title = "Продолжить"
        dismissConfig.cornerStyle = .capsule
        dismissConfig.buttonSize = .medium
        vpnDismissButton.configuration = dismissConfig
        vpnDismissButton.accessibilityLabel = "Продолжить работу и загрузить страницу"
        vpnDismissButton.accessibilityIdentifier = "browser.vpnDismiss"
        vpnDismissButton.addTarget(self, action: #selector(dismissVPNOverlay), for: .touchUpInside)

        let buttonsStack = UIStackView(arrangedSubviews: [vpnSettingsButton, vpnDismissButton])
        buttonsStack.axis = .vertical
        buttonsStack.spacing = 10
        buttonsStack.distribution = .fillEqually

        let contentStack = UIStackView(arrangedSubviews: [icon, titleLabel, descLabel, buttonsStack])
        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        vpnModalCard.addSubview(contentStack)
        vpnOverlay.addSubview(vpnModalCard)
        view.addSubview(vpnOverlay)

        NSLayoutConstraint.activate([
            icon.heightAnchor.constraint(equalToConstant: 44),
            vpnSettingsButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            vpnDismissButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            contentStack.leadingAnchor.constraint(equalTo: vpnModalCard.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: vpnModalCard.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: vpnModalCard.topAnchor, constant: 22),
            contentStack.bottomAnchor.constraint(equalTo: vpnModalCard.bottomAnchor, constant: -20),

            vpnModalCard.centerXAnchor.constraint(equalTo: vpnOverlay.centerXAnchor),
            vpnModalCard.centerYAnchor.constraint(equalTo: vpnOverlay.centerYAnchor),
            vpnModalCard.leadingAnchor.constraint(greaterThanOrEqualTo: vpnOverlay.leadingAnchor, constant: 32),
            vpnModalCard.trailingAnchor.constraint(lessThanOrEqualTo: vpnOverlay.trailingAnchor, constant: -32),
            vpnModalCard.widthAnchor.constraint(lessThanOrEqualToConstant: 380),

            vpnOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            vpnOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vpnOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            vpnOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupLayout() {
        [topBarView, progressView, webView!, bottomBarContainer, errorView].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        webViewBottomConstraint = webView.bottomAnchor.constraint(equalTo: bottomBarContainer.topAnchor)

        NSLayoutConstraint.activate([
            topBarView.topAnchor.constraint(equalTo: view.topAnchor),
            topBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            addressBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 5),

            progressView.topAnchor.constraint(equalTo: topBarView.bottomAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webViewBottomConstraint,

            bottomBarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBarContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -44),
            bottomBarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorView.topAnchor.constraint(equalTo: webView.topAnchor),
            errorView.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])
    }

    private func observeWebView() {
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in self?.updateControls() },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in self?.updateControls() },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.updateControls() },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.updateControls() },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                self?.updateControls()
                self?.onAddressChanged?()
            }
        ]
        updateControls()
    }

    private func updateControls() {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
        shareButton.isEnabled = webView.url != nil && errorView.isHidden
        progressView.progress = Float(webView.estimatedProgress)
        progressView.isHidden = !webView.isLoading || !errorView.isHidden
        let reloadConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        reloadButton.setImage(UIImage(systemName: webView.isLoading ? "xmark" : "arrow.clockwise", withConfiguration: reloadConfig), for: .normal)
        reloadButton.accessibilityLabel = webView.isLoading ? "Остановить загрузку" : "Обновить страницу"
        if !webView.isLoading { refreshControl.endRefreshing() }
        if !urlTextField.isFirstResponder {
            let url = errorView.isHidden ? (webView.url ?? requestedURL) : requestedURL
            urlTextField.text = url?.host ?? url?.absoluteString
            urlTextField.textAlignment = .center
            title = Bank.matching(url, in: preferences.services)?.name ?? "Браузер"
        }
    }

    private func updateDefaultBankLabel() {
        homeButton.accessibilityLabel = "Открыть \(preferences.defaultBank.name) — стартовый сервис"
    }

    @objc private func showBanks() {
        view.endEditing(true)
        let picker = BankPickerViewController(preferences: preferences, onOpen: { [weak self] bank in
            self?.loadURL(bank.url)
        }, onDefaultChanged: { [weak self] in self?.updateDefaultBankLabel() })
        let navigation = UINavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.detents = [.large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        present(navigation, animated: true)
    }

    private func loadURL(_ url: URL) {
        guard HTTPSNavigationPolicy.allows(url) else { showHTTPWarning(); return }
        requestedURL = url
        errorView.isHidden = true
        webView.isHidden = false
        urlTextField.text = url.host ?? url.absoluteString
        guard contentReady else {
            title = Bank.matching(url, in: preferences.services)?.name ?? "Браузер"
            prepareSecureContent()
            return
        }
        activeNavigation = webView.load(URLRequest(url: url))
        updateControls()
    }

    private func prepareSecureContent() {
        guard !preparingContent else { return }
        preparingContent = true
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: SecureWebContent.ruleIdentifier,
            encodedContentRuleList: SecureWebContent.rules
        ) { [weak self] ruleList, error in
            guard let self = self, !self.isClosed else { return }
            self.preparingContent = false
            guard error == nil, let ruleList = ruleList else {
                self.webView.isHidden = true
                self.errorView.isHidden = false
                self.errorMessage.text = "Не удалось безопасно открыть сайт. Попробуйте ещё раз или перезапустите приложение."
                self.updateControls()
                return
            }
            self.webView.configuration.userContentController.add(ruleList)
            self.secureRules = ruleList
            self.contentReady = true
            if let url = self.requestedURL { self.loadURL(url) }
        }
    }

    @objc private func openDefaultBank() { view.endEditing(true); loadURL(preferences.defaultBank.url) }
    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }
    @objc private func refreshPage() { webView.reload() }
    @objc private func retryPage() { if let url = requestedURL { loadURL(url) } }
    @objc private func reloadOrStop() {
        if webView.isLoading { webView.stopLoading() }
        else if !errorView.isHidden || !contentReady { retryPage() }
        else { webView.reload() }
    }

    @objc private func sharePage() {
        guard let url = webView.url else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = shareButton
        present(activity, animated: true)
    }

    private func showHTTPWarning() {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Нужен защищённый адрес", message: "Соединения по HTTP заблокированы. Используйте адрес, начинающийся с https://.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Понятно", style: .default))
        present(alert, animated: true)
    }

    private func showFailure(_ error: Error, navigation: WKNavigation?) {
        let error = error as NSError
        guard error.code != NSURLErrorCancelled,
              activeNavigation == nil || navigation === activeNavigation else { return }
        if let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL { requestedURL = url }
        refreshControl.endRefreshing()
        progressView.isHidden = true
        webView.isHidden = true
        errorView.isHidden = false
        if [-1200, -1201, -1202, -1203, -1204, -1205, -1206].contains(error.code) {
            errorMessage.text = "Не удалось подтвердить защищённое соединение с сайтом. Попробуйте позже или выберите другой сервис."
        } else if error.code == NSURLErrorNotConnectedToInternet {
            errorMessage.text = "Проверьте подключение к интернету и попробуйте снова."
        } else {
            errorMessage.text = "\(requestedURL?.host ?? "Сайт") сейчас недоступен. Попробуйте загрузить страницу ещё раз."
        }
        updateControls()
        onAddressChanged?()
    }

    /// Обрабатывает запуск приложения: проверяет VPN один раз при старте.
    /// Если VPN активен и опция включена, блокирует загрузку страницы до действия пользователя.
    private func handleInitialLaunch(url: URL) {
        if !Self.didPerformStartupVPNCheck {
            Self.didPerformStartupVPNCheck = true
            if preferences.warnOnVPN && VPNMonitor.shared.isVPNActive {
                pendingLaunchURL = url
                urlTextField.text = url.host ?? url.absoluteString
                title = Bank.matching(url, in: preferences.services)?.name ?? "Браузер"
                setVPNOverlayVisible(true)
                return
            }
        }
        loadURL(url)
    }

    private func setVPNOverlayVisible(_ visible: Bool) {
        guard vpnOverlay.isHidden == visible else { return }
        if visible {
            vpnOverlay.alpha = 0
            vpnOverlay.isHidden = false
            view.bringSubviewToFront(vpnOverlay)
            UIView.animate(withDuration: 0.25) {
                self.vpnOverlay.alpha = 1
            }
        } else {
            UIView.animate(withDuration: 0.2, animations: {
                self.vpnOverlay.alpha = 0
            }) { _ in
                self.vpnOverlay.isHidden = true
            }
        }
    }

    @objc private func openVPNSettings() {
        VPNMonitor.openVPNSettings()
    }

    @objc private func dismissVPNOverlay() {
        setVPNOverlayVisible(false)
        if let url = pendingLaunchURL {
            pendingLaunchURL = nil
            loadURL(url)
        }
    }

    @objc private func handleVPNChange() {
        // Если при смене сети или возвращении из Настроек VPN отключился
        if !vpnOverlay.isHidden && !VPNMonitor.shared.isVPNActive {
            dismissVPNOverlay()
        }
    }

    @objc private func keyboardWillShow(notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveInt = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        let options = UIView.AnimationOptions(rawValue: curveInt << 16)

        UIView.animate(withDuration: duration, delay: 0, options: options, animations: {
            self.bottomBarContainer.alpha = 0
        }) { _ in
            if self.bottomBarContainer.alpha == 0 {
                self.bottomBarContainer.isHidden = true
            }
        }
    }

    @objc private func keyboardWillHide(notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveInt = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        let options = UIView.AnimationOptions(rawValue: curveInt << 16)

        self.bottomBarContainer.isHidden = false
        UIView.animate(withDuration: duration, delay: 0, options: options, animations: {
            self.bottomBarContainer.alpha = 1
        })
    }
}

extension BrowserViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.textAlignment = .left
        textField.text = (errorView.isHidden ? (webView.url ?? requestedURL) : requestedURL)?.absoluteString
        textField.selectAll(nil)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.textAlignment = .center
        updateControls()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let input = textField.text ?? ""
        guard let url = BrowserAddress.resolve(input) else { return false }
        textField.resignFirstResponder()
        loadURL(url)
        return true
    }
}

extension BrowserViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        CustomTrustManager.shared.handle(challenge, completionHandler: completionHandler)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = contentReady && HTTPSNavigationPolicy.allows(navigationAction.request.url)
        decisionHandler(allowed ? .allow : .cancel)
        if !allowed && navigationAction.targetFrame?.isMainFrame != false { showHTTPWarning() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(contentReady && HTTPSNavigationPolicy.allows(navigationResponse.response.url) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activeNavigation = navigation
        if let url = webView.url { requestedURL = url }
        errorView.isHidden = true
        webView.isHidden = false
        updateControls()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation else { return }
        refreshControl.endRefreshing()
        updateControls()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showFailure(error, navigation: navigation)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showFailure(error, navigation: navigation)
    }
}

extension BrowserViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, contentReady, let rules = secureRules else { return nil }
        guard HTTPSNavigationPolicy.allows(navigationAction.request.url) else { showHTTPWarning(); return nil }
        // Return WebKit's supplied configuration to preserve POST data and window.opener.
        return onCreateWindow?(configuration, rules)
    }

    func webViewDidClose(_ webView: WKWebView) {
        if suppliedConfiguration != nil { onCloseWindow?() }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard viewIfLoaded?.window != nil, presentedViewController == nil else { completionHandler(); return }
        let alert = UIAlertController(title: webView.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard viewIfLoaded?.window != nil, presentedViewController == nil else { completionHandler(false); return }
        let alert = UIAlertController(title: webView.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }
}
