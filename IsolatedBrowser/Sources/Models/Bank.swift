import Foundation

struct Bank: Equatable {
    let id: String
    let name: String
    let service: String
    let domain: String
    let address: String

    var url: URL { URL(string: address)! }

    static let all: [Bank] = [
        Bank(id: "kub", name: "Кредит Урал Банк", service: "КУБ-Direct", domain: "creditural.ru", address: "https://direct.creditural.ru/"),
        Bank(id: "alfa", name: "Альфа-Банк", service: "Альфа-Онлайн · личный кабинет", domain: "alfabank.ru", address: "https://web.alfabank.ru/"),
        Bank(id: "vtb", name: "ВТБ", service: "ВТБ Онлайн", domain: "vtb.ru", address: "https://online.vtb.ru/"),
        Bank(id: "sber", name: "СберБанк", service: "СберБанк Онлайн", domain: "sberbank.ru", address: "https://online.sberbank.ru/"),
        Bank(id: "gpb", name: "Газпромбанк", service: "Интернет-банк", domain: "gpb.ru", address: "https://online.gpb.ru/"),
        Bank(id: "tbank", name: "Т-Банк", service: "Личный кабинет", domain: "tbank.ru", address: "https://www.tbank.ru/"),
        Bank(id: "gosuslugi", name: "Госуслуги", service: "Портал государственных услуг", domain: "gosuslugi.ru", address: "https://gosuslugi.ru/")
    ]

    static func matching(_ url: URL?) -> Bank? {
        guard let host = url?.host?.lowercased() else { return nil }
        return all.first { host == $0.domain || host.hasSuffix("." + $0.domain) }
    }
}

final class BrowserPreferences {
    private let defaults: UserDefaults
    private let defaultBankKey = "browser.defaultBankID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var defaultBank: Bank {
        get {
            Bank.all.first { $0.id == defaults.string(forKey: defaultBankKey) } ?? Bank.all[0]
        }
        set {
            guard Bank.all.contains(newValue) else { return }
            defaults.set(newValue.id, forKey: defaultBankKey)
        }
    }
}
