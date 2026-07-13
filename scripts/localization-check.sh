#!/usr/bin/env bash
set -euo pipefail

repo="."
mode=""
base_sha=""
head_sha=""

usage() {
	cat <<'USAGE'
Usage:
  localization-check.sh --all --repo /path/to/repo
  localization-check.sh --staged --repo /path/to/repo
  localization-check.sh --changed --base BASE --head HEAD --repo /path/to/repo

Checks tracked Swift localization files for missing ja localizations and
AppKit/custom UI strings that SwiftUI extraction will not pick up.
USAGE
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--all)
		mode="all"
		shift
		;;
	--staged)
		mode="staged"
		shift
		;;
	--changed)
		mode="changed"
		shift
		;;
	--base)
		if [[ $# -lt 2 || "$2" == --* ]]; then
			echo "error: --base requires a revision" >&2
			exit 2
		fi
		base_sha="$2"
		shift 2
		;;
	--head)
		if [[ $# -lt 2 || "$2" == --* ]]; then
			echo "error: --head requires a revision" >&2
			exit 2
		fi
		head_sha="$2"
		shift 2
		;;
	--repo)
		if [[ $# -lt 2 || "$2" == --* ]]; then
			echo "error: --repo requires a path" >&2
			exit 2
		fi
		repo="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "error: unsupported option: $1" >&2
		usage >&2
		exit 2
		;;
	esac
done

if [[ "$mode" != "all" && "$mode" != "staged" && "$mode" != "changed" ]]; then
	echo "error: --all, --staged, or --changed is required" >&2
	usage >&2
	exit 2
fi

if [[ ! -d "$repo/.git" ]]; then
	echo "error: repository not found: $repo" >&2
	exit 2
fi

found=0
paths_file="$(mktemp "${TMPDIR:-/tmp}/localization-check-paths.XXXXXX")"
trap 'rm -f "$paths_file"' EXIT

append_existing_files() {
	local path
	while IFS= read -r -d '' path; do
		case "$path" in
		*.swift | *.xcstrings) ;;
		*) continue ;;
		esac
		[[ -f "$repo/$path" ]] || continue
		[[ ! -L "$repo/$path" ]] || continue
		printf '%s\n' "$path" >>"$paths_file"
	done
}

case "$mode" in
all)
	git -C "$repo" -c core.quotepath=false ls-files -z '*.swift' '*.xcstrings' ':!:DerivedData/**' ':!:.build/**' ':!:build/**' | append_existing_files
	;;
staged)
	git -C "$repo" -c core.quotepath=false diff -z --cached --name-only --diff-filter=ACMRT | append_existing_files
	;;
changed)
	if [[ -z "$base_sha" || -z "$head_sha" ]]; then
		echo "error: --changed requires --base and --head" >&2
		exit 2
	fi
	if [[ "$base_sha" == "0000000000000000000000000000000000000000" ]]; then
		git -C "$repo" -c core.quotepath=false ls-files -z '*.swift' '*.xcstrings' ':!:DerivedData/**' ':!:.build/**' ':!:build/**' | append_existing_files
	else
		git -C "$repo" -c core.quotepath=false diff -z --name-only --diff-filter=ACMRT "$base_sha" "$head_sha" | append_existing_files
	fi
	;;
esac

xcstrings_files="$(grep -E '\.xcstrings$' "$paths_file" || true)"
if [[ -n "$xcstrings_files" ]]; then
	while IFS= read -r file; do
		[[ -f "$repo/$file" ]] || continue
		missing="$(
			jq -r '
			  select((.sourceLanguage // "en") == "en")
			  | .strings
			  | to_entries[]
			  | select(.value.extractionState != "stale")
			  | select(.key | test("[A-Za-z]"))
			  | select(.key | test("[ぁ-んァ-ン一-龯]") | not)
			  | select(.key | test("^(https?://|/|HEAD@\\{|[-+~]?[0-9%@{}._/: -]+$)") | not)
			  | select(((.value.localizations // {}) | has("ja")) | not)
			  | .key
			' "$repo/$file"
		)"
		if [[ -n "$missing" ]]; then
			[[ "$found" -eq 0 ]] && echo "[localization] Localizable.xcstringsのja未登録キー:"
			while IFS= read -r key; do
				printf '  %s: %s\n' "$file" "$key"
			done <<<"$missing"
			found=1
		fi
	done <<<"$xcstrings_files"
fi

swift_files="$(grep -E '\.swift$' "$paths_file" || true)"
if [[ -n "$swift_files" ]]; then
	appkit_matches="$(
		while IFS= read -r file; do
			[[ -f "$repo/$file" ]] || continue
			grep -nE 'NSMenuItem[[:space:]]*\([[:space:]]*title:[[:space:]]*"|Action[[:space:]]*\([[:space:]]*title:[[:space:]]*"|panel\.(title|message)[[:space:]]*=[[:space:]]*"|column\.title[[:space:]]*=[[:space:]]*"' "$repo/$file" | sed "s#^$repo/##" || true
		done <<<"$swift_files"
	)"
	if [[ -n "$appkit_matches" ]]; then
		[[ "$found" -eq 0 ]] && echo "[localization] SwiftUI自動抽出に乗らないUI文字列:"
		printf '%s\n' "$appkit_matches" | sed 's/^/  /'
		found=1
	fi
fi

exit "$found"
