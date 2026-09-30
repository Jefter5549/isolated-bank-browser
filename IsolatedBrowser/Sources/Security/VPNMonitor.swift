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
    /// Предотвращает ложные срабатывания (например, utun системных служб Apple, AirDrop или Private Relay).
    static func checkActiveVPN(path: NWPath? = nil) -> Bool {
        #if canImport(CFNetwork)
        // 1. Наиболее надежный способ детекта VPN в iOS без ложных срабатываний:
        // Системный словарь __SCOPED__ в CFNetwork содержит активные интерфейсы туннелей (tap, tun, ppp, ipsec),
        // привязанные к маршрутизации сетевого стека.
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

        // 2. Если NWPath активен и системно использует тип .other
        if let path = path, path.status == .satisfied, path.usesInterfaceType(.other) {
            return true
        }

        // 3. Дополнительная проверка getifaddrs:
        // В современных iOS utun0..utun3 часто заняты локальными демонами Apple.
        // Явные VPN туннели используют ppp, ipsec, tun, tap.
        // utun учитывается только если это кастомный utun с активным IP-адресом и p2p флагом (IFF_POINTOPOINT).
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

            // utun: проверяем Point-to-Point флаг и отсекаем utun0 (системный default в iOS)
            let isPointToPoint = (flags & IFF_POINTOPOINT) == IFF_POINTOPOINT
            if isPointToPoint && name.hasPrefix("utun") && name != "utun0" {
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
        name.hasPrefix("tap") ||
        name.hasPrefix("utun")
    }

    /// Явные туннельные интерфейсы getifaddrs
    static func isExplicitVPNInterfaceName(_ name: String) -> Bool {
        name.hasPrefix("ppp") ||
        name.hasPrefix("ipsec") ||
        name.hasPrefix("tun") ||
        name.hasPrefix("tap")
    }

    /// Открывает экран VPN в системных Настройках iOS
    static func openVPNSettings() {
        #if canImport(UIKit)
        let candidates = [
            "App-Prefs:root=General&path=Network/VPN",
            "App-Prefs:root=General&path=VPN",
            "App-prefs:root=General&path=VPN",
            UIApplication.openSettingsURLString
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

extension Notification.Name {
    static let vpnStatusDidChange = Notification.Name("BrowserVPNStatusDidChangeNotification")
}
