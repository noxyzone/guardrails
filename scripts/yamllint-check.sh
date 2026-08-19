#!/usr/bin/env bash
set -euo pipefail

repo="."
mode=""
base_sha=""
head_sha=""
files_from=""

usage() {
    cat <<'USAGE'
Usage:
  yamllint-check.sh --staged --repo /path/to/repo
  yamllint-check.sh --files-from /path/to/files --repo /path/to/repo
  yamllint-check.sh --changed --base BASE --head HEAD --repo /path/to/repo

Checks only commit/PR target *.yaml/*.yml files with the shared .yamllint.yml
config. .github/workflows/ is excluded; actionlint owns that scope.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --staged)
        mode="staged"
        shift
        ;;
    --changed)
        mode="changed"
        shift
        ;;
    --files-from)
        if [[ $# -lt 2 || "$2" == --* ]]; then
            echo "error: --files-from requires a path" >&2
            exit 2
        fi
        mode="files"
        files_from="$2"
        shift 2
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

if [[ "$mode" != "staged" && "$mode" != "changed" && "$mode" != "files" ]]; then
    echo "error: --staged, --changed, or --files-from is required" >&2
    usage >&2
    exit 2
fi
if [[ "$mode" == "files" && ! -f "$files_from" ]]; then
    echo "error: file list not found: $files_from" >&2
    exit 2
fi

if [[ ! -d "$repo/.git" ]]; then
    echo "error: repository not found: $repo" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guardrails_dir="$(cd "$script_dir/.." && pwd)"
config="$guardrails_dir/.yamllint.yml"

if [[ ! -f "$config" ]]; then
    echo "error: yamllint config not found: $config" >&2
    exit 2
fi

paths_file="$(mktemp "${TMPDIR:-/tmp}/yamllint-check-paths.XXXXXX")"
filtered_paths_file="$(mktemp "${TMPDIR:-/tmp}/yamllint-check-filtered-paths.XXXXXX")"
trap 'rm -f "$paths_file" "$filtered_paths_file"' EXIT

is_yaml_path() {
    case "$1" in
    .github/workflows/*) return 1 ;;
    *.yaml | *.yml) return 0 ;;
    *) return 1 ;;
    esac
}

append_existing_files() {
    local path
    while IFS= read -r -d '' path; do
        [[ -f "$repo/$path" ]] || continue
        [[ ! -L "$repo/$path" ]] || continue
        is_yaml_path "$path" || continue
        printf '%s\0' "$path" >>"$paths_file"
    done
}

append_listed_files() {
    local path
    while IFS= read -r path || [[ -n "$path" ]]; do
        [[ -f "$repo/$path" ]] || continue
        [[ ! -L "$repo/$path" ]] || continue
        is_yaml_path "$path" || continue
        printf '%s\0' "$path" >>"$paths_file"
    done
}

if [[ "$mode" == "staged" ]]; then
    git -C "$repo" -c core.quotepath=false diff -z --cached --name-only --diff-filter=ACMRT | append_existing_files
elif [[ "$mode" == "files" ]]; then
    append_listed_files <"$files_from"
else
    if [[ -z "$base_sha" || -z "$head_sha" ]]; then
        echo "error: --changed requires --base and --head" >&2
        exit 2
    fi

    if [[ "$base_sha" == "0000000000000000000000000000000000000000" ]]; then
        git -C "$repo" -c core.quotepath=false ls-files -z | append_existing_files
    else
        git -C "$repo" -c core.quotepath=false diff -z --name-only --diff-filter=ACMRT "$base_sha" "$head_sha" | append_existing_files
    fi
fi

if [[ ! -s "$paths_file" ]]; then
    exit 0
fi

"$script_dir/quality-gate-path-filter.sh" --repo "$repo" --null <"$paths_file" >"$filtered_paths_file"
if [[ ! -s "$filtered_paths_file" ]]; then
    exit 0
fi

(cd "$repo" && xargs -0 -r yamllint --strict --config-file "$config" -- <"$filtered_paths_file")
