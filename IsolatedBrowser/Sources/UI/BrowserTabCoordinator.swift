import UIKit
import WebKit

/// Retains each page, including history and forms, until explicitly closed.
final class BrowserTabCoordinator {
    let navigationController = UINavigationController()
    private var tabs: [BrowserViewController] = []
    private weak var picker: BrowserTabsViewController?

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
        picker?.tableView.reloadData()
    }

    private func showTabs() {
        guard navigationController.presentedViewController == nil else { return }
        let controller = BrowserTabsViewController(style: .insetGrouped)
        controller.rows = { [weak self] in self?.tabs ?? [] }
        controller.isSelected = { [weak self] in self?.navigationController.topViewController === $0 }
        controller.onSelect = { [weak self, weak controller] browser in
            controller?.dismiss(animated: true) { self?.select(browser) }
        }
        controller.onClose = { [weak self] in self?.close($0) }
        controller.onNew = { [weak self, weak controller] in
            controller?.dismiss(animated: true) { _ = self?.addTab() }
        }
        picker = controller
        let sheet = UINavigationController(rootViewController: controller)
        sheet.modalPresentationStyle = .pageSheet
        sheet.sheetPresentationController?.detents = [.large()]
        sheet.sheetPresentationController?.prefersGrabberVisible = true
        navigationController.present(sheet, animated: true)
    }
}

private final class BrowserTabsViewController: UITableViewController {
    var rows: () -> [BrowserViewController] = { [] }
    var isSelected: (BrowserViewController) -> Bool = { _ in false }
    var onSelect: ((BrowserViewController) -> Void)?
    var onClose: ((BrowserViewController) -> Void)?
    var onNew: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Вкладки"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(newTab))
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Новая вкладка"
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
    }

    @objc private func done() { dismiss(animated: true) }
    @objc private func newTab() { onNew?() }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows().count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let browser = rows()[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.text = browser.tabTitle
        content.secondaryText = browser.tabHost
        content.image = UIImage(systemName: isSelected(browser) ? "checkmark.circle.fill" : "globe")
        content.textProperties.numberOfLines = 2
        cell.contentConfiguration = content
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        close.accessibilityLabel = "Закрыть вкладку \(browser.tabTitle)"
        close.addAction(UIAction { [weak self, weak browser] _ in
            if let browser = browser { self?.onClose?(browser) }
        }, for: .touchUpInside)
        cell.accessoryView = close
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { onSelect?(rows()[indexPath.row]) }
}
