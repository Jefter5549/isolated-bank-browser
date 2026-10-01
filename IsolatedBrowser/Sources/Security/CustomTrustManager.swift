import Foundation
import Security

/// Управляет изолированным доверием к сертификатам Минцифры РФ (Russian Trusted Root & Sub CA).
final class CustomTrustManager {
    static let shared = CustomTrustManager()

    private(set) var customAnchors: [SecCertificate] = []

    private init() {
        loadCertificates()
    }

    // Позволяет проверять тот же механизм с локальным тестовым CA без изменения Keychain.
    init(customAnchors: [SecCertificate]) {
        self.customAnchors = customAnchors
    }

    private func loadCertificates() {
        let certNames = ["russian_trusted_root_ca", "russian_trusted_sub_ca"]
        var candidateBundles: [Bundle] = [Bundle.main]
        candidateBundles.append(contentsOf: Bundle.allBundles)
        candidateBundles.append(contentsOf: Bundle.allFrameworks)

        for name in certNames {
            var loaded = false
            for bundle in candidateBundles {
                if let path = bundle.path(forResource: name, ofType: "der") ?? bundle.path(forResource: name, ofType: "cer"),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let cert = SecCertificateCreateWithData(nil, data as CFData) {
                    if !customAnchors.contains(cert) {
                        customAnchors.append(cert)
                    }
                    loaded = true
                    break
                }
            }
            if !loaded {
                NSLog("[CustomTrustManager] Предупреждение: сертификат %@ не найден в бандлах", name)
            }
        }

        NSLog("[CustomTrustManager] Успешно загружено %d якорей Минцифры", customAnchors.count)
    }

    /// Проверяет цепочку, срок действия, назначение сертификата и имя HTTPS-сервера.
    /// Встроенные CA дополняют системное доверие только для этого SecTrust.
    func evaluate(serverTrust: SecTrust, host: String) -> Bool {
        guard !host.isEmpty,
              host == host.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }

        // Сохраняем ограничения вызывающей стороны и обязательно добавляем SSL hostname policy.
        var existingPolicies: CFArray?
        guard SecTrustCopyPolicies(serverTrust, &existingPolicies) == errSecSuccess,
              let policies = existingPolicies as? [SecPolicy] else {
            return false
        }
        let sslPolicy = SecPolicyCreateSSL(true, host as CFString)
        guard SecTrustSetPolicies(serverTrust, (policies + [sslPolicy]) as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificates(serverTrust, customAnchors as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(serverTrust, false) == errSecSuccess else {
            return false
        }

        // Никаких повторных попыток с ослабленной политикой или доверием по имени CA.
        return SecTrustEvaluateWithError(serverTrust, nil)
    }

    func handle(_ challenge: URLAuthenticationChallenge,
                completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let serverTrust = challenge.protectionSpace.serverTrust,
              evaluate(serverTrust: serverTrust, host: challenge.protectionSpace.host) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
