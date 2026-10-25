#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# source時には実バイナリを起動しない。Linuxでも検証関数だけを使う。
# shellcheck source=tests/vendored-macos-tools-runtime-test.sh
source "$ROOT_DIR/tests/vendored-macos-tools-runtime-test.sh"

export TEST_EXECUTION_MARKER="$FIXTURE/executed"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nprintf executed >"$TEST_EXECUTION_MARKER"\nprintf "0.63.2\\n"\n' >"$FIXTURE/good"
printf '#!/usr/bin/env bash\nprintf "0.63.1\\n"\n' >"$FIXTURE/wrong-version"
printf '#!/usr/bin/env bash\nexit 42\n' >"$FIXTURE/failed"
printf '#!/usr/bin/env bash\nprintf "0.63.2\\n"\n' >"$FIXTURE/not-executable"
chmod +x "$FIXTURE/good" "$FIXTURE/wrong-version" "$FIXTURE/failed"

expect_failure() {
    local reason="$1"
    shift
    if verify_tool SwiftLint "$@" >"$FIXTURE/stdout" 2>"$FIXTURE/stderr"; then
        fail "accepted $reason"
    fi
    grep -Fq "$reason" "$FIXTURE/stderr" || fail "missing diagnostic: $reason"
    if [[ "$reason" != 'version mismatch' ]] && grep -Fq 'version mismatch' "$FIXTURE/stderr"; then
        fail "misdiagnosed $reason as version mismatch"
    fi
}

expect_failure 'not executable (exit 126)' "$FIXTURE/not-executable" 0.63.2 - version
expect_failure 'not executable (exit 42)' "$FIXTURE/failed" 0.63.2 - version
expect_failure 'version mismatch' "$FIXTURE/wrong-version" 0.63.2 - version
expect_failure 'checksum mismatch' "$FIXTURE/good" 0.63.2 "$(printf '%064d' 0)" version
[[ ! -e "$TEST_EXECUTION_MARKER" ]] || fail 'checksum failure executed the binary'

expected_sha="$(shasum -a 256 "$FIXTURE/good" | awk '{print $1}')"
verify_tool SwiftLint "$FIXTURE/good" 0.63.2 "$expected_sha" version || fail 'rejected matching version and checksum'
[[ -f "$TEST_EXECUTION_MARKER" ]] || fail 'positive control did not execute the binary'

# 誤配線時もLinuxでMach-Oを実行する前に失敗させる。
uname() { printf 'Linux\n'; }
if main >"$FIXTURE/stdout" 2>"$FIXTURE/stderr"; then
    fail 'accepted a non-macOS runtime'
fi
grep -Fq 'requires macOS' "$FIXTURE/stderr" || fail 'missing platform diagnostic'

printf 'PASS: vendored macOS runtime diagnostics\n'
