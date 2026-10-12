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

    private let lock = NSLock()
    private var detailsCache: [String: SecurityDetails] = [:]

    func securityDetails(for host: String) -> SecurityDetails? {
        let key = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let direct = detailsCache[key] { return direct }
        return detailsCache.first(where: { key.hasSuffix($0.key) || $0.key.hasSuffix(key) })?.value
    }

    func storeSecurityDetails(_ details: SecurityDetails) {
        let key = details.host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        lock.lock()
        detailsCache[key] = details
        lock.unlock()
    }

    func inspect(serverTrust: SecTrust, host: String) -> SecurityDetails {
        var chain: [SecCertificate] = []
        let count = SecTrustGetCertificateCount(serverTrust)
        for i in 0..<count {
            if let cert = SecTrustGetCertificateAtIndex(serverTrust, i) {
                chain.append(cert)
            }
        }

        let leafCert = chain.first
        let leafName = leafCert.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? host

        let caCert = chain.count > 1 ? chain[1] : (chain.last ?? leafCert)
        let caName = caCert.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? "Доверенный УЦ"

        let isMintsifry = chain.contains { cert in
            customAnchors.contains(where: { anchor in
                CFEqual(cert, anchor) || (SecCertificateCopyData(cert) as Data) == (SecCertificateCopyData(anchor) as Data)
            })
        } || chain.contains { cert in
            if let summary = SecCertificateCopySubjectSummary(cert) as String? {
                let lower = summary.lowercased()
                return lower.contains("russian trusted") || lower.contains("минцифры") || lower.contains("ministry of digital")
            }
            return false
        }

        let type: SecurityDetails.CertificateAuthorityType
        if isMintsifry {
            type = .mintsifry(caName: caName)
        } else {
            type = .system(caName: caName)
        }

        return SecurityDetails(
            host: host,
            caType: type,
            issuerName: caName,
            subjectName: leafName
        )
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
        let success = SecTrustEvaluateWithError(serverTrust, nil)
        if success {
            let details = inspect(serverTrust: serverTrust, host: host)
            storeSecurityDetails(details)
        }
        return success
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

struct SecurityDetails: Equatable {
    enum CertificateAuthorityType: Equatable {
        case mintsifry(caName: String)
        case system(caName: String)
        case unknown
    }

    let host: String
    let caType: CertificateAuthorityType
    let issuerName: String
    let subjectName: String
}
