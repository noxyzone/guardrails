#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUALITY_GATES="$ROOT_DIR/.github/workflows/quality-gates.yml"
CHANGE_DETECTION="$ROOT_DIR/scripts/quality-gate-change-detection.sh"
TARGETS="$ROOT_DIR/scripts/quality-gate-targets.sh"
CONFIG="$ROOT_DIR/.zizmor.yml"

if [[ ! -f "$CONFIG" ]]; then
    echo "FAIL: shared zizmor config .zizmor.yml is required" >&2
    exit 1
fi

if ! rg -Fq '"noxyzone/guardrails/*": ref-pin' "$CONFIG"; then
    echo "FAIL: .zizmor.yml must allow noxyzone/guardrails to track main" >&2
    exit 1
fi
if ! rg -Fq '"*": hash-pin' "$CONFIG"; then
    echo "FAIL: .zizmor.yml must keep hash-pin as the default policy" >&2
    exit 1
fi

# shellcheck disable=SC2016
for required in \
    'zizmor: ${{ steps.changed.outputs.zizmor }}' \
    'needs.detect_changes.outputs.zizmor == '\''true'\''' \
    'gh release download v1.29.0 --repo zizmorcore/zizmor --pattern zizmor-x86_64-unknown-linux-gnu.tar.gz' \
    'dd96df044a6e8538d5f423790f453bdd03d49e5b2bcc38214acc41a2f1297839' \
    'xargs -0 -r zizmor --offline --no-progress --config .guardrails/.zizmor.yml --'; do
    if ! rg -Fq "$required" "$QUALITY_GATES"; then
        echo "FAIL: QualityGates must wire zizmor rule: $required" >&2
        exit 1
    fi
done

if ! rg -q 'zizmor="\$\(has_targets zizmor\)"' "$CHANGE_DETECTION"; then
    echo "FAIL: change detection must derive zizmor from shared targets" >&2
    exit 1
fi

if ! rg -Fq 'actionlint | zizmor) [[ "$path" =~ ^\.github/workflows/[^/]+\.(yaml|yml)$ ]]' "$TARGETS"; then
    echo "FAIL: shared targets must scope zizmor to direct workflow files" >&2
    exit 1
fi

echo "PASS"
