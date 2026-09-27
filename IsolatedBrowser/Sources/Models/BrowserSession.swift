import Foundation

/// Stores addresses only. Cookies and website storage remain managed by WebKit.
struct BrowserSession: Codable {
    var urls: [URL?]
    var selectedIndex: Int

    static func restorableURL(_ url: URL?) -> URL? {
        guard let url = url, url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}

final class BrowserSessionStore {
    private let defaults: UserDefaults
    private let key = "browser.tabs.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> BrowserSession? {
        guard let data = defaults.data(forKey: key),
              var session = try? JSONDecoder().decode(BrowserSession.self, from: data),
              !session.urls.isEmpty else { return nil }
        session.urls = Array(session.urls.prefix(12)).map(BrowserSession.restorableURL)
        session.selectedIndex = min(max(0, session.selectedIndex), session.urls.count - 1)
        return session
    }

    func save(_ session: BrowserSession) {
        let sanitized = BrowserSession(urls: Array(session.urls.prefix(12)).map(BrowserSession.restorableURL),
                                       selectedIndex: session.selectedIndex)
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        defaults.set(data, forKey: key)
    }
}
