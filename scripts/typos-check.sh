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
  typos-check.sh --staged --repo /path/to/repo
  typos-check.sh --files-from /path/to/files --repo /path/to/repo
  typos-check.sh --changed --base BASE --head HEAD --repo /path/to/repo

Checks only commit/PR target files with a repo-local or shared typos.toml config.
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
config="$guardrails_dir/typos.toml"
repo_config_file=""
for config_name in _typos.toml .typos.toml typos.toml; do
    candidate="$repo/$config_name"
    if [[ -f "$candidate" ]]; then
        config="$candidate"
        break
    fi
    if git -C "$repo" cat-file -e ":$config_name" 2>/dev/null; then
        repo_config_file="$(mktemp "${TMPDIR:-/tmp}/typos-check-config.XXXXXX")"
        git -C "$repo" show ":$config_name" >"$repo_config_file"
        config="$repo_config_file"
        break
    fi
done

if [[ ! -f "$config" ]]; then
    echo "error: typos config not found: $config" >&2
    exit 2
fi

paths_file="$(mktemp "${TMPDIR:-/tmp}/typos-check-paths.XXXXXX")"
filtered_paths_file=""
cleanup() {
    rm -f "$paths_file"
    [[ -z "$filtered_paths_file" ]] || rm -f "$filtered_paths_file"
    [[ -z "$repo_config_file" ]] || rm -f "$repo_config_file"
}
trap cleanup EXIT

append_existing_files() {
    local path
    while IFS= read -r -d '' path; do
        [[ -f "$repo/$path" ]] || continue
        [[ ! -L "$repo/$path" ]] || continue
        printf '%s\n' "$path" >>"$paths_file"
    done
}

append_listed_files() {
    local path
    while IFS= read -r path || [[ -n "$path" ]]; do
        [[ -f "$repo/$path" ]] || continue
        [[ ! -L "$repo/$path" ]] || continue
        printf '%s\n' "$path" >>"$paths_file"
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

filtered_paths_file="$(mktemp "${TMPDIR:-/tmp}/typos-check-filtered-paths.XXXXXX")"
"$script_dir/quality-gate-path-filter.sh" --repo "$repo" <"$paths_file" >"$filtered_paths_file"
if [[ ! -s "$filtered_paths_file" ]]; then
    exit 0
fi

(cd "$repo" && typos --isolated --force-exclude --config "$config" --file-list "$filtered_paths_file")
