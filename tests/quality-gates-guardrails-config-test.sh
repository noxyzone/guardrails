#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/quality-gates.yml"

# shellcheck disable=SC2016
for required in \
	'guardrails-ref:' \
	'required: true' \
	'ref: \$\{\{ inputs\.guardrails-ref \}\}' \
	'changed_files="\$\(git diff --name-only --diff-filter=ACMRT "\$base_sha" "\$head_sha"\)"' \
	'ast_grep: \$\{\{ steps\.changed\.outputs\.ast_grep \}\}' \
	'ast_grep="\$\(bool_for '\''\\\.swift\$'\''\)"' \
	'printf '\''ast_grep=%s\\n'\'' "\$ast_grep"' \
	'uses: actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955' \
	'npm ci --prefix \.guardrails/\.github/quality-gates --ignore-scripts' \
	'pipx install ruff==0\.15\.22' \
	'brew install ast-grep swiftformat swiftlint' \
	'HOMEBREW_CORE_REVISION: d9fca872b542d66e0143ad467fa1e9ed6618d423' \
	'GH_TOKEN: \$\{\{ github\.token \}\}' \
	'treefmt_tmp="\$\(mktemp -d\)"' \
	'gh release download v2\.3\.0 --repo numtide/treefmt --pattern treefmt_2\.3\.0_linux_amd64\.tar\.gz --output "\$treefmt_tmp/treefmt\.tar\.gz"' \
	'tar xzf "\$treefmt_tmp/treefmt\.tar\.gz" -C "\$treefmt_tmp"' \
	'sudo install "\$treefmt_tmp/treefmt" /usr/local/bin/treefmt' \
	'gh release download v3\.13\.1 --repo mvdan/sh --pattern shfmt_v3\.13\.1_linux_amd64 --output shfmt' \
	'gh release download 0\.10\.0 --repo tamasfe/taplo --pattern taplo-linux-x86_64\.gz --output taplo\.gz' \
	'5d3ad279590f1c29c0e6b409dc2a6ce24ad4439e267be8eb0e4e671aed6c02a8' \
	'fb096c5d1ac6beabbdbaa2874d025badb03ee07929f0c9ff67563ce8c75398b1' \
	'8fe196b894ccf9072f98d4e1013a180306e17d244830b03986ee5e8eabeb6156' \
	'72a930c9a94fc3914aa56835c5b859c892a797d40c1c42638b98d93f16ff519c' \
	'\.guardrails/scripts/localization-check\.sh --changed --base "\$base_sha" --head "\$head_sha" --repo "\$GITHUB_WORKSPACE"' \
	'needs\.detect_changes\.outputs\.ast_grep == '\''true'\''' \
	'ast-grep scan --config \.guardrails/sgconfig\.yml --report-style short'; do
	if ! rg -q "$required" "$WORKFLOW"; then
		echo "FAIL: QualityGates must wire ast-grep rule: $required" >&2
		exit 1
	fi
done

for forbidden in \
	'uses: actions/checkout@v[0-9]' \
	'npm install' \
	'pipx install ruff$'; do
	if rg -q "$forbidden" "$WORKFLOW"; then
		echo "FAIL: QualityGates contains mutable dependency: $forbidden" >&2
		exit 1
	fi
done

if [[ "$(rg -c 'sha256sum --check --strict' "$WORKFLOW")" != "4" ]]; then
	echo "FAIL: every downloaded release asset must have an exact SHA-256 check" >&2
	exit 1
fi

if rg -q 'tar xzf treefmt\.tar\.gz' "$WORKFLOW"; then
	echo "FAIL: QualityGates must not extract treefmt release assets in the repository root" >&2
	exit 1
fi

if rg -q 'git diff --name-only --diff-filter=ACMRT .* \|\| true' "$WORKFLOW"; then
	echo "FAIL: QualityGates must not swallow git diff failures in change detection" >&2
	exit 1
fi

if [[ "$(rg -c '^          fetch-depth: 0$' "$WORKFLOW")" != "1" ]]; then
	echo "FAIL: change detection checkout must define fetch-depth exactly once" >&2
	exit 1
fi

echo "PASS"
