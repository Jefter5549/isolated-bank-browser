import Foundation

struct Bank: Equatable, Codable, Identifiable {
    let id: String
    var name: String
    var service: String
    var domain: String
    var address: String
    var iconName: String?
    var iconTintHex: String?
    var isCustom: Bool

    init(
        id: String,
        name: String,
        service: String,
        domain: String,
        address: String,
        iconName: String? = nil,
        iconTintHex: String? = nil,
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.service = service
        self.domain = domain
        self.address = address
        self.iconName = iconName
        self.iconTintHex = iconTintHex
        self.isCustom = isCustom
    }

    var url: URL {
        URL(string: address) ?? URL(string: "https://gosuslugi.ru/")!
    }

    static let defaultList: [Bank] = [
        Bank(id: "gosuslugi", name: "Госуслуги", service: "Портал государственных услуг", domain: "gosuslugi.ru", address: "https://gosuslugi.ru/", iconName: "doc.text.fill", iconTintHex: "#1270E0"),
        Bank(id: "kub", name: "Кредит Урал Банк", service: "КУБ-Direct", domain: "creditural.ru", address: "https://direct.creditural.ru/", iconName: "building.columns.fill", iconTintHex: "#006699"),
        Bank(id: "alfa", name: "Альфа-Банк", service: "Альфа-Онлайн · личный кабинет", domain: "alfabank.ru", address: "https://web.alfabank.ru/", iconName: "creditcard.fill", iconTintHex: "#EF3124"),
        Bank(id: "vtb", name: "ВТБ", service: "ВТБ Онлайн", domain: "vtb.ru", address: "https://online.vtb.ru/", iconName: "building.columns.fill", iconTintHex: "#0A2896"),
        Bank(id: "sber", name: "СберБанк", service: "СберБанк Онлайн", domain: "sberbank.ru", address: "https://online.sberbank.ru/", iconName: "creditcard.fill", iconTintHex: "#21A038"),
        Bank(id: "gpb", name: "Газпромбанк", service: "Интернет-банк", domain: "gpb.ru", address: "https://online.gpb.ru/", iconName: "flame.fill", iconTintHex: "#0072BC"),
        Bank(id: "tbank", name: "Т-Банк", service: "Личный кабинет", domain: "tbank.ru", address: "https://www.tbank.ru/", iconName: "shield.fill", iconTintHex: "#FFDD2D")
    ]

    static var all: [Bank] {
        BrowserPreferences().services
    }

    static func matching(_ url: URL?) -> Bank? {
        matching(url, in: all)
    }

    static func matching(_ url: URL?, in list: [Bank]) -> Bank? {
        guard let host = url?.host?.lowercased() else { return nil }
        return list.first { host == $0.domain || host.hasSuffix("." + $0.domain) }
    }
}

final class BrowserPreferences {
    private let defaults: UserDefaults
    private let defaultBankKey = "browser.defaultBankID"
    private let servicesKey = "browser.customServices.v1"
    private let warnOnVPNKey = "browser.warnOnVPN"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var services: [Bank] {
        get {
            guard let data = defaults.data(forKey: servicesKey),
                  let decoded = try? JSONDecoder().decode([Bank].self, from: data),
                  !decoded.isEmpty else {
                return Bank.defaultList
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: servicesKey)
            }
        }
    }

    var defaultBank: Bank {
        get {
            let currentServices = services
            let savedID = defaults.string(forKey: defaultBankKey)
            if let savedID = savedID, let match = currentServices.first(where: { $0.id == savedID }) {
                return match
            }
            return currentServices.first ?? Bank.defaultList[0]
        }
        set {
            guard services.contains(where: { $0.id == newValue.id }) || Bank.defaultList.contains(where: { $0.id == newValue.id }) else { return }
            defaults.set(newValue.id, forKey: defaultBankKey)
        }
    }

    func addService(_ service: Bank) {
        var current = services
        current.removeAll { $0.id == service.id }
        current.append(service)
        services = current
    }

    func removeService(id: String) {
        var current = services
        current.removeAll { $0.id == id }
        if defaults.string(forKey: defaultBankKey) == id {
            defaults.set(current.first?.id ?? Bank.defaultList[0].id, forKey: defaultBankKey)
        }
        services = current.isEmpty ? Bank.defaultList : current
    }

    func updateService(_ service: Bank) {
        var current = services
        if let idx = current.firstIndex(where: { $0.id == service.id }) {
            current[idx] = service
            services = current
        }
    }

    func reorderServices(from sourceIndex: Int, to destinationIndex: Int) {
        var current = services
        guard sourceIndex >= 0, sourceIndex < current.count,
              destinationIndex >= 0, destinationIndex < current.count,
              sourceIndex != destinationIndex else { return }
        let moved = current.remove(at: sourceIndex)
        current.insert(moved, at: destinationIndex)
        services = current
    }

    func resetServicesToDefaults() {
        defaults.removeObject(forKey: servicesKey)
        defaults.removeObject(forKey: defaultBankKey)
    }

    var warnOnVPN: Bool {
        get {
            defaults.object(forKey: warnOnVPNKey) == nil ? true : defaults.bool(forKey: warnOnVPNKey)
        }
        set {
            defaults.set(newValue, forKey: warnOnVPNKey)
        }
    }
}
