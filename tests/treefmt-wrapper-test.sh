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
printf '%s\n' '--swiftversion 6.0' >"$FIXTURE/guardrails/.swiftformat"

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

mkdir -p "$FIXTURE/repo/.guardrails"
printf 'existing treefmt\n' >"$FIXTURE/repo/.guardrails/treefmt.toml"
printf 'existing prettier\n' >"$FIXTURE/repo/.guardrails/prettier.cjs"
printf 'existing swiftformat\n' >"$FIXTURE/repo/.guardrails/.swiftformat"
printf 'existing editorconfig\n' >"$FIXTURE/repo/.editorconfig"
if ! PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
	/bin/bash "$FIXTURE/guardrails/scripts/treefmt-check.sh" \
	--repo "$FIXTURE/repo" >/dev/null 2>&1; then
	echo "FAIL: treefmt-check.sh rejected an existing guardrails checkout" >&2
	exit 1
fi
if [[ "$(<"$FIXTURE/repo/.guardrails/treefmt.toml")" != "existing treefmt" ]] ||
	[[ "$(<"$FIXTURE/repo/.guardrails/prettier.cjs")" != "existing prettier" ]] ||
	[[ "$(<"$FIXTURE/repo/.guardrails/.swiftformat")" != "existing swiftformat" ]] ||
	[[ "$(<"$FIXTURE/repo/.editorconfig")" != "existing editorconfig" ]]; then
	echo "FAIL: treefmt-check.sh modified an existing repository configuration" >&2
	exit 1
fi
rm -rf "$FIXTURE/repo/.guardrails"
rm "$FIXTURE/repo/.editorconfig"

cat >"$FIXTURE/bin/cp" <<'FAILING_SECOND_COPY'
#!/usr/bin/env bash
set -euo pipefail
copy_count=0
if [[ -f "${COPY_COUNT_FILE:?}" ]]; then
	copy_count="$(<"$COPY_COUNT_FILE")"
fi
copy_count=$((copy_count + 1))
printf '%s\n' "$copy_count" >"$COPY_COUNT_FILE"
if [[ "$copy_count" == 2 ]]; then
	exit 23
fi
/bin/cp "$@"
FAILING_SECOND_COPY
chmod +x "$FIXTURE/bin/cp"
if PATH="$FIXTURE/bin:$PATH" COPY_COUNT_FILE="$FIXTURE/copy-count" \
	TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
	/bin/bash "$FIXTURE/guardrails/scripts/treefmt-check.sh" \
	--repo "$FIXTURE/repo" >/dev/null 2>&1; then
	echo "FAIL: treefmt-check.sh accepted an incomplete guardrails copy" >&2
	exit 1
fi
if [[ -e "$FIXTURE/repo/.guardrails" ]]; then
	echo "FAIL: treefmt-check.sh left a partial guardrails directory after copy failure" >&2
	exit 1
fi

if PATH="$FIXTURE/bin:$PATH" COPY_COUNT_FILE="$FIXTURE/copy-count" \
	TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
	/bin/bash -c '
		printf() {
			if [[ "$#" == 2 && "$1" == "%s\n" && "$2" == "root = true" ]]; then
				builtin printf "$@"
				return 23
			fi
			builtin printf "$@"
		}
		source "$1" --repo "$2"
	' _ "$FIXTURE/guardrails/scripts/treefmt-check.sh" "$FIXTURE/repo" \
	>/dev/null 2>&1; then
	echo "FAIL: treefmt-check.sh accepted an incomplete editorconfig write" >&2
	exit 1
fi
if [[ -e "$FIXTURE/repo/.editorconfig" ]]; then
	echo "FAIL: treefmt-check.sh left a partial editorconfig after write failure" >&2
	exit 1
fi
if [[ -e "$FIXTURE/repo/.guardrails" ]]; then
	echo "FAIL: treefmt-check.sh left guardrails assets after editorconfig failure" >&2
	exit 1
fi

echo "PASS"
