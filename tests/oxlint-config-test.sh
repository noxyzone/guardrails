#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT_DIR/.oxlintrc.json"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

command -v oxlint >/dev/null || {
    echo "FAIL: oxlint is required for this real-tool test" >&2
    exit 1
}
oxlint_version="$(oxlint --version)"
[[ "$oxlint_version" == "Version: 1.65.0" ]] || {
    echo "FAIL: oxlint version must be 1.65.0, got $oxlint_version" >&2
    exit 1
}

printf 'const x = {\n' >"$FIXTURE/syntax-error.js"
printf 'export const ok = 1;\n' >"$FIXTURE/good.js"
printf 'const x: any = 1;\nexport const y = x;\n' >"$FIXTURE/explicit-any.ts"
printf 'const unused = 1;\nexport const y = 2;\n' >"$FIXTURE/unused.ts"
printf '// @ts-ignore\nexport const z = 1;\n' >"$FIXTURE/ts-ignore.ts"
printf 'export const boxed: Number = 1;\n' >"$FIXTURE/wrapper-object.ts"

if oxlint -c "$CONFIG" "$FIXTURE/syntax-error.js" >/dev/null 2>&1; then
    echo "FAIL: Oxlint must detect JS syntax errors" >&2
    exit 1
fi
oxlint -c "$CONFIG" "$FIXTURE/good.js" >/dev/null || {
    echo "FAIL: Oxlint must accept syntactically valid JS" >&2
    exit 1
}
if oxlint -c "$CONFIG" "$FIXTURE/explicit-any.ts" >/dev/null 2>&1; then
    echo "FAIL: Oxlint must detect typescript/no-explicit-any" >&2
    exit 1
fi
if oxlint -c "$CONFIG" "$FIXTURE/unused.ts" >/dev/null 2>&1; then
    echo "FAIL: Oxlint must detect no-unused-vars" >&2
    exit 1
fi
if oxlint -c "$CONFIG" "$FIXTURE/ts-ignore.ts" >/dev/null 2>&1; then
    echo "FAIL: Oxlint must detect typescript/ban-ts-comment" >&2
    exit 1
fi
if oxlint -c "$CONFIG" "$FIXTURE/wrapper-object.ts" >/dev/null 2>&1; then
    echo "FAIL: Oxlint must detect typescript/no-wrapper-object-types" >&2
    exit 1
fi

echo "PASS"
