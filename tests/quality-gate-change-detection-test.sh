#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.email fixture@example.com
git -C "$FIXTURE" config user.name Fixture
printf 'base\n' >"$FIXTURE/base.txt"
printf 'old\n' >"$FIXTURE/original.ts"
git -C "$FIXTURE" add -- base.txt original.ts
base_tree="$(git -C "$FIXTURE" write-tree)"
base_sha="$(printf 'base\n' | git -C "$FIXTURE" commit-tree "$base_tree")"

swift_path=$'Sources/tab\tname.swift'
shell_path=$'scripts/tab\tname.sh'
markdown_path='docs/-note.md'
renamed_path='renamed module.ts'
mkdir -p "$FIXTURE/Sources" "$FIXTURE/scripts" "$FIXTURE/docs"
printf 'struct Fixture {}\n' >"$FIXTURE/$swift_path"
printf '#!/usr/bin/env bash\n' >"$FIXTURE/$shell_path"
printf '# Fixture\n' >"$FIXTURE/$markdown_path"
git -C "$FIXTURE" mv -- original.ts "$renamed_path"
git -C "$FIXTURE" add -- "$swift_path" "$shell_path" "$markdown_path" "$renamed_path"
head_tree="$(git -C "$FIXTURE" write-tree)"
head_sha="$(printf 'special names\n' | git -C "$FIXTURE" commit-tree "$head_tree" -p "$base_sha")"

output="$FIXTURE/outputs.txt"
"$ROOT_DIR/scripts/quality-gate-change-detection.sh" \
	--repo "$FIXTURE" \
	--base "$base_sha" \
	--head "$head_sha" \
	--output "$output"

for expected in \
	'any=true' \
	'ast_grep=true' \
	'eslint=true' \
	'localization=true' \
	'markdownlint=true' \
	'shell=true' \
	'swift=true' \
	'text_spacing=true' \
	'treefmt_non_swift=true' \
	'ubuntu=true'; do
	if ! grep -Fxq -- "$expected" "$output"; then
		printf 'FAIL: missing output %s\n' "$expected" >&2
		exit 1
	fi
done

fallback_output="$FIXTURE/fallback-outputs.txt"
"$ROOT_DIR/scripts/quality-gate-change-detection.sh" \
	--repo "$FIXTURE" \
	--all \
	--output "$fallback_output"
if ! grep -Fxq 'swift=true' "$fallback_output" || ! grep -Fxq 'eslint=true' "$fallback_output"; then
	printf 'FAIL: tracked-file fallback did not classify special names\n' >&2
	exit 1
fi

config_base_tree="$(git -C "$FIXTURE" write-tree)"
config_base_commit="$(printf 'config base\n' | git -C "$FIXTURE" commit-tree "$config_base_tree" -p "$head_sha")"
printf 'rules:\n' >"$FIXTURE/.swiftlint.yml"
git -C "$FIXTURE" add -- .swiftlint.yml
config_head_tree="$(git -C "$FIXTURE" write-tree)"
config_head_commit="$(printf 'config head\n' | git -C "$FIXTURE" commit-tree "$config_head_tree" -p "$config_base_commit")"
config_output="$FIXTURE/config-outputs.txt"
"$ROOT_DIR/scripts/quality-gate-change-detection.sh" \
	--repo "$FIXTURE" \
	--base "$config_base_commit" \
	--head "$config_head_commit" \
	--output "$config_output"
if ! grep -Fxq 'swift=true' "$config_output"; then
	printf 'FAIL: SwiftLint config changes must expand and enable the Swift gate\n' >&2
	exit 1
fi

printf 'PASS\n'
