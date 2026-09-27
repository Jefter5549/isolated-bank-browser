#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d /tmp/bank-tabs.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
cp -R "$repo_dir/IsolatedBrowser" "$test_dir/"
cp "$repo_dir/project.yml" "$test_dir/"
cat "$repo_dir/Tests/Tabs/CoordinatorProbe.swift" >> "$test_dir/IsolatedBrowser/Sources/UI/BrowserTabCoordinator.swift"
python3 - "$test_dir" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
p=root/'project.yml'
s=p.read_text().replace('space.jefter.isolatedbrowser','space.jefter.isolatedbrowser.tabtests')
s=s.replace('        PRODUCT_NAME:', '        SUPPORTS_MACCATALYST: YES\n        PRODUCT_NAME:')
p.write_text(s)
p=root/'IsolatedBrowser/Sources/App/SceneDelegate.swift'
s=p.read_text().replace('        window.makeKeyAndVisible()', '        window.makeKeyAndVisible()\n        coordinator.runTabProbe(output: "'+str(root/'results.txt')+'")')
p.write_text(s)
PY
cd "$test_dir"
xcodegen generate > "$test_dir/build.log"
if ! xcodebuild -project IsolatedBrowser.xcodeproj -scheme IsolatedBrowser \
  -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath "$test_dir/build" \
  build CODE_SIGNING_ALLOWED=NO >> "$test_dir/build.log" 2>&1; then
  tail -60 "$test_dir/build.log"
  exit 1
fi
test_app="$test_dir/build/Build/Products/Debug-maccatalyst/IsolatedBrowser.app"
codesign --force --deep --sign - "$test_app"
open -n "$test_app"
for attempt in {1..45}; do
  if [ -f "$test_dir/results.txt" ]; then
    cat "$test_dir/results.txt"
    grep -q '^SUCCESS$' "$test_dir/results.txt"
    exit $?
  fi
  sleep 1
done
echo 'FAIL tab probe timed out'
exit 1
