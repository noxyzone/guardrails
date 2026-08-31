#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT_DIR/.zizmor.yml"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

command -v zizmor >/dev/null || {
    echo "FAIL: zizmor is required for this real-tool test" >&2
    exit 1
}
zizmor_version="$(zizmor --version)"
[[ "$zizmor_version" == "zizmor 1.29.0" ]] || {
    echo "FAIL: zizmor version must be 1.29.0, got $zizmor_version" >&2
    exit 1
}

mkdir -p "$FIXTURE/.github/workflows"
cat >"$FIXTURE/.github/workflows/unpinned.yml" <<'YML'
name: Unpinned
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
YML
cat >"$FIXTURE/.github/workflows/guardrails-main.yml" <<'YML'
name: Guardrails Main
on: push
permissions:
  contents: read
jobs:
  quality-gates:
    uses: noxyzone/guardrails/.github/workflows/quality-gates.yml@main
YML
cat >"$FIXTURE/.github/workflows/pinned.yml" <<'YML'
name: Pinned
on: push
permissions:
  contents: read
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Checkout repository
        uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803
        with:
          persist-credentials: false
      - name: Echo
        run: echo hello
YML

if zizmor --offline --no-progress --config "$CONFIG" "$FIXTURE/.github/workflows/unpinned.yml" >/dev/null 2>&1; then
    echo "FAIL: zizmor must fail unpinned GitHub Actions uses" >&2
    exit 1
fi
zizmor --offline --no-progress --config "$CONFIG" "$FIXTURE/.github/workflows/guardrails-main.yml" >/dev/null || {
    echo "FAIL: zizmor must accept noxyzone/guardrails reusable workflows at main" >&2
    exit 1
}
zizmor --offline --no-progress --config "$CONFIG" "$FIXTURE/.github/workflows/pinned.yml" >/dev/null || {
    echo "FAIL: zizmor must accept hash-pinned checkout with persist-credentials false" >&2
    exit 1
}

echo "PASS"
