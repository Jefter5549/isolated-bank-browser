#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/isolated-browser-tls.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
openssl_bin="${OPENSSL_BIN:-openssl}"
cd "$test_dir"

# Ephemeral keys, never imported into Keychain. No downloads or package dependencies.
"$openssl_bin" req -x509 -newkey rsa:2048 -nodes -sha256 -days 30 \
  -subj '/CN=Local TLS Regression Root' -keyout root.key -out root.pem \
  -addext 'basicConstraints=critical,CA:TRUE,pathlen:1' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign' 2>/dev/null
"$openssl_bin" req -new -newkey rsa:2048 -nodes -subj '/CN=Local TLS Regression Intermediate' \
  -keyout intermediate.key -out intermediate.csr 2>/dev/null
cat > intermediate.ext <<'EOF'
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF
"$openssl_bin" x509 -req -in intermediate.csr -CA root.pem -CAkey root.key -CAcreateserial \
  -days 20 -sha256 -extfile intermediate.ext -out intermediate.pem 2>/dev/null

for name in valid client; do
  usage=serverAuth
  if [ "$name" = client ]; then usage=clientAuth; fi
  "$openssl_bin" req -new -newkey rsa:2048 -nodes -subj '/CN=bank.test' \
    -keyout "$name.key" -out "$name.csr" 2>/dev/null
  cat > "$name.ext" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=$usage
subjectAltName=DNS:bank.test
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF
  "$openssl_bin" x509 -req -in "$name.csr" -CA intermediate.pem -CAkey intermediate.key -CAcreateserial \
    -days 2 -sha256 -extfile "$name.ext" -out "$name.pem" 2>/dev/null
done

for name in vtb sberbank creditural russian-trusted ministry russian-name; do
  subject="$name attacker"
  case "$name" in
    russian-trusted) subject='russian trusted attacker' ;;
    ministry) subject='ministry of digital attacker' ;;
    russian-name) subject='минцифры attacker' ;;
  esac
  "$openssl_bin" req -x509 -newkey rsa:2048 -nodes -sha256 -days 2 -utf8 \
    -subj "/CN=$subject" -keyout "$name.key" -out "$name.pem" \
    -addext 'subjectAltName=DNS:bank.test' -addext 'extendedKeyUsage=serverAuth' 2>/dev/null
done
for pem in *.pem; do
  "$openssl_bin" x509 -in "$pem" -outform DER -out "${pem%.pem}.der"
done
python3 - <<'PY'
from pathlib import Path
data = bytearray(Path('valid.der').read_bytes())
data[-1] ^= 1
Path('tampered.der').write_bytes(data)
PY

xcrun swiftc -module-cache-path "$test_dir/ModuleCache" \
  "$repo_dir/IsolatedBrowser/Sources/Security/CustomTrustManager.swift" \
  "$repo_dir/IsolatedBrowser/Sources/Security/HTTPSNavigationPolicy.swift" \
  "$repo_dir/Tests/TLS/main.swift" -o "$test_dir/tls-tests"
"$test_dir/tls-tests" "$test_dir" "$@"
