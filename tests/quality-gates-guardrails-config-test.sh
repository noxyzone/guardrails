#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/quality-gates.yml"
TREEFMT_WORKFLOW="$ROOT_DIR/.github/workflows/treefmt.yml"
SWIFTLINT_WORKFLOW="$ROOT_DIR/.github/workflows/swiftlint.yml"
PRETTIER_CONFIG="$ROOT_DIR/prettier.cjs"
VENDORED_TOOLS_MANIFEST="$ROOT_DIR/config/vendored-tools.tsv"

# shellcheck disable=SC2016
for required in \
    'scope:' \
    'default: changed' \
    'quality-gate-scope-args\.sh' \
    'SCOPE_INPUT: \$\{\{ inputs\.scope \}\}' \
    '--scope "\$SCOPE_INPUT"' \
    '--event-name "\$\{\{ github\.event_name \}\}"' \
    'done <"\$scope_args_file"' \
    'ref: main' \
    'quality-gate-change-detection\.sh' \
    'quality-gate-targets\.sh' \
    'actionlint: \$\{\{ steps\.changed\.outputs\.actionlint \}\}' \
    '--base "\$base_sha"' \
    '--head "\$head_sha"' \
    '--output "\$GITHUB_OUTPUT"' \
    'ast_grep: \$\{\{ steps\.changed\.outputs\.ast_grep \}\}' \
    'uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803' \
    'chmod \+x \.guardrails/bin/linux-x86_64/\*' \
    'printf '\''%s\\n'\'' "\$GITHUB_WORKSPACE/\.guardrails/bin/linux-x86_64" >> "\$GITHUB_PATH"' \
    'printf '\''%s\\n'\'' "\$GITHUB_WORKSPACE/\.guardrails/\.github/quality-gates/node_modules/\.bin" >> "\$GITHUB_PATH"' \
    '\[\[ "\$\(\.guardrails/bin/linux-x86_64/treefmt --version\)" == "treefmt v2\.5\.0" \]\]' \
    '\[\[ "\$\(\.guardrails/bin/linux-x86_64/shfmt --version\)" == "v3\.13\.1" \]\]' \
    '\[\[ "\$\(\.guardrails/bin/linux-x86_64/taplo --version\)" == "taplo 0\.10\.0" \]\]' \
    '\[\[ "\$\(\.guardrails/bin/linux-x86_64/ruff --version\)" == "ruff 0\.15\.22" \]\]' \
    'app-aarch64-apple-darwin\.zip' \
    '0a2fef273b0ff1238b8307add911714f92021d25b919fa3ec9b6b2e046bb29cf' \
    'printf '\''%s\\n'\'' "\$SWIFT_TOOLS_BIN" >> "\$GITHUB_PATH"' \
    'ast-grep version mismatch: expected 0\.44\.1' \
    'chmod \+x \.guardrails/bin/macos-arm64/swiftformat \.guardrails/bin/macos-arm64/swiftlint' \
    'printf '\''%s\\n'\'' "\$GITHUB_WORKSPACE/\.guardrails/bin/macos-arm64" >> "\$GITHUB_PATH"' \
    '\[\[ "\$\(\.guardrails/bin/macos-arm64/swiftformat --version\)" == "0\.61\.1" \]\]' \
    '\[\[ "\$\(\.guardrails/bin/macos-arm64/swiftlint version\)" == "0\.63\.2" \]\]' \
    'GH_TOKEN: \$\{\{ github\.token \}\}' \
    'gh release download v1\.7\.12 --repo rhysd/actionlint --pattern actionlint_1\.7\.12_linux_amd64\.tar\.gz' \
    '8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8' \
    'actionlint_version="\$\(actionlint -version\)"' \
    'actionlint_version="\$\{actionlint_version%%\$'"'"'\\n'"'"'\*\}"' \
    '\[\[ "\$actionlint_version" == "1\.7\.12" \]\]' \
    'actionlint -shellcheck= -pyflakes=' \
    '72a930c9a94fc3914aa56835c5b859c892a797d40c1c42638b98d93f16ff519c' \
    '\.guardrails/scripts/localization-check\.sh --files-from "\$localization_files" --repo "\$GITHUB_WORKSPACE"' \
    'needs\.detect_changes\.outputs\.swift == '\''true'\'' \|\| needs\.detect_changes\.outputs\.ast_grep == '\''true'\''' \
    'ast-grep scan --config \.guardrails/sgconfig\.yml --report-style short' \
    'lfs: true'; do
    if ! rg -q -- "$required" "$WORKFLOW"; then
        echo "FAIL: QualityGates must wire ast-grep rule: $required" >&2
        exit 1
    fi
done

for forbidden in 'guardrails-ref:' 'inputs\.guardrails-ref'; do
    if rg -q -- "$forbidden" "$WORKFLOW"; then
        echo "FAIL: QualityGates must not allow callers to override guardrails/main: $forbidden" >&2
        exit 1
    fi
done

while IFS= read -r guardrails_workflow; do
    repository_count="$(rg -c '^[[:space:]]*repository:[[:space:]]*noxyzone/guardrails$' "$guardrails_workflow")"
    main_ref_count="$(rg -c '^[[:space:]]*ref:[[:space:]]*main$' "$guardrails_workflow")"
    if [[ "$repository_count" != "$main_ref_count" ]]; then
        echo "FAIL: every noxyzone/guardrails checkout must explicitly track main: $guardrails_workflow" >&2
        exit 1
    fi
done < <(rg -l 'repository:[[:space:]]*noxyzone/guardrails' "$ROOT_DIR/.github/workflows" --glob '*.yml' --glob '*.yaml')

# treefmt.ymlはQualityGatesと同じ固定formatter契約（vendored binaries）を再利用する。
# shellcheck disable=SC2016
for required in \
    'uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803' \
    'lfs: true' \
    'chmod \+x \.guardrails/bin/linux-x86_64/\*' \
    '\[\[ "\$\(\.guardrails/bin/linux-x86_64/treefmt --version\)" == "treefmt v2\.5\.0" \]\]' \
    '\[\[ "\$\(\.guardrails/bin/linux-x86_64/shfmt --version\)" == "v3\.13\.1" \]\]' \
    '\[\[ "\$\(\.guardrails/bin/linux-x86_64/taplo --version\)" == "taplo 0\.10\.0" \]\]' \
    '\[\[ "\$\(\.guardrails/bin/linux-x86_64/ruff --version\)" == "ruff 0\.15\.22" \]\]' \
    'chmod \+x \.guardrails/bin/macos-arm64/swiftformat' \
    '\[\[ "\$\(\.guardrails/bin/macos-arm64/swiftformat --version\)" == "0\.61\.1" \]\]'; do
    if ! rg -q -- "$required" "$TREEFMT_WORKFLOW"; then
        echo "FAIL: Treefmt workflow must match the pinned QualityGates formatter contract: $required" >&2
        exit 1
    fi
done

for treefmt_workflow in "$WORKFLOW" "$TREEFMT_WORKFLOW"; do
    if rg -q 'v2\.3\.0|treefmt_2\.3\.0|5d3ad279590f1c29c0e6b409dc2a6ce24ad4439e267be8eb0e4e671aed6c02a8' "$treefmt_workflow"; then
        echo "FAIL: Treefmt workflow retains the old 2.3.0 contract: $treefmt_workflow" >&2
        exit 1
    fi
    # shellcheck disable=SC2016
    if [[ "$(rg -c -- '\[\[ "\$\(\.guardrails/bin/linux-x86_64/treefmt --version\)" == "treefmt v2\.5\.0" \]\]' "$treefmt_workflow")" != "1" ]]; then
        echo "FAIL: Treefmt workflow must assert the vendored 2.5.0 treefmt binary exactly once: $treefmt_workflow" >&2
        exit 1
    fi
done

for forbidden in \
    'uses: actions/checkout@v[0-9]' \
    'sudo apt-get install.*shfmt' \
    'brew install swiftformat' \
    'pipx install ruff' \
    'npm install' \
    'npm ci --prefix' \
    'gh release download v2\.5\.0 --repo numtide/treefmt' \
    'gh release download v3\.13\.1 --repo mvdan/sh' \
    'gh release download 0\.10\.0 --repo tamasfe/taplo' \
    'gh release download 0\.61\.1 --repo nicklockwood/SwiftFormat'; do
    if rg -q -- "$forbidden" "$TREEFMT_WORKFLOW"; then
        echo "FAIL: Treefmt workflow contains a mutable formatter dependency: $forbidden" >&2
        exit 1
    fi
done

# SwiftLint単独workflowもQualityGatesと同じvendored binaryを使う。
# shellcheck disable=SC2016
for required in \
    'uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803' \
    'lfs: true' \
    'chmod +x .guardrails/bin/macos-arm64/swiftlint' \
    '[[ "$(.guardrails/bin/macos-arm64/swiftlint version)" == "0.63.2" ]]' \
    'export PATH="$GITHUB_WORKSPACE/.guardrails/bin/macos-arm64:/usr/bin:/bin"'; do
    if ! grep -Fq "$required" "$SWIFTLINT_WORKFLOW"; then
        echo "FAIL: SwiftLint workflow must use the vendored 0.63.2 binary: $required" >&2
        exit 1
    fi
done

for forbidden in \
    'uses: actions/checkout@v[0-9]' \
    'brew install swiftlint' \
    'gh release download' \
    'portable_swiftlint.zip'; do
    if rg -q -- "$forbidden" "$SWIFTLINT_WORKFLOW"; then
        echo "FAIL: SwiftLint workflow contains a mutable tool dependency: $forbidden" >&2
        exit 1
    fi
done

expected_manifest_row=$'swiftlint\tmacos-arm64\t0.63.2\thttps://github.com/realm/SwiftLint/releases/download/0.63.2/portable_swiftlint.zip\tc59a405c85f95b92ced677a500804e081596a4cae4a6a485af76065557d6ed29\t2991cdee904be388d6d15e9cea560c3d6b0d8c009462b8261ed608709b7712c7\tlicenses/swiftlint.txt'
grep -Fxq "$expected_manifest_row" "$VENDORED_TOOLS_MANIFEST" || {
    echo "FAIL: vendored tools manifest must pin SwiftLint provenance and integrity" >&2
    exit 1
}
[[ "$("$ROOT_DIR/bin/macos-arm64/swiftlint" version)" == "0.63.2" ]] || {
    echo "FAIL: vendored SwiftLint version mismatch" >&2
    exit 1
}
[[ "$(shasum -a 256 "$ROOT_DIR/bin/macos-arm64/swiftlint" | awk '{print $1}')" == "2991cdee904be388d6d15e9cea560c3d6b0d8c009462b8261ed608709b7712c7" ]] || {
    echo "FAIL: vendored SwiftLint binary checksum mismatch" >&2
    exit 1
}
[[ -f "$ROOT_DIR/licenses/swiftlint.txt" ]] || {
    echo "FAIL: vendored SwiftLint license is missing" >&2
    exit 1
}

# shellcheck disable=SC2016
for required in \
    'const qualityGatesPackageRoot = path.join(__dirname, ".github/quality-gates");' \
    'return require.resolve(name, { paths: [qualityGatesPackageRoot] });'; do
    if ! rg -Fq "$required" "$PRETTIER_CONFIG"; then
        echo "FAIL: Prettier plugins must resolve from the QualityGates package root before using the local fallback: $required" >&2
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
    '.guardrails/scripts/gitleaks-check.sh --files-from "$gitleaks_files" --repo "$GITHUB_WORKSPACE"' \
    'xargs -0 -r actionlint -shellcheck= -pyflakes=' \
    '.guardrails/scripts/guardrails-main-ref-check.sh --repo "$GITHUB_WORKSPACE" --files-from "$RUNNER_TEMP/quality-gate-targets/zizmor.bin"' \
    'xargs -0 .guardrails/scripts/treefmt-check.sh --check --without-swiftformat --repo "$GITHUB_WORKSPACE" --' \
    'xargs -0 -r "$GITHUB_WORKSPACE/.guardrails/.github/quality-gates/node_modules/.bin/markdownlint-cli2" --config .guardrails/.markdownlint-cli2.yaml --' \
    'xargs -0 -r oxlint -c .guardrails/.oxlintrc.json --' \
    '.guardrails/scripts/osv-scanner-check.sh --files-from "$osv_files" --repo "$GITHUB_WORKSPACE"' \
    'xargs -0 -r zizmor --offline --no-progress --config .guardrails/.zizmor.yml --' \
    'xargs -0 -r ruff check --' \
    'xargs -0 -r shellcheck --' \
    'xargs -0 ast-grep scan --config .guardrails/sgconfig.yml --report-style short --' \
    'xargs -0 swiftlint lint --force-exclude --no-cache --config .guardrails/.swiftlint.yml --' \
    'while IFS= read -r -d '\'''\'' path; do' \
    'printf '\''./%s\0'\'' "$path"' \
    'done <"$targets" | xargs -0 swiftformat --lint --config .guardrails/.swiftformat'; do
    if ! rg -Fq "$required" "$WORKFLOW"; then
        echo "FAIL: QualityGates must NUL-delimit file arguments using supported tool options: $required" >&2
        exit 1
    fi
done

# shellcheck disable=SC2016
for forbidden in \
    'uses: actions/checkout@v[0-9]' \
    '\[\[ "\$\(actionlint -version\)" == "1\.7\.12" \]\]' \
    'npm install' \
    'npm ci --prefix' \
    'pipx install ruff' \
    'HOMEBREW_CORE_REVISION' \
    'brew install ast-grep' \
    'gh release download v2\.5\.0 --repo numtide/treefmt' \
    'gh release download v3\.13\.1 --repo mvdan/sh' \
    'gh release download 0\.10\.0 --repo tamasfe/taplo' \
    'gh release download 0\.61\.1 --repo nicklockwood/SwiftFormat' \
    'gh release download 0\.63\.2 --repo realm/SwiftLint' \
    'portable_swiftlint\.zip' \
    'brew install swiftlint' \
    'xargs -0 swiftformat --lint --config .guardrails/.swiftformat <"\$targets"' \
    'range_mode=direct' \
    'scope_args=\(--all\)' \
    'scope_args=\(--changed' \
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

if rg -Fq '$HOME/.local/bin' "$WORKFLOW"; then
    echo "FAIL: QualityGates must not assume pipx installs applications under HOME/.local/bin" >&2
    exit 1
fi

if rg -Fq 'xargs -0 swiftformat --lint --config .guardrails/.swiftformat --' "$WORKFLOW"; then
    echo "FAIL: QualityGates must not pass the unsupported -- option to SwiftFormat" >&2
    exit 1
fi

if [[ "$(rg -c 'sha256sum --check --strict' "$WORKFLOW")" != "6" ]]; then
    echo "FAIL: every downloaded release asset must have an exact SHA-256 check" >&2
    exit 1
fi

if rg -q 'tar xzf treefmt\.tar\.gz' "$WORKFLOW"; then
    echo "FAIL: QualityGates must not extract treefmt release assets in the repository root" >&2
    exit 1
fi

if rg -q '^      any: \$\{\{ steps\.changed\.outputs\.any \}\}$' "$WORKFLOW"; then
    echo "FAIL: QualityGates must not publish the unused any job output" >&2
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

if [[ "$(rg -c 'quality-gate-scope-args\.sh' "$WORKFLOW")" != "3" ]]; then
    echo "FAIL: every change-scoped workflow entrance must use the shared scope resolver" >&2
    exit 1
fi
if [[ "$(rg -c '^          SCOPE_INPUT: \$\{\{ inputs\.scope \}\}$' "$WORKFLOW")" != "3" ]]; then
    echo "FAIL: every change-scoped workflow entrance must isolate scope through the step environment" >&2
    exit 1
fi
if [[ "$(rg -c -- '--scope "\$SCOPE_INPUT"' "$WORKFLOW")" != "3" ]]; then
    echo "FAIL: every change-scoped workflow entrance must pass the isolated scope as one shell argument" >&2
    exit 1
fi
if rg -q -- '--scope "\$\{\{ inputs\.scope \}\}"' "$WORKFLOW"; then
    echo "FAIL: workflow expressions must not be interpolated directly into the scope resolver shell command" >&2
    exit 1
fi

if [[ "$(rg -c -- 'lfs: true' "$WORKFLOW")" != "2" ]]; then
    echo "FAIL: both ubuntu_guardrails and macos_guardrails guardrails checkouts must fetch LFS content" >&2
    exit 1
fi

echo "PASS"
