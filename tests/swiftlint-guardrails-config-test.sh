#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/swiftlint.yml"
CONFIG="$ROOT_DIR/.swiftlint.yml"

if ! rg -q 'repository: noxyzone/guardrails' "$WORKFLOW"; then
	echo "FAIL: SwiftLint workflow must checkout noxyzone/guardrails" >&2
	exit 1
fi

if ! rg -q -- '--config .guardrails/.swiftlint.yml' "$WORKFLOW"; then
	echo "FAIL: SwiftLint workflow must use .guardrails/.swiftlint.yml" >&2
	exit 1
fi

if ! rg -q -- '--force-exclude' "$WORKFLOW"; then
	echo "FAIL: SwiftLint workflow must honor .swiftlint.yml excluded paths for explicit file arguments" >&2
	exit 1
fi

for excluded in "':!:DerivedData/**'" "':!:.build/**'" "':!:build/**'"; do
	if ! rg -Fq "$excluded" "$WORKFLOW"; then
		echo "FAIL: SwiftLint workflow must filter excluded path before invoking SwiftLint: $excluded" >&2
		exit 1
	fi
done

if rg -q -- '--strict' "$WORKFLOW"; then
	echo "FAIL: SwiftLint workflow must not block every warning; promote banned warnings to errors in .swiftlint.yml" >&2
	exit 1
fi

for rule in no_print_call no_try_optional; do
	if ! awk -v rule="$rule" '
		$0 ~ "^  " rule ":" { in_rule = 1; next }
		in_rule && /^  [^[:space:]][^:]*:/ { in_rule = 0 }
		in_rule && /^[[:space:]]+severity:[[:space:]]+error$/ { found = 1 }
		END { exit found ? 0 : 1 }
	' "$CONFIG"; then
		echo "FAIL: SwiftLint custom rule must remain error severity: $rule" >&2
		exit 1
	fi
done

echo "PASS"
