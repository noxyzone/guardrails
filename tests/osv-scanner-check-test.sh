#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_SCRIPT="$ROOT_DIR/scripts/osv-scanner-check.sh"
QUALITY_GATES="$ROOT_DIR/.github/workflows/quality-gates.yml"
CHANGE_DETECTION="$ROOT_DIR/scripts/quality-gate-change-detection.sh"
TARGETS="$ROOT_DIR/scripts/quality-gate-targets.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

if [[ ! -x "$CHECK_SCRIPT" ]]; then
    echo "FAIL: osv-scanner-check.sh must exist and be executable" >&2
    exit 1
fi

# shellcheck disable=SC2016
for required in \
    'osv: ${{ steps.changed.outputs.osv }}' \
    'needs.detect_changes.outputs.osv == '\''true'\''' \
    'gh release download v2.5.1 --repo google/osv-scanner --pattern osv-scanner_linux_amd64' \
    'f9f25499a2c8cc367b3af45df2ea7eeca7fbccceab9c35079968f4b3652194be' \
    '.guardrails/scripts/osv-scanner-check.sh --files-from "$osv_files" --repo "$GITHUB_WORKSPACE"'; do
    if ! rg -Fq "$required" "$QUALITY_GATES"; then
        echo "FAIL: QualityGates must wire OSV-Scanner rule: $required" >&2
        exit 1
    fi
done

if ! rg -q 'osv="\$\(has_targets osv\)"' "$CHANGE_DETECTION"; then
    echo "FAIL: change detection must derive OSV from shared targets" >&2
    exit 1
fi

if ! rg -q 'Package.resolved' "$TARGETS"; then
    echo "FAIL: shared targets must include Swift Package.resolved for OSV" >&2
    exit 1
fi

git -C "$FIXTURE" init -q
printf '{ "pins": [], "version": 2 }\n' >"$FIXTURE/Package.resolved"
printf 'not a lockfile\n' >"$FIXTURE/README.md"
git -C "$FIXTURE" add -- Package.resolved README.md
printf '%s\n' Package.resolved README.md >"$FIXTURE/files.txt"

fake_bin="$FIXTURE/bin"
mkdir -p "$fake_bin"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'printf "%s\\n" "$@" >"$FAKE_OSV_ARGS"' 'exit 0' >"$fake_bin/osv-scanner"
chmod +x "$fake_bin/osv-scanner"

FAKE_OSV_ARGS="$FIXTURE/args.txt" PATH="$fake_bin:$PATH" \
    "$CHECK_SCRIPT" --files-from "$FIXTURE/files.txt" --repo "$FIXTURE"

if ! rg -Fq -- '-L' "$FIXTURE/args.txt"; then
    echo "FAIL: osv-scanner-check.sh must pass lockfiles with -L" >&2
    exit 1
fi
if ! rg -Fq -- 'Package.resolved' "$FIXTURE/args.txt"; then
    echo "FAIL: osv-scanner-check.sh must scan Package.resolved" >&2
    exit 1
fi
if rg -Fq -- 'README.md' "$FIXTURE/args.txt"; then
    echo "FAIL: osv-scanner-check.sh must not pass non-lockfiles" >&2
    exit 1
fi

if "$CHECK_SCRIPT" --repo "$FIXTURE" >/dev/null 2>"$FIXTURE/usage.err"; then
    echo "FAIL: osv-scanner-check.sh must require --files-from" >&2
    exit 1
fi

# Goは中央targetsで対応付けたmanifestだけを受け取る。
mkdir -p "$FIXTURE/space module"
printf 'module example.invalid/fixture\n\ngo 1.25\n' >"$FIXTURE/space module/go.mod"
printf '%s\n' 'space module/go.mod' Package.resolved >"$FIXTURE/go-files.txt"
FAKE_OSV_ARGS="$FIXTURE/go-args.txt" PATH="$fake_bin:$PATH" \
    "$CHECK_SCRIPT" --files-from "$FIXTURE/go-files.txt" --repo "$FIXTURE"
printf '%s\n' scan source --no-resolve --format table -L 'space module/go.mod' -L Package.resolved >"$FIXTURE/expected-go-args.txt"
cmp -s "$FIXTURE/expected-go-args.txt" "$FIXTURE/go-args.txt" || {
    echo 'FAIL: Go manifest and other lockfile arguments must be preserved' >&2
    exit 1
}
assert_go_contract_rejected() {
    local path="$1"
    local status=0
    printf '%s\n' "$path" >"$FIXTURE/rejected-files.txt"
    # 新しいmarkerによりscanner未実行を実証する。
    local marker="$FIXTURE/not-called-$2.txt"
    FAKE_OSV_ARGS="$marker" PATH="$fake_bin:$PATH" \
        "$CHECK_SCRIPT" --files-from "$FIXTURE/rejected-files.txt" --repo "$FIXTURE" >"$FIXTURE/rejected.out" 2>"$FIXTURE/rejected.err" || status=$?
    if [[ "$status" != 2 || -e "$marker" ]]; then
        echo 'FAIL: invalid Go input must exit 2 before scanner invocation' >&2
        exit 1
    fi
}
printf 'sum\n' >"$FIXTURE/space module/go.sum"
assert_go_contract_rejected 'space module/go.sum' sum
assert_go_contract_rejected 'missing/go.mod' missing
mkdir -p "$FIXTURE/directory/go.mod" "$FIXTURE/link"
assert_go_contract_rejected 'directory/go.mod' directory
ln -s '../space module/go.mod' "$FIXTURE/link/go.mod"
assert_go_contract_rejected 'link/go.mod' symlink

echo "PASS"
