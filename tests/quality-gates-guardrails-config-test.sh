#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/quality-gates.yml"

# shellcheck disable=SC2016
for required in \
	'guardrails-ref:' \
	'required: true' \
	'ref: \$\{\{ inputs\.guardrails-ref \}\}' \
	'changed_files="\$\(git diff --name-only --diff-filter=ACMRT "\$base_sha" "\$head_sha"\)"' \
	'ast_grep: \$\{\{ steps\.changed\.outputs\.ast_grep \}\}' \
	'ast_grep="\$\(bool_for '\''\\\.swift\$'\''\)"' \
	'printf '\''ast_grep=%s\\n'\'' "\$ast_grep"' \
	'brew install ast-grep swiftformat swiftlint' \
	'GH_TOKEN: \$\{\{ github\.token \}\}' \
	'gh release download v2\.3\.0 --repo numtide/treefmt --pattern treefmt_2\.3\.0_linux_amd64\.tar\.gz --output treefmt\.tar\.gz' \
	'gh release download v3\.13\.1 --repo mvdan/sh --pattern shfmt_v3\.13\.1_linux_amd64 --output shfmt' \
	'gh release download 0\.10\.0 --repo tamasfe/taplo --pattern taplo-linux-x86_64\.gz --output taplo\.gz' \
	'prettier@3\.9\.4' \
	'@prettier/plugin-xml@3\.4\.2' \
	'prettier-plugin-go-template@0\.0\.15' \
	'prettier-plugin-sh@0\.18\.1' \
	'prettier-plugin-toml@2\.0\.6' \
	'needs\.detect_changes\.outputs\.ast_grep == '\''true'\''' \
	'ast-grep scan --config \.guardrails/sgconfig\.yml --report-style short'; do
	if ! rg -q "$required" "$WORKFLOW"; then
		echo "FAIL: QualityGates must wire ast-grep rule: $required" >&2
		exit 1
	fi
done

if rg -q 'git diff --name-only --diff-filter=ACMRT .* \|\| true' "$WORKFLOW"; then
	echo "FAIL: QualityGates must not swallow git diff failures in change detection" >&2
	exit 1
fi

echo "PASS"
