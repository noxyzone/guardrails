#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="$ROOT_DIR/scripts/quality-gate-path-filter.sh"
WORKFLOW="$ROOT_DIR/.github/workflows/quality-gates.yml"

actual="$({
	printf '%s\n' \
		'.agents/skills/.system/imagegen/SKILL.md' \
		'.agents/skills/aidlc-build-and-test/SKILL.md' \
		'.codex/agents/aidlc-quality-agent.toml' \
		'.codex/aidlc-common/conductor.md' \
		'.codex/hooks/aidlc-audit.ts' \
		'.codex/knowledge/aidlc-review/knowledge.md' \
		'.codex/scopes/aidlc-runtime.toml' \
		'.codex/sensors/aidlc-reviewer.ts' \
		'.codex/tools/aidlc-state.ts' \
		'.codex/tools/data/stage-graph.json' \
		'aidlc/spaces/default/memory/org.md' \
		'.codex/hooks.json' \
		'.codex/rules/default.rules' \
		'scripts/aidlc-ts-check.sh'
} | "$FILTER")"
expected="$(printf '%s\n' '.codex/hooks.json' '.codex/rules/default.rules' 'scripts/aidlc-ts-check.sh')"
if [[ "$actual" != "$expected" ]]; then
	printf 'FAIL: managed artifact filter output mismatch\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
	exit 1
fi

null_actual="$({
	printf '%s\0' \
		'.codex/tools/aidlc-state.ts' \
		$'--ignore-pattern=evil.cjs\nkept.ts' \
		'scripts/aidlc-ts-check.sh'
} | "$FILTER" --null | od -An -tx1 | tr -d ' \n')"
null_expected="$(printf '%s\0' $'--ignore-pattern=evil.cjs\nkept.ts' 'scripts/aidlc-ts-check.sh' | od -An -tx1 | tr -d ' \n')"
if [[ "$null_actual" != "$null_expected" ]]; then
	printf 'FAIL: null-delimited managed artifact filter output mismatch\nexpected: %s\nactual: %s\n' "$null_expected" "$null_actual" >&2
	exit 1
fi

# These assertions intentionally preserve child-shell variables as literal workflow text.
# shellcheck disable=SC2016
for required in \
	'.guardrails/scripts/quality-gate-targets.sh' \
	'xargs -0 -r "$GITHUB_WORKSPACE/.guardrails/.github/quality-gates/node_modules/.bin/secretlint"' \
	'xargs -0 -r "$GITHUB_WORKSPACE/.guardrails/.github/quality-gates/node_modules/.bin/eslint"' \
	'xargs -0 -r shellcheck --' \
	'xargs -0 swiftlint lint' \
	'xargs -0 swiftformat --lint'; do
	if ! rg -Fq "$required" "$WORKFLOW"; then
		printf 'FAIL: QualityGates does not preserve safe file arguments: %s\n' "$required" >&2
		exit 1
	fi
done

# shellcheck disable=SC2016
for forbidden in \
	'printf '\''%s\n'\'' "$files" | xargs' \
	'printf '\''%s\n'\'' "$swift_files" | xargs' \
	'git ls-files -z'; do
	if rg -Fq "$forbidden" "$WORKFLOW"; then
		printf 'FAIL: QualityGates contains unsafe newline-delimited file arguments: %s\n' "$forbidden" >&2
		exit 1
	fi
done

for script in "$ROOT_DIR/scripts/quality-gate-targets.sh" "$ROOT_DIR/scripts/text-spacing-check.sh" "$ROOT_DIR/scripts/typos-check.sh" "$ROOT_DIR/scripts/treefmt-check.sh"; do
	if ! rg -q 'quality-gate-path-filter\.sh' "$script"; then
		printf 'FAIL: managed artifact filtering is not wired into %s\n' "$script" >&2
		exit 1
	fi
done

echo "PASS"
