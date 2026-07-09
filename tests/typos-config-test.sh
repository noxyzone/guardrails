#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT_DIR/typos.toml"

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

echo "PASS"
