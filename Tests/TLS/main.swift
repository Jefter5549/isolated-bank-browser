import Foundation
import Security

// Compiled with the production Security sources; uses Apple's real trust evaluator.
let fixtureDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
var failures = 0
var checks = 0

func check(_ description: String, _ condition: Bool) {
    checks += 1
    if !condition { failures += 1 }
    print("\(condition ? "PASS" : "FAIL") \(description)")
}

func certificate(_ name: String) throws -> SecCertificate {
    let data = try Data(contentsOf: fixtureDirectory.appendingPathComponent(name + ".der"))
    guard let cert = SecCertificateCreateWithData(nil, data as CFData) else {
        fatalError("Invalid fixture: \(name)")
    }
    return cert
}

func trust(_ names: [String], basicPolicy: Bool = false, date: Date = Date()) throws -> SecTrust {
    let certificates = try names.map(certificate)
    var result: SecTrust?
    let policy = basicPolicy ? SecPolicyCreateBasicX509() : SecPolicyCreateSSL(true, "bank.test" as CFString)
    precondition(SecTrustCreateWithCertificates(certificates as CFArray, policy, &result) == errSecSuccess)
    precondition(SecTrustSetNetworkFetchAllowed(result!, false) == errSecSuccess)
    precondition(SecTrustSetVerifyDate(result!, date as CFDate) == errSecSuccess)
    return result!
}

final class TestProtectionSpace: URLProtectionSpace, @unchecked Sendable {
    var suppliedTrust: SecTrust?
    override var serverTrust: SecTrust? { suppliedTrust }
}

final class TestChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}

func disposition(_ manager: CustomTrustManager, trust: SecTrust?, host: String = "bank.test",
                 method: String = NSURLAuthenticationMethodServerTrust)
    -> (URLSession.AuthChallengeDisposition, URLCredential?) {
    let space = TestProtectionSpace(host: host, port: 443, protocol: "https", realm: nil,
                                    authenticationMethod: method)
    space.suppliedTrust = trust
    let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil,
                                              previousFailureCount: 0, failureResponse: nil,
                                              error: nil, sender: TestChallengeSender())
    var calls = 0
    var result: (URLSession.AuthChallengeDisposition, URLCredential?)?
    manager.handle(challenge) { action, credential in
        calls += 1
        result = (action, credential)
    }
    check("challenge completion called exactly once", calls == 1)
    return result!
}

let root = try certificate("root")
let manager = CustomTrustManager(customAnchors: [root])
let good = ["valid", "intermediate"]
check("matching hostname and custom-root chain", manager.evaluate(serverTrust: try trust(good), host: "bank.test"))
check("DNS hostname case-insensitive", manager.evaluate(serverTrust: try trust(good), host: "BANK.TEST"))
check("wrong hostname rejected", !manager.evaluate(serverTrust: try trust(good), host: "other.test"))
check("Basic X.509 input cannot bypass hostname", !manager.evaluate(serverTrust: try trust(good, basicPolicy: true), host: "other.test"))
check("empty hostname rejected", !manager.evaluate(serverTrust: try trust(good), host: ""))
check("whitespace hostname rejected", !manager.evaluate(serverTrust: try trust(good), host: " bank.test"))
check("expired leaf rejected", !manager.evaluate(serverTrust: try trust(good, date: Date().addingTimeInterval(3 * 86400)), host: "bank.test"))
check("not-yet-valid chain rejected", !manager.evaluate(serverTrust: try trust(good, date: Date().addingTimeInterval(-3 * 86400)), host: "bank.test"))
check("client-auth-only leaf rejected", !manager.evaluate(serverTrust: try trust(["client", "intermediate"]), host: "bank.test"))
check("untrusted chain rejected", !CustomTrustManager.shared.evaluate(serverTrust: try trust(good), host: "bank.test"))
check("missing intermediate rejected offline", !manager.evaluate(serverTrust: try trust(["valid"]), host: "bank.test"))
check("tampered signature rejected", !manager.evaluate(serverTrust: try trust(["tampered", "intermediate"]), host: "bank.test"))

for alias in ["vtb", "sberbank", "creditural", "russian-trusted", "ministry", "russian-name"] {
    check("forged \(alias) certificate rejected", !CustomTrustManager.shared.evaluate(serverTrust: try trust([alias]), host: "bank.test"))
}

let accepted = disposition(manager, trust: try trust(good))
check("valid challenge gets credential", accepted.0 == .useCredential && accepted.1 != nil)
let rejected = disposition(manager, trust: try trust(good), host: "wrong.test")
check("invalid challenge explicitly cancelled", rejected.0 == .cancelAuthenticationChallenge && rejected.1 == nil)
let missing = disposition(manager, trust: nil)
check("missing server trust explicitly cancelled", missing.0 == .cancelAuthenticationChallenge && missing.1 == nil)
let unrelated = disposition(manager, trust: nil, method: NSURLAuthenticationMethodHTTPBasic)
check("non-TLS authentication keeps default handling", unrelated.0 == .performDefaultHandling && unrelated.1 == nil)

for url in ["http://bank.test", "HTTP://bank.test", "http://bank.test/redirect"] {
    check("cleartext navigation blocked: \(url)", !HTTPSNavigationPolicy.allows(URL(string: url)))
}
for url in ["https://bank.test", "HTTPS://bank.test", "about:blank", "blob:https://bank.test/id", "data:text/plain,hello"] {
    check("navigation retained: \(url)", HTTPSNavigationPolicy.allows(URL(string: url)))
}
check("missing navigation URL rejected", !HTTPSNavigationPolicy.allows(nil))

// Optional real-network control: same challenge handler, no custom anchors.
if CommandLine.arguments.contains("--live") {
    final class LiveDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
        let manager: CustomTrustManager
        var trustChallenges = 0
        init(manager: CustomTrustManager) { self.manager = manager }
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                trustChallenges += 1
            }
            manager.handle(challenge, completionHandler: completionHandler)
        }
    }
    for (description, liveManager) in [("without custom anchors", CustomTrustManager(customAnchors: [])),
                                       ("with bundled anchors", CustomTrustManager.shared)] {
        let semaphore = DispatchSemaphore(value: 0)
        let delegate = LiveDelegate(manager: liveManager)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: URL(string: "https://github.com")!) { _, response, error in
            check("public HTTPS works \(description)", error == nil && (response as? HTTPURLResponse)?.statusCode == 200)
            check("public HTTPS exercised trust handler \(description)", delegate.trustChallenges > 0)
            semaphore.signal()
        }.resume()
        if semaphore.wait(timeout: .now() + 40) == .timedOut {
            check("public HTTPS completed before timeout", false)
        }
        session.invalidateAndCancel()
    }
}

print("\(checks - failures)/\(checks) TLS checks passed")
exit(failures == 0 ? 0 : 1)
