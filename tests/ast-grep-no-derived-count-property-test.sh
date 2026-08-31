#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULE="$ROOT_DIR/ast-grep/no-derived-count-property.yml"
FIXTURE_DIR="$ROOT_DIR/tests/fixtures/no-derived-count-property"

if ! command -v ast-grep >/dev/null 2>&1; then
    echo "error: required command not found: ast-grep" >&2
    exit 127
fi

scan_output() {
    local fixture="$1"
    ast-grep scan -r "$RULE" --report-style short --stdin <"$FIXTURE_DIR/$fixture" 2>/dev/null || true
}

assert_detects() {
    local fixture="$1"
    local output
    output="$(scan_output "$fixture")"
    if ! printf '%s' "$output" | rg -q 'no-derived-count-property'; then
        echo "FAIL: expected $fixture to trigger no-derived-count-property" >&2
        exit 1
    fi
}

assert_clean() {
    local fixture="$1"
    local output
    output="$(scan_output "$fixture")"
    if printf '%s' "$output" | rg -q 'no-derived-count-property'; then
        echo "FAIL: expected $fixture not to trigger no-derived-count-property" >&2
        exit 1
    fi
}

# 検出例: TCA StateでArrayの直後にCount付きの格納Intプロパティを持つ
assert_detects detect.swift.fixture

# 非検出例: 計算プロパティは対象外
assert_clean non_detect_computed_property.swift

# 非検出例: Arrayに隣接しない格納Intプロパティは対象外
assert_clean non_detect_not_adjacent.swift

# 非検出例: Count接尾辞を持たない格納Intプロパティは対象外
assert_clean non_detect_unrelated_int.swift

# 非検出例: TCAのState以外の構造体は対象外
assert_clean non_detect_non_state_struct.swift

# 非検出例: Reducer内の一時計算（ローカル変数）は対象外
assert_clean non_detect_reducer_temp_calc.swift

# 非検出例: View側の文字列整形は対象外
assert_clean non_detect_view_formatting.swift

echo "PASS"
