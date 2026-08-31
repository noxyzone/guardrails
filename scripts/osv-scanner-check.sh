#!/usr/bin/env bash
set -euo pipefail

repo="."
files_from=""

usage() {
    cat <<'USAGE'
Usage:
  osv-scanner-check.sh --files-from /path/to/files --repo /path/to/repo

Checks listed lockfiles, including Package.resolved, with OSV-Scanner.
USAGE
}

is_lockfile() {
    case "${1##*/}" in
    Cargo.lock | Gemfile.lock | Package.resolved | Pipfile.lock | Podfile.lock | bun.lock | bun.lockb | composer.lock | go.sum | gradle.lockfile | mix.lock | npm-shrinkwrap.json | package-lock.json | pdm.lock | pnpm-lock.yaml | poetry.lock | pubspec.lock | uv.lock | yarn.lock)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --files-from)
        if [[ $# -lt 2 || "$2" == --* ]]; then
            echo "error: --files-from requires a path" >&2
            exit 2
        fi
        files_from="$2"
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

if [[ -z "$files_from" ]]; then
    echo "error: --files-from is required" >&2
    usage >&2
    exit 2
fi
if [[ ! -f "$files_from" ]]; then
    echo "error: file list not found: $files_from" >&2
    exit 2
fi
if [[ ! -d "$repo/.git" ]]; then
    echo "error: repository not found: $repo" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
paths_file="$(mktemp "${TMPDIR:-/tmp}/osv-scanner-check-paths.XXXXXX")"
filtered_paths_file="$(mktemp "${TMPDIR:-/tmp}/osv-scanner-check-filtered-paths.XXXXXX")"
trap 'rm -f "$paths_file" "$filtered_paths_file"' EXIT

while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -n "$path" ]] || continue
    is_lockfile "$path" || continue
    [[ -f "$repo/$path" ]] || continue
    [[ ! -L "$repo/$path" ]] || continue
    printf '%s\0' "$path" >>"$paths_file"
done <"$files_from"

if [[ ! -s "$paths_file" ]]; then
    exit 0
fi

"$script_dir/quality-gate-path-filter.sh" --repo "$repo" --null <"$paths_file" >"$filtered_paths_file"
if [[ ! -s "$filtered_paths_file" ]]; then
    exit 0
fi

scan_args=(scan source --no-resolve --format table)
while IFS= read -r -d '' path; do
    scan_args+=(-L "$path")
done <"$filtered_paths_file"

(cd "$repo" && osv-scanner "${scan_args[@]}")
