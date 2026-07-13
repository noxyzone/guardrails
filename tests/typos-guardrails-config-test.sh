#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/typos.yml"
QUALITY_GATES="$ROOT_DIR/.github/workflows/quality-gates.yml"
CONFIG="$ROOT_DIR/typos.toml"

if ! rg -q 'repository: noxyzone/guardrails' "$WORKFLOW"; then
	echo "FAIL: Typos workflow must checkout noxyzone/guardrails" >&2
	exit 1
fi

if ! rg -q 'gh release download v1\.48\.0 --repo crate-ci/typos' "$WORKFLOW"; then
	echo "FAIL: Typos workflow must pin typos CLI download" >&2
	exit 1
fi

if ! rg -q '\.guardrails/scripts/typos-check\.sh --changed --base "\$base_sha" --head "\$head_sha" --repo "\$GITHUB_WORKSPACE"' "$WORKFLOW"; then
	echo "FAIL: Typos workflow must use shared typos-check.sh" >&2
	exit 1
fi

if ! rg -q 'fetch-depth: 0' "$WORKFLOW"; then
	echo "FAIL: Typos workflow must checkout enough history for changed-file scope" >&2
	exit 1
fi

# shellcheck disable=SC2016
for required in \
	'typos: \$\{\{ steps\.changed\.outputs\.typos \}\}' \
	'typos="\$any"' \
	'needs\.detect_changes\.outputs\.typos == '\''true'\''' \
	'gh release download v1\.48\.0 --repo crate-ci/typos' \
	'\.guardrails/scripts/typos-check\.sh --changed --base "\$base_sha" --head "\$head_sha" --repo "\$GITHUB_WORKSPACE"'; do
	if ! rg -q "$required" "$QUALITY_GATES"; then
		echo "FAIL: QualityGates must wire Typos rule: $required" >&2
		exit 1
	fi
done

for excluded in \
	'".claude/cache/"' \
	'".claude/plans/"' \
	'".claude/plugins/"' \
	'".claude/projects/"' \
	'".claude/shell-snapshots/"' \
	'".claude/todos/"' \
	'".codex/cache/"' \
	'"artifacts/"' \
	'"contrib/"' \
	'"node_modules/"' \
	'"pipedream/html/"'; do
	if ! rg -Fq "$excluded" "$CONFIG"; then
		echo "FAIL: typos.toml must exclude generated or external path: $excluded" >&2
		exit 1
	fi
done

echo "PASS"
