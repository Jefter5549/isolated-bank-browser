// Appended to BrowserTabCoordinator.swift in a disposable Catalyst test build.
// Exercises production controllers and real WebKit without banking credentials.
extension BrowserTabCoordinator {
    func runTabProbe(output: String) {
        Task { @MainActor in
            var results: [String] = []
            func check(_ value: Bool, _ name: String) throws {
                results.append("\(value ? "PASS" : "FAIL") \(name)")
                if !value { throw NSError(domain: name, code: 1) }
            }
            func waitUntil(timeout: TimeInterval = 10, condition: () async throws -> Bool) async throws {
                let start = Date()
                while Date().timeIntervalSince(start) < timeout {
                    if try await condition() { return }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                throw NSError(domain: "waitUntilTimeout", code: 1)
            }
            do {
                let rules = try await WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: SecureWebContent.ruleIdentifier, encodedContentRuleList: SecureWebContent.rules)
                let config = WKWebViewConfiguration()
                config.preferences.javaScriptCanOpenWindowsAutomatically = true
                let first = addTab(configuration: config, rules: rules)!
                let original = tabs[0]
                close(original)
                first.webView.loadHTMLString("<title>Tab probe</title><input id='memo'><script>window.marker=42</script>", baseURL: URL(string: "https://tabs.invalid"))
                try await waitUntil {
                    let ready = try? await first.webView.evaluateJavaScript("document.getElementById('memo') !== null && window.marker === 42") as? Bool
                    return ready == true
                }
                _ = try await first.webView.evaluateJavaScript("document.getElementById('memo').value='retained'; 1")
                let second = addTab(configuration: WKWebViewConfiguration(), rules: rules)!
                try check(tabs.count == 2 && first.webView !== second.webView, "independent web views")
                select(first)
                let retained = try await first.webView.evaluateJavaScript("document.getElementById('memo').value")
                try check(retained as? String == "retained", "form retained after tab switching")
                close(second)
                try check(tabs.count == 1 && navigationController.topViewController === first, "closing background tab preserves selection")
                let background = addTab(configuration: WKWebViewConfiguration(), rules: rules)!
                select(first)
                _ = try await first.webView.evaluateJavaScript("window.child=window.open('about:blank'); 1")
                try await waitUntil { self.tabs.count == 3 }
                try check(tabs.count == 3, "window.open creates a tab")
                let child = tabs.last!
                try await waitUntil {
                    let val = try? await child.webView.evaluateJavaScript("window.opener && window.opener.marker === 42") as? Bool
                    return val == true
                }
                let opener = try await child.webView.evaluateJavaScript("window.opener.marker")
                try check((opener as? NSNumber)?.intValue == 42, "popup retains window.opener")
                _ = try await child.webView.evaluateJavaScript("window.close(); 1")
                try await waitUntil { self.tabs.count == 2 }
                try check(tabs.count == 2 && navigationController.topViewController === first, "window.close returns to actual source")
                close(background)
                close(first)
                try check(tabs.count == 1 && tabs[0] !== first, "closing last tab creates default bank tab")
                results.append("SUCCESS")
            } catch {
                results.append("ERROR \(error)")
            }
            try? results.joined(separator: "\n").write(toFile: output, atomically: true, encoding: .utf8)
            exit(results.last == "SUCCESS" ? 0 : 1)
        }
    }
}
