#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/yamllint.yml"
QUALITY_GATES="$ROOT_DIR/.github/workflows/quality-gates.yml"
CHANGE_DETECTION="$ROOT_DIR/scripts/quality-gate-change-detection.sh"
TARGETS="$ROOT_DIR/scripts/quality-gate-targets.sh"
CHECK_SCRIPT="$ROOT_DIR/scripts/yamllint-check.sh"

if ! rg -q 'repository: noxyzone/guardrails' "$WORKFLOW"; then
    echo "FAIL: YAMLLint workflow must checkout noxyzone/guardrails" >&2
    exit 1
fi

if ! rg -q 'pipx install "yamllint==1\.38\.0"' "$WORKFLOW"; then
    echo "FAIL: YAMLLint workflow must pin the yamllint version" >&2
    exit 1
fi

if ! rg -q '\.guardrails/scripts/yamllint-check\.sh --changed --base "\$base_sha" --head "\$head_sha" --repo "\$GITHUB_WORKSPACE"' "$WORKFLOW"; then
    echo "FAIL: YAMLLint workflow must use shared yamllint-check.sh" >&2
    exit 1
fi

if ! rg -q 'fetch-depth: 0' "$WORKFLOW"; then
    echo "FAIL: YAMLLint workflow must checkout enough history for changed-file scope" >&2
    exit 1
fi

# shellcheck disable=SC2016
for required in \
    'yamllint: \$\{\{ steps\.changed\.outputs\.yamllint \}\}' \
    'needs\.detect_changes\.outputs\.yamllint == '\''true'\''' \
    'pipx install "yamllint==1\.38\.0"' \
    '\.guardrails/scripts/yamllint-check\.sh --files-from "\$yamllint_files" --repo "\$GITHUB_WORKSPACE"'; do
    if ! rg -q "$required" "$QUALITY_GATES"; then
        echo "FAIL: QualityGates must wire YAMLLint rule: $required" >&2
        exit 1
    fi
done

if ! rg -q 'yamllint="\$\(has_targets yamllint\)"' "$CHANGE_DETECTION"; then
    echo "FAIL: change detection must derive YAMLLint from shared targets" >&2
    exit 1
fi

if ! rg -q 'yamllint\) \[\[ "\$path" =~ \\\.\(yaml\|yml\)\$ && ! "\$path" =~ \^\\\.github/workflows/ \]\]' "$TARGETS"; then
    echo "FAIL: shared targets must scope YAMLLint to *.yaml/*.yml outside .github/workflows/" >&2
    exit 1
fi

if ! rg -q '\.github/workflows/\*' "$CHECK_SCRIPT"; then
    echo "FAIL: yamllint-check.sh must document the actionlint workflow exclusion" >&2
    exit 1
fi

echo "PASS"
