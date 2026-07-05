#!/usr/bin/env bash
set -euo pipefail

export LC_ALL="${TEXT_SPACING_LOCALE:-C.UTF-8}"

usage() {
	echo "usage: text-spacing-check.sh (--all|--staged) [--repo PATH]" >&2
	exit 2
}

MODE=""
REPO="."
while [ "$#" -gt 0 ]; do
	case "$1" in
	--all | --staged)
		[ -z "$MODE" ] || usage
		MODE="$1"
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

supports_grep_p() {
	local grep_cmd="$1"
	printf 'あ A\n' | "$grep_cmd" -P '[\p{Hiragana}\p{Katakana}\p{Han}] [A-Za-z0-9]' >/dev/null 2>&1
}

if [ -x /run/current-system/sw/bin/grep ] && supports_grep_p /run/current-system/sw/bin/grep; then
	GREP_CMD="/run/current-system/sw/bin/grep"
elif [ -x /opt/homebrew/bin/ggrep ] && supports_grep_p /opt/homebrew/bin/ggrep; then
	GREP_CMD="/opt/homebrew/bin/ggrep"
elif command -v ggrep >/dev/null 2>&1 && supports_grep_p ggrep; then
	GREP_CMD="ggrep"
elif command -v grep >/dev/null 2>&1 && supports_grep_p grep; then
	GREP_CMD="grep"
else
	echo "text-spacing-check.sh: GNU grep with -P support is required (run scripts/install/nix-darwin-apply.sh)" >&2
	exit 2
fi

collect_files() {
	case "$MODE" in
	--all)
		git -C "$REPO" ls-files
		;;
	--staged)
		git -C "$REPO" -c core.quotepath=false diff --cached --name-only --diff-filter=ACM
		;;
	*)
		usage
		;;
	esac
}

is_target_file() {
	case "$1" in
	*.md | *.txt | *.toml | *.yaml | *.yml | *.json | *.jsonc | *.html | *.css)
		return 0
		;;
	esac
	return 1
}

is_excluded_file() {
	case "$1" in
	.claude/plugins/* | .claude/todos/* | .claude/cache/* | .claude/projects/* | .claude/plans/* | .claude/shell-snapshots/* | node_modules/* | contrib/* | artifacts/* | pipedream/html/*)
		return 0
		;;
	esac
	return 1
}

FOUND=0
SPACING_PATTERN='[\p{Hiragana}\p{Katakana}\p{Han}] [A-Za-z0-9]|[A-Za-z0-9] [\p{Hiragana}\p{Katakana}\p{Han}]'
FILES="$(collect_files | while IFS= read -r file; do
	is_target_file "$file" || continue
	is_excluded_file "$file" && continue
	printf '%s\n' "$file"
done)"

[ -n "$FILES" ] || exit 0

while IFS= read -r file; do
	full_path="$REPO/$file"
	[ -L "$full_path" ] && continue
	[ -f "$full_path" ] || continue

	candidates="$("$GREP_CMD" -nP "$SPACING_PATTERN" "$full_path" || true)"
	[ -n "$candidates" ] || continue

	while IFS= read -r candidate; do
		line_number="${candidate%%:*}"
		line="${candidate#*:}"
		fence_count="$(sed -n "1,${line_number}p" "$full_path" | "$GREP_CMD" -c '^```' || true)"
		[ $((fence_count % 2)) -eq 1 ] && continue
		# shellcheck disable=SC2016
		cleaned="$(printf '%s\n' "$line" | sed -E 's/`[^`]+`//g; s#https?://[^[:space:]]+##g')"
		if printf '%s\n' "$cleaned" | "$GREP_CMD" -nP "$SPACING_PATTERN" >/dev/null; then
			[ "$FOUND" -eq 0 ] && echo "[text-spacing] 和欧間スペース違反:"
			printf '  %s:%s:%s\n' "$file" "$line_number" "$line"
			FOUND=1
		fi
	done <<<"$candidates"
done <<<"$FILES"

exit "$FOUND"
