#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="$ROOT_DIR/scripts/quality-gate-path-filter.sh"
TARGETS="$ROOT_DIR/scripts/quality-gate-targets.sh"
WORKFLOW="$ROOT_DIR/.github/workflows/quality-gates.yml"

# 廃止optionも既存の不正引数・mode排他と同じく終了code2で拒否する。
for invalid in --manifest-paths --unknown --repo --null --treefmt-excludes; do
    args=("$invalid")
    case "$invalid" in
    --null) args+=(--treefmt-excludes) ;;
    --treefmt-excludes) args+=(--null) ;;
    esac
    if "$FILTER" "${args[@]}" </dev/null >/dev/null 2>&1; then
        printf 'FAIL: invalid arguments must be rejected: %s\n' "${args[*]}" >&2
        exit 1
    else
        status=$?
        if [[ "$status" != 2 ]]; then
            printf 'FAIL: invalid arguments must exit 2, got %s: %s\n' "$status" "${args[*]}" >&2
            exit 1
        fi
    fi
done

actual="$({
    printf '%s\n' \
        '.agents/skills/.system/imagegen/SKILL.md' \
        'bin/tool' \
        '.github/quality-gates/node_modules/package/index.js' \
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
        '.agents/skills/openai-curated-build-run-debug/agents/openai.yaml' \
        '.agents/skills/.system/imagegen/SKILL.md' \
        'bin/tool' \
        '.github/quality-gates/node_modules/package/index.js' \
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

# 旧manifestの内容によらず、一般の入力pathはそのまま検査対象になる。
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
git -C "$fixture" init -q
if "$FILTER" --repo "$fixture/missing" </dev/null >/dev/null 2>&1; then
    printf 'FAIL: nonexistent repository path must be rejected\n' >&2
    exit 1
fi
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
    '.codex/config.toml' \
    '.codex/agents/aidlc-quality-agent.toml' \
    '.codex/agents/aidlc-project-agent.toml' \
    'aidlc/spaces/default/memory/org.md')"
if [[ "$manifest_actual" != "$manifest_expected" ]]; then
    printf 'FAIL: legacy manifest paths must remain ordinary inputs\nexpected:\n%s\nactual:\n%s\n' "$manifest_expected" "$manifest_actual" >&2
    exit 1
fi

# 壊れたheader・revision・pathでもmanifestを読まず、各modeの出力を変えない。
manifest_excludes="$("$FILTER" --repo "$fixture" --treefmt-excludes)"
default_actual="$(cd "$fixture" && printf '%s\n' "$manifest_expected" | "$FILTER")"
if [[ "$default_actual" != "$manifest_expected" ]]; then
    printf 'FAIL: default repository resolution must preserve ordinary paths\n' >&2
    exit 1
fi
printf '%s\n' 'invalid header' '# upstream-revision: invalid' '../unsafe*' >"$fixture/.aidlc-distribution-manifest"
for mode in lines null treefmt-excludes; do
    case "$mode" in
    lines)
        malformed_actual="$(printf '%s\n' "$manifest_expected" | "$FILTER" --repo "$fixture")"
        malformed_expected="$manifest_expected"
        ;;
    null)
        malformed_actual="$(printf '%s\0' '.codex/config.toml' | "$FILTER" --repo "$fixture" --null | od -An -tx1 | tr -d ' \n')"
        malformed_expected="$(printf '%s\0' '.codex/config.toml' | od -An -tx1 | tr -d ' \n')"
        ;;
    treefmt-excludes)
        malformed_actual="$("$FILTER" --repo "$fixture" --treefmt-excludes)"
        malformed_expected="$manifest_excludes"
        ;;
    esac
    if [[ "$malformed_actual" != "$malformed_expected" ]]; then
        printf 'FAIL: malformed legacy manifest affects %s output\n' "$mode" >&2
        exit 1
    fi
done

mkdir -p \
    "$fixture/.agents/skills/openai-curated-build-run-debug" \
    "$fixture/.agents/skills/nocturnalzone-build-run-debug" \
    "$fixture/.agents/skills/openai-curatedness-build-run-debug"
printf '%s\n' '公式 配布物の検査違反fixture' >"$fixture/.agents/skills/openai-curated-build-run-debug/SKILL.md"
printf '%s\n' '自作スキルfixture' >"$fixture/.agents/skills/nocturnalzone-build-run-debug/SKILL.md"
printf '%s\n' '類似名fixture' >"$fixture/.agents/skills/openai-curatedness-build-run-debug/SKILL.md"
git -C "$fixture" add \
    .agents/skills/openai-curated-build-run-debug \
    .agents/skills/nocturnalzone-build-run-debug \
    .agents/skills/openai-curatedness-build-run-debug

# QualityGatesの共通対象収集を実際に通し、個別ignoreを持たない検査面も
# managed artifact filterで同じ境界になることを確認する。
quality_target_expected="$(printf '%s\0' \
    '.agents/skills/nocturnalzone-build-run-debug/SKILL.md' \
    '.agents/skills/openai-curatedness-build-run-debug/SKILL.md' |
    od -An -tx1 | tr -d ' \n')"
for kind in markdownlint gitleaks typos text_spacing treefmt_non_swift; do
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

mkdir -p "$fixture/.github/workflows" "$fixture/.github/workflows/nested"
printf 'name: Project workflow\non: push\njobs: {}\n' >"$fixture/.github/workflows/project workflow.yml"
printf 'name: Nested workflow\non: push\njobs: {}\n' >"$fixture/.github/workflows/nested/outside.yaml"
git -C "$fixture" add -- .github/workflows
actionlint_target_expected="$(
    printf '%s\0' '.github/workflows/project workflow.yml' |
        od -An -tx1 | tr -d ' \n'
)"
actionlint_target_actual="$(
    "$TARGETS" --repo "$fixture" --staged --kind actionlint |
        od -An -tx1 | tr -d ' \n'
)"
if [[ "$actionlint_target_actual" != "$actionlint_target_expected" ]]; then
    printf 'FAIL: actionlint targets must include only direct workflow files with NUL-safe paths\nexpected: %s\nactual: %s\n' \
        "$actionlint_target_expected" "$actionlint_target_actual" >&2
    exit 1
fi

treefmt_excludes="$("$FILTER" --repo /tmp --treefmt-excludes)"
legacy_bash_treefmt_excludes="$(PATH=/usr/bin:/bin "$FILTER" --repo /tmp --treefmt-excludes)"
if [[ "$legacy_bash_treefmt_excludes" != "$treefmt_excludes" ]]; then
    printf 'FAIL: Treefmt excludes must support the system Bash\n' >&2
    exit 1
fi
expected_excludes="$(printf '%s\n' \
    '.agents/skills/.system/**' \
    '.agents/skills/openai-curated-*/**' \
    'bin/**' \
    '.github/quality-gates/node_modules/**')"
if [[ "$treefmt_excludes" != "$expected_excludes" || "$manifest_excludes" != "$expected_excludes" ]]; then
    printf 'FAIL: Treefmt excludes must contain exactly the four generic patterns\n' >&2
    exit 1
fi
# shellcheck disable=SC2041 # 単一要素のglob文字列リテラルであり、コマンド実行ではない
for required_exclude in \
    '.agents/skills/.system/**' \
    '.agents/skills/openai-curated-*/**' \
    'bin/**' \
    '.github/quality-gates/node_modules/**'; do
    if ! printf '%s\n' "$treefmt_excludes" | rg -Fxq -- "$required_exclude"; then
        printf 'FAIL: Treefmt excludes do not cover managed artifact path: %s\n' "$required_exclude" >&2
        exit 1
    fi
done

# These assertions intentionally preserve child-shell variables as literal workflow text.
# shellcheck disable=SC2016
for required in \
    '.guardrails/scripts/quality-gate-targets.sh' \
    'xargs -0 -r actionlint -shellcheck= -pyflakes=' \
    'xargs -0 -r oxlint -c .guardrails/.oxlintrc.json --' \
    'xargs -0 -r zizmor --offline --no-progress --config .guardrails/.zizmor.yml --' \
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
