# guardrails

`noxyzone`配下のGitHubリポジトリで共通利用する品質ゲートを管理するリポジトリです。

各リポジトリにはcaller workflowだけを配置し、実際のチェック処理と設定はこのリポジトリの再利用workflowへ集約します。

## 共有ゲート

| ゲート       | workflow                             | 主な対象                                                   | 検出・確認内容                                       |
| ------------ | ------------------------------------ | ---------------------------------------------------------- | ---------------------------------------------------- |
| GitIdentity  | `.github/workflows/git-identity.yml` | commit author/committer                                    | GitHub noreply email以外の公開混入                   |
| SecretLint   | `.github/workflows/secretlint.yml`   | Git管理下の実ファイル                                      | API key、token、password、秘密鍵などの秘密情報混入   |
| Treefmt      | `.github/workflows/treefmt.yml`      | JSON、YAML、TOML、Markdown、Swift、shell scriptなど        | 未整形差分                                           |
| TextSpacing  | `.github/workflows/text-spacing.yml` | `*.md`、`*.txt`、`*.toml`、`*.yaml`、`*.json`、HTML、CSS等 | 日本語と英数字の間に入った半角スペース               |
| SwiftLint    | `.github/workflows/swiftlint.yml`    | `*.swift`                                                  | SwiftLint標準ルールと`try?`禁止などの独自ルール      |
| MarkdownLint | `.github/workflows/markdownlint.yml` | `*.md`                                                     | 見出し、リスト、空行などのMarkdown記法               |
| ESLint       | `.github/workflows/eslint.yml`       | `*.js`、`*.cjs`、`*.mjs`、`*.ts`                           | ESLint指摘                                           |
| Ruff         | `.github/workflows/ruff.yml`         | `*.py`                                                     | Ruff指摘                                             |
| Shebang      | `.github/workflows/shebang.yml`      | shell script                                               | `#!/bin/bash`等を検出し、`#!/usr/bin/env bash`を要求 |
| ShellCheck   | `.github/workflows/shellcheck.yml`   | zsh系を除くshell script                                    | ShellCheck指摘                                       |

## 除外ルール

- GitIdentity
  commit author/committer emailは`@users.noreply.github.com`のみ許可します。
- SecretLint
  symlinkと存在しないpathを除外します。
- Treefmt
  `treefmt.toml`に従います。現在は`.agents/skills/.system/**`、`artifacts/**`を除外します。
- TextSpacing
  `.claude/plugins/`、`.claude/todos/`、`.claude/cache/`、`.claude/projects/`、`.claude/plans/`、`.claude/shell-snapshots/`、`node_modules/`、`contrib/`、`artifacts/`を除外します。
- SwiftLint
  `.swiftlint.yml`の`excluded`に従います。現在は`DerivedData`、`.build`、`build`を除外します。
- MarkdownLint
  各repoの`.markdownlintignore`に従います。
- ESLint
  明示除外はありません。対象repo側のESLint設定があればそれに従います。
- Ruff
  明示除外はありません。対象repo側のRuff設定があればそれに従います。
- Shebang
  明示除外はありません。
- ShellCheck
  `*/zsh/*`とzsh判定されたshell scriptを除外します。

## 設定ファイル

| ファイル                  | 用途                        |
| ------------------------- | --------------------------- |
| `.swiftlint.yml`          | SwiftLint設定               |
| `.markdownlint-cli2.yaml` | MarkdownLint設定            |
| `.secretlintrc.json`      | SecretLint設定              |
| `.swiftformat`            | SwiftFormat設定             |
| `prettier.json`           | Treefmt内で使うPrettier設定 |
| `treefmt.toml`            | Treefmt設定                 |
