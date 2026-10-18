<!-- ABOUTME: Documents the executed comparison with a pinned Mozilla Happy Eyeballs state machine. -->
<!-- ABOUTME: Separates observable differences, model choices, and unverified protocol claims. -->
# Mozilla Happy Eyeballsとの独立比較

2026-10-18に`mozilla/happy-eyeballs`の固定版を実行し、**17本の共通入力列で13本が一致、4本で差**を確認した。比較するのは各入力直後の接続開始先・開始時刻、勝者、キャンセル先である。実ソケットやDNS通信は使わず、Mozillaが公開する純粋な状態機械をそのまま呼ぶ。

## 固定した対象

| 項目 | 値 |
| --- | --- |
| Mozilla実装 | [`dec4cea08c26806b9c3c81a97884c81c54316762`](https://github.com/mozilla/happy-eyeballs/tree/dec4cea08c26806b9c3c81a97884c81c54316762)、2026-10-15のコミット、crate 1.0.0 |
| MozillaがREADMEで宣言する仕様 | `draft-ietf-happy-happyeyeballs-v3-02`。ソースの一部は`-04`も参照 |
| Leanモデル | `draft-ietf-happy-happyeyeballs-v3-04`、Lean 4.35.0 |
| Rust環境 | ローカル実行はrustc 1.98.1 / cargo 1.98.1 |
| 上流コード | `specs/happy-eyeballs/mozilla/`にソース・テスト・Cargo定義/lock・ライセンスを未変更保存 |
| アダプター依存 | `tests/happy-eyeballs/mozilla/Cargo.lock`。上流lockを起点にJSON入出力用のserde_jsonを追加 |
| 接続条件 | `example.com:443`、単一ServiceMode、HTTP/2のみ、IPv6優先、ECH無効、alt-svcなし |
| 時刻 | 呼出側が渡す仮想ミリ秒。`Instant`の基準点からの差だけを使い、sleepしない |

[manifest](../specs/happy-eyeballs/manifest.json)がソースのSHA256／Git blobを固定する。公開版`-02`の全文もSHA256付きで保存した。runnerはMozillaから到達する依存の名前・版・checksumが上流lockと同じであることを検査し、アダプター用JSONライブラリの依存と区別する。

## 入力と観測の対応

Rustアダプターは型・ID・アドレスを変換し、Mozillaの`process_input`／`process_output`を呼ぶ。候補選択や待機条件を移植しない。Ruby runnerは同じ入力をLeanのJSON Oracleへ渡す。

| 共通入力 | Mozilla | Lean |
| --- | --- | --- |
| `dnsA` / `dnsAAAA` | 発行済みquery IDへの正常なDNS回答。空配列はNODATA | 同名イベント |
| `https service` | priority 1、同じhostname、ALPN h2、任意のIP hints | 同名イベント |
| `https noData` | `Https(Ok([]))`。解決エラーとは区別 | 正常な負のサービス回答 |
| `advance` | 仮想時刻を進めて出力を取得 | 時刻を進める |
| `failure` | 対象attempt IDへの失敗通知 | 同名イベント |
| `success` | 接続全体の成功通知 | 同時刻の`transportReady`→`beginTls`→`success` |

各入力の後、Mozillaは`None`、`Timer`、終端出力まで出力を取り出し、Leanは`start`を提案する。開始の可否は各実装が判断する。Mozillaの`Timer`は報告に残すが、比較対象は実際の開始出力であり、指定されていない時刻へ自動的に時計を進めない。したがって、タイマー予定時刻に必ず呼び出す環境の活性を検証したものではない。

アドレス識別子は1〜254で、IPv4は`192.0.2.n`、IPv6は`2001:db8::n`へ可逆に写す。これらへの通信は行わない。ALPNはh2だけなので、同じアドレスの異なるプロトコルを混同しない。

`starts`は順序を含めて比較する。`cancelled`は順序を正規化し、`winner`は有効な成功通知に続くMozillaの`Succeeded`出力から求める。最終状態だけでなく**全prefix**を比較する。途中で差が出ても、同時刻の追加DNS回答で最終観測が一致するケースを、runner自身のテストに含めた。

## 実行結果

| 入力列 | 結果 | 観測 |
| --- | --- | --- |
| Resolution Delay境界 | 一致 | Aのみの回答から49msでは未開始、50msで開始 |
| Connection Attempt Delay境界 | 一致 | 249msでは追加なし、250msで次候補 |
| 遅れて届くIPv4 | 一致 | IPv6→IPv4→次のIPv6の順 |
| 勝者とキャンセル | 一致 | IPv4成功後にIPv6をキャンセル。古いIPv6成功通知でも勝者を維持 |
| preferred-familyのNODATA | 一致 | AAAA空回答によって待機を解除 |
| 独自delay | 一致 | Resolution 25ms、Attempt 100msを反映 |
| 全DNS空回答 | 一致 | 接続開始なし。終端理由は比較対象外 |
| A/AAAA/HTTPSの全6到着順 | 6本で一致 | 同時刻のDNS入力と250ms後の接続観測 |
| `ipv6-hint-start` | 差 | LeanはIPv6 hintで0ms開始、MozillaはAAAA未着のため50msまで待つ |
| `failure-spacing` | 差 | デフォルト250ms設定で、Mozillaは失敗直後に0msで次候補を開始。Leanは250msで開始 |
| `hint-fallback` | 差 | 正式なAAAA回答に含まれないhintを、Mozillaは250/500msに追加試行。Leanは使わない |
| `resolution-timer-origin` | 差 | HTTPS NODATAの100ms後にAが届くと、Mozillaは100ms、Leanは150msで開始 |

4件はいずれも開始履歴の差である。勝者・キャンセルの比較で差がなかったことは、未実行の競合列まで一致することを意味しない。

### 失敗直後の開始間隔

`failure-spacing`からイベント削除で次の3イベントへ縮小し、両側で再実行した。時刻はすべて0ms、Connection Attempt Delayはデフォルト250msである。

```json
{"events":[
  {"kind":"dnsAAAA","addresses":[6,7]},
  {"kind":"https","answer":"noData"},
  {"kind":"failure","family":"ipv6","address":6}
]}
```

Leanの開始時刻は`[0]`、Mozillaは`[0, 0]`だった。各1イベントを削除した3候補も検査した。DNSイベントを削除した2候補は未発行接続へのcallbackとなり入力不適格、failureを削除した候補では10ms未満の開始は消える。これは**有効な入力列の範囲での1イベント削除最小性**であり、全設定・全入力における最短性ではない。縮小時の実行エラーや入力不適格を不一致として数えない。

`-02`と`-04`の§6にはともに10msの必須下限がある。固定実装では失敗済みattemptが待機判定から除かれる。さらに上流の`failed_connection_tries_next_immediately`や`failed_attempts_do_not_increase_delay`は即時再試行を期待しており、未把握の新しい動作を発見したとは主張しない。出力をその時刻に実行する呼出側では10ms未満の開始になるが、実際の組込み先が追加の間隔制御を持つかは未確認である。[発見記録](findings.md)でAPI境界の未解決事項として扱う。

### ほかの差の位置づけ

- IPv6 hintによる即時開始は`-04`の具体例に合わせたLeanの解釈である。Mozillaはpreferred-familyのquery完了を別途要求する。`-02`の具体例はTODOのままであり、単に現行draft違反と断定しない。
- hintの保持はMozillaソースに、RFC 9460 §7.3のSHOULDから意図的に外れる方針として説明されている。今回の実行では、正式なアドレスの失敗通知がなくても待ち時間後にhintが試行された。意図された方針と実際の条件を分けて記録する。
- Resolution Delayを最初の正の回答から測るのはLeanモデルの方針である。Mozillaは最初の完了回答から測り、NODATAも含める。この違いだけでどちらかを不正とは判断しない。

## 再現手順

Rust/Cargoと、README記載のLean・Ruby環境を用意し、リポジトリ直下で実行する。初回のCargo依存取得にはネットワークが必要。

```bash
export CARGO_HOME="$PWD/.tools/cargo-home"
export CARGO_TARGET_DIR="$PWD/.tools/mozilla-target"
cargo build --locked --manifest-path tests/happy-eyeballs/mozilla/Cargo.toml
cargo test --locked --manifest-path specs/happy-eyeballs/mozilla/Cargo.toml
cargo test --locked --offline --manifest-path tests/happy-eyeballs/mozilla/Cargo.toml
ruby tests/happy-eyeballs/mozilla/test_runner.rb
ruby tests/happy-eyeballs/mozilla/run.rb
```

確認した結果は、上流120テスト（doc-test 1件を含む）、アダプター3テスト、Ruby runnerの4検査、17入力列の差分比較である。runnerはLean OracleとRustアダプターをビルドしてから実行する。4件の既知の差には、差が出るprefix・フィールド・両側の最終観測を固定した。未知の差、期待した差の消失、版やソースの不整合は失敗になる。

reportは`.tools/mozilla-comparison/report.json`、縮小入力は同ディレクトリの`failure-spacing-minimized.json`に保存する。reportにはsource commit、依存一覧、コンパイラ版、ソース／実行ファイルのハッシュ、入力、全prefix、Mozillaの出力を残す。途中で失敗した場合は`complete: false`である。`test_runner.rb`は誤った期待値で失敗することも確認するため、最終確認はその後に`run.rb`を実行する。

この比較は独立したローカル検証で、通常のLean CIには追加していない。既存の`main`のCI成功は、この比較のリモート実行を意味しない。

## 比較の限界

- TLS開始・TCP進捗はMozilla APIに独立した入出力がなく、直接比較できない。LeanではSVCB-optional、security wait無効の設定を用い、接続成功通知を完全なTCP/TLS完了とみなす。TLS待機の定理の実装検証には使わない。
- AliasMode、DNSエラー／再回答／stale refresh、複数service group、ECH、QUIC、alt-svc、IPv4優先、接続の外部キャンセルは対象外。未対応入力を無視して成功扱いにせずエラーにする。
- DNSの送信順、タイマー通知そのもの、接続全体の失敗理由、レイテンシ性能、実ソケット、Firefoxへの組込みは比較していない。
- 同じ時刻の通知も1件ごとに出力を取り出す。複数の結果をまとめて渡す別の呼出規約を検証したものではない。
- 既知の差を説明するためにLeanやMozillaのモデル定義を変更していない。自然言語の解釈の判断と、その判断に基づくモデル変更は別の作業である。
