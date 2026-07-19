#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/treefmt-check.sh"

if ! rg -q 'TREEFMT_TIMEOUT_SECONDS:-60' "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must use the shared 60s default timeout" >&2
	exit 1
fi

if ! rg -q 'treefmt_walk="git"' "$SCRIPT" || ! rg -q 'treefmt_walk="filesystem"' "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must use filesystem walking for explicit file paths" >&2
	exit 1
fi

if ! rg -q "treefmt --tree-root \"\\\$repo_root\" --walk \"\\\$treefmt_walk\" --excludes 'node_modules/\\*\\*' --excludes '\\.guardrails/\\*\\*' --config-file \"\\\$treefmt_config_path\"" "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must pin treefmt root and exclude generated dependency trees" >&2
	exit 1
fi

if ! rg -q "treefmt --ci --tree-root \"\\\$repo_root\" --walk \"\\\$treefmt_walk\" --excludes 'node_modules/\\*\\*' --excludes '\\.guardrails/\\*\\*' --config-file \"\\\$treefmt_config_path\"" "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must pin CI root and exclude generated dependency trees" >&2
	exit 1
fi

if ! rg -q "git diff --stat >&2" "$SCRIPT" || ! rg -q "git diff -- >&2" "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must print formatter diffs when CI mode detects changes" >&2
	exit 1
fi

if ! rg -q 'mktemp "\$\{TMPDIR:-/tmp\}/treefmt-noswift\.XXXXXX\.toml"' "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must keep generated treefmt config outside the repo tree" >&2
	exit 1
fi

echo "PASS"
