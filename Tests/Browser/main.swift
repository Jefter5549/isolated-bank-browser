import Foundation
import Network

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
check("clean start defaults to gosuslugi", preferences.defaultBank.id == "gosuslugi")
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
check("unknown saved ID falls back safely", preferences.defaultBank.id == "gosuslugi")
defaults.set(123, forKey: "browser.defaultBankID")
check("invalid stored value falls back safely", preferences.defaultBank.id == "gosuslugi")
check("bank matching does not accept lookalike suffix", Bank.matching(URL(string: "https://web.alfabank.ru.evil.test")) == nil)
check("Alfa auth subdomain retains bank identity", Bank.matching(URL(string: "https://private.auth.alfabank.ru")) == alfa)
check("bank matching handles host casing", Bank.matching(URL(string: "https://WEB.ALFABANK.RU")) == alfa)

// Custom service operations
let custom = Bank(id: "custom-nalog", name: "ФНС", service: "Личный кабинет", domain: "nalog.gov.ru", address: "https://nalog.gov.ru/", iconName: "doc.text", iconTintHex: "#0055AA", isCustom: true)
preferences.addService(custom)
check("added custom service exists", preferences.services.contains(where: { $0.id == "custom-nalog" }))
check("matching finds custom service", Bank.matching(URL(string: "https://lkfl2.nalog.gov.ru/lkfl"))?.id == "custom-nalog")

var updatedCustom = custom
updatedCustom.name = "ФНС России"
preferences.updateService(updatedCustom)
check("updated custom service reflected", preferences.services.first(where: { $0.id == "custom-nalog" })?.name == "ФНС России")

let beforeReorder = preferences.services.map(\.id)
preferences.reorderServices(from: 0, to: 1)
check("reordering changes service position", preferences.services[1].id == beforeReorder[0])

preferences.removeService(id: "custom-nalog")
check("removed custom service absent", !preferences.services.contains(where: { $0.id == "custom-nalog" }))

preferences.resetServicesToDefaults()
check("reset restores defaultList with gosuslugi first", preferences.services.first?.id == "gosuslugi")

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

check("VPN warning enabled by default", preferences.warnOnVPN == true)
preferences.warnOnVPN = false
check("VPN warning disabled when set", preferences.warnOnVPN == false)
let restoredPrefs = BrowserPreferences(defaults: defaults)
check("VPN warning preference restored", restoredPrefs.warnOnVPN == false)
preferences.warnOnVPN = true
check("VPN warning re-enabled", preferences.warnOnVPN == true)

check("other interface type recognized as VPN tunnel", VPNMonitor.isVPNInterfaceType(.other))
check("wifi interface type recognized as non-VPN", !VPNMonitor.isVPNInterfaceType(.wifi))
check("cellular interface type recognized as non-VPN", !VPNMonitor.isVPNInterfaceType(.cellular))
check("loopback interface type recognized as non-VPN", !VPNMonitor.isVPNInterfaceType(.loopback))
check("checkActiveVPN with nil path returns false", !VPNMonitor.checkActiveVPN(path: nil))

print("\(count - failures)/\(count) browser checks passed")
if failures > 0 { exit(1) }
