#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/quality-gates.yml"

# shellcheck disable=SC2016
for required in \
	'guardrails-ref:' \
	'required: true' \
	'scope:' \
	'default: changed' \
	'scope_args=\(--all\)' \
	'scope_args=\(--changed --base "\$base_sha" --head "\$head_sha"\)' \
	'ref: \$\{\{ inputs\.guardrails-ref \}\}' \
	'quality-gate-change-detection\.sh' \
	'quality-gate-targets\.sh' \
	'--base "\$base_sha"' \
	'--head "\$head_sha"' \
	'--output "\$GITHUB_OUTPUT"' \
	'ast_grep: \$\{\{ steps\.changed\.outputs\.ast_grep \}\}' \
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
	'\.guardrails/scripts/localization-check\.sh --files-from "\$localization_files" --repo "\$GITHUB_WORKSPACE"' \
	'needs\.detect_changes\.outputs\.swift == '\''true'\'' \|\| needs\.detect_changes\.outputs\.ast_grep == '\''true'\''' \
	'ast-grep scan --config \.guardrails/sgconfig\.yml --report-style short'; do
	if ! rg -q -- "$required" "$WORKFLOW"; then
		echo "FAIL: QualityGates must wire ast-grep rule: $required" >&2
		exit 1
	fi
done

for required_doc in \
	'commit時はstagedファイルだけをcheck-onlyで検査' \
	'PR時はmerge-baseからheadまでの変更ファイルだけを検査' \
	'全trackedファイル検査はPR必須ゲートから分離'; do
	if ! grep -Fq "$required_doc" "$ROOT_DIR/README.md"; then
		echo "FAIL: README must document the target-scope contract: $required_doc" >&2
		exit 1
	fi
done

# shellcheck disable=SC2016
for required in \
	'xargs -0 -r "$GITHUB_WORKSPACE/.guardrails/.github/quality-gates/node_modules/.bin/secretlint" --secretlintrc .guardrails/.secretlintrc.json --' \
	'xargs -0 .guardrails/scripts/treefmt-check.sh --check --without-swiftformat --repo "$GITHUB_WORKSPACE" --' \
	'xargs -0 -r "$GITHUB_WORKSPACE/.guardrails/.github/quality-gates/node_modules/.bin/markdownlint-cli2" --config .guardrails/.markdownlint-cli2.yaml --' \
	'xargs -0 -r "$GITHUB_WORKSPACE/.guardrails/.github/quality-gates/node_modules/.bin/eslint" --config .guardrails/eslint.config.js --no-config-lookup --' \
	'xargs -0 -r ruff check --' \
	'xargs -0 -r shellcheck --' \
	'xargs -0 ast-grep scan --config .guardrails/sgconfig.yml --report-style short --' \
	'xargs -0 swiftlint lint --force-exclude --no-cache --config .guardrails/.swiftlint.yml --' \
	'xargs -0 swiftformat --lint --config .guardrails/.swiftformat --'; do
	if ! rg -Fq "$required" "$WORKFLOW"; then
		echo "FAIL: QualityGates must NUL-delimit file arguments and terminate tool options: $required" >&2
		exit 1
	fi
done

# shellcheck disable=SC2016
for forbidden in \
	'uses: actions/checkout@v[0-9]' \
	'npm install' \
	'pipx install ruff$' \
	'\$PWD/node_modules/\.bin' \
	'git ls-files -z' \
	'text-spacing-check\.sh --all' \
	'typos-check\.sh --changed' \
	'localization-check\.sh --changed'; do
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

if [[ "$(rg -c '^          fetch-depth: 0$' "$WORKFLOW")" != "3" ]]; then
	echo "FAIL: every change-scoped job checkout must define fetch-depth: 0" >&2
	exit 1
fi

echo "PASS"
