import Foundation

enum BrowserAddress {
    static func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.lowercased().hasPrefix("https://") || text.lowercased().hasPrefix("http://") {
            guard let url = URL(string: text), let host = url.host, !host.isEmpty else { return nil }
            return url
        }
        if text.contains("://") { return nil }
        if text.contains("."), text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
           let url = URL(string: "https://" + text), let host = url.host, !host.isEmpty {
            return url
        }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return components.url
    }
}
