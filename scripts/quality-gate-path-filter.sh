#!/usr/bin/env bash
set -euo pipefail

usage() {
	printf 'usage: quality-gate-path-filter.sh [--null | --treefmt-excludes]\n' >&2
	exit 2
}

is_managed_artifact_path() {
	case "$1" in
	.agents/skills/aidlc* | \
		.codex/agents/aidlc-* | \
		.codex/aidlc-common | .codex/aidlc-common/* | \
		.codex/hooks/aidlc-* | \
		.codex/knowledge/aidlc-* | \
		.codex/scopes/aidlc-* | \
		.codex/sensors/aidlc-* | \
		.codex/tools/aidlc-* | \
		.codex/tools/data | .codex/tools/data/* | \
		aidlc/spaces | aidlc/spaces/*)
		return 0
		;;
	esac
	return 1
}

if (($# > 1)); then
	usage
fi
if (($# == 1)); then
	if [[ "$1" == "--null" ]]; then
		while IFS= read -r -d '' path; do
			[[ -n "$path" ]] || continue
			is_managed_artifact_path "$path" && continue
			printf '%s\0' "$path"
		done
		exit 0
	fi
	[[ "$1" == "--treefmt-excludes" ]] || usage
	printf '%s\n' \
		'.agents/skills/aidlc*/**' \
		'.codex/agents/aidlc-*/**' \
		'.codex/aidlc-common/**' \
		'.codex/hooks/aidlc-*/**' \
		'.codex/hooks/aidlc-*' \
		'.codex/knowledge/aidlc-*/**' \
		'.codex/scopes/aidlc-*/**' \
		'.codex/sensors/aidlc-*/**' \
		'.codex/tools/aidlc-*/**' \
		'.codex/tools/aidlc-*' \
		'.codex/tools/data/**' \
		'aidlc/spaces/**'
	exit 0
fi

while IFS= read -r path || [[ -n "$path" ]]; do
	[[ -n "$path" ]] || continue
	is_managed_artifact_path "$path" && continue
	printf '%s\n' "$path"
done
