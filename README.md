# guardrails

`noxyzone`配下のGitHubリポジトリで共通利用する品質ゲートを管理するリポジトリです。

各リポジトリにはcaller workflowだけを配置し、実際のチェック処理と設定はこのリポジトリの再利用workflowへ集約します。

## 共有ゲート

| ゲート       | workflow                             | 主な対象                                                   | 検出・確認内容                                                                 |
| ------------ | ------------------------------------ | ---------------------------------------------------------- | ------------------------------------------------------------------------------ |
| GitIdentity  | `.github/workflows/git-identity.yml` | commit author/committer                                    | GitHub noreply email以外の公開混入                                             |
| SecretLint   | `.github/workflows/secretlint.yml`   | Git管理下の実ファイル                                      | API key、token、password、秘密鍵などの秘密情報混入                             |
| Treefmt      | `.github/workflows/treefmt.yml`      | JSON、YAML、TOML、Markdown、Swift、shell scriptなど        | 未整形差分、repoローカル`.swiftformat`の混入                                   |
| TextSpacing  | `.github/workflows/text-spacing.yml` | `*.md`、`*.txt`、`*.toml`、`*.yaml`、`*.json`、HTML、CSS等 | 日本語と英数字の間に入った半角スペース                                         |
| Localization | `.github/workflows/localization.yml` | `*.xcstrings`、SwiftのAppKit/独自UI入口                    | 日本語ローカライズ欠落、SwiftUI自動抽出に乗らないUI文字列の直書き              |
| SwiftLint    | `.github/workflows/swiftlint.yml`    | `*.swift`                                                  | SwiftLint標準ルールと`print()`・`try?`禁止などの独自ルール                     |
| MarkdownLint | `.github/workflows/markdownlint.yml` | `*.md`                                                     | 見出し、リスト、空行などのMarkdown記法                                         |
| ESLint       | `.github/workflows/eslint.yml`       | `*.js`、`*.cjs`、`*.mjs`、`*.ts`                           | ESLint指摘                                                                     |
| Ruff         | `.github/workflows/ruff.yml`         | `*.py`                                                     | Ruff指摘                                                                       |
| ast-grep     | `.github/workflows/ast-grep.yml`     | `*.swift`                                                  | Swift構造ルール（通知送信、管理外型extension、UIテスト環境判定、非仮想化一覧） |
| Shebang      | `.github/workflows/shebang.yml`      | shell script                                               | `#!/bin/bash`等を検出し、`#!/usr/bin/env bash`を要求                           |
| ShellCheck   | `.github/workflows/shellcheck.yml`   | zsh系を除くshell script                                    | ShellCheck指摘                                                                 |

## 除外ルール

- GitIdentity
  commit author/committer emailは`@users.noreply.github.com`のみ許可します。
- SecretLint
  symlinkと存在しないpathを除外します。
- Treefmt
  `treefmt.toml`に従います。現在は`.agents/skills/.system/**`、`artifacts/**`を除外します。repoローカルの`.swiftformat`は許可せず、共有`guardrails/.swiftformat`を使います。
- TextSpacing
  `.claude/plugins/`、`.claude/todos/`、`.claude/cache/`、`.claude/projects/`、`.claude/plans/`、`.claude/shell-snapshots/`、`node_modules/`、`contrib/`、`artifacts/`を除外します。
- Localization
  `sourceLanguage`が`en`で、`extractionState`が`stale`ではない英語source keyに`ja`ローカライズを要求します。URL、絶対path、`HEAD@{}`、記号/数値/format placeholderのみのキーは除外します。SwiftUI自動抽出に乗らない`NSMenuItem(title:)`、`Action(title:)`、`panel.title/message`、`column.title`の直書きを検出します。
- SwiftLint
  `.swiftlint.yml`の`excluded`に従います。現在は`DerivedData`、`.build`、`build`を除外します。SwiftLintのerrorはブロックし、warningは原則ブロックしません。禁止したいwarningは`.swiftlint.yml`でerrorへ昇格します。
- MarkdownLint
  各repoの`.markdownlintignore`に従います。
- ESLint
  明示除外はありません。対象repo側のESLint設定があればそれに従います。
- Ruff
  明示除外はありません。対象repo側のRuff設定があればそれに従います。
- ast-grep
  `sgconfig.yml`と`ast-grep/*.yml`に従います。現在は`*.swift`を対象にします。
- Shebang
  明示除外はありません。
- ShellCheck
  `*/zsh/*`とzsh判定されたshell scriptを除外します。

## 設定ファイル

| ファイル                  | 用途                        |
| ------------------------- | --------------------------- |
| `.markdownlint-cli2.yaml` | MarkdownLint設定            |
| `.markdownlintignore`     | MarkdownLint共有除外設定    |
| `.secretlintrc.json`      | SecretLint設定              |
| `.swiftformat`            | SwiftFormat設定             |
| `.swiftlint.yml`          | SwiftLint設定               |
| `eslint.config.js`        | ESLint設定                  |
| `prettier.cjs`            | Treefmt内で使うPrettier設定 |
| `sgconfig.yml`            | ast-grep設定                |
| `treefmt.toml`            | Treefmt設定                 |
