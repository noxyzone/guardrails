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
printf 'runnでscenario testを実行する。\n' >"$TMP_ROOT/runn.md"
printf 'Relace: Relace Search\n' >"$TMP_ROOT/relace.md"
for fixture_file in standalone.md slash-form.md full-selector.md runn.md relace.md; do
    if ! typos --isolated --force-exclude --config "$CONFIG" "$TMP_ROOT/$fixture_file" >/dev/null; then
        echo "FAIL: typos.toml must allow product names: $fixture_file" >&2
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

# 同名の固定oracleの記号列だけを許可し、同じfileの通常語と別名fileは検査する。
oracle_path=".agents/skills/nocturnalzone-evaluating-agent-models/references/refinement-semantic-oracles-v1.json"
mkdir -p "$TMP_ROOT/$(dirname "$oracle_path")"
lower_symbol="$(printf '%s%s' 'b' 'a')"
upper_symbol="$(printf '%s%s' 'B' 'A')"
printf '{"input":["W|%s","R|A|%s"]}\n' "$lower_symbol" "$upper_symbol" >"$TMP_ROOT/$oracle_path"
if ! (cd "$TMP_ROOT" && typos --isolated --force-exclude --config "$CONFIG" "$oracle_path" >/dev/null); then
    echo "FAIL: fixed semantic oracle symbols must be allowed for their exact filename" >&2
    exit 1
fi

printf '{"input":["W|%s","R|A|%s"]}\n' "$lower_symbol" "$upper_symbol" >"$TMP_ROOT/other-oracle.json"
if (cd "$TMP_ROOT" && typos --isolated --force-exclude --config "$CONFIG" other-oracle.json >/dev/null); then
    echo "FAIL: oracle symbol allowances must not apply to other filenames" >&2
    exit 1
fi

printf '{"description":"%s%s"}\n' 't' 'eh' >"$TMP_ROOT/$oracle_path"
if (cd "$TMP_ROOT" && typos --isolated --force-exclude --config "$CONFIG" "$oracle_path" >/dev/null); then
    echo "FAIL: the fixed oracle must continue to reject ordinary misspellings" >&2
    exit 1
fi

echo "PASS"
