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

if ! "$TEXT_SPACING_CHECK" --files-from "$FIXTURE/managed-markdown-paths" --repo "$FIXTURE"; then
    echo "FAIL: text spacing must exclude manifest paths when --repo points outside the current directory" >&2
    exit 1
fi

if ! "$LLM_CLI_STREAM_CHECK" --files-from "$FIXTURE/managed-shell-paths" --repo "$FIXTURE"; then
    echo "FAIL: LLM stream check must exclude manifest paths when --repo points outside the current directory" >&2
    exit 1
fi

printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'exit 1' >"$FIXTURE/bin/typos"
chmod +x "$FIXTURE/bin/typos"
if ! PATH="$FIXTURE/bin:$PATH" "$TYPOS_CHECK" --files-from "$FIXTURE/managed-markdown-paths" --repo "$FIXTURE"; then
    echo "FAIL: typos check must exclude manifest paths before invoking typos" >&2
    exit 1
fi

echo "PASS: quality-gate repo propagation"
