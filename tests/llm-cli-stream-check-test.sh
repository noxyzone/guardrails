#!/usr/bin/env bash
set -euo pipefail

CHECK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/llm-cli-stream-check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/scripts/workflow"

cat >"$TMP/scripts/workflow/bad.sh" <<'BAD'
#!/usr/bin/env bash
"$@" | tee "$log_file"
"$codex_bin" exec - <in 2>&1 | tee "$codex_log"
BAD

cat >"$TMP/scripts/workflow/good.sh" <<'GOOD'
#!/usr/bin/env bash
printf '%s\n' "$*" | tee -a "$watch_log"
sed 's/^/  /' "$f.err" | tee -a "$watch_log"
codex exec - <in | tee "$codex_log" >/dev/null
takt --task x | tee "$log" # guardrail-allow: llm-cli-stream
GOOD

git -C "$TMP" init -q
git -C "$TMP" add -A

if out="$("$CHECK" --all --repo "$TMP")"; then
	echo "FAIL: expected non-zero exit for violations" >&2
	echo "$out" >&2
	exit 1
fi

printf '%s\n' "$out" | grep -qF 'scripts/workflow/bad.sh:2:' || {
	echo "FAIL: missing \"\$@\" | tee violation" >&2
	echo "$out" >&2
	exit 1
}
printf '%s\n' "$out" | grep -qF 'scripts/workflow/bad.sh:3:' || {
	echo "FAIL: missing codex_bin tee violation" >&2
	echo "$out" >&2
	exit 1
}
if printf '%s\n' "$out" | grep -qF 'good.sh'; then
	echo "FAIL: compliant file was flagged" >&2
	echo "$out" >&2
	exit 1
fi

echo "PASS: llm-cli-stream-check"
