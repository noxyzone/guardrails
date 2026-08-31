#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT_DIR/scripts/guardrails-main-ref-check.sh"
TRASH="/Users/noxy/nocturnalzone/scripts/workspace/nocturnalzone-trash.sh"
TMP_ROOT="$(mktemp -d)"

cleanup() {
    "$TRASH" "$TMP_ROOT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

repo="$TMP_ROOT/repo"
files_from="$TMP_ROOT/files.bin"
mkdir -p "$repo/.github/workflows"
printf '%s\0' '.github/workflows/guardrails.yml' >"$files_from"

cat >"$repo/.github/workflows/guardrails.yml" <<'YAML'
name: Guardrails
on: pull_request
jobs:
  quality-gates:
    uses: noxyzone/guardrails/.github/workflows/quality-gates.yml@main
YAML
"$CHECK" --repo "$repo" --files-from "$files_from" || fail 'main caller must pass'

cat >"$repo/.github/workflows/guardrails.yml" <<'YAML'
name: Guardrails
on: pull_request
jobs:
  quality-gates:
    uses: noxyzone/guardrails/.github/workflows/quality-gates.yml@0123456789abcdef0123456789abcdef01234567
YAML
if "$CHECK" --repo "$repo" --files-from "$files_from" >/dev/null 2>&1; then
    fail 'SHA-pinned guardrails caller must fail'
fi

cat >"$repo/.github/workflows/guardrails.yml" <<'YAML'
name: Guardrails
on: pull_request
jobs:
  quality-gates:
    uses: noxyzone/guardrails/.github/workflows/quality-gates.yml@main
    with:
      guardrails-ref: main
YAML
if "$CHECK" --repo "$repo" --files-from "$files_from" >/dev/null 2>&1; then
    fail 'guardrails-ref override must fail'
fi

printf '%s\0' 'README.md' >"$files_from"
printf '# Fixture\n' >"$repo/README.md"
"$CHECK" --repo "$repo" --files-from "$files_from" || fail 'non-workflow files must pass'

echo 'PASS: guardrails-main-ref-check'
