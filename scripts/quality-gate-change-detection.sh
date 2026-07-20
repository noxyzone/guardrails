#!/usr/bin/env bash
set -euo pipefail

repo=""
base=""
head=""
output=""

while (($# > 0)); do
	case "$1" in
	--repo)
		repo="$2"
		shift 2
		;;
	--base)
		base="$2"
		shift 2
		;;
	--head)
		head="$2"
		shift 2
		;;
	--output)
		output="$2"
		shift 2
		;;
	*)
		printf 'error: unknown argument: %s\n' "$1" >&2
		exit 2
		;;
	esac
done

[[ -d "$repo/.git" || -f "$repo/.git" ]] || {
	printf 'error: --repo must identify a Git worktree\n' >&2
	exit 2
}
[[ -n "$output" ]] || {
	printf 'error: --output is required\n' >&2
	exit 2
}

any=false
ast_grep=false
eslint=false
localization=false
markdownlint=false
ruff=false
shell=false
swift=false
text_spacing=false
treefmt_non_swift=false

classify_path() {
	local path="$1"
	any=true
	case "$path" in
	*.swift)
		ast_grep=true
		localization=true
		swift=true
		;;
	*.xcstrings)
		localization=true
		text_spacing=true
		treefmt_non_swift=true
		;;
	esac
	case "$path" in
	*.cjs | *.js | *.mjs | *.ts) eslint=true ;;
	esac
	case "$path" in
	*.md) markdownlint=true ;;
	esac
	case "$path" in
	*.py) ruff=true ;;
	esac
	case "$path" in
	*.sh) shell=true ;;
	esac
	case "$path" in
	*.css | *.html | *.json | *.jsonc | *.md | *.toml | *.txt | *.yaml | *.yml)
		text_spacing=true
		;;
	esac
	case "$path" in
	*.cjs | *.css | *.entitlements | *.html | *.ipynb | *.js | *.json | *.jsonc | *.md | *.mjs | *.plist | *.py | *.sh | *.svg | *.toml | *.ts | *.tsx | *.xcscheme | *.xcstrings | *.xctestplan | *.xcworkspacedata | *.xml | *.xsd | *.yaml | *.yml)
		treefmt_non_swift=true
		;;
	esac
}

cd "$repo"
if [[ -n "$base" && "$base" != "0000000000000000000000000000000000000000" ]]; then
	while IFS= read -r -d '' path; do
		classify_path "$path"
	done < <(git diff --name-only -z --diff-filter=ACMRT "$base" "$head" --)
else
	while IFS= read -r -d '' path; do
		classify_path "$path"
	done < <(git ls-files -z)
fi

secretlint="$any"
typos="$any"
ubuntu=false
for needed in "$eslint" "$localization" "$markdownlint" "$ruff" "$secretlint" "$shell" "$text_spacing" "$treefmt_non_swift" "$typos"; do
	if [[ "$needed" == true ]]; then
		ubuntu=true
	fi
done

{
	printf 'any=%s\n' "$any"
	printf 'ast_grep=%s\n' "$ast_grep"
	printf 'eslint=%s\n' "$eslint"
	printf 'localization=%s\n' "$localization"
	printf 'markdownlint=%s\n' "$markdownlint"
	printf 'ruff=%s\n' "$ruff"
	printf 'secretlint=%s\n' "$secretlint"
	printf 'shell=%s\n' "$shell"
	printf 'swift=%s\n' "$swift"
	printf 'text_spacing=%s\n' "$text_spacing"
	printf 'treefmt_non_swift=%s\n' "$treefmt_non_swift"
	printf 'typos=%s\n' "$typos"
	printf 'ubuntu=%s\n' "$ubuntu"
} >>"$output"
