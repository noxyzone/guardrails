#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="$ROOT_DIR/scripts/quality-gate-path-filter.sh"
TARGETS="$ROOT_DIR/scripts/quality-gate-targets.sh"
WORKFLOW="$ROOT_DIR/.github/workflows/quality-gates.yml"

actual="$({
	printf '%s\n' \
		'.agents/skills/.system/imagegen/SKILL.md' \
		'.agents/skills/hatch-pet/SKILL.md' \
		'.agents/skills/openai-curated-build-run-debug/SKILL.md' \
		'.agents/skills/nocturnalzone-build-run-debug/SKILL.md' \
		'.agents/skills/openai-curatedness-build-run-debug/SKILL.md' \
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
} | "$FILTER" --repo /tmp)"
expected="$(printf '%s\n' \
	'.agents/skills/nocturnalzone-build-run-debug/SKILL.md' \
	'.agents/skills/openai-curatedness-build-run-debug/SKILL.md' \
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
	'scripts/aidlc-ts-check.sh')"
if [[ "$actual" != "$expected" ]]; then
	printf 'FAIL: managed artifact filter output mismatch\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
	exit 1
fi

null_actual="$({
	printf '%s\0' \
		'.agents/skills/hatch-pet/agents/openai.yaml' \
		'.agents/skills/openai-curated-build-run-debug/agents/openai.yaml' \
		'.agents/skills/nocturnalzone-build-run-debug/SKILL.md' \
		'.agents/skills/openai-curatedness-build-run-debug/SKILL.md' \
		'.codex/tools/aidlc-state.ts' \
		$'--ignore-pattern=evil.cjs\nkept.ts' \
		'scripts/aidlc-ts-check.sh'
} | "$FILTER" --repo /tmp --null | od -An -tx1 | tr -d ' \n')"
null_expected="$(printf '%s\0' \
	'.agents/skills/nocturnalzone-build-run-debug/SKILL.md' \
	'.agents/skills/openai-curatedness-build-run-debug/SKILL.md' \
	'.codex/tools/aidlc-state.ts' \
	$'--ignore-pattern=evil.cjs\nkept.ts' \
	'scripts/aidlc-ts-check.sh' | od -An -tx1 | tr -d ' \n')"
if [[ "$null_actual" != "$null_expected" ]]; then
	printf 'FAIL: null-delimited managed artifact filter output mismatch\nexpected: %s\nactual: %s\n' "$null_expected" "$null_actual" >&2
	exit 1
fi

# An AIDLC distribution manifest excludes only its exact official paths. It must
# not hide adjacent project-owned files merely because their names resemble
# packaged AIDLC paths.
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
git -C "$fixture" init -q
cat >"$fixture/.aidlc-distribution-manifest" <<'MANIFEST'
# aidlc-distribution-manifest-v1
# upstream-revision: 207db2ea65352ca89717d5970bef97825114bddf
.codex/config.toml
.codex/agents/aidlc-quality-agent.toml
MANIFEST
manifest_actual="$({
	printf '%s\n' \
		'.codex/config.toml' \
		'.codex/agents/aidlc-quality-agent.toml' \
		'.codex/agents/aidlc-project-agent.toml' \
		'aidlc/spaces/default/memory/org.md'
} | "$FILTER" --repo "$fixture")"
manifest_expected="$(printf '%s\n' \
	'.codex/agents/aidlc-project-agent.toml' \
	'aidlc/spaces/default/memory/org.md')"
if [[ "$manifest_actual" != "$manifest_expected" ]]; then
	printf 'FAIL: manifest filtering must exclude only exact distribution paths\nexpected:\n%s\nactual:\n%s\n' "$manifest_expected" "$manifest_actual" >&2
	exit 1
fi

mkdir -p \
	"$fixture/.agents/skills/hatch-pet" \
	"$fixture/.agents/skills/openai-curated-build-run-debug" \
	"$fixture/.agents/skills/nocturnalzone-build-run-debug" \
	"$fixture/.agents/skills/openai-curatedness-build-run-debug"
printf '%s\n' '公式 配布物の検査違反fixture' >"$fixture/.agents/skills/hatch-pet/SKILL.md"
printf '%s\n' '公式 配布物の検査違反fixture' >"$fixture/.agents/skills/openai-curated-build-run-debug/SKILL.md"
printf '%s\n' '自作スキルfixture' >"$fixture/.agents/skills/nocturnalzone-build-run-debug/SKILL.md"
printf '%s\n' '類似名fixture' >"$fixture/.agents/skills/openai-curatedness-build-run-debug/SKILL.md"
git -C "$fixture" add \
	.agents/skills/hatch-pet \
	.agents/skills/openai-curated-build-run-debug \
	.agents/skills/nocturnalzone-build-run-debug \
	.agents/skills/openai-curatedness-build-run-debug

# QualityGatesの共通対象収集を実際に通し、個別ignoreを持たない検査面も
# managed artifact filterで同じ境界になることを確認する。
quality_target_expected="$(printf '%s\0' \
	'.agents/skills/nocturnalzone-build-run-debug/SKILL.md' \
	'.agents/skills/openai-curatedness-build-run-debug/SKILL.md' |
	od -An -tx1 | tr -d ' \n')"
for kind in markdownlint secretlint typos text_spacing treefmt_non_swift; do
	quality_target_actual="$(
		"$TARGETS" --repo "$fixture" --all --kind "$kind" |
			od -An -tx1 | tr -d ' \n'
	)"
	if [[ "$quality_target_actual" != "$quality_target_expected" ]]; then
		printf 'FAIL: %s targets do not preserve the managed artifact boundary\nexpected: %s\nactual: %s\n' \
			"$kind" "$quality_target_expected" "$quality_target_actual" >&2
		exit 1
	fi
done

treefmt_excludes="$("$FILTER" --repo /tmp --treefmt-excludes)"
# shellcheck disable=SC2041 # 単一要素のglob文字列リテラルであり、コマンド実行ではない
for required_exclude in \
	'.agents/skills/.system/**' \
	'.agents/skills/hatch-pet/**' \
	'.agents/skills/openai-curated-*/**'; do
	if ! printf '%s\n' "$treefmt_excludes" | rg -Fxq -- "$required_exclude"; then
		printf 'FAIL: Treefmt excludes do not cover managed artifact path: %s\n' "$required_exclude" >&2
		exit 1
	fi
done

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
