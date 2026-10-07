---
id: GUARDRAILS-ADR-0001
type: ADR
status: accepted
date: "2026-10-07"
updated: null
scope: GUARDRAILS
authority: delegated
decisionMakers:
  - Luxy
confidence: high
consulted:
  - Advisor
informed:
  - ユーザー
related: []
supersedes: []
supersededBy: []
---

# formatterの実行期限をGNU timeoutへ委譲する

## Context and Problem Statement

treefmt-check.shの独自watchdogは、formatter終了後にwatchdogのsubshellを終了してもsleepの子プロセスを回収せず、呼び出し元から継承したFDを保持させていた。隔離fixtureで実wrapperが正常終了した0.786秒後にもPPID1のsleepがkernel FDを保持し、設定した8秒の期限経過後にlockを再取得できることを確認した。実運用の未確認要求は再送せず保全する。

## Decision Drivers

- 呼び出し元の排他FDを独自timerの孤児化で保持させない
- 期限と終了statusを標準ツールの管理範囲へ委譲する
- 文書同期のFD保持拒否を弱めず、原因側を修正する

## Considered Options

- 公式GNU coreutilsのtimeoutへ実行期限を委譲する
- Bash watchdogのsignal trapでsleepの終了と回収を実装する
- 呼び出し元でFD保持拒否を迂回する

## Decision Outcome

独自watchdogとtimer markerを廃止し、GNU timeout --kill-after=1sへ実行を委譲する。GNU timeout、またはHomebrewが提供するgtimeoutを明示的に解決し、利用できない場合は導入要件を示して失敗する。旧watchdogへのfallbackは設けない。default60秒と設定検証、通常の終了status、期限超過時の既存エラー表現を維持する。--foregroundは使用しない。

## Consequences

- 公開consumerにもGNU coreutilsが必要になるためREADMEへ依存を明示する。作業Macでは既存宣言と公式配布版を用い、新たな環境導入は行わない
- 独自timerの子プロセスはなくなるが、formatter自身が正常終了後に残す任意の子孫のcleanupを保証するものではない
- 実wrapperを用いた隔離FD回帰テストを既存テスト入口へ接続する
- 文書同期のkernel FD再取得、実出力証拠、未確認履歴の保全契約は変更しない

## Confirmation

変更前のFD回帰テストで失敗を確認し、変更後に正常終了、非ゼロ終了、期限超過とTERMを無視するfixtureでFD再取得と終了statusを確認する。実formatterによる隔離probeも再確認する。Git公開と実運用再開は、それぞれのgateと所有境界を満たしてから判定する。

## Pros and Cons of the Options

GNU timeoutは独自signal処理とtimer子プロセスを削除できる一方、非NixのmacOS consumerにはcoreutils導入が必要となる。Bash trap案は依存を増やさないが、起動とPID代入間のsignal競合、子プロセス回収を自前で管理する。FD拒否の迂回は原因を残すため採用しない。

## Review Conditions

GNU timeoutで既存の終了status契約を維持できない場合、公式ツールでも本timer由来のFD保持が再現する場合、または対応platformの依存条件が変わった場合に再検討する。外部キャンセルの保証を拡張する場合は別途判断する。

## More Information

- scripts/treefmt-check.sh
- tests/treefmt-wrapper-test.sh
- 隔離実測:/private/tmp/nz-docsync-fd-formatter-probe-cmxcnhg0
- ユーザーの進行指示に基づく限定的な根本原因修正。中央GitとAGENTS.mdの比較freezeは維持する。
