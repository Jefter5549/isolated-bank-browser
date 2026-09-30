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
        let hasOther = path.usesInterfaceType(.other) || path.availableInterfaces.contains { $0.type == .other }
        let hasVPNInterface = Self.checkActiveVPN()
        isVPNActive = hasOther || hasVPNInterface
    }

    /// Проверяет физическое наличие активных туннельных интерфейсов (utun, ppp, ipsec).
    static func checkActiveVPN() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return false }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isRunning = (flags & IFF_RUNNING) == IFF_RUNNING
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
            guard isUp && isRunning && !isLoopback else { continue }

            let name = String(cString: ptr.pointee.ifa_name).lowercased()
            if isVPNInterfaceName(name) {
                return true
            }
        }
        return false
    }

    static func isVPNInterfaceName(_ name: String) -> Bool {
        name.hasPrefix("utun") ||
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
