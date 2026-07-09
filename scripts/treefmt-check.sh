#!/usr/bin/env bash
set -euo pipefail

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guardrails_dir="$(cd "$script_dir/.." && pwd)"
repo_root="."
created_guardrails_dir=0
created_editorconfig=0
treefmt_noswift_config_path=""
treefmt_mode="check"
treefmt_args=()
treefmt_timeout_seconds="${TREEFMT_TIMEOUT_SECONDS:-10}"
treefmt_without_swiftformat=0

while [[ "$#" -gt 0 ]]; do
	case "$1" in
	--check)
		treefmt_mode="check"
		;;
	--write)
		treefmt_mode="write"
		;;
	--without-swiftformat)
		treefmt_without_swiftformat=1
		;;
	--repo)
		[[ "$#" -ge 2 ]] || fail "--repo requires a path"
		repo_root="$2"
		shift
		;;
	*)
		treefmt_args+=("$1")
		;;
	esac
	shift
done

repo_root="$(cd "$repo_root" && pwd)"

if [[ ! -f "$guardrails_dir/treefmt.toml" ]]; then
	fail "treefmt config not found: $guardrails_dir/treefmt.toml"
fi

if [[ ! -e "$repo_root/.guardrails" ]]; then
	mkdir "$repo_root/.guardrails"
	cp "$guardrails_dir/treefmt.toml" "$repo_root/.guardrails/treefmt.toml"
	cp "$guardrails_dir/prettier.cjs" "$repo_root/.guardrails/prettier.cjs"
	created_guardrails_dir=1
fi

cleanup() {
	if [[ -n "$treefmt_noswift_config_path" ]]; then
		rm -f "$treefmt_noswift_config_path"
	fi
	if [[ "$created_guardrails_dir" == 1 ]]; then
		rm -rf "$repo_root/.guardrails"
	fi
	if [[ "$created_editorconfig" == 1 ]]; then
		rm "$repo_root/.editorconfig"
	fi
}
trap cleanup EXIT

if ! command -v treefmt >/dev/null; then
	fail "treefmt is not installed"
fi

case "$treefmt_timeout_seconds" in
'' | *[!0-9]*)
	fail "TREEFMT_TIMEOUT_SECONDS must be a positive integer"
	;;
0)
	fail "TREEFMT_TIMEOUT_SECONDS must be greater than 0"
	;;
esac

run_with_timeout() {
	local timeout_seconds="$1"
	local timeout_marker
	local command_pid
	local watchdog_pid
	local status

	shift
	timeout_marker="$(mktemp "${TMPDIR:-/tmp}/treefmt-timeout.XXXXXX")"
	rm -f "$timeout_marker"

	"$@" &
	command_pid="$!"
	(
		sleep "$timeout_seconds"
		if kill -0 "$command_pid" 2>/dev/null; then
			: >"$timeout_marker"
			kill "$command_pid" 2>/dev/null || true
			sleep 1
			kill -9 "$command_pid" 2>/dev/null || true
		fi
	) &
	watchdog_pid="$!"

	if wait "$command_pid"; then
		status=0
	else
		status="$?"
	fi
	kill "$watchdog_pid" 2>/dev/null || true
	wait "$watchdog_pid" 2>/dev/null || true

	if [[ -e "$timeout_marker" ]]; then
		rm -f "$timeout_marker"
		fail "treefmt timed out after ${timeout_seconds}s"
	fi
	rm -f "$timeout_marker"
	return "$status"
}

if [[ ! -e "$repo_root/.editorconfig" ]]; then
	printf '%s\n' 'root = true' >"$repo_root/.editorconfig"
	created_editorconfig=1
fi

{
	printf '%s\n' '--swiftversion 6.0'
	printf '%s\n' '--exclude DerivedData,.build,build'
	printf '%s\n' '--indent 4'
	printf '%s\n' '--maxwidth none'
	printf '%s\n' '--wraparguments before-first'
	printf '%s\n' '--wrapcollections before-first'
	printf '%s\n' '--wrapparameters before-first'
	printf '%s\n' '--commas inline'
	printf '%s\n' '--trimwhitespace always'
	printf '%s\n' '--header ignore'
	printf '%s\n' '--disable redundantSelf'
	printf '%s\n' '--disable unusedArguments'
	printf '%s\n' '--disable wrapMultilineStatementBraces'
} >"$repo_root/.guardrails/.swiftformat"

if [[ "$treefmt_without_swiftformat" == 1 ]]; then
	treefmt_noswift_config_path="$(mktemp "${TMPDIR:-/tmp}/treefmt-noswift.XXXXXX.toml")"
	awk '
        /^\[formatter\.swiftformat\]$/ {
            skip=1
            next
        }
        skip && /^\[formatter\./ {
            skip=0
        }
        !skip {
            print
        }
	' "$repo_root/.guardrails/treefmt.toml" >"$treefmt_noswift_config_path"
	treefmt_config_path="$treefmt_noswift_config_path"
else
	treefmt_config_path=".guardrails/treefmt.toml"
fi

cd "$repo_root"
if [[ "$treefmt_mode" == "write" ]]; then
	run_with_timeout "$treefmt_timeout_seconds" treefmt --tree-root "$repo_root" --config-file "$treefmt_config_path" "${treefmt_args[@]}"
else
	run_with_timeout "$treefmt_timeout_seconds" treefmt --ci --tree-root "$repo_root" --config-file "$treefmt_config_path" "${treefmt_args[@]}"
fi
