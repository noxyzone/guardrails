#!/usr/bin/env bash
set -euo pipefail

repo=""
base=""
head=""
output=""
all=0
changed=0
range_mode="merge-base"
range_mode_selected=0

usage() {
	cat <<'USAGE' >&2
usage: quality-gate-change-detection.sh --repo PATH (--changed --base SHA --head SHA [--range-mode merge-base|direct] | --all) --output PATH
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
	--output)
		(($# >= 2)) || usage
		output="$2"
		shift 2
		;;
	--range-mode)
		(($# >= 2)) || usage
		range_mode="$2"
		range_mode_selected=1
		shift 2
		;;
	--changed)
		changed=1
		shift
		;;
	--all)
		all=1
		shift
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
if [[ "$all" == 0 && (-z "$base" || -z "$head") ]]; then
	printf 'error: --base and --head are required unless --all is used\n' >&2
	exit 2
fi
if [[ "$all" == 1 && (-n "$base" || -n "$head") ]]; then
	printf 'error: --all cannot be combined with --base or --head\n' >&2
	exit 2
fi
if [[ "$all" == 1 && "$changed" == 1 ]]; then
	printf 'error: --all cannot be combined with --changed\n' >&2
	exit 2
fi
if [[ "$range_mode" != merge-base && "$range_mode" != direct ]]; then
	printf 'error: --range-mode must be merge-base or direct\n' >&2
	exit 2
fi
if [[ "$all" == 1 && "$range_mode_selected" == 1 ]]; then
	printf 'error: --all cannot be combined with --range-mode\n' >&2
	exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
targets_file="$(mktemp "${TMPDIR:-/tmp}/quality-gate-change-detection.XXXXXX")"
trap 'rm -f "$targets_file"' EXIT
scope_args=(--all)
if [[ "$all" == 0 ]]; then
	scope_args=(--changed --base "$base" --head "$head" --range-mode "$range_mode")
fi

has_targets() {
	local kind="$1"
	"$script_dir/quality-gate-targets.sh" --repo "$repo" "${scope_args[@]}" --kind "$kind" >"$targets_file"
	if [[ -s "$targets_file" ]]; then
		printf 'true'
	else
		printf 'false'
	fi
}

any="$(has_targets any)"
ast_grep="$(has_targets ast_grep)"
eslint="$(has_targets eslint)"
localization="$(has_targets localization)"
markdownlint="$(has_targets markdownlint)"
ruff="$(has_targets ruff)"
secretlint="$(has_targets secretlint)"
shell="$(has_targets shell)"
swift="$(has_targets swift)"
text_spacing="$(has_targets text_spacing)"
treefmt_non_swift="$(has_targets treefmt_non_swift)"
typos="$(has_targets typos)"
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
