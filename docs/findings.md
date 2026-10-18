# 発見・反例・未解決事項

検証日: 2026-10-18。分類は **Specification issue**（仕様の問題）、**Implementation issue**（実装の問題）、**Model issue**（形式化・候補性質の問題）、**Open question**（解釈や原因が未確定）の4種とする。今回、標準仕様の新規欠陥を確定した結果はない。モデル初稿の修正、強すぎる仮説への反例、仕様と実装の条件差を区別して記録する。

上流Issue/PRの投稿はしていない。記録した検索は限定的で、重複が存在しないことの保証ではない。上流報告には再現確認と人間のレビューが必要。

## Happy Eyeballs v3

### HE-F01: IPv6 hintを優先familyの回答に数えない初稿を修正

- 分類: **Model issue**、修正済み。
- 対象: `draft-ietf-happy-happyeyeballs-v3-04` §§4.2、4.2.1、4.2.2。Git SHA `915b2e601dadce9e1eb0c6f7a6b8a7023dc9e790`。
- 想定した性質: ServiceModeでIPv6 hintを得ていれば、AAAAが未到着でも例示された接続を開始できる。
- 必要な前提: 単一サービス、正のIPv6 hint、開始済み試行なし、1つのsecurity/application group。
- 最小列: `https(service, [ipv6:6]) → start`。時刻は0msのまま。
- 観測: 初稿ではpreferred-familyの条件を `aaaa.isSome` だけで判定し、開始しなかった。§4.2.2のHTTPS hintsの例では、この段階で接続を開始する。`resolutionReady` でIPv6 hintも数えるよう修正し、現在の出力は `startTimes: [0]`。
- 再現: `lake exe oracle happy-eyeballs tests/happy-eyeballs/hints-start-without-aaaa.json`。
- 帰属: このPoC初稿の誤解。既存の外部実装のバグや仕様上の矛盾は主張しない。
- 重複確認: 2026-10-18にupstreamの公開Issue一覧とhint関連の検索を確認した。検索から本件との対応は確認できなかったが、閉じたIssue／全メールアーカイブは網羅していない。本件はローカルモデル修正であり、上流投稿の対象にしない。
- 確信度: モデルの修正必要性は高い。本文のpreferred-family回答の表現だけでなく、具体例もトレーサビリティに含める必要がある。

### HE-F02: Resolution DelayはTLS待機の上限ではない

- 分類: **Model issue**（単純化案／仮説の棄却）。現行モデルはこの誤りを実装していない。
- 対象: 同draft §§4.2、6.1、6.3。
- 仮説: 正のアドレスがあり、Resolution Delayを過ぎ、TCPが準備できればTLS開始を許せる。
- 前提: `dnsProtected = true`、`supportsSecurityParam = true`、`reliesOnSecurityParam = true`。HTTPSは未到着。
- 最小列: `dnsA([4]) → advance(50) → start → transportReady(ipv4:4)`。
- 結果: TCPは50msに開始するが、`resolutionReady = true` と同時に `tlsAllowed = false`。`beginTls(ipv4:4)` を追加すると拒否数が1増え、TLS開始履歴は空のまま。
- 再現: `lake exe oracle happy-eyeballs tests/happy-eyeballs/resolution-not-tls-counterexample.json`、拒否実演は `tests/happy-eyeballs/tls-pending.json`。
- 最小性: 4種類のイベントalphabetで幅優先探索。長さ0〜3に反例がなく、長さ4で上記を発見。冗長な0msイベントを加えた列を削除縮小し、4イベントに戻ることをテストした。他のalphabetや別の観測命題での大域最小性は主張しない。
- 帰属: 仕様の欠陥ではなく、transportの開始条件を暗号handshakeに誤って共用する解釈の問題。2つの許可条件を分離する必要が、実行可能な反例として明示された。
- 重複確認: upstreamの公開Issue一覧、SVCB／Resolution Delayを含む検索を確認したが、閉じたIssueとメール全体の照合は未完了。draft本文が既にこの待機を要求しているため、新規仕様欠陥として投稿しない。
- 確信度: 固定モデルでの反例は実行確認済み。仕様への対応は§6.3の待機要件に直接対応する。新しいネットワーク攻撃の発見は主張しない。

### HE-F03: 安全性違反と外部実装不一致は未発見

14種類のイベントを深さ4まで、3configで探索し、124,113の状態訪問において `checkState` の違反はなかった。時間境界、AliasMode、hint置換、遅れて来るIPv4、勝者競合は別のシナリオでも確認した。任意長の安全性は帰納証明による。

Happy Eyeballsの外部実装を固定した差分実行は未実施なので、外部実装との一致／不一致について結論はない。仕様の矛盾をこのPoCで確認したという結論もない。

### HE-O01: 複数service groupへの拡張

- 分類: **Open question**、未実装。
- 関連: §6のservice group順序と、低優先度groupへのfallback遅延。
- 既存議論: [Issue #113](https://github.com/ietf-wg-happy/draft-happy-eyeballs-v3/issues/113) の本文に同じ設計上の論点があることを確認した。取得画面は古い可能性があり、現在のIssue状態までは断定しない。
- 本PoCは単一サービスなので反例を構成していない。この論点を今回の新規発見に数えない。

### ERC-8004

検証日: 2026-10-18。原文commit `503591a6e80e6e1affdd6403341e25269141f046`、
実装commit `b9e466c250744a7e06b13dff9d3c2844ed64f825`。
上流Issue/PRの自動投稿は行っていない。

### ERC-F1: feedbackの追加数値上限

- 分類: **Open question**。仕様モデルと固定実装の実行上の不一致は確認したが、追加制約が仕様違反かの断定は保留する。
- 関連節: Reputation Registry / Giving Feedback。
- 想定した性質: 有効Agentに対する非管理者からの、int128の範囲内・decimals 0–18の投稿は、
  今回対象とする数値・権限条件では受理される。
- 必要な前提: fresh registry、Agent 0をowner 1が登録、caller 2は非管理者、任意の付加URI/tagを省略。
- 最小操作列: `register(1)` → `feedback(2, agent=0, value=10^38+1, decimals=0)`。
  fresh stateでは登録なしのfeedbackは無効なので、操作数2はこの条件で最小。
  値は正側の実装上限を1だけ超える最小整数であり、int128最大値より小さい。
- 観測結果: Lean oracleは受理する。固定Solidityは`MAX_ABS_VALUE = 1e38`を定義し、
  それを超える値を明示的に拒否する。Solidity 0.8.24／Shanghai／optimizer 200／viaIRで
  ビルドしたローカルEVMでも`value too large`によるrevertを確認し、feedbackは追加されなかった。
  この差はソース読解だけでなく実際のtransactionでも再現済みである。
- 最小化の検証: 2操作から各1操作を削除した候補を、Leanとfresh EVMで再評価した。
  いずれも受理／拒否と最終観測状態が一致し、この2操作は削除最小だった。
  エラー文字列は比較対象外なので、未登録Agentへの投稿の拒否理由が異なることを
  別の不一致として数えていない。
- 証拠: [仕様L206–217](https://github.com/ethereum/ERCs/blob/503591a6e80e6e1affdd6403341e25269141f046/ERCS/erc-8004.md#L206)、
  [Solidity定数L13](https://github.com/erc-8004/erc-8004-contracts/blob/b9e466c250744a7e06b13dff9d3c2844ed64f825/contracts/ReputationRegistryUpgradeable.sol#L13)、
  [拒否条件L106](https://github.com/erc-8004/erc-8004-contracts/blob/b9e466c250744a7e06b13dff9d3c2844ed64f825/contracts/ReputationRegistryUpgradeable.sol#L106)。
- Lean再現: `lake exe oracle erc8004 tests/erc8004/value-cap-witness.json`。
  `runTests`でもこのtraceとint128上下限を検査する。
- EVM再現: [固定環境の準備手順](evm-comparison.md)の後、`node tests/erc8004/evm/run.mjs`。
  同じfixtureを使い、通常4ケースの一致と本ケースの特定理由による拒否、削除候補を検査する。
- 解釈: 単なるモデルのint128取り違えではない。実装が集計演算などの都合で追加制限を採った
  可能性はあるが、採用理由は未確認。仕様で追加の上限を許すのか、実装/仕様のどちらを変える
  のかを人間が判断する必要がある。
- 重複確認: GitHub Issues検索で `repo:erc-8004/erc-8004-contracts MAX_ABS_VALUE`、
  `"value too large"`、`overflow`、`repo:ethereum/ERCs 8004 int128`は結果0件。
  これは限定した検索結果であり、全PR・Ethereum Magicians・非公開議論の確認は未了。
- 確信度: 固定ソースとローカルEVMの動作差は高い。実運用の影響・意図・仕様違反という分類は未確定。

### ERC-F2: 過去のownerも永久にfeedback禁止、という仮説への反例

- 分類: **Model issue**（候補不変条件の過剰な一般化を検出したもの）。仕様/実装の欠陥とはしない。
- 関連節: Identity Registry、Giving Feedbackのowner/approved operator禁止。
- 想定した性質: 一度でもAgentを所有したアドレスからは、そのAgentにfeedbackを投稿できない。
- 必要な前提: 原子的な移転、旧ownerが新ownerの承認を持たない。
- 最小操作列: `register(1)` → `transfer(1, agent=0, newOwner=2)` →
  `feedback(1, agent=0, value=100, decimals=0)`。
- 観測結果: 3操作すべて受理される。仕様の禁止は投稿時点のowner/operatorに関するもので、
  旧ownerの永久禁止ではない。固定SolidityのローカルEVMでも同じ3操作が受理され、
  最終状態が一致した。権限失効と履歴上の利害関係は異なる性質だった。
- 最小化: 3操作alphabetについて長さ0–3を短い順に全列挙し、このtraceが最初の反例となることを
  `runTests`で確認。削除により短くした列には、登録・過去の所有・投稿が揃わない。
- Lean再現: `lake exe oracle erc8004 tests/erc8004/former-owner-feedback.json`。
- 重複確認: `repo:erc-8004/erc-8004-contracts "previous owner"`は0件。
  既存[Issue #99](https://github.com/erc-8004/erc-8004-contracts/issues/99)はfeedbackの根拠/Sybil耐性を
  広く議論しているが、同一反例の報告と確認したわけではない。関連議論の完全な調査は未了。
- 確信度: 抽象モデルと固定Solidityのローカル実行で反例を確認した。禁止範囲の区別は高い確信度。

### 検出されなかったもの

今回の有界探索では、移転時walletクリア、現管理者の自己feedback拒否、request/response権限の
モデル内違反は検出しなかった。これは16,104遷移の探索結果である。対応する一般的安全性は
別途Lean定理で検証したが、Solidity全体や経済的な信頼性の正しさは結論しない。
