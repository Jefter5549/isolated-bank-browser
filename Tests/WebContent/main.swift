import AppKit
import WebKit

// Real WKWebView test. The test-only bundle allows HTTP so the positive control
// proves that blocking comes from the production content rule, not ATS.
let port = CommandLine.arguments[1]
let counterFile = CommandLine.arguments[2]
let resultFile = CommandLine.arguments[3]
let base = "http://127.0.0.1:\(port)"
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var views: [WKWebView] = []
var failures = 0

func counts() -> [String: Int] {
    guard let data = FileManager.default.contents(atPath: counterFile),
          let result = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
    return result
}
func finish() {
    try! (failures == 0 ? "PASS" : "FAIL").write(toFile: resultFile, atomically: true, encoding: .utf8)
    exit(failures == 0 ? 0 : 1)
}
func check(_ name: String, _ passed: Bool) {
    print("\(passed ? "PASS" : "FAIL") \(name)")
    if !passed { failures += 1 }
}
func runPage(_ name: String, rule: WKContentRuleList?, completion: @escaping () -> Void) {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    if let rule = rule { configuration.userContentController.add(rule) }
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 600), configuration: configuration)
    views.append(webView)
    webView.loadHTMLString("""
    <html><head><link rel="stylesheet" href="\(base)/\(name)/style"></head><body>
    <img src="\(base)/\(name)/image">
    <script src="\(base)/\(name)/script"></script>
    <iframe src="\(base)/\(name)/frame"></iframe>
    <script>
    fetch('\(base)/\(name)/fetch').catch(()=>{});
    try { new WebSocket('ws://127.0.0.1:\(port)/\(name)/websocket'); } catch(e) {}
    </script></body></html>
    """, baseURL: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: completion)
}

WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "regression-" + UUID().uuidString,
                                                       encodedContentRuleList: SecureWebContent.rules) { rule, error in
    check("production rule compiles in WebKit", rule != nil && error == nil)
    guard let rule = rule else { finish(); return }
    runPage("control", rule: nil) {
        runPage("blocked", rule: rule) {
            let result = counts()
            for resource in ["image", "script", "style", "frame", "fetch", "websocket"] {
                check("positive HTTP control reached server: \(resource)", (result["/control/" + resource] ?? 0) > 0)
                check("cleartext blocked before request: \(resource)", (result["/blocked/" + resource] ?? 0) == 0)
            }
            WKContentRuleListStore.default().removeContentRuleList(forIdentifier: rule.identifier) { _ in finish() }
        }
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
    check("WebKit test completed in time", false)
    finish()
}
app.run()
