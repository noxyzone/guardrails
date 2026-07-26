#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/treefmt-check.sh"

if ! rg -q 'TREEFMT_TIMEOUT_SECONDS:-60' "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must use the shared 60s default timeout" >&2
	exit 1
fi

if ! rg -q 'treefmt_walk="git"' "$SCRIPT" || ! rg -q 'treefmt_walk="filesystem"' "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must use filesystem walking for explicit file paths" >&2
	exit 1
fi

if ! rg -q 'treefmt_command=\(' "$SCRIPT" ||
	! rg -q -- "--tree-root \"\\\$repo_root\"" "$SCRIPT" ||
	! rg -q -- "--walk \"\\\$treefmt_walk\"" "$SCRIPT" ||
	! rg -q -- "--excludes 'node_modules/\\*\\*'" "$SCRIPT" ||
	! rg -q -- "--excludes '\\.guardrails/\\*\\*'" "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must pin treefmt root and exclude generated dependency trees" >&2
	exit 1
fi

if ! rg -q 'treefmt_command\+=\(--ci\)' "$SCRIPT" ||
	! rg -q 'run_with_timeout "\$treefmt_timeout_seconds" "\$\{treefmt_command\[@\]\}"' "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must pin CI root and exclude generated dependency trees" >&2
	exit 1
fi

if ! rg -q "git diff --stat >&2" "$SCRIPT" || ! rg -q "git diff -- >&2" "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must print formatter diffs when CI mode detects changes" >&2
	exit 1
fi

if ! rg -q 'mktemp "\$\{TMPDIR:-/tmp\}/treefmt-noswift\.XXXXXX\.toml"' "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must keep generated treefmt config outside the repo tree" >&2
	exit 1
fi

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/guardrails/scripts" "$FIXTURE/bin" "$FIXTURE/repo"
ln -s "$SCRIPT" "$FIXTURE/guardrails/scripts/treefmt-check.sh"
printf '[formatter.prettier]\n' >"$FIXTURE/guardrails/treefmt.toml"
printf 'module.exports = {};\n' >"$FIXTURE/guardrails/prettier.cjs"

cat >"$FIXTURE/bin/treefmt" <<'FAKE_TREEFMT'
#!/usr/bin/env bash
set -euo pipefail
printf 'invoked\n' >"${TREEFMT_INVOKED_FILE:?}"
FAKE_TREEFMT
cat >"$FIXTURE/guardrails/scripts/quality-gate-path-filter.sh" <<'FAILING_FILTER'
#!/usr/bin/env bash
set -euo pipefail
exit 23
FAILING_FILTER
chmod +x "$FIXTURE/bin/treefmt" "$FIXTURE/guardrails/scripts/quality-gate-path-filter.sh"

if PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
	"$FIXTURE/guardrails/scripts/treefmt-check.sh" --repo "$FIXTURE/repo" >/dev/null 2>&1; then
	echo "FAIL: treefmt-check.sh accepted a failing path filter" >&2
	exit 1
fi
if [[ -e "$FIXTURE/treefmt-invoked" ]]; then
	echo "FAIL: treefmt-check.sh invoked treefmt after the path filter failed" >&2
	exit 1
fi

cat >"$FIXTURE/guardrails/scripts/quality-gate-path-filter.sh" <<'EMPTY_FILTER'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EMPTY_FILTER
rm "$FIXTURE/guardrails/prettier.cjs"
if PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
	"$FIXTURE/guardrails/scripts/treefmt-check.sh" --repo "$FIXTURE/repo" >/dev/null 2>&1; then
	echo "FAIL: treefmt-check.sh accepted a missing required asset" >&2
	exit 1
fi
if [[ -e "$FIXTURE/repo/.guardrails" ]]; then
	echo "FAIL: treefmt-check.sh left an incomplete guardrails directory" >&2
	exit 1
fi

printf 'module.exports = {};\n' >"$FIXTURE/guardrails/prettier.cjs"
if ! PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
	/bin/bash "$FIXTURE/guardrails/scripts/treefmt-check.sh" \
	--repo "$FIXTURE/repo" >/dev/null 2>&1; then
	echo "FAIL: treefmt-check.sh rejected an empty explicit path list" >&2
	exit 1
fi
if [[ ! -e "$FIXTURE/treefmt-invoked" ]]; then
	echo "FAIL: treefmt-check.sh did not invoke treefmt for the repository default" >&2
	exit 1
fi

echo "PASS"
