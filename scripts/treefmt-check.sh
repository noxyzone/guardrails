#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

# timeout診断の分離に使う動的FD割当({varname}>&2)はbash 4.1以降の機能のため、
# それ以前のbashでは起動直後に利用条件を示して失敗させる。
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 1))); then
    fail "bash 4.1 or later is required for treefmt-check.sh (got ${BASH_VERSION})"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guardrails_dir="$(cd "$script_dir/.." && pwd)"
repo_root="."
treefmt_exclusions_path=""
treefmt_config_path=""
treefmt_timeout_log_path=""
treefmt_mode="check"
treefmt_args=()
treefmt_timeout_seconds="${TREEFMT_TIMEOUT_SECONDS:-60}"
treefmt_without_swiftformat=0
treefmt_walk="git"
treefmt_exclude_args=()

while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --check)
        treefmt_mode="check"
        ;;
    --write)
        treefmt_mode="write"
        ;;
    --without-swiftformat)
        treefmt_without_swiftformat=1
        ;;
    --repo)
        [[ "$#" -ge 2 ]] || fail "--repo requires a path"
        repo_root="$2"
        shift
        ;;
    --)
        shift
        treefmt_args+=("$@")
        break
        ;;
    *)
        treefmt_args+=("$1")
        ;;
    esac
    shift
done

if [[ "${#treefmt_args[@]}" -gt 0 ]]; then
    treefmt_walk="filesystem"
fi

repo_root="$(cd "$repo_root" && pwd)"

cleanup() {
    if [[ -n "$treefmt_exclusions_path" ]]; then
        rm -f "$treefmt_exclusions_path"
    fi
    if [[ -n "$treefmt_config_path" ]]; then
        rm -f "$treefmt_config_path"
    fi
    if [[ -n "$treefmt_timeout_log_path" ]]; then
        rm -f "$treefmt_timeout_log_path"
    fi
}
trap cleanup EXIT

for required_asset in treefmt.toml prettier.cjs .swiftformat; do
    if [[ ! -f "$guardrails_dir/$required_asset" ]]; then
        fail "required guardrails asset not found: $guardrails_dir/$required_asset"
    fi
done

treefmt_exclusions_path="$(mktemp "${TMPDIR:-/tmp}/treefmt-excludes.XXXXXX")"
if ! "$script_dir/quality-gate-path-filter.sh" --repo "$repo_root" --treefmt-excludes >"$treefmt_exclusions_path"; then
    fail "quality gate path filter failed"
fi
while IFS= read -r exclusion; do
    treefmt_exclude_args+=(--excludes "$exclusion")
done <"$treefmt_exclusions_path"

if ! command -v treefmt >/dev/null; then
    fail "treefmt is not installed"
fi

case "$treefmt_timeout_seconds" in
'' | *[!0-9]*)
    fail "TREEFMT_TIMEOUT_SECONDS must be a positive integer"
    ;;
0)
    fail "TREEFMT_TIMEOUT_SECONDS must be greater than 0"
    ;;
esac

# GNU coreutilsのtimeoutへ実行期限を委譲する。PATH上のtimeout（Ubuntu CI、Nix環境）、
# 次いでHomebrew coreutilsのgtimeoutを解決し、GNU版でなければ導入要件を示して失敗する。
treefmt_timeout_bin=""
if command -v timeout >/dev/null 2>&1; then
    treefmt_timeout_bin="$(command -v timeout)"
elif command -v gtimeout >/dev/null 2>&1; then
    treefmt_timeout_bin="$(command -v gtimeout)"
else
    fail "GNU coreutils timeout is required; on macOS install coreutils via Homebrew"
fi
if ! "$treefmt_timeout_bin" --version 2>/dev/null | grep -q 'GNU coreutils'; then
    fail "GNU coreutils timeout is required, but $treefmt_timeout_bin is not GNU coreutils"
fi

run_with_timeout() {
    local timeout_seconds="$1"
    local status=0
    local stderr_dup_fd
    local saved_lc_all="${LC_ALL-}"

    shift
    # --foregroundを付けないためtimeoutはcommandを独立process groupへ置き、期限超過時に
    # groupへTERM、--kill-afterの猶予後にKILLする。このscriptはwatchdogの子プロセスを
    # 持たないため、正常終了後に期限分のsleepを残さない。formatter自身が残す子孫の
    # cleanupはこのwrapperの保証範囲外である。
    #
    # timeout自身のstderrだけをprivate logへ分離する。helperがformatterのstderrを
    # 複製FD経由で本来のstreamへ戻すため、logにはGNU timeoutの--verbose診断だけが
    # 残る。発火の有無はこのlogでのみ判定し、status 124/137だけを根拠に書き換えない
    # ため、formatter自身の正常終了statusはそのまま保存される。診断の文言を固定する
    # ためtimeoutだけをLC_ALL=Cで起動し、formatterのLC_ALLはhelperが元の値へ戻す。
    exec {stderr_dup_fd}>&2
    treefmt_timeout_log_path="$(mktemp "${TMPDIR:-/tmp}/treefmt-timeout.XXXXXX")"
    # timeout診断の識別用のLC_ALL=Cをformatterへ渡さないため、先に元の値を退避する。
    LC_ALL=C NZ_TREEFMT_SAVED_LC_ALL="$saved_lc_all" \
        "$treefmt_timeout_bin" --verbose --kill-after=1s "${timeout_seconds}s" \
        "$script_dir/treefmt-timeout-command.sh" "$stderr_dup_fd" "$@" \
        2>"$treefmt_timeout_log_path" || status="$?"
    exec {stderr_dup_fd}>&-
    if grep -Fq 'timeout: sending signal ' "$treefmt_timeout_log_path"; then
        fail "treefmt timed out after ${timeout_seconds}s"
    fi
    rm -f "$treefmt_timeout_log_path"
    treefmt_timeout_log_path=""
    return "$status"
}

toml_guardrails_dir="${guardrails_dir//\\/\\\\}"
toml_guardrails_dir="${toml_guardrails_dir//\"/\\\"}"
treefmt_config_path="$(mktemp "${TMPDIR:-/tmp}/treefmt-runtime.XXXXXX.toml")"
awk -v guardrails_dir="$toml_guardrails_dir" -v without_swiftformat="$treefmt_without_swiftformat" -v treefmt_mode="$treefmt_mode" '
    /^\[formatter\.swiftformat\]$/ && without_swiftformat == 1 {
        skip=1
        next
    }
    skip && /^\[formatter\./ {
        skip=0
    }
    skip {
        next
    }
    /^\[formatter\./ {
        in_shfmt = ($0 == "[formatter.shfmt]")
    }
    $0 == "options = [\"--config\", \".guardrails/prettier.cjs\", \"--write\"]" {
        if (treefmt_mode == "check") {
            printf "options = [\"--config\", \"%s/prettier.cjs\", \"--check\"]\n", guardrails_dir
        } else {
            printf "options = [\"--config\", \"%s/prettier.cjs\", \"--write\"]\n", guardrails_dir
        }
        next
    }
    in_shfmt && $0 == "  \"-w\"," && treefmt_mode == "check" {
        print "  \"-d\","
        next
    }
    $0 == "options = [\"format\"]" && treefmt_mode == "check" {
        print "options = [\"format\", \"--check\"]"
        next
    }
    $0 == "options = [\"--config\", \".guardrails/.swiftformat\"]" {
        if (treefmt_mode == "check") {
            printf "options = [\"--config\", \"%s/.swiftformat\", \"--lint\"]\n", guardrails_dir
        } else {
            printf "options = [\"--config\", \"%s/.swiftformat\"]\n", guardrails_dir
        }
        next
    }
    {
        print
    }
' "$guardrails_dir/treefmt.toml" >"$treefmt_config_path"

cd "$repo_root"
treefmt_command=(treefmt)
if [[ "$treefmt_mode" == "check" ]]; then
    treefmt_command+=(--ci)
fi
treefmt_command+=(
    --tree-root "$repo_root"
    --walk "$treefmt_walk"
    --excludes 'node_modules/**'
    --excludes '.guardrails/**'
)
if [[ "${#treefmt_exclude_args[@]}" -gt 0 ]]; then
    treefmt_command+=("${treefmt_exclude_args[@]}")
fi
treefmt_command+=(--config-file "$treefmt_config_path")
if [[ "${#treefmt_args[@]}" -gt 0 ]]; then
    # 先頭がハイフンのファイル名をoptionとして解釈させないため、必ず--で終端する。
    treefmt_command+=(--)
    treefmt_command+=("${treefmt_args[@]}")
fi

if [[ "$treefmt_mode" == "write" ]]; then
    run_with_timeout "$treefmt_timeout_seconds" "${treefmt_command[@]}"
else
    if run_with_timeout "$treefmt_timeout_seconds" "${treefmt_command[@]}"; then
        exit 0
    else
        treefmt_status="$?"
    fi
    printf '%s\n' '[treefmt] formatter check failed' >&2
    if [[ "${#treefmt_args[@]}" -gt 0 ]] &&
        command -v git >/dev/null &&
        git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        printf '%s\n' '[treefmt] target diff summary:' >&2
        git diff --shortstat -- "${treefmt_args[@]}" >&2 || true
    fi
    exit "$treefmt_status"
fi
