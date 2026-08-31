#!/usr/bin/env bash
set -euo pipefail

repo=""
mode=""
files_from=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --repo)
        repo="$2"
        shift 2
        ;;
    --staged)
        mode="staged"
        shift
        ;;
    --files-from)
        mode="files"
        files_from="$2"
        shift 2
        ;;
    *)
        printf 'error: unknown argument: %s\n' "$1" >&2
        exit 2
        ;;
    esac
done

if [[ -z "$repo" || -z "$mode" ]]; then
    echo 'Usage: guardrails-main-ref-check.sh --repo <path> (--staged|--files-from <path>)' >&2
    exit 2
fi
if [[ "$mode" == "files" && ! -f "$files_from" ]]; then
    printf 'error: files list not found: %s\n' "$files_from" >&2
    exit 2
fi

repo="$(cd "$repo" && pwd -P)"

content_for_path() {
    local path="$1"

    if [[ "$mode" == "staged" ]]; then
        (cd "$repo" && git show ":$path")
    else
        cat "$repo/$path"
    fi
}

check_path() {
    local path="$1"

    case "$path" in
    .github/workflows/*.yml | .github/workflows/*.yaml) ;;
    *) return ;;
    esac

    if content_for_path "$path" |
        rg -n 'uses:[[:space:]]*noxyzone/guardrails/\.github/workflows/[^@[:space:]]+@' |
        grep -Ev '@main([[:space:]]|$)' >/dev/null; then
        printf 'error: %s must track noxyzone/guardrails workflows at @main\n' "$path" >&2
        failed=true
    fi

    if content_for_path "$path" | rg -q '^[[:space:]]*guardrails-ref:'; then
        printf 'error: %s must not override guardrails/main through guardrails-ref\n' "$path" >&2
        failed=true
    fi
}

failed=false
if [[ "$mode" == "staged" ]]; then
    (cd "$repo" && git rev-parse --show-toplevel >/dev/null)
    while IFS= read -r -d '' path; do
        check_path "$path"
    done < <((cd "$repo" && git diff --cached --name-only --diff-filter=ACMRT -z --))
else
    while IFS= read -r -d '' path; do
        check_path "$path"
    done <"$files_from"
fi

if "$failed"; then
    exit 1
fi
