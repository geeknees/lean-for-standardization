# lean-for-標準化

自然言語の標準仕様をLean 4で形式化し、仕様の条件、隠れた前提、反例、実装との不一致を調べるOSS研究プロジェクトです。Leanでプログラムを書いたこと自体を成果とせず、仕様について得られた知見を記録します。

最初のPoCは **Happy Eyeballs v3** と **ERC-8004: Trustless Agents**。純粋な状態遷移モデル、カーネルで検証する証明、JSON Oracle、境界テスト、有界探索、仕様対応表を揃えています。

## 検証済みの範囲

| 対象 | 形式化した範囲 | 主な証明 |
|---|---|---|
| Happy Eyeballs `-04` | 単一サービスの非同期A/AAAA/HTTPS、ヒント、Resolution Delay、接続候補、開始間隔、TCP/TLS、成功・失敗・キャンセル | 任意の有限イベント列で開始間隔≥10ms、必要なDNS情報以前のTLS開始禁止、勝者の不変性、成功後の新規開始禁止 |
| ERC-8004 Draft | Identityの所有者・承認・wallet、Reputation投稿、Validation request/response | 移転時wallet・token承認消去、現在の管理者によるfeedback禁止、request/response権限、拒否時の全状態保持 |

Lean **4.35.0**でローカルビルド・証明検証・公理依存監査を実行済みです。17件のJSONシナリオに加え、Happy Eyeballsは124,113状態の訪問、ERC-8004は16,104遷移の有界探索を検査しました。重複状態を含む有限探索であり、網羅性を示す数ではありません。

ERC-8004は固定したSolidity **0.8.24**／ローカルEVMでも比較し、4シナリオで観測が一致、feedback値域について1件の不一致を再現しました。詳細と再現手順は[独立EVM比較](docs/evm-comparison.md)にあります。

仕様全体への準拠や、現実のネットワーク／EVMの正しさを証明したものではありません。各結果の前提は[仕様対応表](docs/spec-traceability.md)、[限界](docs/limitations.md)、[研究レポート](docs/research-report.md)に記載しています。

## 再現手順

依存はLean同梱のStd／Leanライブラリと、補助スクリプト用のRubyです。Mathlib・追加Lakeパッケージは不要です。Leanは`lean-toolchain`、Lakeの依存は`lake-manifest.json`で管理します。

elanが導入済みなら、そのまま次の検証コマンドへ進めます。未導入なら、リポジトリ内の`.tools/`に導入します。ネットワーク接続が必要です。

```bash
bash scripts/bootstrap-lean.sh
export ELAN_HOME="$PWD/.tools/elan"
export PATH="$ELAN_HOME/bin:$PATH"
```

```bash
lake build
lake env lean LeanForStandardization.lean
lake env lean Audit.lean
ruby scripts/check-audit.rb
lake exe model-tests
ruby scripts/check.rb
ruby scripts/check-json.rb
```

`Audit.lean`は定義・定理の**推移的な公理依存**を調べます。許容する基盤公理は`propext`、`Classical.choice`、`Quot.sound`のみです。`check-audit.rb`は独自公理・未完成証明・ネイティブ決定手続きへの依存を注入し、監査の拒否動作も検証します。文字列検索だけで証明品質を判定しません。

`check.rb`は保存原文のSHA256・Git blob hashと補助的なソース規約を検査します。`check-json.rb`は保存された`expect`と実際のCLI結果を比較し、不正JSONの拒否も検査します。

## JSON Oracle

```bash
lake exe oracle happy-eyeballs tests/happy-eyeballs/spacing-boundary.json
lake exe oracle erc8004 tests/erc8004/transfer-wallet.json
lake exe oracle erc8004 tests/erc8004/value-cap-witness.json
```

`FILE.json`の代わりに`-`を渡すと標準入力を読みます。構文・形式エラーは終了コード1、プロトコルとして拒否された操作は終了コード0のJSON結果として返します。

Happy Eyeballs入力は`config`と`events`、ERC-8004入力は`operations`です。入力例と出力項目は各[Track A](docs/happy-eyeballs.md)、[Track B](docs/erc8004.md)にあります。大きなfeedback値にはdecimal stringを使えます。`expect`はテスト用の期待値であり、モデルの実行には影響しません。

## 今回得られた知見

- Resolution Delay満了とTCP完了だけでは、セキュリティ条件のあるTLS開始は許されません。強すぎる仮説への4イベント反例を保存しました。
- HTTPSのIPv6ヒントだけで進めるケースを原文と照合し、AAAAを待ちすぎていたモデル初稿を修正しました。
- 自己feedback禁止は現在の管理権限を対象とします。登録→移転→元ownerによる投稿の3操作で、「過去のownerも永久に禁止される」という仮説を反証しました。
- 公式Solidityのfeedbackには、仕様の`int128`より狭い`±10^38`の制限があります。`10^38+1`をLeanは受理し、ローカルEVMは`value too large`で拒否する差を再現し、登録→投稿の2操作に削除最小化しました。追加制約が仕様上許されるかは未確定です。

仕様欠陥の発見とは限りません。出典、最小列、既存議論の確認、確信度は[findings](docs/findings.md)を参照してください。上流への自動投稿は行いません。

## 構成

```text
LeanForStandardization/{HappyEyeballs,ERC8004}/
  Basic.lean        状態・イベント・操作
  Model.lean        純粋なstep/run
  Properties.lean   証明
  Oracle.lean       JSON入出力
  Tests.lean        シナリオ・有界探索・反例探索
tests/              保存したJSON列と独立EVM比較runner
specs/              固定した原文・比較ソース・ハッシュ
docs/               要件、方法、対応表、発見、限界、研究レポート
Audit.lean          コンパイル済み依存関係の監査
```

[GitHub Actions](.github/workflows/lean.yml)はビルド、証明、公理依存監査、モデルテスト、原文照合、JSONシナリオを実行する構成です。GitHub上の実行結果はまだ確認していません。EVM比較は追加依存を持つ独立手順とし、通常のLean CIには含めません。

[仕様の固定版](docs/spec-versions.md)・[研究の問い](docs/research-questions.md)・[方法](docs/methodology.md)も参照してください。研究構成は[lean4-dom](https://github.com/takahashim/lean4-dom)を参考にしました。

独自コードはMIT License。`specs/`の原文は上流の著作権・ライセンスを保持します。
