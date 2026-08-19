#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGETS="$ROOT_DIR/scripts/quality-gate-targets.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_null_paths() {
    local output_file="$1"
    shift
    local expected_file="$FIXTURE/expected.txt"
    local actual_file="$FIXTURE/actual.txt"

    printf '%s\n' "$@" | LC_ALL=C sort >"$expected_file"
    tr '\0' '\n' <"$output_file" | LC_ALL=C sort >"$actual_file"
    cmp -s "$expected_file" "$actual_file" || {
        printf 'expected:\n' >&2
        cat "$expected_file" >&2
        printf 'actual:\n' >&2
        cat "$actual_file" >&2
        fail "target paths differ"
    }
}

repo="$FIXTURE/repo"
mkdir -p "$repo/Sources" "$repo/docs" "$repo/aidlc/spaces/default" "$repo/.codex/tools"
git -C "$repo" init -q
git -C "$repo" config user.email fixture@example.invalid
git -C "$repo" config user.name Fixture
printf 'struct Changed {}\n' >"$repo/Sources/Changed.swift"
printf 'struct Unchanged {}\n' >"$repo/Sources/Unchanged.swift"
printf '# Deleted\n' >"$repo/docs/deleted.md"
printf 'export const renamed = true;\n' >"$repo/rename-old.ts"
printf '# workflow record\n' >"$repo/aidlc/spaces/default/state.md"
printf 'export const managed = true;\n' >"$repo/.codex/tools/aidlc-state.ts"
git -C "$repo" add -- .
base_tree="$(git -C "$repo" write-tree)"
base_commit="$(printf 'base\n' | git -C "$repo" commit-tree "$base_tree")"

printf 'struct Changed { let value = 1 }\n' >"$repo/Sources/Changed.swift"
git -C "$repo" mv -- rename-old.ts $'rename\ttarget.ts'
git -C "$repo" update-index --force-remove docs/deleted.md
printf '# changed workflow record\n' >"$repo/aidlc/spaces/default/state.md"
printf 'export const managed = false;\n' >"$repo/.codex/tools/aidlc-state.ts"
git -C "$repo" add -- Sources/Changed.swift $'rename\ttarget.ts' aidlc/spaces/default/state.md .codex/tools/aidlc-state.ts
head_tree="$(git -C "$repo" write-tree)"
head_commit="$(printf 'head\n' | git -C "$repo" commit-tree "$head_tree" -p "$base_commit")"

changed_output="$FIXTURE/changed.bin"
"$TARGETS" --repo "$repo" --changed --base "$base_commit" --head "$head_commit" --kind any >"$changed_output"
assert_null_paths "$changed_output" \
    ".codex/tools/aidlc-state.ts" \
    "Sources/Changed.swift" \
    "aidlc/spaces/default/state.md" \
    $'rename\ttarget.ts'

git -C "$repo" reset -q
printf 'staged\n' >"$repo/staged.txt"
printf 'unstaged\n' >"$repo/unstaged.txt"
git -C "$repo" add -- staged.txt
staged_output="$FIXTURE/staged.bin"
"$TARGETS" --repo "$repo" --staged --kind any >"$staged_output"
assert_null_paths "$staged_output" "staged.txt"

printf '#!/usr/bin/env bash\nexit 0\n' >"$repo/tool"
line_number=0
while [[ "$line_number" -lt 20000 ]]; do
    printf ': # padding %s\n' "$line_number" >>"$repo/tool"
    line_number=$((line_number + 1))
done
git -C "$repo" add -- tool
shell_output="$FIXTURE/shell.bin"
"$TARGETS" --repo "$repo" --staged --kind shell >"$shell_output"
assert_null_paths "$shell_output" "tool"

printf 'not a shell script\n' >"$repo/all-mode-tool"
git -C "$repo" add -- all-mode-tool
printf '#!/usr/bin/env bash\nexit 0\n' >"$repo/all-mode-tool"
all_shell_output="$FIXTURE/all-shell.bin"
"$TARGETS" --repo "$repo" --all --kind shell >"$all_shell_output"
assert_null_paths "$all_shell_output" "all-mode-tool" "tool"

git -C "$repo" add -- Sources/Changed.swift Sources/Unchanged.swift
swift_base_tree="$(git -C "$repo" write-tree)"
swift_base_commit="$(printf 'swift base\n' | git -C "$repo" commit-tree "$swift_base_tree")"
printf 'rules:\n' >"$repo/.swiftlint.yml"
git -C "$repo" add -- .swiftlint.yml
swift_config_tree="$(git -C "$repo" write-tree)"
swift_config_commit="$(printf 'swift config\n' | git -C "$repo" commit-tree "$swift_config_tree" -p "$swift_base_commit")"
swift_output="$FIXTURE/swift.bin"
"$TARGETS" --repo "$repo" --changed --base "$swift_base_commit" --head "$swift_config_commit" --kind swift >"$swift_output"
assert_null_paths "$swift_output" "Sources/Changed.swift" "Sources/Unchanged.swift"

git -C "$repo" read-tree "$swift_config_tree"
git -C "$repo" update-index --force-remove .swiftlint.yml
swift_config_deleted_tree="$(git -C "$repo" write-tree)"
swift_config_deleted_commit="$(
    printf 'swift config deleted\n' |
        git -C "$repo" commit-tree "$swift_config_deleted_tree" -p "$swift_config_commit"
)"
swift_config_deleted_output="$FIXTURE/swift-config-deleted.bin"
"$TARGETS" \
    --repo "$repo" \
    --changed \
    --base "$swift_config_commit" \
    --head "$swift_config_deleted_commit" \
    --kind swift >"$swift_config_deleted_output"
assert_null_paths "$swift_config_deleted_output" "Sources/Changed.swift" "Sources/Unchanged.swift"

git -C "$repo" read-tree --reset "$swift_config_commit"
git -C "$repo" update-index --force-remove .swiftlint.yml
swift_config_staged_deleted_output="$FIXTURE/swift-config-staged-deleted.bin"
"$TARGETS" --repo "$repo" --staged --kind swift >"$swift_config_staged_deleted_output"
assert_null_paths "$swift_config_staged_deleted_output" "Sources/Changed.swift" "Sources/Unchanged.swift"

diverged_repo="$FIXTURE/diverged-repo"
mkdir -p "$diverged_repo"
git -C "$diverged_repo" init -q
git -C "$diverged_repo" config user.email fixture@example.invalid
git -C "$diverged_repo" config user.name Fixture
printf 'ancestor\n' >"$diverged_repo/shared.txt"
printf 'ancestor\n' >"$diverged_repo/head.txt"
git -C "$diverged_repo" add -- shared.txt head.txt
ancestor_tree="$(git -C "$diverged_repo" write-tree)"
ancestor_commit="$(printf 'ancestor\n' | git -C "$diverged_repo" commit-tree "$ancestor_tree")"

printf 'base branch only\n' >"$diverged_repo/shared.txt"
git -C "$diverged_repo" add -- shared.txt
base_branch_tree="$(git -C "$diverged_repo" write-tree)"
base_branch_commit="$(printf 'base branch\n' | git -C "$diverged_repo" commit-tree "$base_branch_tree" -p "$ancestor_commit")"

git -C "$diverged_repo" read-tree "$ancestor_tree"
printf 'head branch only\n' >"$diverged_repo/head.txt"
git -C "$diverged_repo" add -- head.txt
head_branch_tree="$(git -C "$diverged_repo" write-tree)"
head_branch_commit="$(printf 'head branch\n' | git -C "$diverged_repo" commit-tree "$head_branch_tree" -p "$ancestor_commit")"
diverged_output="$FIXTURE/diverged.bin"
"$TARGETS" --repo "$diverged_repo" --changed --base "$base_branch_commit" --head "$head_branch_commit" --kind any >"$diverged_output"
assert_null_paths "$diverged_output" "head.txt"

direct_output="$FIXTURE/direct.bin"
"$TARGETS" \
    --repo "$diverged_repo" \
    --changed \
    --range-mode direct \
    --base "$base_branch_commit" \
    --head "$head_branch_commit" \
    --kind any >"$direct_output"
assert_null_paths "$direct_output" "head.txt" "shared.txt"

newline_path=$'docs/line\nbreak.md'
printf '# newline\n' >"$repo/$newline_path"
git -C "$repo" add -- "$newline_path"
if "$TARGETS" --repo "$repo" --staged --kind markdownlint >"$FIXTURE/newline.bin" 2>"$FIXTURE/newline.err"; then
    fail "newline paths must fail closed"
fi
grep -F 'path contains a newline' "$FIXTURE/newline.err" >/dev/null ||
    fail "newline path failure must explain the unsupported path"

if "$TARGETS" --repo "$repo" --staged --all --kind any >"$FIXTURE/conflicting-staged-all.bin" 2>/dev/null; then
    fail "staged and all modes must be mutually exclusive"
fi
if "$TARGETS" \
    --repo "$repo" \
    --changed \
    --all \
    --base "$base_commit" \
    --head "$head_commit" \
    --kind any >"$FIXTURE/conflicting-changed-all.bin" 2>/dev/null; then
    fail "changed and all modes must be mutually exclusive"
fi
if "$TARGETS" \
    --repo "$repo" \
    --staged \
    --changed \
    --base "$base_commit" \
    --head "$head_commit" \
    --kind any >"$FIXTURE/conflicting-staged-changed.bin" 2>/dev/null; then
    fail "staged and changed modes must be mutually exclusive"
fi

actionlint_repo="$FIXTURE/actionlint-repo"
mkdir -p "$actionlint_repo/.github/workflows"
git -C "$actionlint_repo" init -q
git -C "$actionlint_repo" config user.email fixture@example.invalid
git -C "$actionlint_repo" config user.name Fixture
printf 'name: Unchanged\non: push\njobs: {}\n' >"$actionlint_repo/.github/workflows/unchanged.yml"
printf 'name: Delete\non: push\njobs: {}\n' >"$actionlint_repo/.github/workflows/delete.yaml"
printf 'name: Rename\non: push\njobs: {}\n' >"$actionlint_repo/.github/workflows/rename.yml"
printf 'name: Nested\non: push\njobs: {}\n' >"$actionlint_repo/.github/workflows/nested.yml"
mkdir -p "$actionlint_repo/.github/workflows/nested"
printf 'name: Out of scope\non: push\njobs: {}\n' >"$actionlint_repo/.github/workflows/nested/outside.yml"
git -C "$actionlint_repo" add -- .
actionlint_base_tree="$(git -C "$actionlint_repo" write-tree)"
actionlint_base_commit="$(printf 'actionlint base\n' | git -C "$actionlint_repo" commit-tree "$actionlint_base_tree")"
printf 'name: Changed\non: pull_request\njobs: {}\n' >"$actionlint_repo/.github/workflows/changed.yaml"
git -C "$actionlint_repo" mv -- \
    .github/workflows/rename.yml \
    '.github/workflows/renamed workflow.yml'
git -C "$actionlint_repo" update-index --force-remove .github/workflows/delete.yaml
git -C "$actionlint_repo" add -- .github/workflows/changed.yaml '.github/workflows/renamed workflow.yml'
actionlint_head_tree="$(git -C "$actionlint_repo" write-tree)"
actionlint_head_commit="$(
    printf 'actionlint head\n' |
        git -C "$actionlint_repo" commit-tree "$actionlint_head_tree" -p "$actionlint_base_commit"
)"
actionlint_changed_output="$FIXTURE/actionlint-changed.bin"
"$TARGETS" \
    --repo "$actionlint_repo" \
    --changed \
    --base "$actionlint_base_commit" \
    --head "$actionlint_head_commit" \
    --kind actionlint >"$actionlint_changed_output"
assert_null_paths "$actionlint_changed_output" \
    ".github/workflows/changed.yaml" \
    ".github/workflows/renamed workflow.yml"

printf 'config-variables: null\n' >"$actionlint_repo/.github/actionlint.yaml"
git -C "$actionlint_repo" add -- .github/actionlint.yaml
actionlint_config_tree="$(git -C "$actionlint_repo" write-tree)"
actionlint_config_commit="$(
    printf 'actionlint config\n' |
        git -C "$actionlint_repo" commit-tree "$actionlint_config_tree" -p "$actionlint_head_commit"
)"
actionlint_config_output="$FIXTURE/actionlint-config.bin"
"$TARGETS" \
    --repo "$actionlint_repo" \
    --changed \
    --base "$actionlint_head_commit" \
    --head "$actionlint_config_commit" \
    --kind actionlint >"$actionlint_config_output"
assert_null_paths "$actionlint_config_output" \
    ".github/workflows/changed.yaml" \
    ".github/workflows/nested.yml" \
    ".github/workflows/renamed workflow.yml" \
    ".github/workflows/unchanged.yml"

printf 'config-variables: null\n' >"$actionlint_repo/.github/actionlint.yml"
git -C "$actionlint_repo" add -- .github/actionlint.yml
actionlint_yml_tree="$(git -C "$actionlint_repo" write-tree)"
actionlint_yml_commit="$(
    printf 'nonstandard actionlint config\n' |
        git -C "$actionlint_repo" commit-tree "$actionlint_yml_tree" -p "$actionlint_config_commit"
)"
actionlint_yml_output="$FIXTURE/actionlint-yml.bin"
"$TARGETS" \
    --repo "$actionlint_repo" \
    --changed \
    --base "$actionlint_config_commit" \
    --head "$actionlint_yml_commit" \
    --kind actionlint >"$actionlint_yml_output"
[[ ! -s "$actionlint_yml_output" ]] ||
    fail ".github/actionlint.yml must not expand scope without an explicit config-file contract"

yamllint_repo="$FIXTURE/yamllint-repo"
mkdir -p "$yamllint_repo/.github/workflows" "$yamllint_repo/config"
git -C "$yamllint_repo" init -q
git -C "$yamllint_repo" config user.email fixture@example.invalid
git -C "$yamllint_repo" config user.name Fixture
printf 'name: Unrelated\non: push\njobs: {}\n' >"$yamllint_repo/.github/workflows/unrelated.yml"
printf 'name: unchanged\n' >"$yamllint_repo/config/unchanged.yaml"
git -C "$yamllint_repo" add -- .
yamllint_base_tree="$(git -C "$yamllint_repo" write-tree)"
yamllint_base_commit="$(printf 'yamllint base\n' | git -C "$yamllint_repo" commit-tree "$yamllint_base_tree")"
printf 'name: Changed\non: pull_request\njobs: {}\n' >"$yamllint_repo/.github/workflows/unrelated.yml"
printf 'name: changed\n' >"$yamllint_repo/config/changed.yml"
git -C "$yamllint_repo" add -- .github/workflows/unrelated.yml config/changed.yml
yamllint_head_tree="$(git -C "$yamllint_repo" write-tree)"
yamllint_head_commit="$(
    printf 'yamllint head\n' |
        git -C "$yamllint_repo" commit-tree "$yamllint_head_tree" -p "$yamllint_base_commit"
)"
yamllint_output="$FIXTURE/yamllint.bin"
"$TARGETS" \
    --repo "$yamllint_repo" \
    --changed \
    --base "$yamllint_base_commit" \
    --head "$yamllint_head_commit" \
    --kind yamllint >"$yamllint_output"
assert_null_paths "$yamllint_output" "config/changed.yml"

printf 'rules:\n  document-start: disable\n' >"$yamllint_repo/.yamllint.yml"
git -C "$yamllint_repo" add -- .yamllint.yml
yamllint_config_tree="$(git -C "$yamllint_repo" write-tree)"
yamllint_config_commit="$(
    printf 'yamllint config\n' |
        git -C "$yamllint_repo" commit-tree "$yamllint_config_tree" -p "$yamllint_head_commit"
)"
yamllint_config_output="$FIXTURE/yamllint-config.bin"
"$TARGETS" \
    --repo "$yamllint_repo" \
    --changed \
    --base "$yamllint_head_commit" \
    --head "$yamllint_config_commit" \
    --kind yamllint >"$yamllint_config_output"
assert_null_paths "$yamllint_config_output" ".yamllint.yml" "config/changed.yml" "config/unchanged.yaml"

printf 'PASS: quality gate targets\n'
