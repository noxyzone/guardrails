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

# 旧配布物の名称だけでは、人が保守する通常ファイルを検査から外さない。
ordinary_paths=(
    ".agents/skills/aidlc-fixture/SKILL.md"
    ".codex/agents/aidlc-fixture/notes.md"
    ".codex/aidlc-common/notes.md"
    ".codex/hooks/aidlc-fixture.sh"
    ".codex/knowledge/aidlc-fixture/notes.md"
    ".codex/scopes/aidlc-fixture/notes.md"
    ".codex/sensors/aidlc-fixture.sh"
    ".codex/tools/aidlc-fixture.sh"
    ".codex/tools/data/notes.md"
)
for ordinary_path in "${ordinary_paths[@]}"; do
    mkdir -p "$TMP_ROOT/$(dirname "$ordinary_path")"
    printf '%s%s\n' 't' 'eh' >"$TMP_ROOT/$ordinary_path"
    if (cd "$TMP_ROOT" && typos --isolated --force-exclude --config "$CONFIG" "$ordinary_path" >/dev/null); then
        echo "FAIL: obsolete path exclusions must not hide ordinary files: $ordinary_path" >&2
        exit 1
    fi
done

# 保持中の履歴は引き続き除外し、データの整形や削除を要求しない。
mkdir -p "$TMP_ROOT/aidlc/spaces/history"
printf '%s%s\n' 't' 'eh' >"$TMP_ROOT/aidlc/spaces/history/retained.md"
if ! (cd "$TMP_ROOT" && typos --isolated --force-exclude --config "$CONFIG" aidlc/spaces/history/retained.md >/dev/null); then
    echo "FAIL: retained history must remain excluded" >&2
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

# 公開Sumのregex内で分割された識別子は、同名configにだけ限定する。
checksum_literal="$(rg '^regexes = .*Mv2mzuHuZuY2' "$ROOT_DIR/gitleaks-default.toml")"
printf '%s\n' "$checksum_literal" >"$TMP_ROOT/gitleaks-default.toml"
if ! typos --isolated --force-exclude --config "$CONFIG" "$TMP_ROOT/gitleaks-default.toml" >/dev/null; then
    echo "FAIL: sourced checksum literal must be allowed in its exact config filename" >&2
    exit 1
fi
printf '%s\n' "$checksum_literal" >"$TMP_ROOT/other-config.toml"
if typos --isolated --force-exclude --config "$CONFIG" "$TMP_ROOT/other-config.toml" >/dev/null; then
    echo "FAIL: checksum identifier allowance must not apply to other filenames" >&2
    exit 1
fi
printf '%s%s\n' 'N' 'd' >"$TMP_ROOT/gitleaks-default.toml"
if typos --isolated --force-exclude --config "$CONFIG" "$TMP_ROOT/gitleaks-default.toml" >/dev/null; then
    echo "FAIL: checksum identifier allowance must not allow ordinary misspellings" >&2
    exit 1
fi
printf '%s\n# %s%s\n' "$checksum_literal" 't' 'eh' >"$TMP_ROOT/gitleaks-default.toml"
if typos --isolated --force-exclude --config "$CONFIG" "$TMP_ROOT/gitleaks-default.toml" >/dev/null; then
    echo "FAIL: checksum config must still reject a different typo in the same file" >&2
    exit 1
fi

echo "PASS"
