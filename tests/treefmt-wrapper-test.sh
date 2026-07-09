#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/treefmt-check.sh"

if ! rg -q 'treefmt --tree-root "\$repo_root" --config-file "\$treefmt_config_path"' "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must pin treefmt tree root to --repo" >&2
	exit 1
fi

if ! rg -q 'treefmt --ci --tree-root "\$repo_root" --config-file "\$treefmt_config_path"' "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must pin CI tree root to --repo" >&2
	exit 1
fi

if ! rg -q 'mktemp "\$\{TMPDIR:-/tmp\}/treefmt-noswift\.XXXXXX\.toml"' "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must keep generated treefmt config outside the repo tree" >&2
	exit 1
fi

echo "PASS"
