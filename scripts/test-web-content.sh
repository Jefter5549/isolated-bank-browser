#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/bank-browser-webkit.XXXXXX")"
server_pid=''
cleanup() {
  if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; fi
  rm -rf "$test_dir"
}
trap cleanup EXIT
python3 "$repo_dir/Tests/WebContent/server.py" "$test_dir/port" "$test_dir/counts.json" &
server_pid=$!
for attempt in {1..30}; do
  [ -s "$test_dir/port" ] && break
  sleep 0.1
done
port="$(cat "$test_dir/port")"
bundle="$test_dir/WebContentTests.app"
mkdir -p "$bundle/Contents/MacOS"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>space.jefter.webcontent-regression</string>
<key>CFBundleExecutable</key><string>WebContentTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>
</dict></plist>
PLIST
xcrun swiftc -module-cache-path "$test_dir/ModuleCache" \
  "$repo_dir/IsolatedBrowser/Sources/Security/SecureWebContent.swift" \
  "$repo_dir/Tests/WebContent/main.swift" -o "$bundle/Contents/MacOS/WebContentTests"
codesign --force --sign - "$bundle" 2>/dev/null
open -W -n --stdout "$test_dir/output" --stderr "$test_dir/errors" "$bundle" --args "$port" "$test_dir/counts.json" "$test_dir/result"
cat "$test_dir/output"
if [ "$(cat "$test_dir/result" 2>/dev/null)" != PASS ]; then
  cat "$test_dir/errors"
  exit 1
fi
