#!/usr/bin/env bash
set -euo pipefail

usage() {
	printf 'usage: quality-gate-path-filter.sh [--repo PATH] [--null | --treefmt-excludes | --manifest-paths]\n' >&2
	exit 2
}

repo_root=""
mode="lines"

while (($# > 0)); do
	case "$1" in
	--repo)
		(($# >= 2)) || usage
		repo_root="$2"
		shift 2
		;;
	--null)
		[[ "$mode" == "lines" ]] || usage
		mode="null"
		shift
		;;
	--treefmt-excludes)
		[[ "$mode" == "lines" ]] || usage
		mode="treefmt-excludes"
		shift
		;;
	--manifest-paths)
		[[ "$mode" == "lines" ]] || usage
		mode="manifest-paths"
		shift
		;;
	*) usage ;;
	esac
done

if [[ -z "$repo_root" ]]; then
	repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -z "$repo_root" ]] || repo_root="$(cd "$repo_root" && pwd -P)"

distribution_manifest="$repo_root/.aidlc-distribution-manifest"
distribution_paths=()

is_aidlc_distribution_path() {
	case "$1" in
	.agents/skills/aidlc* | \
		.codex/aidlc-common | .codex/aidlc-common/* | \
		.codex/config.toml | \
		.codex/hooks.json | \
		.codex/rules/default.rules | \
		.codex/trust-seed.toml | \
		.codex/sensors/aidlc-* | \
		.codex/tools/aidlc.ts | .codex/tools/aidlc-* | \
		.codex/tools/data | .codex/tools/data/* | \
		.codex/agents/aidlc-* | \
		.codex/knowledge/aidlc-* | \
		.codex/hooks/aidlc-* | \
		.codex/scopes/aidlc-*)
		return 0
		;;
	esac
	return 1
}

load_distribution_manifest() {
	local path
	local revision
	[[ -f "$distribution_manifest" ]] || return 0
	IFS= read -r path <"$distribution_manifest" ||
		fail "AIDLC distribution manifest is empty: $distribution_manifest"
	[[ "$path" == "# aidlc-distribution-manifest-v1" ]] ||
		fail "AIDLC distribution manifest has an unsupported header: $distribution_manifest"
	IFS= read -r revision < <(/usr/bin/sed -n '2p' "$distribution_manifest") || true
	[[ "$revision" =~ ^#\ upstream-revision:\ [0-9a-f]{40}$ ]] ||
		fail "AIDLC distribution manifest has an invalid upstream revision: $distribution_manifest"
	while IFS= read -r path || [[ -n "$path" ]]; do
		[[ -n "$path" && "$path" != \#* ]] || continue
		case "$path" in
		/* | *..* | *'['* | *'*'* | *'?'*)
			fail "AIDLC distribution manifest has an unsafe path: $path"
			;;
		esac
		is_aidlc_distribution_path "$path" ||
			fail "AIDLC distribution manifest has a non-distribution path: $path"
		distribution_paths+=("$path")
	done <"$distribution_manifest"
}

fail() {
	printf 'error: %s\n' "$*" >&2
	exit 2
}

load_distribution_manifest

is_managed_artifact_path() {
	local distribution_path
	case "$1" in
	.agents/skills/.system | .agents/skills/.system/* | \
		.agents/skills/hatch-pet | .agents/skills/hatch-pet/* | \
		.agents/skills/openai-curated-*)
		return 0
		;;
	esac
	for distribution_path in "${distribution_paths[@]}"; do
		[[ "$1" == "$distribution_path" ]] && return 0
	done
	return 1
}

case "$mode" in
null)
	while IFS= read -r -d '' path; do
		[[ -n "$path" ]] || continue
		is_managed_artifact_path "$path" && continue
		printf '%s\0' "$path"
	done
	;;
treefmt-excludes)
	printf '%s\n' '.agents/skills/.system/**'
	printf '%s\n' '.agents/skills/hatch-pet/**'
	printf '%s\n' '.agents/skills/openai-curated-*/**'
	printf '%s\n' "${distribution_paths[@]}"
	;;
manifest-paths)
	printf '%s\n' "${distribution_paths[@]}"
	;;
lines)
	while IFS= read -r path || [[ -n "$path" ]]; do
		[[ -n "$path" ]] || continue
		is_managed_artifact_path "$path" && continue
		printf '%s\n' "$path"
	done
	;;
esac
