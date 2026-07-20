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
git -C "$FIXTURE" commit -qm base
base_sha="$(git -C "$FIXTURE" rev-parse HEAD)"

swift_path=$'Sources/line\nbreak.swift'
shell_path=$'scripts/tab\tname.sh'
markdown_path='docs/-note.md'
renamed_path=$'renamed\nmodule.ts'
mkdir -p "$FIXTURE/Sources" "$FIXTURE/scripts" "$FIXTURE/docs"
printf 'struct Fixture {}\n' >"$FIXTURE/$swift_path"
printf '#!/usr/bin/env bash\n' >"$FIXTURE/$shell_path"
printf '# Fixture\n' >"$FIXTURE/$markdown_path"
git -C "$FIXTURE" mv -- original.ts "$renamed_path"
git -C "$FIXTURE" add -- "$swift_path" "$shell_path" "$markdown_path" "$renamed_path"
git -C "$FIXTURE" commit -qm special-names
head_sha="$(git -C "$FIXTURE" rev-parse HEAD)"

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
	--base "" \
	--head "$head_sha" \
	--output "$fallback_output"
if ! grep -Fxq 'swift=true' "$fallback_output" || ! grep -Fxq 'eslint=true' "$fallback_output"; then
	printf 'FAIL: tracked-file fallback did not classify special names\n' >&2
	exit 1
fi

printf 'PASS\n'
