#!/usr/bin/env bash
set -euo pipefail

repo=""
files_from=""

usage() {
    printf 'usage: gofmt-check.sh --repo PATH --files-from PATH\n' >&2
    exit 2
}

while (($# > 0)); do
    case "$1" in
    --repo)
        (($# >= 2)) || usage
        repo="$2"
        shift 2
        ;;
    --files-from)
        (($# >= 2)) || usage
        files_from="$2"
        shift 2
        ;;
    *) usage ;;
    esac
done

[[ -n "$repo" && -n "$files_from" ]] || usage
[[ -d "$repo" ]] || {
    printf 'error: --repo must identify a directory: %s\n' "$repo" >&2
    exit 2
}
[[ -f "$files_from" ]] || {
    printf 'error: --files-from must identify a file: %s\n' "$files_from" >&2
    exit 2
}
command -v gofmt >/dev/null 2>&1 || {
    printf 'error: gofmt is not installed\n' >&2
    exit 2
}

failed=0
while IFS= read -r -d '' path; do
    case "$path" in
    /* | ../* | */../* | */..)
        printf '[gofmt] unsafe repository-relative path: %q\n' "$path" >&2
        failed=1
        continue
        ;;
    esac
    if [[ "$path" != *.go ]]; then
        printf '[gofmt] non-Go target: %s\n' "$path" >&2
        failed=1
        continue
    fi
    if [[ ! -f "$repo/$path" ]]; then
        printf '[gofmt] target does not exist: %s\n' "$path" >&2
        failed=1
        continue
    fi

    result=""
    if ! result="$(gofmt -l "$repo/$path" 2>/dev/null)"; then
        printf '[gofmt] could not format: %s\n' "$path" >&2
        failed=1
    elif [[ -n "$result" ]]; then
        printf '[gofmt] formatting required: %s\n' "$path" >&2
        failed=1
    fi
done <"$files_from"

exit "$failed"
