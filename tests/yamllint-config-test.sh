#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT_DIR/.yamllint.yml"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

for required in \
    'document-start: disable' \
    'line-length: disable' \
    'check-keys: false' \
    'max-spaces-inside: 1'; do
    if ! rg -q -- "$required" "$CONFIG"; then
        echo "FAIL: .yamllint.yml must keep relaxed rule: $required" >&2
        exit 1
    fi
done

# Prettier writes flow-style mappings with a single inner space; the config
# must not flag it (guardrails/treefmt.toml formats *.yaml/*.yml with Prettier).
printf 'items: [{ name: x }]\n' >"$TMP_ROOT/prettier-flow-style.yaml"
if ! yamllint --strict --config-file "$CONFIG" "$TMP_ROOT/prettier-flow-style.yaml" >/dev/null; then
    echo "FAIL: .yamllint.yml must accept Prettier's single-space flow style" >&2
    exit 1
fi

# A long embedded shell command line must not fail line-length.
printf 'run: %s\n' "$(printf 'x%.0s' $(seq 1 200))" >"$TMP_ROOT/long-line.yaml"
if ! yamllint --strict --config-file "$CONFIG" "$TMP_ROOT/long-line.yaml" >/dev/null; then
    echo "FAIL: .yamllint.yml must not enforce line-length" >&2
    exit 1
fi

# A duplicate mapping key is a real bug and must still be rejected.
printf 'a: 1\na: 2\n' >"$TMP_ROOT/duplicate-key.yaml"
if yamllint --strict --config-file "$CONFIG" "$TMP_ROOT/duplicate-key.yaml" >/dev/null; then
    echo "FAIL: .yamllint.yml must continue to reject duplicate mapping keys" >&2
    exit 1
fi

echo "PASS"
