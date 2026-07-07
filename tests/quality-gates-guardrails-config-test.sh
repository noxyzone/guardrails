#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/quality-gates.yml"

# shellcheck disable=SC2016
for required in \
	'ast_grep: \$\{\{ steps\.changed\.outputs\.ast_grep \}\}' \
	'ast_grep="\$\(bool_for '\''\\\.swift\$'\''\)"' \
	'printf '\''ast_grep=%s\\n'\'' "\$ast_grep"' \
	'brew install ast-grep swiftformat swiftlint' \
	'needs\.detect_changes\.outputs\.ast_grep == '\''true'\''' \
	'ast-grep scan --config \.guardrails/sgconfig\.yml --report-style short'; do
	if ! rg -q "$required" "$WORKFLOW"; then
		echo "FAIL: QualityGates must wire ast-grep rule: $required" >&2
		exit 1
	fi
done

echo "PASS"
