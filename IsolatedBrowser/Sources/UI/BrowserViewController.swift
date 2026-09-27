import UIKit
import WebKit

final class BrowserViewController: UIViewController {
    private let preferences = BrowserPreferences()
    private(set) var webView: WKWebView!
    private let addressBar = UIView()
    private let urlTextField = UITextField()
    private let reloadButton = UIButton(type: .system)
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let toolbar = UIToolbar()
    private let refreshControl = UIRefreshControl()
    private let errorView = UIScrollView()
    private let errorContent = UIStackView()
    private let errorMessage = UILabel()
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
    var restorationURL: URL? { BrowserSession.restorableURL(webView?.url ?? requestedURL ?? initialURL) }
    var onShowTabs: (() -> Void)?
    var onCreateWindow: ((WKWebViewConfiguration, WKContentRuleList) -> WKWebView?)?
    var onCloseWindow: (() -> Void)?
    private var tabsButton: UIBarButtonItem!
    var tabCount = 1 { didSet { updateTabCount() } }
    var tabTitle: String { webView?.title ?? title ?? "Новая вкладка" }
    var tabHost: String { (webView?.url ?? requestedURL ?? initialURL)?.host ?? "Новая вкладка" }

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
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
    }

    private func updateTabCount() {
        tabsButton?.title = "▣ \(tabCount)"
        tabsButton?.accessibilityLabel = "Вкладки: \(tabCount)"
    }

    @objc private func showTabs() { view.endEditing(true); onShowTabs?() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.tintColor = .systemBlue
        setupNavigationBar()
        setupAddressBar()
        setupWebView()
        setupToolbar()
        setupErrorView()
        setupLayout()
        observeWebView()
        if let url = initialURL { loadURL(url) }
    }

    private func setupNavigationBar() {
        title = "Браузер"
        navigationItem.largeTitleDisplayMode = .never
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Банки", style: .plain,
                                                           target: self, action: #selector(showBanks))
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Банки и стартовая страница"
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "browser.banks"
    }

    private func setupAddressBar() {
        addressBar.backgroundColor = .secondarySystemBackground
        addressBar.layer.cornerRadius = 14
        addressBar.layer.cornerCurve = .continuous
        let globe = UIImageView(image: UIImage(systemName: "globe"))
        globe.tintColor = .secondaryLabel
        globe.contentMode = .scaleAspectFit
        globe.isAccessibilityElement = false
        urlTextField.placeholder = "Сайт или поисковый запрос"
        urlTextField.font = .preferredFont(forTextStyle: .body)
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
        reloadButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        reloadButton.accessibilityLabel = "Обновить страницу"
        reloadButton.accessibilityIdentifier = "browser.reload"
        reloadButton.addTarget(self, action: #selector(reloadOrStop), for: .touchUpInside)
        for child in [globe, urlTextField, reloadButton] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addressBar.addSubview(child)
        }
        NSLayoutConstraint.activate([
            globe.leadingAnchor.constraint(equalTo: addressBar.leadingAnchor, constant: 14),
            globe.centerYAnchor.constraint(equalTo: addressBar.centerYAnchor),
            globe.widthAnchor.constraint(equalToConstant: 20), globe.heightAnchor.constraint(equalToConstant: 20),
            urlTextField.leadingAnchor.constraint(equalTo: globe.trailingAnchor, constant: 10),
            urlTextField.topAnchor.constraint(equalTo: addressBar.topAnchor, constant: 12),
            urlTextField.bottomAnchor.constraint(equalTo: addressBar.bottomAnchor, constant: -12),
            urlTextField.trailingAnchor.constraint(equalTo: reloadButton.leadingAnchor, constant: -2),
            reloadButton.trailingAnchor.constraint(equalTo: addressBar.trailingAnchor, constant: -2),
            reloadButton.centerYAnchor.constraint(equalTo: addressBar.centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 44), reloadButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        view.addSubview(addressBar)
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
        backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(goBack))
        forwardButton = UIBarButtonItem(image: UIImage(systemName: "chevron.right"), style: .plain, target: self, action: #selector(goForward))
        homeButton = UIBarButtonItem(image: UIImage(systemName: "house"), style: .plain, target: self, action: #selector(openDefaultBank))
        shareButton = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(sharePage))
        backButton.accessibilityLabel = "Назад"
        forwardButton.accessibilityLabel = "Вперёд"
        shareButton.accessibilityLabel = "Поделиться страницей"
        homeButton.accessibilityIdentifier = "browser.home"
        updateDefaultBankLabel()
        func space() -> UIBarButtonItem { UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil) }
        tabsButton = UIBarButtonItem(title: "", style: .plain, target: self, action: #selector(showTabs))
        tabsButton.accessibilityIdentifier = "browser.tabs"
        updateTabCount()
        toolbar.items = [backButton, space(), forwardButton, space(), homeButton, space(), shareButton, space(), tabsButton]
        let appearance = UIToolbarAppearance()
        appearance.configureWithDefaultBackground()
        toolbar.standardAppearance = appearance
        toolbar.scrollEdgeAppearance = appearance
        view.addSubview(toolbar)
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
        banks.setTitle("Выбрать другой банк", for: .normal)
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

    private func setupLayout() {
        [addressBar, progressView, webView!, toolbar, errorView].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            addressBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            addressBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            addressBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            addressBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            progressView.topAnchor.constraint(equalTo: addressBar.bottomAnchor, constant: 8),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),
            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 50),
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
        reloadButton.setImage(UIImage(systemName: webView.isLoading ? "xmark" : "arrow.clockwise"), for: .normal)
        reloadButton.accessibilityLabel = webView.isLoading ? "Остановить загрузку" : "Обновить страницу"
        if !webView.isLoading { refreshControl.endRefreshing() }
        if !urlTextField.isFirstResponder {
            let url = errorView.isHidden ? (webView.url ?? requestedURL) : requestedURL
            urlTextField.text = url?.host ?? url?.absoluteString
            title = Bank.matching(url)?.name ?? "Браузер"
        }
    }

    private func updateDefaultBankLabel() {
        homeButton.accessibilityLabel = "Открыть \(preferences.defaultBank.name) — банк по умолчанию"
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
            title = Bank.matching(url)?.name ?? "Браузер"
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
            errorMessage.text = "Не удалось подтвердить защищённое соединение с сайтом. Попробуйте позже или выберите другой банк."
        } else if error.code == NSURLErrorNotConnectedToInternet {
            errorMessage.text = "Проверьте подключение к интернету и попробуйте снова."
        } else {
            errorMessage.text = "\(requestedURL?.host ?? "Сайт") сейчас недоступен. Попробуйте загрузить страницу ещё раз."
        }
        updateControls()
    }
}

extension BrowserViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.text = (errorView.isHidden ? (webView.url ?? requestedURL) : requestedURL)?.absoluteString
        textField.selectAll(nil)
    }

    func textFieldDidEndEditing(_ textField: UITextField) { updateControls() }

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
