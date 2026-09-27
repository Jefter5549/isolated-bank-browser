import Foundation

/// Запрещает HTTP-переходы, включая редиректы, фреймы и всплывающие окна.
/// За HTTPS и смешанные сетевые ресурсы дополнительно отвечает стандартная ATS.
enum HTTPSNavigationPolicy {
    static func allows(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme else { return false }
        return scheme.lowercased() != "http"
    }
}
