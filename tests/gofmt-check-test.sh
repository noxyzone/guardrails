#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT_DIR/scripts/gofmt-check.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

repo="$FIXTURE/repo"
mkdir -p "$repo/cmd/app"
printf 'package main\n\nfunc main() {}\n' >"$repo/cmd/app/good.go"
printf 'package main\nfunc main(){println("bad")}\n' >"$repo/cmd/app/bad.go"
printf 'cmd/app/good.go\0' >"$FIXTURE/good.bin"
printf 'cmd/app/bad.go\0' >"$FIXTURE/bad.bin"

"$CHECK" --repo "$repo" --files-from "$FIXTURE/good.bin" >/dev/null ||
    fail "gofmt-check rejected formatted Go"

if "$CHECK" --repo "$repo" --files-from "$FIXTURE/bad.bin" >"$FIXTURE/bad.stdout" 2>"$FIXTURE/bad.stderr"; then
    fail "gofmt-check accepted unformatted Go"
fi
if [[ -s "$FIXTURE/bad.stdout" ]]; then
    fail "gofmt-check must not emit source or path details to stdout"
fi
grep -F 'cmd/app/bad.go' "$FIXTURE/bad.stderr" >/dev/null ||
    fail "gofmt-check must identify the unformatted file"
if [[ "$(<"$repo/cmd/app/bad.go")" != $'package main\nfunc main(){println("bad")}' ]]; then
    fail "gofmt-check modified the source file"
fi

printf 'PASS: gofmt check\n'
