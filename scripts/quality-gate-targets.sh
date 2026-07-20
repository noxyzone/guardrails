#!/usr/bin/env bash
set -euo pipefail

repo=""
mode=""
base=""
head=""
kind=""

usage() {
	cat <<'USAGE' >&2
usage: quality-gate-targets.sh --repo PATH (--staged | --changed --base SHA --head SHA | --all) --kind KIND

Writes matching paths as a NUL-delimited stream. KIND is one of:
  any ast_grep eslint localization markdownlint ruff secretlint shell swift
  text_spacing treefmt_non_swift typos
USAGE
	exit 2
}

while (($# > 0)); do
	case "$1" in
	--repo)
		(($# >= 2)) || usage
		repo="$2"
		shift 2
		;;
	--staged)
		mode="staged"
		shift
		;;
	--changed)
		mode="changed"
		shift
		;;
	--all)
		mode="all"
		shift
		;;
	--base)
		(($# >= 2)) || usage
		base="$2"
		shift 2
		;;
	--head)
		(($# >= 2)) || usage
		head="$2"
		shift 2
		;;
	--kind)
		(($# >= 2)) || usage
		kind="$2"
		shift 2
		;;
	*) usage ;;
	esac
done

[[ -n "$repo" && -n "$mode" && -n "$kind" ]] || usage
case "$kind" in
any | ast_grep | eslint | localization | markdownlint | ruff | secretlint | shell | swift | text_spacing | treefmt_non_swift | typos) ;;
*) usage ;;
esac
if [[ "$mode" == "changed" && (-z "$base" || -z "$head") ]]; then
	usage
fi
git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
	printf 'error: --repo must identify a Git worktree: %s\n' "$repo" >&2
	exit 2
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_paths="$(mktemp "${TMPDIR:-/tmp}/quality-gate-targets-source.XXXXXX")"
filtered_paths="$(mktemp "${TMPDIR:-/tmp}/quality-gate-targets-filtered.XXXXXX")"
all_paths="$(mktemp "${TMPDIR:-/tmp}/quality-gate-targets-all.XXXXXX")"
trap 'rm -f "$source_paths" "$filtered_paths" "$all_paths"' EXIT

write_scope_paths() {
	local output="$1"
	case "$mode" in
	staged)
		git -C "$repo" -c core.quotepath=false diff -z --cached --name-only --diff-filter=ACMRT -- >"$output"
		;;
	changed)
		if [[ "$base" == "0000000000000000000000000000000000000000" ]]; then
			git -C "$repo" -c core.quotepath=false ls-tree -r --name-only -z "$head" -- >"$output"
		else
			git -C "$repo" -c core.quotepath=false diff -z --name-only --diff-filter=ACMRT "$base...$head" -- >"$output"
		fi
		;;
	all)
		git -C "$repo" -c core.quotepath=false ls-files -z >"$output"
		;;
	esac
}

write_all_paths() {
	local output="$1"
	case "$mode" in
	changed)
		git -C "$repo" -c core.quotepath=false ls-tree -r --name-only -z "$head" -- >"$output"
		;;
	*)
		git -C "$repo" -c core.quotepath=false ls-files -z >"$output"
		;;
	esac
}

is_scope_expansion_path() {
	local path="$1"
	case "$kind:$path" in
	ast_grep:sgconfig.yml | ast_grep:.sgconfig.yml | \
		eslint:eslint.config.* | eslint:.eslint* | \
		markdownlint:.markdownlintignore | markdownlint:.markdownlint-cli2.* | markdownlint:.markdownlint.json* | \
		ruff:pyproject.toml | ruff:ruff.toml | ruff:.ruff.toml | \
		secretlint:.secretlintrc* | \
		shell:.shellcheckrc | \
		swift:.swiftformat | swift:.swiftlint.yml | swift:swiftlint.yml | \
		treefmt_non_swift:.editorconfig | treefmt_non_swift:.prettierignore | treefmt_non_swift:.prettierrc* | treefmt_non_swift:prettier.config.* | treefmt_non_swift:treefmt.toml | \
		typos:_typos.toml | typos:.typos.toml | typos:typos.toml)
		return 0
		;;
	esac
	return 1
}

matches_kind() {
	local path="$1"
	local object
	local first_line
	case "$kind" in
	any | secretlint | typos) return 0 ;;
	ast_grep | swift) [[ "$path" == *.swift ]] ;;
	eslint) [[ "$path" =~ \.(cjs|js|mjs|ts|tsx)$ ]] ;;
	localization) [[ "$path" == *.swift || "$path" == *.xcstrings ]] ;;
	markdownlint) [[ "$path" == *.md ]] ;;
	ruff) [[ "$path" == *.py ]] ;;
	shell)
		if [[ "$path" == *.sh ]]; then
			return 0
		fi
		if [[ "$mode" == "changed" ]]; then
			object="$head:$path"
		else
			object=":$path"
		fi
		first_line=""
		if ! IFS= read -r first_line < <(git -C "$repo" show "$object" 2>/dev/null); then
			[[ -n "$first_line" ]] || return 1
		fi
		[[ "$first_line" =~ ^#!.*(bash|sh|zsh|ksh|dash)([[:space:]]|$) ]]
		;;
	text_spacing) [[ "$path" =~ \.(css|html|json|jsonc|md|toml|txt|xcstrings|yaml|yml)$ ]] ;;
	treefmt_non_swift) [[ "$path" =~ \.(cjs|css|entitlements|html|ipynb|js|json|jsonc|md|mjs|plist|py|sh|svg|toml|ts|tsx|xcscheme|xcstrings|xctestplan|xcworkspacedata|xml|xsd|yaml|yml)$ ]] ;;
	esac
}

write_scope_paths "$source_paths"
"$script_dir/quality-gate-path-filter.sh" --null <"$source_paths" >"$filtered_paths"

expand_scope=0
while IFS= read -r -d '' path; do
	if [[ "$path" == *$'\n'* ]]; then
		printf 'error: path contains a newline and cannot be passed safely to quality gate tools: %q\n' "$path" >&2
		exit 2
	fi
	if is_scope_expansion_path "$path"; then
		expand_scope=1
	fi
done <"$filtered_paths"

if [[ "$expand_scope" == 1 ]]; then
	write_all_paths "$all_paths"
	"$script_dir/quality-gate-path-filter.sh" --null <"$all_paths" >"$filtered_paths"
fi

while IFS= read -r -d '' path; do
	if [[ "$path" == *$'\n'* ]]; then
		printf 'error: path contains a newline and cannot be passed safely to quality gate tools: %q\n' "$path" >&2
		exit 2
	fi
	if matches_kind "$path"; then
		printf '%s\0' "$path"
	fi
done <"$filtered_paths"
