#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/bank-browser-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -module-cache-path "$test_dir/ModuleCache" \
  "$repo_dir/IsolatedBrowser/Sources/Models/Bank.swift" \
  "$repo_dir/IsolatedBrowser/Sources/Models/BrowserAddress.swift" \
  "$repo_dir/IsolatedBrowser/Sources/Security/VPNMonitor.swift" \
  "$repo_dir/Tests/Browser/main.swift" -o "$test_dir/browser-tests"
"$test_dir/browser-tests"
