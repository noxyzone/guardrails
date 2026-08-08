#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT_DIR/typos.toml"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

for required in \
	'"Vendor/"' \
	'extend-ignore-re = \[' \
	'"\[0-9a-f\]\{7,40\}"' \
	'\[default.extend-identifiers\]' \
	'ND = "ND"'; do
	if ! rg -q "$required" "$CONFIG"; then
		echo "FAIL: typos.toml must keep false-positive exclusions: $required" >&2
		exit 1
	fi
done

printf 'persiyanov/herdr-reviewr\n' >"$TMP_ROOT/reviewr.txt"
if ! typos --config "$CONFIG" "$TMP_ROOT/reviewr.txt" >/dev/null; then
	echo "FAIL: typos.toml must allow the reviewr product name" >&2
	exit 1
fi

echo "PASS"
