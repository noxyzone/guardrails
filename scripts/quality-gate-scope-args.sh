#!/usr/bin/env bash
set -euo pipefail

usage() {
	printf 'usage: quality-gate-scope-args.sh --scope (changed|all) --event-name NAME [--base SHA --head SHA]\n' >&2
	exit 2
}

scope=""
event_name=""
base=""
head=""

while (($# > 0)); do
	case "$1" in
	--scope)
		(($# >= 2)) || usage
		scope="$2"
		shift 2
		;;
	--event-name)
		(($# >= 2)) || usage
		event_name="$2"
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
	*)
		usage
		;;
	esac
done

[[ -n "$event_name" ]] || usage
case "$scope" in
all)
	printf '%s\0' --all
	;;
changed)
	[[ -n "$base" && -n "$head" ]] || {
		printf 'error: changed scope requires non-empty base and head revisions\n' >&2
		exit 2
	}
	range_mode=direct
	if [[ "$event_name" == pull_request ]]; then
		range_mode=merge-base
	fi
	printf '%s\0' --changed --base "$base" --head "$head" --range-mode "$range_mode"
	;;
*)
	printf 'error: scope must be changed or all\n' >&2
	exit 2
	;;
esac
