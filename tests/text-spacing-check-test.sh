#!/usr/bin/env bash
set -euo pipefail

CHECK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/text-spacing-check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/violations" "$TMP/compliant"

cat >"$TMP/violations/spacing.md" <<'BAD'
日本語 A
A 日本語
BAD

cat >"$TMP/compliant/spacing.md" <<'GOOD'
日本語A
select · next
Enter to select · ↑/↓
GOOD

git -C "$TMP/violations" init -q
git -C "$TMP/violations" add -A
git -C "$TMP/compliant" init -q
git -C "$TMP/compliant" add -A

set +e
violation_output="$("$CHECK" --all --repo "$TMP/violations" 2>&1)"
violation_status=$?
set -e

if [ "$violation_status" -eq 0 ]; then
    echo "FAIL: 和欧間スペース違反を検出しても成功終了した" >&2
    echo "$violation_output" >&2
    exit 1
fi
printf '%s\n' "$violation_output" | grep -qF '日本語 A' || {
    echo "FAIL: 和→欧方向の違反が検出されていない" >&2
    echo "$violation_output" >&2
    exit 1
}
printf '%s\n' "$violation_output" | grep -qF 'A 日本語' || {
    echo "FAIL: 欧→和方向の違反が検出されていない" >&2
    echo "$violation_output" >&2
    exit 1
}

set +e
compliant_output="$("$CHECK" --all --repo "$TMP/compliant" 2>&1)"
compliant_status=$?
set -e

if [ "$compliant_status" -ne 0 ]; then
    echo "FAIL: 適合fixtureを誤検出した" >&2
    echo "$compliant_output" >&2
    exit 1
fi

printf 'PASS: text-spacing-check\n'
