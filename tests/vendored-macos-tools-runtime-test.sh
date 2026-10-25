#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

verify_tool() {
    local label="$1" binary="$2" expected_version="$3" expected_sha="$4"
    local actual_sha output rc
    shift 4

    # 整合性が崩れた配布物は、版を調べるためにも実行しない。
    if [[ "$expected_sha" != '-' ]]; then
        if ! actual_sha="$(shasum -a 256 "$binary" | awk '{print $1}')"; then
            printf 'FAIL: vendored %s checksum could not be read\n' "$label" >&2
            return 1
        fi
        if [[ "$actual_sha" != "$expected_sha" ]]; then
            printf 'FAIL: vendored %s checksum mismatch\n' "$label" >&2
            return 1
        fi
    fi

    if output="$("$binary" "$@" 2>&1)"; then
        :
    else
        rc=$?
        printf 'FAIL: vendored %s not executable (exit %s)\n' "$label" "$rc" >&2
        return 1
    fi
    if [[ "$output" != "$expected_version" ]]; then
        printf 'FAIL: vendored %s version mismatch (expected %s)\n' "$label" "$expected_version" >&2
        return 1
    fi
}

main() {
    local manifest_values expected_version expected_sha
    if [[ "$(uname -s)" != Darwin ]]; then
        echo 'FAIL: vendored macOS runtime test requires macOS' >&2
        return 1
    fi

    # 来歴・license・宣言値自体はLinuxの静的検査で固定する。
    # 実行するこのjobでもmanifestのSHAを照合する。
    if ! manifest_values="$(awk -F '\t' '
        $1 == "swiftlint" && $2 == "macos-arm64" { count++; version = $3; sha = $6 }
        END {
            if (count != 1 || version == "" || length(sha) != 64 || sha ~ /[^0-9a-f]/) exit 1
            print version, sha
        }
    ' "$ROOT_DIR/config/vendored-tools.tsv")"; then
        echo 'FAIL: vendored SwiftLint manifest entry is invalid' >&2
        return 1
    fi
    read -r expected_version expected_sha <<<"$manifest_values"
    verify_tool SwiftLint "$ROOT_DIR/bin/macos-arm64/swiftlint" "$expected_version" "$expected_sha" version || return 1
    # SwiftFormatはmanifest未登録のため、現行の固定versionを維持する。
    verify_tool SwiftFormat "$ROOT_DIR/bin/macos-arm64/swiftformat" 0.61.1 - --version || return 1
    echo 'PASS'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
