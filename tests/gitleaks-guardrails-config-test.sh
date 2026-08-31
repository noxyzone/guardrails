#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUALITY_GATES="$ROOT_DIR/.github/workflows/quality-gates.yml"
CHANGE_DETECTION="$ROOT_DIR/scripts/quality-gate-change-detection.sh"
TARGETS="$ROOT_DIR/scripts/quality-gate-targets.sh"
CHECK_SCRIPT="$ROOT_DIR/scripts/gitleaks-check.sh"

if [[ ! -x "$CHECK_SCRIPT" ]]; then
    echo "FAIL: gitleaks-check.sh must exist and be executable" >&2
    exit 1
fi

# shellcheck disable=SC2016
for required in \
    'gitleaks: ${{ steps.changed.outputs.gitleaks }}' \
    'needs.detect_changes.outputs.gitleaks == '\''true'\''' \
    'gh release download v8.30.1 --repo gitleaks/gitleaks --pattern gitleaks_8.30.1_linux_x64.tar.gz' \
    '551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb' \
    '.guardrails/scripts/gitleaks-check.sh --files-from "$gitleaks_files" --repo "$GITHUB_WORKSPACE"'; do
    if ! rg -Fq "$required" "$QUALITY_GATES"; then
        echo "FAIL: QualityGates must wire gitleaks rule: $required" >&2
        exit 1
    fi
done

if rg -q 'secretlint' "$QUALITY_GATES"; then
    echo "FAIL: QualityGates must not retain SecretLint after gitleaks replacement" >&2
    exit 1
fi

if ! rg -q 'gitleaks="\$\(has_targets gitleaks\)"' "$CHANGE_DETECTION"; then
    echo "FAIL: change detection must derive gitleaks from shared targets" >&2
    exit 1
fi

if ! rg -q 'any \| gitleaks \| typos\) return 0' "$TARGETS"; then
    echo "FAIL: shared targets must enable gitleaks for every filtered path" >&2
    exit 1
fi

echo "PASS"
