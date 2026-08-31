#!/usr/bin/env bash
set -euo pipefail

repo="."
files_from=""

usage() {
    cat <<'USAGE'
Usage:
  gitleaks-check.sh --files-from /path/to/files --repo /path/to/repo

Checks listed files with gitleaks dir. Secrets in output are redacted.
USAGE
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
paths_file="$(mktemp "${TMPDIR:-/tmp}/gitleaks-check-paths.XXXXXX")"
filtered_paths_file="$(mktemp "${TMPDIR:-/tmp}/gitleaks-check-filtered-paths.XXXXXX")"
trap 'rm -f "$paths_file" "$filtered_paths_file"' EXIT

while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -n "$path" ]] || continue
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

status=0
while IFS= read -r -d '' path; do
    if ! (cd / && env -u GITLEAKS_CONFIG -u GITLEAKS_CONFIG_TOML gitleaks stdin --no-banner --redact --exit-code 1 <"$repo/$path"); then
        echo "gitleaks default rule finding: $path" >&2
        status=1
    fi
    if ! (cd / && gitleaks stdin --no-banner --redact --exit-code 1 --config "$script_dir/../.gitleaks.toml" <"$repo/$path"); then
        echo "gitleaks shared rule finding: $path" >&2
        status=1
    fi
done <"$filtered_paths_file"
exit "$status"
