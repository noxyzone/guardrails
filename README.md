# guardrails

`noxyzone`配下のGitHubリポジトリで共通利用する品質ゲートを管理するリポジトリです。

各リポジトリにはcaller workflowだけを配置し、実際のチェック処理と設定はこのリポジトリの再利用workflowへ集約します。

## 共有ゲート

| ゲート       | workflow                               | 主な対象                                                   | 検出・確認内容                                                                                                                   |
| ------------ | -------------------------------------- | ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| GitIdentity  | `.github/workflows/git-identity.yml`   | commit author/committer                                    | GitHub noreply email以外の公開混入                                                                                               |
| QualityGates | `.github/workflows/quality-gates.yml`  | PRで変更されたファイル種別に応じた各guardrails検査         | 変更ファイル判定、Actionlint・zizmor・gitleaks・OSV-Scanner・Oxlintを含む必要jobの実行、不要job skip、各guardrails検査結果の集約 |
| Treefmt      | `.github/workflows/treefmt.yml`        | JSON、YAML、TOML、Markdown、Swift、shell scriptなど        | Ubuntuでの非Swift整形差分、macOSでのSwiftFormat差分、repoローカル`.swiftformat`の混入                                            |
| TextSpacing  | `.github/workflows/text-spacing.yml`   | `*.md`、`*.txt`、`*.toml`、`*.yaml`、`*.json`、HTML、CSS等 | 日本語と英数字の間に入った半角スペース                                                                                           |
| Typos        | `.github/workflows/typos.yml`          | Git管理下の実ファイル                                      | ソースコード・ドキュメント・ファイル名の既知typo                                                                                 |
| Localization | `.github/workflows/localization.yml`   | `*.xcstrings`、SwiftのAppKit/独自UI入口                    | 日本語ローカライズ欠落、SwiftUI自動抽出に乗らないUI文字列の直書き                                                                |
| SwiftLint    | `.github/workflows/swiftlint.yml`      | `*.swift`                                                  | SwiftLint標準ルールと`print()`・`try?`禁止などの独自ルール                                                                       |
| MarkdownLint | `.github/workflows/markdownlint.yml`   | `*.md`                                                     | 見出し、リスト、空行などのMarkdown記法                                                                                           |
| Ruff         | `.github/workflows/ruff.yml`           | `*.py`                                                     | Ruff指摘                                                                                                                         |
| ast-grep     | `.github/workflows/ast-grep.yml`       | `*.swift`                                                  | Swift構造ルール（通知送信、管理外型extension、UIテスト環境判定、非仮想化一覧）                                                   |
| YAMLLint     | `.github/workflows/yamllint.yml`       | `*.yaml`、`*.yml`（`.github/workflows/`を除く）            | 重複キー、インデント崩れなどYAML構文・構造の問題                                                                                 |
| Shebang      | `.github/workflows/shebang.yml`        | shell script                                               | `#!/bin/bash`等を検出し、`#!/usr/bin/env bash`を要求                                                                             |
| ShellCheck   | `.github/workflows/shellcheck.yml`     | zsh系を除くshell script                                    | ShellCheck指摘                                                                                                                   |
| LLMCLIStream | `.github/workflows/llm-cli-stream.yml` | zsh系を除くshell script                                    | LLM CLI等サブプロセス出力を`tee`でstdoutへ複製しオーケストレータのstdoutを浪費する垂れ流し                                       |

## ローカル確認

### 対象scopeの契約

- commit時はstagedファイルだけをcheck-onlyで検査し、hookからworktreeやindexを整形・再stageしません。
- PR時はmerge-baseからheadまでの変更ファイルだけを検査し、未変更ファイルの既存違反をPRの失敗理由にしません。
- push時はbeforeからheadまでの二点差分を検査し、force pushや巻き戻しで削除・復元された対象も捕捉します。
- formatter／linter設定を変更した場合は、その設定が支配するファイル種別の全trackedファイルへ対象を拡張します。
- 全trackedファイル検査はPR必須ゲートから分離し、定期実行、手動実行、またはrelease前backstopとして`scope: all`で呼び出します。
- 対象抽出、AIDLC管理path除外、ファイル種別分類の正本は`scripts/quality-gate-targets.sh`です。staged、PR差分、全量の入口だけを切り替え、各toolで独自に対象を再抽出しません。
- pathはNUL区切りでtool直前まで保持します。対応toolへ安全に渡せない改行入りpathは、誤ったファイルを検査する代わりにfail closedします。

PR callerは既定の`changed`scopeを使います。定期全体検査のcallerは同じ再利用workflowへ`scope: all`を渡します。すべてのcallerは`noxyzone/guardrails`の`main`を参照し、共有workflow内部のcheckoutも`main`へ固定します。固定SHA、tag、別branch、`guardrails-ref`による上書きは使いません。`scripts/guardrails-main-ref-check.sh`をローカルhookとQualityGatesの両方から実行し、この契約への違反を確定的に拒否します。このため、workflow実行中に`main`が更新されると、callerが解決したworkflow本体と内部checkoutが異なるcommitになる可能性があります。

```yaml
jobs:
  quality-gates:
    uses: noxyzone/guardrails/.github/workflows/quality-gates.yml@main
    with:
      scope: all
```

TextSpacingとLocalizationはCIとローカル確認で同じ実装を使います。手動・定期・release前backstopの全量確認では次を実行します。通常の作業完了時にはTextSpacingの`--all`を自動実行しません。

```bash
scripts/text-spacing-check.sh --all --repo /path/to/repo
scripts/localization-check.sh --all --repo /path/to/repo
```

LocalizationはPR差分またはcommit対象だけを確認できます。

```bash
scripts/localization-check.sh --changed --base BASE --head HEAD --repo /path/to/repo
scripts/localization-check.sh --staged --repo /path/to/repo
```

TyposはPR差分またはcommit対象だけを確認します。

```bash
scripts/typos-check.sh --changed --base BASE --head HEAD --repo /path/to/repo
scripts/typos-check.sh --staged --repo /path/to/repo
```

pre-commitでは共有対象抽出scriptが作成したindex snapshot上のstaged file一覧を、Actionlint、TextSpacing、Localization、Typosを含む各ゲートへ渡します。Actionlintは`.github/workflows`直下のworkflowだけを対象にし、`-shellcheck= -pyflakes=`で外部linter連携を無効化します。shell scriptは既存のShellCheckゲートが独立して検査します。

## 除外ルール

- GitIdentity
  commit author/committer emailは`@users.noreply.github.com`のみ許可します。
- gitleaks
  symlinkと存在しないpathを除外し、共有`.gitleaks.toml`に従います。標準ルールに加え、SecretLint recommendで検出していたnpm token、低entropy GitHub PAT、汎用password代入を追加ルールで維持し、ダミー値の陽性・陰性を`tests/gitleaks-config-test.sh`で固定します。
- QualityGates
  PRの変更ファイルを判定し、対象ファイル種別がないjobはskipします。Ubuntu側でActionlint、zizmor、gitleaks、Treefmtの非Swift対象、TextSpacing、Typos、YAMLLint、Localization、MarkdownLint、Oxlint、OSV-Scanner、Ruff、Shebang、ShellCheck、LLMCLIStreamを実行し、macOS側でast-grep、SwiftLint、SwiftFormatを実行します。最後に`quality_gates`jobで結果を集約します。Actionlintとzizmorは`.github/workflows`直下の`.yml`と`.yaml`だけを読み、削除済みworkflowとサブディレクトリは対象にしません。OSV-Scannerは`Package.resolved`を含むlockfile変更を検査します。
- Treefmt
  `treefmt.toml`に従います。現在は`.agents/skills/.system/**`、`artifacts/**`を除外します。GitHubActionsでは非Swift整形をUbuntuのTreefmt jobで実行し、SwiftFormatだけをmacOS jobへ分離します。repoローカルの`.swiftformat`は許可せず、共有`guardrails/.swiftformat`を使います。
- TextSpacing
  `.claude/plugins/`、`.claude/todos/`、`.claude/cache/`、`.claude/projects/`、`.claude/plans/`、`.claude/shell-snapshots/`、`node_modules/`、`contrib/`、`artifacts/`、`pipedream/html/`を除外します。
- Typos
  `typos.toml`に従います。現在は`.claude/`、`.codex/cache/`、`node_modules/`、`contrib/`、`Vendor/`、`artifacts/`、`pipedream/html/`配下の生成物・外部由来ファイルを除外し、hexハッシュとMermaidノードIDの誤検出を抑制します。repo側の暗黙設定ではなく共有`guardrails/typos.toml`を使います。
- Localization
  `sourceLanguage`が`en`で、`extractionState`が`stale`ではない英語source keyに`ja`ローカライズを要求します。URL、絶対path、`HEAD@{}`、記号/数値/format placeholderのみのキーは除外します。SwiftUI自動抽出に乗らない`NSMenuItem(title:)`、`Action(title:)`、`panel.title/message`、`column.title`の直書きを検出します。
- SwiftLint
  `.swiftlint.yml`の`excluded`に従います。現在は`DerivedData`、`.build`、`build`を除外します。SwiftLintのerrorはブロックし、warningは原則ブロックしません。禁止したいwarningは`.swiftlint.yml`でerrorへ昇格します。
- MarkdownLint
  各repoの`.markdownlintignore`に従います。
- Oxlint
  共有`.oxlintrc.json`に従います。JSの構文エラーと、typescript-eslint recommended相当の主要ルール（`no-unused-vars`、`no-explicit-any`、`ban-ts-comment`、`no-wrapper-object-types`）およびcorrectnessをerrorにします。
- OSV-Scanner
  `Package.resolved`、`package-lock.json`、`pnpm-lock.yaml`、`yarn.lock`、`Cargo.lock`、`go.sum`などのlockfileを対象にします。認識判定は外部脆弱性DBの件数に依存しません。
- zizmor
  共有`.zizmor.yml`のhash-pin方針に従います。GitHub Actionsの未ピン`uses`を検出し、offlineで検査します。
- Ruff
  明示除外はありません。対象repo側のRuff設定があればそれに従います。
- ast-grep
  `sgconfig.yml`と`ast-grep/*.yml`に従います。現在は`*.swift`を対象にします。
- YAMLLint
  `.yamllint.yml`に従います。`.github/workflows/`はactionlintの担当のため対象外にします。document-startとline-lengthは無効化し、TreefmtがPrettierで整形する`{ }`単一スペースのflow style（`braces`/`brackets`のmax-spaces-inside: 1）を許可します。重複キーなど実際のYAML構文・構造の問題は検出します。
- Shebang
  明示除外はありません。
- ShellCheck
  `*/zsh/*`とzsh判定されたshell scriptを除外します。
- LLMCLIStream
  `*/zsh/*`とzsh判定されたshell scriptを除外し、`contrib/`、`vendor/`、`node_modules/`、`.claude/plugins/`、`plugins/cache/`配下を対象外にします。`printf`・`echo`・`sed`等の小出力producerと、`>/dev/null`で無音化したtee、`# guardrail-allow: llm-cli-stream`付き行は除外します。

## テスト実行

`tests/*.sh`はguardrails自身の確定テストで、`.github/workflows/tests.yml`（push/PR起動、reusable workflowではない）がCIで実行します。fake toolによるwrapper挙動検証（timeout、引数生成、config分岐）と、実物の`treefmt`/`shfmt`/`prettier`/`typos`/`yamllint`/`ast-grep`を使った統合確認は別jobに分離しており、fixture-onlyの成功を統合確認の成功として扱いません。

- `unit_tests`: `tests/*.sh`のうちfake toolや`rg`/`jq`だけで完結するものを実行します。
- `real_tool_tests`: `ast-grep-no-derived-count-property-test.sh`、`gitleaks-config-test.sh`、`osv-scanner-swift-lockfile-test.sh`、`oxlint-config-test.sh`、`treefmt-real-tools-test.sh`、`typos-config-test.sh`、`yamllint-config-test.sh`、`zizmor-config-test.sh`を対象に、vendored binary（`bin/linux-x86_64/`、`.github/quality-gates/node_modules/`）とCI都度DLする`typos`/`yamllint`/`ast-grep`/`gitleaks`/`osv-scanner`/`oxlint`/`zizmor`を用意してから実行します。

新しい`tests/*.sh`を追加した場合、実物ツールが必要なら`.github/workflows/tests.yml`の`real_tool_tests`側の一覧へ追加してください。追加を忘れても`unit_tests`側でcommand not foundとして失敗するため、無言でスキップされることはありません。

## Vendoredツール

CIとローカル環境は`bin/<platform>/`にGit LFSでcommitした同一バイナリを使います。バージョン、公式配布元、配布物とバイナリのSHA-256、ライセンスpathは`config/vendored-tools.tsv`を正本とします。現在、macOS向けSwiftLint 0.63.2をvendoredツールとして管理します。

## 設定ファイル

| ファイル                  | 用途                        |
| ------------------------- | --------------------------- |
| `.markdownlint-cli2.yaml` | MarkdownLint設定            |
| `.markdownlintignore`     | MarkdownLint共有除外設定    |
| `.gitleaks.toml`          | gitleaks設定                |
| `.oxlintrc.json`          | Oxlint設定                  |
| `.swiftformat`            | SwiftFormat設定             |
| `.swiftlint.yml`          | SwiftLint設定               |
| `.zizmor.yml`             | zizmor設定                  |
| `prettier.cjs`            | Treefmt内で使うPrettier設定 |
| `sgconfig.yml`            | ast-grep設定                |
| `treefmt.toml`            | Treefmt設定                 |
| `typos.toml`              | Typos設定                   |
| `.yamllint.yml`           | YAMLLint設定                |

## 検討したが見送ったゲート

- taplo lint（TOML検証）
  Treefmtが`*.toml`に対して`taplo format --check`を既に実行しており、構文が壊れたTOMLは同じエラーメッセージで既にfailします。別ゲートとして`taplo lint`を追加しても検出範囲が増えないため見送ります。
- editorconfig-checker（`.editorconfig`準拠検証）
  2026-08-19時点で、このゲートの対象になるいずれのrepoにも`.editorconfig`が存在しません。ツールは`.editorconfig`が無いと無条件PASSする仕様のため、今追加しても実質no-opです。改行・末尾空白・インデントはTreefmt（Prettier/SwiftFormat/shfmt）が既に整形しています。いずれかのrepoが`.editorconfig`を採用する具体的な必要が出た時点で再検討します。
- 秘密情報スキャン特化ゲート（trufflehog）
  PR時の平文secret混入はgitleaksが検出し、履歴側はnocturnalzone repoの`scripts/guardrails/github-repositories-gitleaks-check.sh`がカバーしています。trufflehogを3つ目の重複ゲートとして追加する明確な責務差分がないため見送ります。
