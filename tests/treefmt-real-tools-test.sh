#!/usr/bin/env bash
set -euo pipefail

# treefmt-wrapper-test.sh verifies wrapper-specific behavior (timeout, argument
# generation, config branching) against a fake treefmt binary. This file runs
# treefmt-check.sh against the real vendored treefmt/shfmt/prettier binaries to
# confirm the generated config actually formats real input, which the fake
# binary cannot exercise. Requires treefmt, shfmt, and prettier on PATH
# (vendored under bin/<platform>/ and .github/quality-gates/node_modules/.bin/
# in CI; already on PATH for a machine with the AI environment bootstrap
# applied locally).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/treefmt-check.sh"

for required_tool in treefmt shfmt prettier; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        echo "error: required command not found: $required_tool" >&2
        exit 127
    fi
done

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

# shfmtの全EditorConfig対応オプションを明示しているため、repo内・親/home相当の
# EditorConfigの有無や競合にかかわらず、実走結果は4スペースになる。
SHFMT_FIXTURES="$FIXTURE/shfmt-fixtures"
mkdir -p \
    "$SHFMT_FIXTURES/no-editorconfig" \
    "$SHFMT_FIXTURES/local-conflict" \
    "$SHFMT_FIXTURES/home-conflict/repo"
printf '%s\n' 'root = true' '' '[*.sh]' 'indent_style = tab' 'binary_next_line = true' \
    >"$SHFMT_FIXTURES/local-conflict/.editorconfig"
printf '%s\n' 'root = true' '' '[*.sh]' 'indent_style = tab' 'switch_case_indent = true' \
    >"$SHFMT_FIXTURES/home-conflict/.editorconfig"
for shfmt_repo in \
    "$SHFMT_FIXTURES/no-editorconfig" \
    "$SHFMT_FIXTURES/local-conflict" \
    "$SHFMT_FIXTURES/home-conflict/repo"; do
    printf '%s\n' 'if true; then' 'echo hi' 'fi' >"$shfmt_repo/fixture.sh"
    HOME="$SHFMT_FIXTURES/home-conflict" "$SCRIPT" --write --repo "$shfmt_repo" -- fixture.sh >/dev/null
    if [[ "$(<"$shfmt_repo/fixture.sh")" != $'if true; then\n    echo hi\nfi' ]]; then
        echo "FAIL: shfmt output changed because of EditorConfig discovery: $shfmt_repo" >&2
        exit 1
    fi
done

# treefmt --ci only fails after formatters report a change; it does not prevent
# formatter-specific write flags. A real formatter run must therefore leave an
# unformatted tracked file untouched in check mode.
CHECK_ONLY_REPO="$FIXTURE/check-only-repo"
git init -q "$CHECK_ONLY_REPO"
git -C "$CHECK_ONLY_REPO" config user.email fixture@example.invalid
git -C "$CHECK_ONLY_REPO" config user.name Fixture
# fixtureのcommitは開発機のglobal core.hooksPathを引き継がせない。共有hookが走ると、
# 意図的に未整形のfixtureをcommitできずテストが実行環境依存で落ちる。
mkdir -p "$FIXTURE/no-hooks"
git -C "$CHECK_ONLY_REPO" config core.hooksPath "$FIXTURE/no-hooks"
printf '{"fixture":true}\n' >"$CHECK_ONLY_REPO/unformatted.json"
git -C "$CHECK_ONLY_REPO" add unformatted.json
git -C "$CHECK_ONLY_REPO" commit -qm initial
check_only_before="$(cat "$CHECK_ONLY_REPO/unformatted.json")"
if "$SCRIPT" --check --repo "$CHECK_ONLY_REPO" >/dev/null 2>&1; then
    echo "FAIL: treefmt-check.sh accepted unformatted input in check mode" >&2
    exit 1
fi
if [[ "$(cat "$CHECK_ONLY_REPO/unformatted.json")" != "$check_only_before" ]] ||
    ! git -C "$CHECK_ONLY_REPO" diff --quiet -- unformatted.json; then
    echo "FAIL: treefmt-check.sh modified a tracked file in check mode" >&2
    exit 1
fi

echo "PASS"
