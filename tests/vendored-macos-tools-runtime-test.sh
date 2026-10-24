#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# バイナリの来歴・checksum・licenseはfixture-onlyの構成テストが検証する。
# このテストはmacOS jobで実行し、静的検証では分からない実行可否を確認する。
[[ "$("$ROOT_DIR/bin/macos-arm64/swiftlint" version)" == "0.63.2" ]] || {
    echo 'FAIL: vendored SwiftLint version mismatch' >&2
    exit 1
}
# SwiftFormatはmanifest未登録のため、QualityGates/Treefmtの固定versionに合わせる。
[[ "$("$ROOT_DIR/bin/macos-arm64/swiftformat" --version)" == "0.61.1" ]] || {
    echo 'FAIL: vendored SwiftFormat version mismatch' >&2
    exit 1
}

echo 'PASS'
