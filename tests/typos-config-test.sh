#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT_DIR/typos.toml"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

for required in \
    '"Vendor/"' \
    'extend-ignore-re = \[' \
    '"\[0-9a-f\]\{7,40\}"' \
    '\[default.extend-identifiers\]' \
    'ND = "ND"'; do
    if ! rg -q "$required" "$CONFIG"; then
        echo "FAIL: typos.toml must keep false-positive exclusions: $required" >&2
        exit 1
    fi
done

printf 'reviewrは不採用。\n' >"$TMP_ROOT/standalone.md"
printf 'memex/reviewrは不採用。\n' >"$TMP_ROOT/slash-form.md"
printf 'persiyanov/herdr-reviewrは不採用。\n' >"$TMP_ROOT/full-selector.md"
for fixture_file in standalone.md slash-form.md full-selector.md; do
    if ! typos --isolated --force-exclude --config "$CONFIG" "$TMP_ROOT/$fixture_file" >/dev/null; then
        echo "FAIL: typos.toml must allow the reviewr product name: $fixture_file" >&2
        exit 1
    fi
done

printf '%s%s\n' 't' 'eh' >"$TMP_ROOT/known-typo.txt"
if [[ "$(cat "$TMP_ROOT/known-typo.txt")" != "$(printf '%s%s' 't' 'eh')" ]]; then
    echo "FAIL: known misspelling fixture content is malformed" >&2
    exit 1
fi
if typos --isolated --force-exclude --config "$CONFIG" "$TMP_ROOT/known-typo.txt" >/dev/null; then
    echo "FAIL: typos.toml must continue to reject known misspellings" >&2
    exit 1
fi

echo "PASS"
