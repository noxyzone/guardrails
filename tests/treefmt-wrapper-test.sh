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

if ! rg -q "git diff --shortstat >&2" "$SCRIPT" || rg -q "git diff -- >&2" "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must summarize formatter failures without printing diff contents" >&2
	exit 1
fi

if ! rg -q 'mktemp "\$\{TMPDIR:-/tmp\}/treefmt-runtime\.XXXXXX\.toml"' "$SCRIPT"; then
	echo "FAIL: treefmt-check.sh must keep generated treefmt config outside the repo tree" >&2
	exit 1
fi

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/guardrails/scripts" "$FIXTURE/bin" "$FIXTURE/repo"
ln -s "$SCRIPT" "$FIXTURE/guardrails/scripts/treefmt-check.sh"
printf '%s\n' \
	'[formatter.prettier]' \
	'command = "prettier"' \
	'options = ["--config", ".guardrails/prettier.cjs", "--write"]' \
	'' \
	'[formatter.swiftformat]' \
	'command = "swiftformat"' \
	'options = ["--config", ".guardrails/.swiftformat"]' \
	>"$FIXTURE/guardrails/treefmt.toml"
printf 'module.exports = {};\n' >"$FIXTURE/guardrails/prettier.cjs"
printf '%s\n' '--swiftversion 6.0' >"$FIXTURE/guardrails/.swiftformat"

cat >"$FIXTURE/bin/treefmt" <<'FAKE_TREEFMT'
#!/usr/bin/env bash
set -euo pipefail
printf 'invoked\n' >"${TREEFMT_INVOKED_FILE:?}"
while (($# > 0)); do
	if [[ "$1" == "--config-file" ]]; then
		/bin/cp "$2" "${TREEFMT_CONFIG_CAPTURE:?}"
		exit "${TREEFMT_EXIT_STATUS:-0}"
	fi
	shift
done
exit 2
FAKE_TREEFMT
cat >"$FIXTURE/guardrails/scripts/quality-gate-path-filter.sh" <<'FAILING_FILTER'
#!/usr/bin/env bash
set -euo pipefail
exit 23
FAILING_FILTER
chmod +x "$FIXTURE/bin/treefmt" "$FIXTURE/guardrails/scripts/quality-gate-path-filter.sh"

if PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
	TREEFMT_CONFIG_CAPTURE="$FIXTURE/config-capture.toml" \
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
	TREEFMT_CONFIG_CAPTURE="$FIXTURE/config-capture.toml" \
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
	TREEFMT_CONFIG_CAPTURE="$FIXTURE/config-capture.toml" \
	/bin/bash "$FIXTURE/guardrails/scripts/treefmt-check.sh" \
	--repo "$FIXTURE/repo" >/dev/null 2>&1; then
	echo "FAIL: treefmt-check.sh rejected an empty explicit path list" >&2
	exit 1
fi
if [[ ! -e "$FIXTURE/treefmt-invoked" ]]; then
	echo "FAIL: treefmt-check.sh did not invoke treefmt for the repository default" >&2
	exit 1
fi

git -C "$FIXTURE/repo" init -q
git -C "$FIXTURE/repo" config user.email fixture@example.invalid
git -C "$FIXTURE/repo" config user.name Fixture
printf 'original\n' >"$FIXTURE/repo/sensitive.txt"
git -C "$FIXTURE/repo" add sensitive.txt
fixture_tree="$(git -C "$FIXTURE/repo" write-tree)"
fixture_commit="$(printf 'initial\n' | git -C "$FIXTURE/repo" commit-tree "$fixture_tree")"
git -C "$FIXTURE/repo" update-ref HEAD "$fixture_commit"
printf 'sensitive-fixture-value\n' >"$FIXTURE/repo/sensitive.txt"
if PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
	TREEFMT_CONFIG_CAPTURE="$FIXTURE/config-capture.toml" TREEFMT_EXIT_STATUS=23 \
	/bin/bash "$FIXTURE/guardrails/scripts/treefmt-check.sh" \
	--repo "$FIXTURE/repo" >"$FIXTURE/treefmt-failure.stdout" \
	2>"$FIXTURE/treefmt-failure.stderr"; then
	echo "FAIL: treefmt-check.sh accepted a formatter failure" >&2
	exit 1
fi
if rg -Fq 'sensitive-fixture-value' "$FIXTURE/treefmt-failure.stderr"; then
	echo "FAIL: treefmt-check.sh exposed repository diff contents" >&2
	exit 1
fi
if ! rg -Fq '1 file changed' "$FIXTURE/treefmt-failure.stderr"; then
	echo "FAIL: treefmt-check.sh omitted the safe repository diff summary" >&2
	exit 1
fi
git -C "$FIXTURE/repo" checkout -q -- sensitive.txt
if ! rg -Fq "options = [\"--config\", \"$FIXTURE/guardrails/prettier.cjs\", \"--write\"]" \
	"$FIXTURE/config-capture.toml" ||
	! rg -Fq "options = [\"--config\", \"$FIXTURE/guardrails/.swiftformat\"]" \
		"$FIXTURE/config-capture.toml"; then
	echo "FAIL: treefmt-check.sh did not bind formatter settings to the selected guardrails directory" >&2
	exit 1
fi

mkdir -p "$FIXTURE/repo/.guardrails"
printf 'existing treefmt\n' >"$FIXTURE/repo/.guardrails/treefmt.toml"
printf 'existing prettier\n' >"$FIXTURE/repo/.guardrails/prettier.cjs"
printf 'existing swiftformat\n' >"$FIXTURE/repo/.guardrails/.swiftformat"
printf 'existing editorconfig\n' >"$FIXTURE/repo/.editorconfig"
if ! PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
	TREEFMT_CONFIG_CAPTURE="$FIXTURE/config-capture.toml" \
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

ln -s missing-guardrails "$FIXTURE/repo/.guardrails"
if ! PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
	TREEFMT_CONFIG_CAPTURE="$FIXTURE/config-capture.toml" \
	/bin/bash "$FIXTURE/guardrails/scripts/treefmt-check.sh" \
	--repo "$FIXTURE/repo" >/dev/null 2>&1; then
	echo "FAIL: treefmt-check.sh rejected an unrelated broken repo-local guardrails symlink" >&2
	exit 1
fi
if [[ ! -L "$FIXTURE/repo/.guardrails" ]] ||
	[[ "$(readlink "$FIXTURE/repo/.guardrails")" != "missing-guardrails" ]]; then
	echo "FAIL: treefmt-check.sh modified a broken repo-local guardrails symlink" >&2
	exit 1
fi
rm "$FIXTURE/repo/.guardrails"

ln -s ../outside-editorconfig "$FIXTURE/repo/.editorconfig"
if PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
	TREEFMT_CONFIG_CAPTURE="$FIXTURE/config-capture.toml" \
	/bin/bash "$FIXTURE/guardrails/scripts/treefmt-check.sh" \
	--repo "$FIXTURE/repo" >/dev/null 2>&1; then
	echo "FAIL: treefmt-check.sh accepted a dangling repository editorconfig symlink" >&2
	exit 1
fi
if [[ ! -L "$FIXTURE/repo/.editorconfig" ]] ||
	[[ -e "$FIXTURE/outside-editorconfig" ]]; then
	echo "FAIL: treefmt-check.sh wrote through a dangling repository editorconfig symlink" >&2
	exit 1
fi
rm "$FIXTURE/repo/.editorconfig"

if PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
	TREEFMT_CONFIG_CAPTURE="$FIXTURE/config-capture.toml" \
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

echo "PASS"
