import Foundation

/// ATS exceptions enable app-local CA evaluation for known bank domains.
/// This rule blocks cleartext requests (including subresources) before networking.
/// Install it before the first load and fail closed if compilation fails.
enum SecureWebContent {
    static let ruleIdentifier = "bank-browser-block-cleartext-v1"
    static let rules = """
    [{"trigger":{"url-filter":"^http://","url-filter-is-case-sensitive":false},"action":{"type":"block"}},
     {"trigger":{"url-filter":"^ws://","url-filter-is-case-sensitive":false},"action":{"type":"block"}}]
    """
}
