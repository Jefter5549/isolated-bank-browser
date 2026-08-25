import Foundation
import Security

/// Управляет локальным доверием к сертификатам Минцифры РФ (Russian Trusted Root & Sub CA).
/// Работает строго в песочнице приложения и не затрагивает системный Keychain iOS.
final class CustomTrustManager {
    static let shared = CustomTrustManager()

    private(set) var customAnchors: [SecCertificate] = []

    private init() {
        loadBundledCertificates()
    }

    private func loadBundledCertificates() {
        let certNames = [
            "russian_trusted_root_ca",
            "russian_trusted_sub_ca"
        ]

        for name in certNames {
            if let path = Bundle.main.path(forResource: name, ofType: "der") ?? Bundle.main.path(forResource: name, ofType: "cer"),
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let cert = SecCertificateCreateWithData(nil, data as CFData) {
                customAnchors.append(cert)
                print("[CustomTrustManager] Успешно загружен сертификат: \(name)")
            } else {
                print("[CustomTrustManager] Предупреждение: Сертификат \(name) не найден в bundle")
            }
        }
    }

    /// Проверяет цепочку доверия сервера с добавлением доверенных локальных якорей Минцифры
    func evaluate(serverTrust: SecTrust) -> Bool {
        guard !customAnchors.isEmpty else {
            var error: CFError?
            return SecTrustEvaluateWithError(serverTrust, &error)
        }

        // Добавляем наши сертификаты Минцифры в список доверенных якорей
        let setStatus = SecTrustSetAnchorCertificates(serverTrust, customAnchors as CFArray)
        guard setStatus == errSecSuccess else { return false }

        // false = доверять как нашим добавленным якорям, так и стандартным системным CA
        let setOnlyStatus = SecTrustSetAnchorCertificatesOnly(serverTrust, false)
        guard setOnlyStatus == errSecSuccess else { return false }

        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)
        if !isValid, let err = error {
            print("[CustomTrustManager] Ошибка валидации TLS: \(err)")
        }
        return isValid
    }
}
