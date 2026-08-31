#!/usr/bin/env bash
set -euo pipefail

FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

command -v osv-scanner >/dev/null || {
    echo "FAIL: osv-scanner is required for this real-tool test" >&2
    exit 1
}
osv_version="$(osv-scanner --version)"
printf '%s\n' "$osv_version" | rg -q '2\.5\.1' || {
    echo "FAIL: osv-scanner version must be 2.5.1, got $osv_version" >&2
    exit 1
}

cat >"$FIXTURE/Package.resolved" <<'EOF'
{
  "originHash" : "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "pins" : [
    {
      "identity" : "swift-argument-parser",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/apple/swift-argument-parser",
      "state" : {
        "revision" : "0fbc8848e389af9889220eb825311863cfff716b",
        "version" : "1.5.0"
      }
    }
  ],
  "version" : 2
}
EOF

set +e
osv-scanner scan source --offline --no-resolve --all-packages --format json \
    -L "$FIXTURE/Package.resolved" >"$FIXTURE/out.json" 2>"$FIXTURE/err.txt"
status=$?
set -e

if [[ ! -s "$FIXTURE/out.json" ]]; then
    echo "FAIL: osv-scanner produced no JSON for Package.resolved" >&2
    exit 1
fi
if ! rg -Fq '"type": "lockfile"' "$FIXTURE/out.json"; then
    echo "FAIL: osv-scanner must classify Package.resolved as a lockfile" >&2
    cat "$FIXTURE/err.txt" >&2
    exit 1
fi
if ! rg -Fq 'Package.resolved' "$FIXTURE/out.json"; then
    echo "FAIL: osv-scanner JSON must name Package.resolved" >&2
    exit 1
fi
if ! rg -Fq '"name": "github.com/apple/swift-argument-parser"' "$FIXTURE/out.json"; then
    echo "FAIL: osv-scanner must extract the Swift package identity from Package.resolved" >&2
    exit 1
fi
if ! rg -q 'Scanned .+Package\.resolved file and found 1 package' "$FIXTURE/err.txt"; then
    echo "FAIL: osv-scanner must report that Package.resolved was parsed" >&2
    cat "$FIXTURE/err.txt" >&2
    exit 1
fi

# Offline DB absence may yield a non-zero exit; recognition must not depend on
# network vulnerability counts.
if [[ "$status" -eq 0 ]]; then
    :
fi

echo "PASS"
