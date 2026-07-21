#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
	echo "usage: llm-cli-stream-check.sh (--all|--staged|--files-from PATH) [--repo PATH]" >&2
	exit 2
}

MODE=""
REPO="."
FILES_FROM=""
while [ "$#" -gt 0 ]; do
	case "$1" in
	--all | --staged)
		[ -z "$MODE" ] || usage
		MODE="$1"
		;;
	--files-from)
		[ -z "$MODE" ] || usage
		[ "$#" -ge 2 ] || usage
		MODE="$1"
		FILES_FROM="$2"
		shift
		;;
	--repo)
		[ "$#" -ge 2 ] || usage
		REPO="$2"
		shift
		;;
	*)
		usage
		;;
	esac
	shift
done

[ -n "$MODE" ] || usage
if [ "$MODE" = "--files-from" ]; then
	[ -f "$FILES_FROM" ] || usage
fi

collect_files() {
	case "$MODE" in
	--all)
		git -C "$REPO" ls-files
		;;
	--staged)
		git -C "$REPO" -c core.quotepath=false diff --cached --name-only --diff-filter=ACM
		;;
	--files-from)
		cat "$FILES_FROM"
		;;
	*)
		usage
		;;
	esac
}

is_shell_file() {
	case "$1" in
	*/zsh/* | */zsh)
		return 1
		;;
	esac
	case "$1" in
	*.sh)
		return 0
		;;
	esac
	return 1
}

is_excluded_file() {
	case "$1" in
	contrib/* | vendor/* | node_modules/* | .claude/plugins/* | plugins/cache/*)
		return 0
		;;
	esac
	return 1
}

# Small, deterministic producers whose piped output is not a heavy subprocess trace.
is_small_producer() {
	case "$1" in
	printf | echo | cat | sed | awk | tr | head | tail | true | false | :)
		return 0
		;;
	esac
	return 1
}

FOUND=0
FILES="$(collect_files | "$script_dir/quality-gate-path-filter.sh" | while IFS= read -r file; do
	is_shell_file "$file" || continue
	is_excluded_file "$file" && continue
	printf '%s\n' "$file"
done)"

[ -n "$FILES" ] || exit 0

while IFS= read -r file; do
	full_path="$REPO/$file"
	[ -L "$full_path" ] && continue
	[ -f "$full_path" ] || continue

	candidates="$(grep -nE '\|[[:space:]]*tee([[:space:]]|$)' "$full_path" || true)"
	[ -n "$candidates" ] || continue

	while IFS= read -r candidate; do
		line_number="${candidate%%:*}"
		line="${candidate#*:}"

		printf '%s\n' "$line" | grep -qE '>[[:space:]]*/dev/null' && continue
		printf '%s\n' "$line" | grep -qF 'guardrail-allow: llm-cli-stream' && continue

		trimmed="${line#"${line%%[![:space:]]*}"}"
		first_token="${trimmed%%[[:space:]]*}"
		first_token="${first_token%%|*}"
		is_small_producer "$first_token" && continue

		if [ "$FOUND" -eq 0 ]; then
			echo "[llm-cli-stream] サブプロセス出力のstdout垂れ流し（ログファイルへ隔離し要約だけ出す。tee利用時は>/dev/nullで無音化する）:"
		fi
		printf '  %s:%s:%s\n' "$file" "$line_number" "$line"
		FOUND=1
	done <<<"$candidates"
done <<<"$FILES"

exit "$FOUND"
