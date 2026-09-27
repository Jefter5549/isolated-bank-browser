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
            func pause() async { try? await Task.sleep(nanoseconds: 700_000_000) }
            do {
                let rules = try await WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: SecureWebContent.ruleIdentifier, encodedContentRuleList: SecureWebContent.rules)
                let config = WKWebViewConfiguration()
                config.preferences.javaScriptCanOpenWindowsAutomatically = true
                let first = addTab(configuration: config, rules: rules)!
                let original = tabs[0]
                close(original)
                first.webView.loadHTMLString("<title>Tab probe</title><input id='memo'><script>window.marker=42</script>", baseURL: URL(string: "https://tabs.invalid"))
                await pause()
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
                await pause()
                try check(tabs.count == 3, "window.open creates a tab")
                let child = tabs.last!
                let opener = try await child.webView.evaluateJavaScript("window.opener.marker")
                try check((opener as? NSNumber)?.intValue == 42, "popup retains window.opener")
                _ = try await child.webView.evaluateJavaScript("window.close(); 1")
                await pause()
                try check(tabs.count == 2 && navigationController.topViewController === first, "window.close returns to actual source")
                close(background)
                close(first)
                try check(tabs.count == 1 && tabs[0] !== first, "closing last tab creates default bank tab")
                let suite = "tab-restoration-tests-" + UUID().uuidString
                let defaults = UserDefaults(suiteName: suite)!
                defer { defaults.removePersistentDomain(forName: suite) }
                let store = BrowserSessionStore(defaults: defaults)
                let urls = [URL(string: "https://first.invalid/path?q=1#part")!, URL(string: "https://second.invalid/")!]
                store.save(BrowserSession(urls: urls, selectedIndex: 1))
                let restored = BrowserTabCoordinator(sessionStore: store)
                try check(restored.tabs.count == 2 && restored.tabs.map { $0.restorationURL } == urls.map(Optional.some), "restores tab order and complete addresses")
                try check(restored.navigationController.topViewController === restored.tabs[1], "restores selected tab")
                try check(!restored.tabs[0].isViewLoaded, "background restored tab stays unloaded")
                try check(restored.tabs[1].webView.configuration.websiteDataStore.isPersistent, "restored tabs use persistent website storage")
                restored.select(restored.tabs[0])
                let switched = BrowserTabCoordinator(sessionStore: store)
                try check(switched.navigationController.topViewController === switched.tabs[0], "selection survives coordinator recreation")
                restored.close(restored.tabs[1])
                let afterClose = BrowserTabCoordinator(sessionStore: store)
                try check(afterClose.tabs.count == 1 && afterClose.tabs[0].restorationURL == urls[0], "closed tab stays closed on restore")
                store.save(BrowserSession(urls: [URL(string: "http://unsafe.invalid"), URL(string: "https://user:pass@example.com")], selectedIndex: 99))
                let sanitized = store.load()!
                try check(sanitized.urls.allSatisfy { $0 == nil } && sanitized.selectedIndex == 1, "invalid addresses and selected index are sanitized")
                defaults.set(Data("broken".utf8), forKey: "browser.tabs.v1")
                try check(store.load() == nil, "corrupt session falls back to default")
                for coordinator in [restored, switched, afterClose] { coordinator.tabs.forEach { $0.closeTab() } }
                results.append("SUCCESS")
            } catch {
                results.append("ERROR \(error)")
            }
            try? results.joined(separator: "\n").write(toFile: output, atomically: true, encoding: .utf8)
            exit(results.last == "SUCCESS" ? 0 : 1)
        }
    }
}
