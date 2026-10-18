# Happy Eyeballs v3: 最初の形式化

対象は [draft-ietf-happy-happyeyeballs-v3-04](https://www.ietf.org/archive/id/draft-ietf-happy-happyeyeballs-v3-04.html)（2026-07-02公開、作業開始時に確認）。GitHub tagの対応コミットは `915b2e601dadce9e1eb0c6f7a6b8a7023dc9e790`。原文は `specs/happy-eyeballs/draft-ietf-happy-happyeyeballs-v3-04.md` に固定している。Internet-Draftであり、最終RFCではない。

## 実行モデル

`LeanForStandardization.HappyEyeballs` は、単一の接続セットアップ、単一サービス／単一のアプリケーション・セキュリティグループ、IPv6を優先するdual-stack環境に限定したTCP/TLSモデルである。実ネットワーク接続を行わない。

`State` はA／AAAAの受信状態、HTTPSの状態、アドレスヒント、最初の正の回答の時刻、開始履歴、進行中の接続、TCP完了状態、TLS開始履歴、失敗、キャンセル、選択した勝者、現在時刻を保持する。候補一覧は `candidates` でDNS回答から計算し、重複した状態として保存しない。

`Event` は `dnsA`、`dnsAAAA`、`https`、`advance`、`start`、`transportReady`、`beginTls`、`success`、`failure`、`cancel`。`step` は純粋関数、`run` はイベント列の評価である。適用条件を満たさない操作は状態を変えない。時刻は自然数のミリ秒で、`advance` は非負時間の経過だけを表す。

タイマーによる時刻の進行と、接続開始のスケジュールを分けている。`advance` 自体は接続を自動開始せず、環境が `start` を提案したときにモデルがResolution DelayとConnection Attempt Delayを検査する。したがって、このモデルが直接証明するのは安全性であり、スケジューラの進行性ではない。

## 仕様上の区別

| 論点 | 仕様での位置づけ | このPoCの扱い |
| --- | --- | --- |
| 非同期DNS | §4.2 SHOULD／SHOULD NOT | A、AAAA、HTTPSを独立したイベントとして処理 |
| Resolution Delay 50ms | §4.2 RECOMMENDED | 設定可能、既定値50ms。最初の正の回答から計測 |
| IPv6 hint | §§4.2.1–4.2.2 SHOULDと具体例 | AAAA未到着でも正のIPv6 hintとServiceModeがあれば開始可能 |
| AliasMode | §4.2.1のアルゴリズム定義 | 最終ServiceModeの到着とは数えない |
| 候補順 | §§5.3、7 | family内のRFC 6724順位は入力に委ね、family間をinterleave。全候補を並べてから開始済みを除く |
| 開始間隔10ms | §6 MUST NOT | `SpacingAllowed` で常に強制。失敗やDNS更新でも迂回不可 |
| 通常の開始間隔250ms | §§6、9 推奨値 | `attemptDelay`の既定値。100ms推奨minimumと10msの必須下限を混同しない |
| TLS待機 | §6.1 MUST、§6.3 MUST | TCP開始とは別の `beginTls` で検査 |
| 成功後の他接続キャンセルと候補無視 | §6 SHOULD | このモデルは従う。最初の受理された成功を固定 |
| protected DNSでのSVCB解決失敗 | §6.3 SHOULD | setupをabortedにし、進行中接続をキャンセル |

`Config.mustWait` は次のいずれかで真になる。

1. SVCB-reliant clientである。
2. 接続中にSVCB-reliantへ移行する可能性がある。
3. DNSが暗号学的に保護され、対象security parameterの利用をサポートし、その存在に依存して機能を有効化する。

1と2は§6.1、3は§6.3から抽出した条件である。§6.3の3条件だけに限定すると、§6.1にある待機義務を落としてしまう。Resolution Delayが満了しても、この待機条件は解除されない。モデルの `noData` は正常な負のサービス回答、`failure` は解決失敗を表し、混同しない。常にreliantなclientは `noData` でもTLSを開始しない。optional clientは正常な負の回答で待機を解除できる。

## 証明済みの範囲

次の定理はLean 4.35.0でコンパイルし、カーネル検証を通過した。

| 定理 | 主張 | 前提・射程 |
| --- | --- | --- |
| `all_traces_spaced` | 初期状態からの全イベント列について、連続する接続開始は10ms以上離れる | 1 setup、固定config、モデルの `step` による遷移 |
| `all_traces_tls_safe` | 待機が必要なconfigでは、全TLS開始履歴が開始時点で完了済みHTTPS回答を観測している | security能力・依存関係はconfig入力。DNSの真正性自体は証明しない |
| `all_traces_valid` | `Spaced`、`TlsSafe`、勝者選択後のactive空集合を同時に保存 | 初期状態からの全イベント列。DNS順序を限定しない |
| `run_winner_stable` | 選択済み勝者は、その後の任意のイベント列で変わらない | 成功通知を逐次処理し、§6のSHOULDに従うモデル方針 |
| `run_no_start_after_winner` | 勝者選択後は任意のイベント列で開始履歴が増えない | 上記と同じ |

`winner` がOption型であるというだけの一意性ではなく、一度選択した勝者が後続の成功通知によって置き換わらないことを帰納法で証明している。TLSも終了状態のDNSフラグだけを検査せず、**開始時点の回答状態**を記録して証明する。後でHTTPS回答が届いても、早すぎたTLS開始を隠せない。

`#print axioms` で `all_traces_valid`、`run_winner_stable`、`run_no_start_after_winner` の推移的依存が `propext`、`Classical.choice`、`Quot.sound` のみであることを確認した。独自axiom、`sorry`、`admit`、`native_decide` は使っていない。実行テストの `#eval` は証明の代用ではない。

## テストと反例探索

`runTests` は49/50ms、9/10ms、失敗直後の再開始、TLS待機、AliasMode、正常な負の回答でのoptional/reliantの違い、保護されないDNSでもreliantへ移行可能なclientの待機、protected DNSの失敗、同時刻の成功競合、古い成功通知、hintの置換、遅れて来るIPv4、DNS3回答の全6順列を検査する。

14種類のイベント、深さ4、3種類のconfigについて、各prefixの安全性を検査した。訪問回数は **124,113状態**。これは重複を除いた状態数ではなく、探索木の状態訪問数である。深さ4では全ての長い競合は現れないため、明示的な長いシナリオを併用している。全長の安全性保証は上記の帰納証明による。

「Resolution Delay満了かつTCP準備完了ならTLS開始可能」という仮説には4イベントの反例を発見した。4種類の探索alphabetで長さ0〜3に反例がないことを検査し、幅優先探索で長さ4の反例を得た。余分なイベントを入れた列に削除縮小を適用し、同じ4イベントに戻ることも検査した。これは仕様の欠陥ではなく、§4.2をTLSまで拡張する誤解への反例である。詳細は `findings.md` を参照。

```sh
lake build LeanForStandardization.HappyEyeballs.Tests
lake exe model-tests
lake exe oracle happy-eyeballs tests/happy-eyeballs/resolution-not-tls-counterexample.json
lake exe oracle happy-eyeballs tests/happy-eyeballs/winner-race.json
```

JSONは `events` と任意の `config` を受け取る。endpointは `{"family":"ipv6","address":6}` の形式で、addressはネットワークアドレスの構文を表さない不透明な識別子である。各fixtureの `expect` は共通テスト実行器の期待出力であり、oracleは無視する。出力の `starts` と `tls` は古い順、`active` は内部順序である。`rejectedActions` は適用条件を満たさず状態を変えなかった操作数であり、DNS受信やゼロ時間の経過は数えない。

## 限界と次の優先順位

- RFC 6724の完全な順位規則、複数サービス優先度、ALPN群、QUIC、IPv6-only/NAT64、RTT学習、キャッシュ／TTLは未形式化。family内の事前順位を外部の責任とした。
- §6.1のTCP等の進捗を受けたNext Connection Attempt Timerの調整SHOULDは未実装。`attemptDelay`は固定で、`transportReady`は次回開始時刻を延長しない。10msの必須下限の証明はこの推奨動作の証明を含まない。
- Configは接続中に変わらない。動的なECHの内容・証明書検証は抽象化している。`success` はアプリケーションの必要条件を満たしたTLS接続の成功通知であり、その正しさは環境の責任。
- `ValidState` は証明対象の安全条件を表す。全ての構造的整合性や全draft適合性を定義したものではない。
- 進行性は未証明。公平な `start` の発火、DNSの必要回答到着、少なくとも1つの到達可能endpoint、有限時間で返るtransport/TLS結果等を仮定する必要がある。
- 安全性定理は任意のDNSイベント順に成り立つが、順序を替えたとき同じ接続が勝つことや同じ遅延で終わることは主張しない。
- 外部のHappy Eyeballs実装との差分テストは未実施。次は実装と観測境界を固定したadapter、複数サービスの順序、QUICのTLS同時開始、条件付き進行性の順に拡張する。

サービス群の順序には既存の [upstream Issue #113](https://github.com/ietf-wg-happy/draft-happy-eyeballs-v3/issues/113) がある。未実装領域の既存議論であり、このPoCが新規発見した問題ではない。
