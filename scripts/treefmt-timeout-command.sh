#!/usr/bin/env bash
set -euo pipefail
# GNU timeout配下でformatterを起動するtreefmt-check.shの薄いhelper。
#
# wrapperはtimeout自身のstderr（--verboseの期限診断）をprivate logへ分離するため、
# このhelperの初期stderrはそのlogを向いている。引数のFD（wrapperが確保した本来の
# stderrの複製）へfd 2を戻し、複製FDだけを閉じて、LC_ALLをwrapperが保存した元の
# 値へ復元してからformatterへexecする。期限とsignalの管理は全てGNU timeout側にある。

if [[ "$#" -lt 2 ]]; then
    printf 'usage: treefmt-timeout-command.sh <stderr-fd> <command> [args...]\n' >&2
    exit 125
fi
stderr_fd="$1"
shift
if [[ ! "$stderr_fd" =~ ^[0-9]+$ ]]; then
    printf 'treefmt-timeout-command.sh: stderr FD must be numeric: %s\n' "$stderr_fd" >&2
    exit 125
fi

# fd 2を本来のstderrへ戻し、複製FDだけを閉じる。以降の診断は呼び出し元へ届く。
exec 2>&"$stderr_fd"
exec {stderr_fd}>&-

# timeout診断の識別用に付けたLC_ALL=Cを、formatterの元の環境へ戻す。
if [[ -n "${NZ_TREEFMT_SAVED_LC_ALL:-}" ]]; then
    export LC_ALL="$NZ_TREEFMT_SAVED_LC_ALL"
else
    unset LC_ALL
fi
unset NZ_TREEFMT_SAVED_LC_ALL

exec "$@"
