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

if ! rg -Fq 'git diff --shortstat -- "${treefmt_args[@]}"' "$SCRIPT" ||
    rg -Fq 'git diff --shortstat >&2' "$SCRIPT" ||
    rg -Fq 'git diff -- >&2' "$SCRIPT"; then
    echo "FAIL: treefmt-check.sh must limit formatter failure summaries to explicit paths without printing diff contents" >&2
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
    '[formatter.shfmt]' \
    'command = "shfmt"' \
    'options = [' \
    '  "-ln",' \
    '  "auto",' \
    '  "-i",' \
    '  "4",' \
    '  "-bn=false",' \
    '  "-ci=false",' \
    '  "-sr=false",' \
    '  "-kp=false",' \
    '  "-fn=false",' \
    '  "--apply-ignore=false",' \
    '  "-w",' \
    ']' \
    '' \
    '[formatter.ruff]' \
    'command = "ruff"' \
    'options = ["format"]' \
    '' \
    '[formatter.taplo]' \
    'command = "taplo"' \
    'options = ["format"]' \
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
if [[ -n "${TREEFMT_FAILURE_MESSAGE:-}" ]]; then
    printf '%s\n' "$TREEFMT_FAILURE_MESSAGE" >&2
fi
if [[ -n "${TREEFMT_ARGS_CAPTURE:-}" ]]; then
	printf '%s\n' "$@" >"$TREEFMT_ARGS_CAPTURE"
fi
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

: >"$FIXTURE/treefmt-args"
if ! PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
    TREEFMT_CONFIG_CAPTURE="$FIXTURE/config-capture.toml" \
    TREEFMT_ARGS_CAPTURE="$FIXTURE/treefmt-args" \
    /bin/bash "$FIXTURE/guardrails/scripts/treefmt-check.sh" \
    --repo "$FIXTURE/repo" -- --write --check --repo reserved-path \
    >/dev/null 2>&1; then
    echo "FAIL: treefmt-check.sh rejected reserved-word paths after --" >&2
    exit 1
fi
if ! rg -Fxq -- '--ci' "$FIXTURE/treefmt-args" ||
    ! rg -Fxq -- '--write' "$FIXTURE/treefmt-args" ||
    ! rg -Fxq -- '--check' "$FIXTURE/treefmt-args" ||
    ! rg -Fxq -- '--repo' "$FIXTURE/treefmt-args" ||
    ! rg -Fxq -- 'reserved-path' "$FIXTURE/treefmt-args"; then
    echo "FAIL: treefmt-check.sh reinterpreted reserved-word paths after --" >&2
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
set +e
PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
    TREEFMT_CONFIG_CAPTURE="$FIXTURE/config-capture.toml" TREEFMT_EXIT_STATUS=23 \
    /bin/bash "$FIXTURE/guardrails/scripts/treefmt-check.sh" \
    --repo "$FIXTURE/repo" -- sensitive.txt >"$FIXTURE/treefmt-failure.stdout" \
    2>"$FIXTURE/treefmt-failure.stderr"
treefmt_failure_status="$?"
set -e
if [[ "$treefmt_failure_status" -ne 23 ]]; then
    echo "FAIL: treefmt-check.sh did not preserve formatter exit status 23 (got $treefmt_failure_status)" >&2
    exit 1
fi
if rg -Fq 'sensitive-fixture-value' "$FIXTURE/treefmt-failure.stderr"; then
    echo "FAIL: treefmt-check.sh exposed repository diff contents" >&2
    exit 1
fi
if ! rg -Fq '1 file changed' "$FIXTURE/treefmt-failure.stderr"; then
    echo "FAIL: treefmt-check.sh omitted the safe target diff summary" >&2
    exit 1
fi
git -C "$FIXTURE/repo" checkout -q -- sensitive.txt

printf 'normal-worktree-sensitive-value\n' >"$FIXTURE/repo/sensitive.txt"
set +e
PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
    TREEFMT_CONFIG_CAPTURE="$FIXTURE/config-capture.toml" TREEFMT_EXIT_STATUS=23 \
    TREEFMT_FAILURE_MESSAGE='formatter failed: sensitive.txt' \
    /bin/bash "$FIXTURE/guardrails/scripts/treefmt-check.sh" \
    --repo "$FIXTURE/repo" >"$FIXTURE/worktree-failure.stdout" \
    2>"$FIXTURE/worktree-failure.stderr"
worktree_failure_status="$?"
set -e
if [[ "$worktree_failure_status" -ne 23 ]]; then
    echo "FAIL: normal worktree did not preserve formatter exit status 23 (got $worktree_failure_status)" >&2
    exit 1
fi
if ! rg -Fq 'formatter failed: sensitive.txt' "$FIXTURE/worktree-failure.stderr" ||
    rg -Fq 'file changed' "$FIXTURE/worktree-failure.stderr" ||
    rg -Fq 'normal-worktree-sensitive-value' "$FIXTURE/worktree-failure.stderr"; then
    echo "FAIL: normal worktree omitted the formatter failure or exposed a repository-wide diff" >&2
    exit 1
fi
git -C "$FIXTURE/repo" checkout -q -- sensitive.txt

mkdir -p "$FIXTURE/index-repo" "$FIXTURE/sparse-snapshot"
git -C "$FIXTURE/index-repo" init -q
git -C "$FIXTURE/index-repo" config user.email fixture@example.invalid
git -C "$FIXTURE/index-repo" config user.name Fixture
printf 'original target\n' >"$FIXTURE/index-repo/target.txt"
for unrelated_index in 1 2 3; do
    printf 'unrelated %s\n' "$unrelated_index" >"$FIXTURE/index-repo/unrelated-$unrelated_index.txt"
done
git -C "$FIXTURE/index-repo" add target.txt unrelated-1.txt unrelated-2.txt unrelated-3.txt
sparse_tree="$(git -C "$FIXTURE/index-repo" write-tree)"
sparse_commit="$(printf 'initial\n' | git -C "$FIXTURE/index-repo" commit-tree "$sparse_tree")"
git -C "$FIXTURE/index-repo" update-ref HEAD "$sparse_commit"
printf 'gitdir: %s/.git\n' "$FIXTURE/index-repo" >"$FIXTURE/sparse-snapshot/.git"
printf 'malformed target\n' >"$FIXTURE/sparse-snapshot/target.txt"
set +e
PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
    TREEFMT_CONFIG_CAPTURE="$FIXTURE/config-capture.toml" TREEFMT_EXIT_STATUS=23 \
    TREEFMT_FAILURE_MESSAGE='formatter failed: target.txt' \
    /bin/bash "$FIXTURE/guardrails/scripts/treefmt-check.sh" \
    --repo "$FIXTURE/sparse-snapshot" -- target.txt \
    >"$FIXTURE/sparse-failure.stdout" 2>"$FIXTURE/sparse-failure.stderr"
sparse_failure_status="$?"
set -e
if [[ "$sparse_failure_status" -ne 23 ]]; then
    echo "FAIL: sparse snapshot did not preserve formatter exit status 23 (got $sparse_failure_status)" >&2
    exit 1
fi
if ! rg -Fq 'formatter failed: target.txt' "$FIXTURE/sparse-failure.stderr"; then
    echo "FAIL: sparse snapshot omitted the formatter target failure" >&2
    exit 1
fi
if ! rg -Fq '1 file changed' "$FIXTURE/sparse-failure.stderr" ||
    rg -Fq '4 files changed' "$FIXTURE/sparse-failure.stderr" ||
    rg -Fq 'unrelated-' "$FIXTURE/sparse-failure.stderr" ||
    rg -Fq 'malformed target' "$FIXTURE/sparse-failure.stderr"; then
    echo "FAIL: sparse snapshot reported unrelated tracked files or diff contents" >&2
    exit 1
fi
if ! rg -Fq "options = [\"--config\", \"$FIXTURE/guardrails/prettier.cjs\", \"--check\"]" \
    "$FIXTURE/config-capture.toml" ||
    rg -Fq -- '"--write"' "$FIXTURE/config-capture.toml" ||
    ! rg -Fq '  "-d",' "$FIXTURE/config-capture.toml" ||
    ! rg -Fq 'options = ["format", "--check"]' "$FIXTURE/config-capture.toml" ||
    ! rg -Fq "options = [\"--config\", \"$FIXTURE/guardrails/.swiftformat\", \"--lint\"]" \
        "$FIXTURE/config-capture.toml"; then
    echo "FAIL: treefmt-check.sh did not use check-only formatter settings" >&2
    exit 1
fi

if ! PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
    TREEFMT_CONFIG_CAPTURE="$FIXTURE/write-config-capture.toml" \
    /bin/bash "$FIXTURE/guardrails/scripts/treefmt-check.sh" \
    --write --repo "$FIXTURE/repo" >/dev/null 2>&1; then
    echo "FAIL: treefmt-check.sh rejected write mode" >&2
    exit 1
fi
if ! rg -Fq "options = [\"--config\", \"$FIXTURE/guardrails/prettier.cjs\", \"--write\"]" \
    "$FIXTURE/write-config-capture.toml" ||
    ! rg -Fq '  "-w",' "$FIXTURE/write-config-capture.toml" ||
    ! rg -Fq 'options = ["format"]' "$FIXTURE/write-config-capture.toml" ||
    ! rg -Fq "options = [\"--config\", \"$FIXTURE/guardrails/.swiftformat\"]" \
        "$FIXTURE/write-config-capture.toml"; then
    echo "FAIL: treefmt-check.sh did not preserve formatter write settings" >&2
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
if ! PATH="$FIXTURE/bin:$PATH" TREEFMT_INVOKED_FILE="$FIXTURE/treefmt-invoked" \
    TREEFMT_CONFIG_CAPTURE="$FIXTURE/config-capture.toml" \
    /bin/bash "$FIXTURE/guardrails/scripts/treefmt-check.sh" \
    --repo "$FIXTURE/repo" >/dev/null 2>&1; then
    echo "FAIL: treefmt-check.sh rejected an unrelated dangling editorconfig symlink" >&2
    exit 1
fi
if [[ ! -L "$FIXTURE/repo/.editorconfig" ]] ||
    [[ -e "$FIXTURE/outside-editorconfig" ]]; then
    echo "FAIL: treefmt-check.sh modified a dangling repository editorconfig symlink" >&2
    exit 1
fi
rm "$FIXTURE/repo/.editorconfig"

echo "PASS"
