#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_SCRIPT="$ROOT_DIR/scripts/gitleaks-check.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

if [[ ! -x "$CHECK_SCRIPT" ]]; then
    echo "FAIL: gitleaks-check.sh must exist and be executable" >&2
    exit 1
fi

git -C "$FIXTURE" init -q
printf 'safe\n' >"$FIXTURE/safe.txt"
git -C "$FIXTURE" add -- safe.txt
printf '%s\n' safe.txt >"$FIXTURE/files.txt"

fake_bin="$FIXTURE/bin"
mkdir -p "$fake_bin"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'printf "%s\\n" "$@" >>"$FAKE_GITLEAKS_ARGS"' 'exit 0' >"$fake_bin/gitleaks"
chmod +x "$fake_bin/gitleaks"

FAKE_GITLEAKS_ARGS="$FIXTURE/args.txt" PATH="$fake_bin:$PATH" \
    "$CHECK_SCRIPT" --files-from "$FIXTURE/files.txt" --repo "$FIXTURE"

if [[ "$(grep -Fxc 'stdin' "$FIXTURE/args.txt")" -ne 2 ]]; then
    echo "FAIL: gitleaks-check.sh must scan with default and shared rules" >&2
    exit 1
fi
if ! rg -Fq -- '--redact' "$FIXTURE/args.txt"; then
    echo "FAIL: gitleaks-check.sh must redact findings" >&2
    exit 1
fi
if ! rg -Fq -- '--config' "$FIXTURE/args.txt" || ! rg -Fq -- '.gitleaks.toml' "$FIXTURE/args.txt"; then
    echo "FAIL: gitleaks-check.sh must use the shared gitleaks config" >&2
    exit 1
fi
if rg -Fq -- 'safe.txt' "$FIXTURE/args.txt"; then
    echo "FAIL: gitleaks-check.sh must pass file contents through stdin without exposing paths as tool arguments" >&2
    exit 1
fi

if "$CHECK_SCRIPT" --repo "$FIXTURE" >/dev/null 2>"$FIXTURE/usage.err"; then
    echo "FAIL: gitleaks-check.sh must require --files-from" >&2
    exit 1
fi

echo "PASS"
