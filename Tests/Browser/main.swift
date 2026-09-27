import Foundation

var failures = 0
var count = 0
func check(_ name: String, _ condition: Bool) {
    count += 1
    if !condition { failures += 1 }
    print("\(condition ? "PASS" : "FAIL") \(name)")
}

let suite = "BankBrowser.Regression.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let preferences = BrowserPreferences(defaults: defaults)
check("existing users start with KUB", preferences.defaultBank.id == "kub")
check("bank IDs are unique", Set(Bank.all.map(\.id)).count == Bank.all.count)
check("all bank addresses use HTTPS", Bank.all.allSatisfy { $0.url.scheme == "https" && $0.url.host != nil })
check("Alfa personal cabinet exists exactly once", Bank.all.filter { $0.url.host == "web.alfabank.ru" }.count == 1)

for bank in Bank.all {
    preferences.defaultBank = bank
    let restored = BrowserPreferences(defaults: UserDefaults(suiteName: suite)!)
    check("restored default bank: \(bank.id)", restored.defaultBank == bank)
    check("correct startup URL: \(bank.id)", restored.defaultBank.url == bank.url)
}
let alfa = Bank.all.first { $0.id == "alfa" }!
preferences.defaultBank = alfa
_ = Bank.matching(URL(string: "https://online.vtb.ru"))
check("browsing does not change chosen default", preferences.defaultBank == alfa)
defaults.set("removed-bank", forKey: "browser.defaultBankID")
check("unknown saved ID falls back safely", preferences.defaultBank.id == "kub")
defaults.set(123, forKey: "browser.defaultBankID")
check("invalid stored value falls back safely", preferences.defaultBank.id == "kub")
check("bank matching does not accept lookalike suffix", Bank.matching(URL(string: "https://web.alfabank.ru.evil.test")) == nil)
check("Alfa auth subdomain retains bank identity", Bank.matching(URL(string: "https://private.auth.alfabank.ru")) == alfa)
check("bank matching handles host casing", Bank.matching(URL(string: "https://WEB.ALFABANK.RU")) == alfa)

check("bare domain defaults to HTTPS", BrowserAddress.resolve("web.alfabank.ru")?.absoluteString == "https://web.alfabank.ru")
check("full URL preserves path and query", BrowserAddress.resolve(" https://web.alfabank.ru/path?a=1&b=2 ")?.absoluteString == "https://web.alfabank.ru/path?a=1&b=2")
check("HTTP remains explicit for security rejection", BrowserAddress.resolve("http://example.com")?.scheme == "http")
check("unsupported explicit schemes rejected", BrowserAddress.resolve("ftp://example.com") == nil)
check("empty input ignored", BrowserAddress.resolve("  \n ") == nil)
check("missing host rejected", BrowserAddress.resolve("https://") == nil)
let query = "банк & переводы + проценты?"
let search = BrowserAddress.resolve(query)!
let items = URLComponents(url: search, resolvingAgainstBaseURL: false)!.queryItems!
check("search query remains one exact parameter", items.count == 1 && items[0].name == "q" && items[0].value == query)
print("\(count - failures)/\(count) browser checks passed")
if failures > 0 { exit(1) }
