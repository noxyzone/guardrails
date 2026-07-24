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
assert_null_paths "$changed_output" "Sources/Changed.swift" $'rename\ttarget.ts'

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

printf 'PASS: quality gate targets\n'
