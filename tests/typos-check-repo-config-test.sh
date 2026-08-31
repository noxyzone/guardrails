#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_SCRIPT="$ROOT_DIR/scripts/typos-check.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

repository="$FIXTURE/repository"
snapshot="$FIXTURE/snapshot"
git -C "$FIXTURE" init -q repository
printf '%s\n' '[files]' 'extend-exclude = ["*.provisionprofile"]' >"$repository/.typos.toml"
git -C "$repository" add -- .typos.toml

mkdir -p "$snapshot"
ln -s "$repository/.git" "$snapshot/.git"
printf '%s%s\n' 'T' 'ye' >"$snapshot/signing.provisionprofile"
printf '%s\n' 'signing.provisionprofile' >"$snapshot/files.txt"

"$CHECK_SCRIPT" --files-from "$snapshot/files.txt" --repo "$snapshot" >/dev/null || {
    echo "FAIL: staged repo-local Typos config must exclude fixed-format provisioning profiles" >&2
    exit 1
}

printf '%s%s\n' 'T' 'ye' >"$snapshot/regular.txt"
printf '%s\n' 'regular.txt' >"$snapshot/files.txt"
if "$CHECK_SCRIPT" --files-from "$snapshot/files.txt" --repo "$snapshot" >/dev/null 2>&1; then
    echo "FAIL: repo-local Typos config must not suppress ordinary text findings" >&2
    exit 1
fi

echo "PASS"
