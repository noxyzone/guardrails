#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUALITY_GATES="$ROOT_DIR/.github/workflows/quality-gates.yml"
CHANGE_DETECTION="$ROOT_DIR/scripts/quality-gate-change-detection.sh"
TARGETS="$ROOT_DIR/scripts/quality-gate-targets.sh"
CONFIG="$ROOT_DIR/.oxlintrc.json"

if [[ -f "$ROOT_DIR/.github/workflows/eslint.yml" ]]; then
    echo "FAIL: eslint.yml must be removed after Oxlint replacement" >&2
    exit 1
fi
if [[ -f "$ROOT_DIR/eslint.config.js" ]]; then
    echo "FAIL: eslint.config.js must be removed after Oxlint replacement" >&2
    exit 1
fi
if [[ -f "$ROOT_DIR/tests/eslint-guardrails-config-test.sh" ]]; then
    echo "FAIL: eslint-guardrails-config-test.sh must be removed after Oxlint replacement" >&2
    exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
    echo "FAIL: shared Oxlint config .oxlintrc.json is required" >&2
    exit 1
fi

for required_rule in \
    '"no-unused-vars": "error"' \
    '"typescript/no-explicit-any": "error"' \
    '"typescript/ban-ts-comment": "error"' \
    '"typescript/no-wrapper-object-types": "error"'; do
    if ! rg -Fq "$required_rule" "$CONFIG"; then
        echo "FAIL: .oxlintrc.json must pin TypeScript recommended-equivalent rule: $required_rule" >&2
        exit 1
    fi
done

if ! rg -Fq '"correctness": "error"' "$CONFIG"; then
    echo "FAIL: .oxlintrc.json must enable correctness as error" >&2
    exit 1
fi

# shellcheck disable=SC2016
for required in \
    'oxlint: ${{ steps.changed.outputs.oxlint }}' \
    'needs.detect_changes.outputs.oxlint == '\''true'\''' \
    'gh release download apps_v1.65.0 --repo oxc-project/oxc --pattern oxlint-x86_64-unknown-linux-gnu.tar.gz' \
    '3ee40ecd4355369c8f5b58ad3a9b6de6d0f048c2f23b17b806c6ae7bffda3896' \
    'xargs -0 -r oxlint -c .guardrails/.oxlintrc.json --'; do
    if ! rg -Fq "$required" "$QUALITY_GATES"; then
        echo "FAIL: QualityGates must wire Oxlint rule: $required" >&2
        exit 1
    fi
done

if rg -q 'eslint' "$QUALITY_GATES"; then
    echo "FAIL: QualityGates must not retain ESLint after Oxlint replacement" >&2
    exit 1
fi

if ! rg -q 'oxlint="\$\(has_targets oxlint\)"' "$CHANGE_DETECTION"; then
    echo "FAIL: change detection must derive Oxlint from shared targets" >&2
    exit 1
fi

if ! rg -Fq 'oxlint) [[ "$path" =~ \.(cjs|js|mjs|ts|tsx)$ ]]' "$TARGETS"; then
    echo "FAIL: shared targets must scope Oxlint to JS/TS files" >&2
    exit 1
fi

echo "PASS"
