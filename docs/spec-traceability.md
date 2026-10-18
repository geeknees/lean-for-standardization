# 仕様トレーサビリティ

`Proven`は固定したLeanモデルの定理をカーネルで検証済み、`Tested`は記載したシナリオを実行済み、`Pending`は未検証、`Counterexample`は候補命題への再現済み反例を表す。仕様や既存実装全体の適合性は意味しない。定理・定義は各Trackの同名Leanファイル、JSONは `tests/<track>/` に置く。

MUST、SHOULD、MAY、大文字規範語のない本文、外部規格から導入した意味論、独自ポリシーをModalityとAssumptionsで区別する。バージョンと原文ハッシュは [固定版一覧](spec-versions.md) を参照。

## Happy Eyeballs v3

全定義と定理の名前空間は `LeanForStandardization.HappyEyeballs`。Sourceの `-04` は `draft-ietf-happy-happyeyeballs-v3-04`、Gitコミット `915b2e601dadce9e1eb0c6f7a6b8a7023dc9e790` を示す。`Proven` は記載した抽象モデルに関する証明であり、draft全体や外部実装の適合性認定ではない。

| Spec ID | Source | Requirement | Modality | Model | Proof | Test | Status | Assumptions |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| HE-ASYNC | [-04 §4.2](https://www.ietf.org/archive/id/draft-ietf-happy-happyeyeballs-v3-04.html#section-4.2) | DNS種別を独立に処理し、十分な情報またはResolution Delay後に開始 | SHOULD、開始条件はアルゴリズム本文、50msはRECOMMENDED | `step`, `resolutionReady`, `markFirstPositive` | — | `resolutionBoundaryEvents`, `dnsOrders` | Tested | dual-stack、IPv6優先、HTTPSをquery済み。最初の正の回答から計測するのはモデル方針（HE-M04参照） |
| HE-MIN-GAP | [-04 §6](https://www.ietf.org/archive/id/draft-ietf-happy-happyeyeballs-v3-04.html#section-6) | 直前の試行開始から10ms未満で次を開始しない | MUST NOT | `SpacingAllowed`, `startConnection`, `Spaced` | `step_preserves_spacing`, `all_traces_spaced` | `spacingBoundaryEvents`, `spacing-boundary.json` | Proven | 1 setup、自然数ms、初期状態から `step` のみ。設定delayが0でも下限は維持 |
| HE-SVCB-WAIT | [-04 §§6.1, 6.3](https://www.ietf.org/archive/id/draft-ietf-happy-happyeyeballs-v3-04.html#section-6.3) | reliant／移行可能client、またはprotected DNS等の3条件が成立するとき、回答前にcrypto handshakeを開始しない | MUST | `Config.mustWait`, `tlsAllowed`, `beginHandshake`, `TlsSafe` | `handshake_preserves_safety`, `all_traces_tls_safe` | `tls-pending.json`, `alias-pending.json`, `no-data-{optional,reliant}.json`, `may-become-reliant.json` | Proven | TCP/TLSのみ。configは能力・依存関係の申告。`noData` と `failure` を区別。実際のDNS真正性は環境前提 |
| HE-WINNER | [-04 §6](https://www.ietf.org/archive/id/draft-ietf-happy-happyeyeballs-v3-04.html#section-6) | 成功後に他試行をキャンセルし、未試行候補を無視 | SHOULDを採用したモデル方針 | `succeed`, `WinnerStopped` | `run_winner_stable`, `run_no_start_after_winner`, `all_traces_valid` | `raceEvents`, `winner-race.json` | Proven | 同時刻通知もイベント順で逐次処理。最初に受理した成功を選ぶ |
| HE-DNS-ORDER-SAFETY | [-04 §§4.2, 7](https://www.ietf.org/archive/id/draft-ietf-happy-happyeyeballs-v3-04.html#section-7) | DNSの非同期更新で上記安全条件を破らない | MUST安全条件と採用SHOULD方針の合成 | `step`, `run`, `ValidState` | `all_traces_valid` | 全6 DNS順列、14イベント深さ4×3config | Proven | 勝者や完了時間の順序独立性ではない |
| HE-ALIAS | [-04 §4.2.1](https://www.ietf.org/archive/id/draft-ietf-happy-happyeyeballs-v3-04.html#section-4.2.1) | AliasModeだけを最終的なサービス情報と扱わない | アルゴリズム本文 | `HttpsAnswer.ready` | TLS安全定理がreadyの定義を利用 | `alias-pending.json`, `runTests` | Tested | aliasの再query／複数targetは抽象化 |
| HE-HINT | [-04 §§4.2.1–4.2.2, 7](https://www.ietf.org/archive/id/draft-ietf-happy-happyeyeballs-v3-04.html#section-4.2.2) | hintsを利用し、実回答で置換し、開始済み試行を維持 | SHOULD、開始例は説明図 | `familyCandidates`, `resolutionReady`, `nextCandidate` | — | `hints-start-without-aaaa.json`, `hint-replacement.json` | Tested | 単一TargetName。IPv6 hintをpreferred-familyの正の情報として数える |
| HE-INTERLEAVE | [-04 §§5.3, 7](https://www.ietf.org/archive/id/draft-ietf-happy-happyeyeballs-v3-04.html#section-7) | 新回答を含め全候補の順位を作り、familyを交互にする | SHOULD | `candidates`, `nextCandidate` | — | `runTests` late IPv4、DNS順列 | Tested | RFC 6724のfamily内順位は入力順が満たす前提。完全なsorting適合性は未証明 |
| HE-PROTECTED-FAILURE | [-04 §6.3](https://www.ietf.org/archive/id/draft-ietf-happy-happyeyeballs-v3-04.html#section-6.3) | 暗号保護DNSでSVCB解決が失敗したら接続を断念 | SHOULDを採用したモデル方針 | `receiveHttps`, `State.aborted` | — | `protected-failure.json` | Tested | `failure` は正常な負の回答とは異なる |
| HE-CONJECTURE-TLS | [-04 §§4.2, 6.1, 6.3](https://www.ietf.org/archive/id/draft-ietf-happy-happyeyeballs-v3-04.html#section-6.3) | 仮説「Resolution Delay満了＋TCP準備完了ならTLS開始可能」 | 仕様要件ではない誤った仮説 | `transportReadyImpliesTlsAllowed` | 不成立、有限探索と削除縮小で反例 | `resolution-not-tls-counterexample.json`, `findTransportCounterexample` | Counterexample | defaultのsecurity条件、4イベントalphabetで最短4イベント。仕様欠陥の主張ではない |
| HE-LIVENESS | [-04 §§4, 6](https://www.ietf.org/archive/id/draft-ietf-happy-happyeyeballs-v3-04.html#section-6) | 到達可能な候補があれば最終的に接続成功 | 未採用の研究目標 | — | — | — | Pending | DNS到着、公平なtimer/start、到達性、成功通知、必要TLS/SVCB完了の環境前提が未形式化 |
| HE-TIMER-ADJUST | [-04 §6.1](https://www.ietf.org/archive/id/draft-ietf-happy-happyeyeballs-v3-04.html#section-6.1) | TCP等の進捗時に次回試行タイマーを調整する | SHOULD | `DelayAllowed`は固定delayのみ | — | — | Pending | TCP進捗を受けたタイマー延長は未実装。開始間隔の必須下限の証明とは別 |
| HE-MOZILLA-COMMON | [固定Mozilla実装](mozilla-comparison.md) | 同じDNS・時刻・callback列で公開観測が一致するという仮説 | 差分検証の研究仮説 | JSON Oracle＋外部scheduler | — | `mozilla/run.rb`、17入力列 | Tested | 単一サービス/h2/ECH無効。13本一致、4本で差。全prefixの開始・勝者・キャンセルに限定 |
| HE-MOZILLA-GAP | -02/-04 §6、Mozilla `connection_attempt` | 外部実装の開始指示も10ms下限を満たすという仮説 | MUST NOTと公開API観測の対応を検査 | `Spaced`、既存Oracle | Leanの定理はそのまま成立 | `mozilla/fixtures/failure-spacing.json` | Counterexample | Mozillaは失敗直後に0ms間隔の指示。3イベントへ削除最小化。実ソケット／呼出側の追加制御は未検証 |
| HE-MOZILLA-HINT | -02/-04 §§4.2.1, 7、-04 §4.2.2 | hintによる開始と正式回答後の候補が一致するという仮説 | SHOULD、説明図、実装方針の差 | `resolutionReady`, `familyCandidates` | — | `mozilla/fixtures/{ipv6-hint-start,hint-fallback}.json` | Counterexample | 2種類の差。hint保持は上流が明示するSHOULDからの意図的逸脱。仕様欠陥の主張ではない |
| HE-MOZILLA-RESOLUTION | -02/-04 §4.2、Mozilla `move_on_with_timeout` | 最初のDNS回答がNODATAでも開始時刻が一致するという仮説 | 起点に関するモデル方針 | `markFirstPositive` | — | `mozilla/fixtures/resolution-timer-origin.json` | Counterexample | 最初の正の回答と最初の完了回答の差。どちらかの不正とは断定しない |

## ERC-8004

全行の仕様ソースは[ERC-8004 Draft, commit 503591a6](https://github.com/ethereum/ERCs/blob/503591a6e80e6e1affdd6403341e25269141f046/ERCS/erc-8004.md)。
定義・定理の名前空間は`LeanForStandardization.ERC8004`。
`Proven`はLeanモデルのカーネル検証済みを意味し、Solidity検証済みという意味ではない。

| Spec ID | Source | Requirement | Modality | Model | Proof | Test | Status | Assumptions |
|---|---|---|---|---|---|---|---|---|
| ERC-ID-TRANSFER | On-chain metadata, [L154](https://github.com/ethereum/ERCs/blob/503591a6e80e6e1affdd6403341e25269141f046/ERCS/erc-8004.md#L154) | Agent移転時walletをクリア | 本文の明示動作、uppercase MUSTなし | `transferAgent`, `execute` | `transfer_clears_wallet_and_approval` | `transfer-wallet.json`, `transferScenario` | Proven | 成功した原子的移転。token承認消去はERC-721の依存意味論 |
| ERC-ID-AUTH-TRANSFER | Identity RegistryのERC-721委譲、[L46](https://github.com/ethereum/ERCs/blob/503591a6e80e6e1affdd6403341e25269141f046/ERCS/erc-8004.md#L46) | 移転後の権限は新ownerとその承認による | ERC-721から導入したモデル要件 | `authorized`, `transferAgent` | `transfer_revokes_unapproved_authority` | `transferScenario`, 新ownerのglobal承認テスト | Proven | 対象者は新ownerではなく、新ownerのglobal operatorでもない |
| ERC-REP-SELF | Giving Feedback, [L217](https://github.com/ethereum/ERCs/blob/503591a6e80e6e1affdd6403341e25269141f046/ERCS/erc-8004.md#L217) | owner/approved operatorの自己feedback禁止 | MUST NOT | `giveFeedback`, `authorized` | `accepted_feedback_excludes_authority`, `authorized_feedback_rejected` | `self-feedback.json`, `runTests` | Proven | token/global承認をモデル化。現在の権限を判定し、過去の権限履歴を禁止に使わない |
| ERC-REP-NUMERIC | Reputation/Giving Feedback, L206–217 | feedbackはint128、decimals 0–18 | int128は型の指定、decimalsはMUST | `int128Valid`, `giveFeedback` | `accepted_feedback_excludes_authority` | 上下限/18/19テスト、`value-cap-witness.json` | Proven | ±10^38制限は仕様要件として追加していない。実装との追加制約差はOpen question |
| ERC-DIFF-VALUE | [固定実装のgiveFeedback](https://github.com/erc-8004/erc-8004-contracts/blob/b9e466c250744a7e06b13dff9d3c2844ed64f825/contracts/ReputationRegistryUpgradeable.sol#L106) と上記仕様 | 仕様モデルと実装で数値域の受理が一致するという仮説 | 差分検証の研究仮説 | `giveFeedback`, JSON Oracle | — | `value-cap-witness.json`, `evm/run.mjs` | Counterexample | `10^38+1`はLean受理、EVM拒否。2操作の削除最小性を検査。追加制約が規格違反かは保留 |
| ERC-VAL-REQUEST | Validation Request, [L357](https://github.com/ethereum/ERCs/blob/503591a6e80e6e1affdd6403341e25269141f046/ERCS/erc-8004.md#L357) | requestはowner/operatorのみ | MUST | `requestValidation` | `request_requires_authority` | `validation-race.json` | Proven | Agent存在、ERC-721 subsetの承認関係 |
| ERC-VAL-RESPONDER | Validation Response, [L373](https://github.com/ethereum/ERCs/blob/503591a6e80e6e1affdd6403341e25269141f046/ERCS/erc-8004.md#L373) | 元requestの指定validatorのみresponse可能 | MUST | `respondValidation` | `response_requires_designated_validator`, `response_preserves_request_binding` | `validation-race.json` | Proven | hashとvalidator bindingが既に保存されている。暗号学的hashの性質は外部 |
| ERC-VAL-RANGE | Validation Response, L373 | responseは0–100 | 本文の明示範囲 | `respondValidation` | `response_requires_designated_validator` | `validationScenario`の0/100/101 | Proven | EVM uint8入力より広いNatを受け、100超を拒否 |
| ERC-VAL-REPEAT | Validation Response, [L375](https://github.com/ethereum/ERCs/blob/503591a6e80e6e1affdd6403341e25269141f046/ERCS/erc-8004.md#L375) | 同一requestへのresponse更新を許す | 本文の明示許可 | `respondValidation` | `response_preserves_request_binding`（bindingの維持のみ） | `validation-race.json` | Tested | 値の単調増加は要求しない。応答が必ず来るという活性は未証明 |
| MODEL-ERC-ATOMIC | EVM revertを抽象化 | 拒否操作は状態/eventを変えない | モデルの原子性方針 | `step` | `rejection_preserves_state` | 拒否シナリオ＋16,104遷移探索 | Proven | bytecode、gas、reentrancyをこの定理から導かない |
| MODEL-ERC-HASH | 固定実装 ValidationRegistryの`validationRequest` | request hashを重複登録させない | 実装に合わせたモデル選択 | `requestValidation` | — | `validation-race.json` | Tested | 仕様はhash識別に言及するが衝突時の規範動作は明確でない |
| MODEL-ERC-WALLET | On-chain metadata + 固定Identity実装 | wallet管理をowner/operatorに許し、外部証明を要求 | モデル選択＋外部前提 | `execute` `.setWallet`/`.unsetWallet` | — | `transfer-wallet.json`, 無効proofテスト | Tested | `proofValid`が署名・deadline・owner/domain bindingを抽象化。署名自体未証明 |
