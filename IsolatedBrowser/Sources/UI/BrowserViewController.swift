import UIKit
import WebKit
import Security

final class BrowserViewController: UIViewController {

    // MARK: - UI Elements
    private var webView: WKWebView!
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let urlTextField = UITextField()
    private let toolbar = UIToolbar()
    private let refreshControl = UIRefreshControl()

    private var backButton: UIBarButtonItem!
    private var forwardButton: UIBarButtonItem!
    private var reloadButton: UIBarButtonItem!
    private var bookmarksButton: UIBarButtonItem!
    private var shareButton: UIBarButtonItem!

    // MARK: - Bank Shortcuts
    private struct BankShortcut {
        let title: String
        let url: String
        let subtitle: String
    }

    private let shortcuts: [BankShortcut] = [
        BankShortcut(title: "🏦 Кредит Урал Банк (КУБ-Direct)", url: "https://direct.creditural.ru/", subtitle: "Прямой вход в КУБ"),
        BankShortcut(title: "🏦 ВТБ Онлайн", url: "https://online.vtb.ru", subtitle: "Основной домен ВТБ"),
        BankShortcut(title: "🏦 СберБанк Онлайн", url: "https://online.sberbank.ru", subtitle: "Сбер веб-клиент"),
        BankShortcut(title: "🏦 Газпромбанк", url: "https://online.gpb.ru", subtitle: "ГПБ Онлайн"),
        BankShortcut(title: "🏦 Альфа-Онлайн", url: "https://web.alfabank.ru", subtitle: "Альфа-Банк"),
        BankShortcut(title: "🏦 Т-Банк", url: "https://www.tbank.ru", subtitle: "Личный кабинет"),
        BankShortcut(title: "🏛 Госуслуги", url: "https://gosuslugi.ru", subtitle: "Портал Госуслуг")
    ]

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        setupNavigationBar()
        setupWebView()
        setupProgressView()
        setupToolbar()
        setupLayout()

        // Загружаем стартовую страницу (КУБ-Direct)
        if let initialUrl = URL(string: "https://direct.creditural.ru/") {
            loadURL(initialUrl)
        }
    }

    // MARK: - Setup UI
    private func setupNavigationBar() {
        navigationItem.titleView = urlTextField
        urlTextField.borderStyle = .roundedRect
        urlTextField.placeholder = "Введите URL или выберите банк..."
        urlTextField.keyboardType = .URL
        urlTextField.autocapitalizationType = .none
        urlTextField.autocorrectionType = .no
        urlTextField.clearButtonMode = .whileEditing
        urlTextField.returnKeyType = .go
        urlTextField.delegate = self
        urlTextField.backgroundColor = .secondarySystemBackground
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let defaultUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        config.applicationNameForUserAgent = "Version/17.5 Mobile/15E148 Safari/604.1"

        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = defaultUA
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false

        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        webView.scrollView.addSubview(refreshControl)

        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.url), options: .new, context: nil)

        view.addSubview(webView)
    }

    private func setupProgressView() {
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.tintColor = .systemBlue
        view.addSubview(progressView)
    }

    private func setupToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(goBack))
        forwardButton = UIBarButtonItem(image: UIImage(systemName: "chevron.right"), style: .plain, target: self, action: #selector(goForward))
        let space = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        bookmarksButton = UIBarButtonItem(image: UIImage(systemName: "building.columns"), style: .plain, target: self, action: #selector(showBookmarks))
        shareButton = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(sharePage))
        reloadButton = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(reloadPage))

        backButton.isEnabled = false
        forwardButton.isEnabled = false

        toolbar.items = [backButton, space, forwardButton, space, bookmarksButton, space, shareButton, space, reloadButton]
        view.addSubview(toolbar)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),

            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    // MARK: - Actions
    @objc private func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    @objc private func goForward() {
        if webView.canGoForward { webView.goForward() }
    }

    @objc private func reloadPage() {
        webView.reload()
    }

    @objc private func handleRefresh() {
        webView.reload()
        refreshControl.endRefreshing()
    }

    @objc private func sharePage() {
        guard let url = webView.url else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(activityVC, animated: true)
    }

    @objc private func showBookmarks() {
        let alert = UIAlertController(title: "Быстрый переход", message: "Основные банковские сервисы:", preferredStyle: .actionSheet)

        for bank in shortcuts {
            alert.addAction(UIAlertAction(title: bank.title, style: .default, handler: { [weak self] _ in
                if let url = URL(string: bank.url) {
                    self?.loadURL(url)
                }
            }))
        }

        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = bookmarksButton
        }

        present(alert, animated: true)
    }

    private func loadURL(_ url: URL) {
        urlTextField.text = url.absoluteString
        let request = URLRequest(url: url)
        webView.load(request)
    }

    // MARK: - KVO Observers
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(WKWebView.estimatedProgress) {
            progressView.progress = Float(webView.estimatedProgress)
            progressView.isHidden = webView.estimatedProgress >= 1.0
        } else if keyPath == #keyPath(WKWebView.canGoBack) {
            backButton.isEnabled = webView.canGoBack
        } else if keyPath == #keyPath(WKWebView.canGoForward) {
            forwardButton.isEnabled = webView.canGoForward
        } else if keyPath == #keyPath(WKWebView.url) {
            if let currentURL = webView.url {
                urlTextField.text = currentURL.absoluteString
            }
        }
    }

    deinit {
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack))
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward))
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
    }
}

// MARK: - UITextFieldDelegate
extension BrowserViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        guard var text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return true
        }

        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            if text.contains(".") && !text.contains(" ") {
                text = "https://" + text
            } else {
                let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
                text = "https://www.google.com/search?q=\(query)"
            }
        }

        if let url = URL(string: text) {
            loadURL(url)
        }
        return true
    }
}

// MARK: - WKNavigationDelegate (TLS Interception)
extension BrowserViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, 
                 didReceive challenge: URLAuthenticationChallenge, 
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        if CustomTrustManager.shared.evaluate(serverTrust: serverTrust, host: host) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progressView.isHidden = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        progressView.isHidden = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        progressView.isHidden = true
        let nsError = error as NSError
        // Игнорируем штатные отмены переходов
        if nsError.code != NSURLErrorCancelled {
            let alert = UIAlertController(title: "Ошибка подключения", message: nsError.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Повторить", style: .default, handler: { [weak self] _ in self?.webView.reload() }))
            alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
            present(alert, animated: true)
        }
    }
}

// MARK: - WKUIDelegate (Camera & Alerts Support)
extension BrowserViewController: WKUIDelegate {

    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, 
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin, 
                 initiatedByFrame frame: WKFrameInfo, 
                 type: WKMediaCaptureType, 
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    func webView(_ webView: WKWebView, 
                 createWebViewWith configuration: WKWebViewConfiguration, 
                 for navigationAction: WKNavigationAction, 
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, 
                 runJavaScriptAlertPanelWithMessage message: String, 
                 initiatedByFrame frame: WKFrameInfo, 
                 completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completionHandler() }))
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, 
                 runJavaScriptConfirmPanelWithMessage message: String, 
                 initiatedByFrame frame: WKFrameInfo, 
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: { _ in completionHandler(false) }))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completionHandler(true) }))
        present(alert, animated: true)
    }
}
