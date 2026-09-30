import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

/// Мониторинг активного VPN-туннеля через NWPathMonitor.
final class VPNMonitor {
    static let shared = VPNMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "space.jefter.isolatedbrowser.vpnmonitor")
    private let initialPathGroup = DispatchGroup()
    private var hasReceivedInitialPath = false

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
        initialPathGroup.enter()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.evaluate(path: path)
            if !self.hasReceivedInitialPath {
                self.hasReceivedInitialPath = true
                self.initialPathGroup.leave()
            }
        }
        monitor.start(queue: queue)
        // Синхронно ожидаем первую оценку пути (обычно занимает единицы миллисекунд),
        // чтобы исключить ложные срабатывания при старте приложения до готовности NWPath.
        _ = initialPathGroup.wait(timeout: .now() + 0.15)
        evaluate(path: monitor.currentPath)
    }

    deinit {
        monitor.cancel()
    }

    private func evaluate(path: NWPath) {
        let isVPN = Self.checkActiveVPN(path: path)
        isVPNActive = isVPN
    }

    /// Проверяет, маршрутизируется ли сетевой трафик через активный VPN-интерфейс (.other).
    /// Исключает ложные срабатывания (VoWiFi / Wi-Fi Calling ipsec0, системные utun службы Apple,
    /// Private Relay, AirDrop, сохранённые отключенные профили в настройках).
    static func checkActiveVPN(path: NWPath? = nil) -> Bool {
        guard let path = path else { return false }
        guard path.status == .satisfied else { return false }
        return path.usesInterfaceType(.other) || path.availableInterfaces.contains(where: { $0.type == .other })
    }

    /// Проверяет, относится ли тип интерфейса к туннельным (VPN)
    static func isVPNInterfaceType(_ type: NWInterface.InterfaceType) -> Bool {
        type == .other
    }

    /// Открывает системные Настройки iOS
    static func openVPNSettings() {
        #if canImport(UIKit)
        let candidates = [
            "App-prefs:root=General&path=VPN",
            "App-Prefs:root=General&path=VPN",
            "App-Prefs:root=VPN",
            "App-prefs:root=VPN",
            "prefs:root=General&path=VPN",
            "prefs:root=VPN",
            "App-prefs:root=",
            "App-Prefs:root=",
            UIApplication.openSettingsURLString
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }
        }
        if let fallback = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(fallback, options: [:], completionHandler: nil)
        }
        #endif
    }
}

extension Notification.Name {
    static let vpnStatusDidChange = Notification.Name("BrowserVPNStatusDidChangeNotification")
}
