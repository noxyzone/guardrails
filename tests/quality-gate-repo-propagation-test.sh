#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEXT_SPACING_CHECK="$ROOT_DIR/scripts/text-spacing-check.sh"
TYPOS_CHECK="$ROOT_DIR/scripts/typos-check.sh"
LLM_CLI_STREAM_CHECK="$ROOT_DIR/scripts/llm-cli-stream-check.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/.agents/skills/aidlc-fixture" "$FIXTURE/bin"
git -C "$FIXTURE" init -q
printf '%s\n' \
    '# aidlc-distribution-manifest-v1' \
    '# upstream-revision: 207db2ea65352ca89717d5970bef97825114bddf' \
    '.agents/skills/aidlc-fixture/managed.md' \
    '.agents/skills/aidlc-fixture/managed.sh' >"$FIXTURE/.aidlc-distribution-manifest"
printf '%s\n' 'あ A' >"$FIXTURE/.agents/skills/aidlc-fixture/managed.md"
# shellcheck disable=SC2016 # fixtureとして書き出すスクリプト本文であり、ここで展開してはならない
printf '%s\n' '#!/usr/bin/env bash' 'codex exec - <in | tee "$log_file"' >"$FIXTURE/.agents/skills/aidlc-fixture/managed.sh"
chmod +x "$FIXTURE/.agents/skills/aidlc-fixture/managed.sh"
printf '%s\n' '.agents/skills/aidlc-fixture/managed.md' >"$FIXTURE/managed-markdown-paths"
printf '%s\n' '.agents/skills/aidlc-fixture/managed.sh' >"$FIXTURE/managed-shell-paths"

# 旧配布manifestの除外はNZ-357で撤去済みである。manifestに記載されたpathも通常の
# 入力として、--repoがcurrent directory外を指す場合にそのrepositoryのfileを検査する。
if "$TEXT_SPACING_CHECK" --files-from "$FIXTURE/managed-markdown-paths" --repo "$FIXTURE" >"$FIXTURE/text-spacing.log" 2>&1; then
    echo "FAIL: text spacing must check legacy manifest paths in the --repo outside the current directory" >&2
    exit 1
fi
if ! grep -Fq '.agents/skills/aidlc-fixture/managed.md:1:' "$FIXTURE/text-spacing.log"; then
    echo "FAIL: text spacing must report the violation from the --repo file" >&2
    exit 1
fi

if "$LLM_CLI_STREAM_CHECK" --files-from "$FIXTURE/managed-shell-paths" --repo "$FIXTURE" >"$FIXTURE/llm-stream.log" 2>&1; then
    echo "FAIL: LLM stream check must check legacy manifest paths in the --repo outside the current directory" >&2
    exit 1
fi
if ! grep -Fq '.agents/skills/aidlc-fixture/managed.sh' "$FIXTURE/llm-stream.log"; then
    echo "FAIL: LLM stream check must report the violation from the --repo file" >&2
    exit 1
fi

# スタブはtyposが起動されたことと、--file-listで渡された検査対象を記録して失敗する。
# shellcheck disable=SC2016 # fixtureとして書き出すスクリプト本文であり、ここで展開してはならない
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' ': >"$TYPOS_ARGS_LOG"' 'while (($#)); do' '    if [[ "$1" == --file-list ]]; then cat "$2" >>"$TYPOS_ARGS_LOG"; fi' '    shift' 'done' 'exit 1' >"$FIXTURE/bin/typos"
chmod +x "$FIXTURE/bin/typos"
if TYPOS_ARGS_LOG="$FIXTURE/typos-args.log" PATH="$FIXTURE/bin:$PATH" "$TYPOS_CHECK" --files-from "$FIXTURE/managed-markdown-paths" --repo "$FIXTURE" >/dev/null 2>&1; then
    echo "FAIL: typos check must propagate the typos failure for legacy manifest paths" >&2
    exit 1
fi
if [[ ! -f "$FIXTURE/typos-args.log" ]] || ! grep -Fq 'managed.md' "$FIXTURE/typos-args.log"; then
    echo "FAIL: typos check must invoke typos with the legacy manifest path from --repo" >&2
    exit 1
fi

echo "PASS: quality-gate repo propagation"
