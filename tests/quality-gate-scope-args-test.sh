#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/quality-gate-scope-args.sh"

scope_hex() {
	"$SCRIPT" "$@" | od -An -tx1 | tr -d ' \n'
}

expected_hex() {
	printf '%s\0' "$@" | od -An -tx1 | tr -d ' \n'
}

assert_scope() {
	local expected="$1"
	shift
	local actual
	actual="$(scope_hex "$@")"
	if [[ "$actual" != "$expected" ]]; then
		printf 'FAIL: scope arguments mismatch\nexpected: %s\nactual: %s\n' "$expected" "$actual" >&2
		exit 1
	fi
}

assert_scope \
	"$(expected_hex --changed --base base-sha --head head-sha --range-mode merge-base)" \
	--scope changed --event-name pull_request --base base-sha --head head-sha
assert_scope \
	"$(expected_hex --changed --base base-sha --head head-sha --range-mode direct)" \
	--scope changed --event-name push --base base-sha --head head-sha
assert_scope \
	"$(expected_hex --all)" \
	--scope all --event-name schedule

if "$SCRIPT" --scope changed --event-name push --base base-sha >/dev/null 2>&1; then
	echo "FAIL: changed scope accepted a missing head revision" >&2
	exit 1
fi
if "$SCRIPT" --scope invalid --event-name push --base base-sha --head head-sha >/dev/null 2>&1; then
	echo "FAIL: invalid scope was accepted" >&2
	exit 1
fi
if "$SCRIPT" --scope all >/dev/null 2>&1; then
	echo "FAIL: missing event name was accepted" >&2
	exit 1
fi

echo "PASS"
