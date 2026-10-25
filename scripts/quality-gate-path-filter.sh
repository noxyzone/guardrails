#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'usage: quality-gate-path-filter.sh [--repo PATH] [--null | --treefmt-excludes]\n' >&2
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
    *) usage ;;
    esac
done

if [[ -z "$repo_root" ]]; then
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -z "$repo_root" ]] || repo_root="$(cd "$repo_root" && pwd -P)"

is_managed_artifact_path() {
    case "$1" in
    .agents/skills/.system | .agents/skills/.system/* | \
        .agents/skills/openai-curated-* | \
        bin | bin/* | \
        .github/quality-gates/node_modules | .github/quality-gates/node_modules/*)
        return 0
        ;;
    esac
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
    printf '%s\n' '.agents/skills/openai-curated-*/**'
    printf '%s\n' 'bin/**'
    printf '%s\n' '.github/quality-gates/node_modules/**'
    ;;
lines)
    while IFS= read -r path || [[ -n "$path" ]]; do
        [[ -n "$path" ]] || continue
        is_managed_artifact_path "$path" && continue
        printf '%s\n' "$path"
    done
    ;;
esac
