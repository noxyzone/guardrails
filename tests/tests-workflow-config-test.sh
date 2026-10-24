#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/tests.yml"
status=0

job_body() {
    awk -v job="$1" '
        /^  [a-z_]+:/ { active = ($0 == "  " job ":") }
        active { print }
    ' "$WORKFLOW"
}

require_text() {
    if ! grep -Fq -- "$2" <<<"$1"; then
        echo "FAIL: $3: $2" >&2
        status=1
    fi
}

unit_job="$(job_body unit_tests)"
real_job="$(job_body real_tool_tests)"
mac_job="$(job_body macos_vendored_tools)"
aggregate_job="$(job_body tests)"

require_text "$unit_job" "tests/vendored-macos-tools-runtime-test.sh | \\" 'unit tests must exclude macOS runtime tests'
require_text "$unit_job" "tests/typos-check-repo-config-test.sh | \\" 'unit tests must exclude real Typos tests'
require_text "$real_job" "tests/typos-check-repo-config-test.sh \\" 'real-tool tests must run the repository Typos test'
require_text "$mac_job" 'runs-on: macos-15' 'vendored tools must run on macOS'
require_text "$mac_job" 'uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803' 'macOS checkout must stay pinned'
require_text "$mac_job" 'persist-credentials: false' 'macOS checkout must not persist credentials'
require_text "$mac_job" 'lfs: true' 'macOS checkout must fetch vendored binaries'
require_text "$mac_job" './tests/vendored-macos-tools-runtime-test.sh' 'macOS job must execute its runtime test'
require_text "$aggregate_job" '- macos_vendored_tools' 'aggregate must depend on macOS runtime tests'
# shellcheck disable=SC2016
require_text "$aggregate_job" '${{ needs.macos_vendored_tools.result }}' 'aggregate must require macOS success'

# shellcheck disable=SC2016
if grep -Eq '"\$ROOT_DIR/bin/macos-arm64/(swiftlint|swiftformat)" (version|--version)' "$ROOT_DIR/tests/quality-gates-guardrails-config-test.sh"; then
    echo 'FAIL: fixture-only tests must not execute macOS binaries' >&2
    status=1
fi

# shellcheck disable=SC2016
while IFS= read -r invocation; do
    require_text "$invocation" '--without-swiftformat' 'Linux real formatter tests must not require SwiftFormat'
done < <(grep -F '"$SCRIPT" --' "$ROOT_DIR/tests/treefmt-real-tools-test.sh")
# shellcheck disable=SC2016
require_text "$(<"$ROOT_DIR/tests/treefmt-real-tools-test.sh")" '"$SCRIPT" --write --without-swiftformat --repo "$CHECK_ONLY_REPO"' 'check-mode fixture must be formatted before the positive control'
# shellcheck disable=SC2016
if ! grep -Fxq '"$SCRIPT" --check --without-swiftformat --repo "$CHECK_ONLY_REPO" >/dev/null' "$ROOT_DIR/tests/treefmt-real-tools-test.sh"; then
    echo 'FAIL: formatted fixture must pass check mode without masking its exit status' >&2
    status=1
fi

if ((status != 0)); then
    exit "$status"
fi
echo 'PASS'
