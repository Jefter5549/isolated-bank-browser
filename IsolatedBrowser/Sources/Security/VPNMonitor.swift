import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

/// Мониторинг активного VPN-туннеля через системные интерфейсы и NWPathMonitor.
final class VPNMonitor {
    static let shared = VPNMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "space.jefter.isolatedbrowser.vpnmonitor")

    private(set) var isVPNActive: Bool = false {
        didSet {
            if oldValue != isVPNActive {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .vpnStatusDidChange, object: self.isVPNActive)
                }
            }
        }
    }

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.evaluate(path: path)
        }
        monitor.start(queue: queue)
        isVPNActive = Self.checkActiveVPN()
    }

    deinit {
        monitor.cancel()
    }

    private func evaluate(path: NWPath) {
        // Проверяем, идет ли активный трафик через VPN
        let isVPN = Self.checkActiveVPN(path: path)
        isVPNActive = isVPN
    }

    /// Проверяет физическое наличие активного VPN соединения.
    /// Предотвращает ложные срабатывания (utun системных служб Apple, AirDrop, Private Relay, AWDL).
    static func checkActiveVPN(path: NWPath? = nil) -> Bool {
        // 1. Проверяем NWPath: если система сообщает, что трафик идет через интерфейс типа .other (VPN-туннель)
        if let path = path, path.status == .satisfied, path.usesInterfaceType(.other) {
            return true
        }

        #if canImport(CFNetwork)
        // 2. Системные scoped настройки прокси:
        // Проверяем наличие интерфейсов tap, tun, ppp, ipsec.
        // utun намеренно НЕ включаем сюда, так как в iOS utun0..utun3 почти всегда создаются
        // системными демонами (mDNSResponder, CloudKit, Private Relay) даже при выключенном VPN.
        if let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
           let scoped = proxySettings["__SCOPED__"] as? [String: Any] {
            for key in scoped.keys {
                let lower = key.lowercased()
                if isScopedVPNInterfaceName(lower) {
                    return true
                }
            }
        }
        #endif

        // 3. Проверка getifaddrs на явные туннельные интерфейсы (ppp, ipsec, tun, tap).
        // Никаких utun здесь не проверяем, чтобы исключить ложные срабатывания на iOS.
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return false }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isRunning = (flags & IFF_RUNNING) == IFF_RUNNING
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
            guard isUp && isRunning && !isLoopback else { continue }

            guard let addr = ptr.pointee.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

            let name = String(cString: ptr.pointee.ifa_name).lowercased()
            if isExplicitVPNInterfaceName(name) {
                return true
            }
        }
        return false
    }

    /// Интерфейсы в __SCOPED__ настройках CFNetwork
    static func isScopedVPNInterfaceName(_ name: String) -> Bool {
        name.hasPrefix("ppp") ||
        name.hasPrefix("ipsec") ||
        name.hasPrefix("tun") ||
        name.hasPrefix("tap")
    }

    /// Явные туннельные интерфейсы getifaddrs
    static func isExplicitVPNInterfaceName(_ name: String) -> Bool {
        name.hasPrefix("ppp") ||
        name.hasPrefix("ipsec") ||
        name.hasPrefix("tun") ||
        name.hasPrefix("tap")
    }

    /// Открывает системные Настройки iOS
    static func openVPNSettings() {
        #if canImport(UIKit)
        let candidates = [
            "App-Prefs:root=General&path=VPN",
            "App-prefs:root=General&path=VPN",
            "App-Prefs:root=VPN",
            "App-prefs:root=VPN",
            "prefs:root=General&path=VPN",
            "prefs:root=VPN",
            "App-Prefs:root=",
            "App-prefs:root=",
            "App-Prefs:",
            "App-prefs:",
            UIApplication.openSettingsURLString
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            // Не используем canOpenURL, так как приватные URL-схемы Apple (App-Prefs/prefs)
            // блокируются canOpenURL без LSApplicationQueriesSchemes, но успешно открываются через open().
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        // Если canOpenURL вернул false для всех схем, вызываем open() напрямую для главного экрана Настроек:
        if let rootURL = URL(string: "App-prefs:root=General&path=VPN") {
            UIApplication.shared.open(rootURL, options: [:]) { success in
                if !success, let generalSettingsURL = URL(string: "App-prefs:root=") {
                    UIApplication.shared.open(generalSettingsURL, options: [:]) { rootSuccess in
                        if !rootSuccess, let appSettings = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(appSettings)
                        }
                    }
                }
            }
        } else if let appSettings = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(appSettings)
        }
        #endif
    }
}

extension Notification.Name {
    static let vpnStatusDidChange = Notification.Name("BrowserVPNStatusDidChangeNotification")
}
