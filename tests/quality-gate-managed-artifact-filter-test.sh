#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="$ROOT_DIR/scripts/quality-gate-path-filter.sh"
WORKFLOW="$ROOT_DIR/.github/workflows/quality-gates.yml"

actual="$({
	printf '%s\n' \
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

for required in \
	'git ls-files | .guardrails/scripts/quality-gate-path-filter.sh | while' \
	'git ls-files | .guardrails/scripts/quality-gate-path-filter.sh | grep -E'; do
	if ! rg -Fq "$required" "$WORKFLOW"; then
		printf 'FAIL: QualityGates does not apply managed artifact filtering: %s\n' "$required" >&2
		exit 1
	fi
done

for script in "$ROOT_DIR/scripts/text-spacing-check.sh" "$ROOT_DIR/scripts/typos-check.sh" "$ROOT_DIR/scripts/treefmt-check.sh"; do
	if ! rg -q 'quality-gate-path-filter\.sh' "$script"; then
		printf 'FAIL: managed artifact filtering is not wired into %s\n' "$script" >&2
		exit 1
	fi
done

echo "PASS"
