---
id: GUARDRAILS-ADR-0002
type: ADR
status: accepted
date: "2026-10-24"
updated: null
scope: GUARDRAILS
authority: delegated
decisionMakers:
  - Luxy
confidence: high
consulted:
  - architect（対象pathの読取制限により条件付き案）
informed:
  - Noxy
related: []
supersedes: []
supersededBy: []
---

# 既知の文書ダイジェストだけを既定の秘密情報検査から除外する

## Context and Problem Statement

未コミット評価仕様のAPI文書SHA-256がgitleaksのgeneric-api-keyへ誤検出された。値3件は台帳、JSON Schema、Chess960のAPI文書実体と照合済みで、資格情報ではない。固定評価仕様の改変はfingerprintを壊す。ユーザーは共有guardrailsの修正を含む完走を明示承認した。

## Decision Drivers

- 既定ルールと共有追加ルールの検出力を維持する
- 評価仕様の固定bytesを変えない
- 各リポジトリの設定で共有検査を弱めない

## Considered Options

- 既定ルールを継承した共有設定で既知のSHA-256値3件を完全一致allowlistにする
- ファイル全体や64桁hex全般を除外する
- 固定評価仕様へinline抑制を埋め込む

## Decision Outcome

既定ルール用の共有設定を追加し、useDefault=trueを維持する。generic-api-keyだけに適用するallowlistで、照合済み文書ダイジェスト3件をアンカー付き完全一致指定する。標準入力検査、環境変数による設定overrideの排除、共有追加ルールの別検査を維持する。CIとローカルは既存の共通wrapperを使う。

## Consequences

- 未知の64桁hex、既知値への前後付加、別の秘密情報ルールは引き続き検出する
- 既知値は検査対象pathを問わず非秘密値として扱う
- 新しい例外は出典照合と回帰テストを伴う共有設定変更が必要になる

## Confirmation

実gitleaks8.30.1で既知値3件が通り、未知値と前後付加が拒否され、既存のAWS・GitLab・Slack・private key・npm・GitHub・password陽性fixtureが失敗判定を維持する。元の通常hook付きコミットを再開し成功まで確認する。

## Pros and Cons of the Options

完全一致の値例外はstdin方式を変えず最小範囲で誤検出を解消する。プロジェクト固有の出典を共有設定で保守する負担がある。広い形式除外やファイル除外は採用しない。

## Review Conditions

gitleaks版、allowlistの意味、出典文書、既定ルールの検出条件が変わった場合に再確認する。

## More Information

- scripts/gitleaks-check.shとtests/gitleaks-config-test.shが実行正本
- 対象出典はnocturnalzone/.agents/skills/nocturnalzone-evaluating-agent-models/references/refinement-{ledger,jsonschema,chess960}-api-v1.md
