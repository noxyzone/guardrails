#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/eslint.yml"
CONFIG="$ROOT_DIR/eslint.config.js"

node -c "$CONFIG"

if grep -q '^export default \[$' "$CONFIG"; then
	echo "FAIL: stale inline export default array remains in eslint.config.js" >&2
	exit 1
fi

if ! grep -q 'repository: noxyzone/guardrails' "$WORKFLOW"; then
	echo "FAIL: ESLint workflow must checkout noxyzone/guardrails" >&2
	exit 1
fi

if ! grep -q -- '--config .guardrails/eslint.config.js' "$WORKFLOW"; then
	echo "FAIL: ESLint workflow must use .guardrails/eslint.config.js" >&2
	exit 1
fi

if grep -q 'npx eslint$' "$WORKFLOW"; then
	echo "FAIL: ESLint workflow must not rely on local config lookup" >&2
	exit 1
fi

for pattern in '**/*.cjs' '**/*.{js,mjs}' '**/*.ts'; do
	if ! grep -Fq "$pattern" "$CONFIG"; then
		echo "FAIL: missing ESLint config pattern: $pattern" >&2
		exit 1
	fi
done

echo "PASS"
