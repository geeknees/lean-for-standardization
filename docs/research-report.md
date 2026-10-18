# 初期PoC研究レポート

実施日: 2026-10-18。対象はHappy Eyeballs v3 `-04`とERC-8004 Draftの固定コミット。両Trackの実行モデル、証明、反例探索、JSON CLI、原文・実装の固定、CI構成を作成し、Lean側を検証した。ERC-8004は独立したローカルEVMとの比較も実行し、4ケースの一致と1ケースの不一致を確認した。

同日の追補として、MozillaのHappy Eyeballs状態機械との比較を実装・実行した。17入力列で13本が一致し、4本で開始履歴の差を確認した。ERC値域制約の意図に関する追加調査はこの追補の対象外である。

## 1. 実装・証明したもの

両Trackに`Basic`、`Model`、`Properties`、`Oracle`、`Tests`を用意した。`step`／`run`は純粋関数であり、CLIからJSON操作列を評価できる。Lean同梱ライブラリ以外のLake依存はない。

主要な性質は次のとおり。HEは`LeanForStandardization.HappyEyeballs`、ERCは`LeanForStandardization.ERC8004`を省略表記する。

| 対象・定理 | 検証した結論 | 必要な前提 |
|---|---|---|
| HE `all_traces_spaced` | 任意の有限列で連続する開始間隔≥10ms | 初期状態からモデルの遷移を使う、単調な自然数ms、固定Config |
| HE `all_traces_tls_safe` | 待機条件下では必要なDNS回答以前にTLSを開始しない | Configがclient能力と依存関係を正しく表す、DNS真正性は外部 |
| HE `run_winner_stable` | 選択済みの勝者を後続通知が置換しない | 逐次化した通知、最初の成功を採用する方針 |
| HE `run_no_start_after_winner` | 選択後のイベント列で開始履歴が増えない | 上記方針。§6のSHOULDを採用 |
| HE `all_traces_valid` | spacing・TLS履歴・勝者選択後のactive消去を合成して保存 | 初期状態、任意のDNS応答順序 |
| ERC `transfer_clears_wallet_and_approval` | 移転でwalletとtoken承認を消去、新ownerを設定 | 抽象操作が成功する |
| ERC `transfer_revokes_unapproved_authority` | 旧承認を使って移転後も管理できない | 対象者は新ownerでもそのglobal operatorでもない |
| ERC `accepted_feedback_excludes_authority` / `authorized_feedback_rejected` | 現owner／token・global operatorの投稿を禁止 | 投稿時点の承認関係。過去の所有履歴を意味しない |
| ERC `request_requires_authority` | request発行者はownerまたは承認者 | 操作成功、Agentの存在 |
| ERC `response_requires_designated_validator` / `response_preserves_request_binding` | responseは指定validatorの0–100値で、requestの関連付けを保持 | 元requestの存在、操作成功 |
| ERC `rejection_preserves_state` | 拒否された任意操作で全状態不変、通知なし | モデルの原子的実行意味論 |

Happy Eyeballsの主要定理は`propext`、`Classical.choice`、`Quot.sound`、ERCの8定理は`propext`だけを推移的に利用する。未完成証明・独自の未証明公理・ネイティブ決定手続きによる証明完了扱いはない。生成補題の数を研究成果の数には含めない。

## 2. 形式化範囲

Happy Eyeballsは単一サービスのdual-stack TCP/TLSモデルで、A／AAAA／HTTPS、アドレスヒント、2種類のdelay、候補選択、接続の開始と終了を扱う。TCP完了とTLS開始、正常な負のDNS回答と解決失敗を別の状態にした。RFC 6724のfamily内順位は入力側へ委ねる。

ERC-8004は3 Registryの権限・状態遷移に限定した。owner、token approval、owner別global operatorを別々に持ち、wallet証明を外部のBoolean入力へ抽象化した。Ethereum全体、署名アルゴリズム、完全なERC-721を再実装していない。

MUST、SHOULD、本文の動作記述、モデル方針の対応は[仕様トレーサビリティ](spec-traceability.md)、具体的な入力・実装範囲は[Track A](happy-eyeballs.md)・[Track B](erc8004.md)を参照。

## 3. 反例と実際に得た知見

| 結果 | 何で確認したか | 分類と主張の限界 |
|---|---|---|
| HTTPSのIPv6 hintだけで開始できる例を初稿が拒否していた | 原文の具体例との照合、2イベントの回帰シナリオ | Model issue、修正済み。Lean定理が自然言語の誤読を自動発見したわけではない |
| Resolution Delay満了＋TCP準備完了でもTLSを待つ | 4イベントalphabetで最短列探索、削除縮小、CLI再現 | Model issue、誤った候補性質の反証。仕様欠陥ではない |
| 元ownerは移転後にfeedbackを投稿できる | 登録→移転→投稿、長さ0–3の有限列探索、EVMで同じ3操作の受理と最終状態一致 | Model issue、永久禁止という過剰な仮説の反証。Sybil耐性を示さない |
| 公式実装のfeedback値域が仕様のint128より狭い | 固定Solidityの`±10^38`条件、Leanで`10^38+1`を受理、EVMは`value too large`で拒否 | Open question。動作差は再現済み。追加制約の意図・仕様違反かの判断は保留 |
| Mozilla版が失敗直後に同時刻で次候補を開始する | 固定ソースの未変更実行、3イベントへの削除縮小 | Open question。公開APIの開始指示は10ms未満。呼出側の制御・実ソケットは未検証。上流テストにも同じ動作の期待がある |
| IPv6 hintの開始、hint保持、Resolution Delayの起点が異なる | 共通のDNS/時刻入力、全prefixの開始履歴 | Open question。版・SHOULDの方針・モデルの選択を含む差であり、バグ3件とは数えない |

EVM比較はSolidity 0.8.24、Shanghai、optimizer/runs 200、viaIR true、固定依存で実施した。移転、自己feedback、元ownerのfeedback、validationの4ケースが一致し、値域だけが不一致だった。数値域の反例は`register(1)`→第三者の`feedback(10^38+1)`の2操作。各1操作を削除するとaccept/rejectと最終状態が一致することも両側で再実行し、削除最小性を確認した。

詳細は[独立EVM比較](evm-comparison.md)に記録した。原文の解釈と既存議論を確認し、人間のレビューを経るまでは上流へ投稿しない。[発見記録](findings.md)には、出典・前提・最小列・最小性の範囲・重複調査・確信度を残した。

生成テストでは、HEの14イベント・深さ4・3Configの124,113状態訪問と、ERCの11操作・長さ1–4の16,104遷移で対象の安全性違反はなかった。長い競合は別の明示シナリオで補う。訪問数は重複を含み、無限の入力空間を網羅したものではない。

Mozilla比較は`dec4cea08c26806b9c3c81a97884c81c54316762`を対象とした。READMEの宣言版は`-02`、Leanは`-04`である。初回待機、試行間隔、遅いIPv4、勝者／キャンセル、空回答、独自delay、DNS全6順列を含む17列を実行した。上流120テストも成功した。公開APIが区別しないTLS開始は比較対象に含めず、単一サービス・h2・ECH無効の範囲で比較した。[Mozilla比較](mozilla-comparison.md)にアダプターの規約、4件の差、入力不適格を除外した縮小結果を記録した。

## 4. 証明していないことと理由

今回選んだ安全性の定理はすべて検証できた。証明ができないものを独自公理で置き換えていない。

活性は未証明。現在のモデルではタイマー経過と`start`が別イベントであり、到達可能な候補があっても環境が開始しなければ接続は成功しない。公平性、必要DNS回答の到着、到達可能性、TCP/TLS完了通知を形式化する必要がある。

完全なRFC 6724、複数service group、QUIC、署名検証、EVM bytecodeとLeanの同値性は未着手の範囲である。安全性を証明したことから性能、可用性、評判の真実性、Sybil耐性、Validatorの判断の正しさは導けない。[限界](limitations.md)に一覧化した。

## 5. 実行したコマンドと結果

`lean-toolchain`は`leanprover/lean4:v4.35.0`。ローカルではリポジトリ内elanのPATHを設定して実行した。

| コマンド | 結果 |
|---|---|
| `lake build` | 成功、両モデル・定理・oracle・テスト実行ファイルをビルド |
| `lake env lean LeanForStandardization.lean` | 成功 |
| `lake env lean Audit.lean` | 許可した基盤公理以外の推移依存なし。private宣言も対象 |
| `ruby scripts/check-audit.rb` | 外部公理への推移依存、未完成証明、native決定依存の3負例を意図した理由で拒否 |
| `lake exe model-tests` | 両Trackの境界・競合・権限・反例探索が成功 |
| `ruby scripts/check-json.rb` | 保存した17シナリオと不正JSON／必須フィールド欠落の拒否を検査 |
| `ruby scripts/check.rb` | 原文のSHA256／Git blob、文書リンク、補助ソース規約を検査 |
| `ruby tests/erc8004/evm/prepare.rb` | 固定ソースと依存lockを検査し、隔離したEVM比較環境を準備 |
| EVM環境で`npm ci --ignore-scripts`と`npm exec -- hardhat compile` | 指定版の依存導入とSolidityコンパイルが完了 |
| `node tests/erc8004/evm/run.mjs` | exit 0。4ケース一致、1ケースの指定した不一致、2つの削除候補で一致を検証 |
| 固定Mozillaソースで`cargo test --locked` | 120件成功（doc-test 1件を含む） |
| Rustアダプターで`cargo test --locked --offline` | 3件成功。開始、勝者／キャンセル、未対応入力の拒否を確認 |
| `ruby tests/happy-eyeballs/mozilla/test_runner.rb` | 全prefix比較、無効callback、削除最小化、誤った期待値での失敗／不完全reportを確認 |
| `ruby tests/happy-eyeballs/mozilla/run.rb` | exit 0。17列中13一致、4件の既知の差、3イベントの開始間隔反例を確認 |
| `git diff --cached --check -- . ':(exclude)specs/happy-eyeballs/mozilla/**'` | 独自変更の空白検査は成功。保存した上流原文の`mozilla/src/lib.rs:1567`にある末尾空白1件は、原文のハッシュを維持するため保持 |

GitHub Actionsには同じLean検証を設定した。2026-10-18に[PR #1](https://github.com/geeknees/lean-for-standardization/pull/1)をマージし、公開した`main`の`44ff755756a10145d08dfd4d61511a04bfe74317`で[Lean CIが成功](https://github.com/geeknees/lean-for-standardization/actions/runs/39134973408)した。EVM・Mozilla比較は独立したローカル実行であり、このCIには含まない。今回の追補差分のリモートCIも未実施。上流Issue投稿は未実施。同じコミットに対するDependabot Updatesには失敗した実行もあるが、Lean検証とは別のワークフローである。

## 6. Leanを使った追加価値

有限テストの例を増やすだけでなく、DNS到着順や古いコールバックを含む**任意の有限イベント列**に安全性を持ち上げられた。TLS開始時点の回答を履歴に残すことで、後から届いた回答によって早すぎる開始が隠れる観測ミスも避けた。

ERCではtoken承認とowner別global承認の違いを、移転後権限の定理に必要な前提として明示できた。実行モデルと証明が同じ定義を使うため、仮説を反例で調べた後、そのモデルの一般性を定理で検査できる。

一方、IPv6 hintの誤読は原文との照合、数値域差はSolidityの読解が発見の入口だった。Leanだけで仕様の正しさや新規性を判断した成果とはしない。「従来のテストより多く発見できた」という比較評価は、対照実験を行っていないため未回答である。

## 7. 次の研究課題

1. Mozilla比較で得た4件の差について、公開APIと呼出側の責任、仕様版、SHOULDの方針、モデルの解釈をレビューする。既存テストに含まれる動作を新規発見とは扱わない。
2. 固定した観測範囲で生成列の比較を増やす。公開APIで観測できないTLS内部は、適切な比較対象／観測方法を決めるまで分離する。
3. 複数service groupとQUICを段階的に加え、スケジューラの公平性を定義して条件付き活性を証明する。
4. ERCの署名期限・owner binding・重複request方針を明確化し、reentrancyや集約処理を別の検証範囲として追加する。
5. AI支援の効果を、失敗した候補、修正理由、作業時間、人間レビューの負荷を測る実験として評価する。

ERC値域差の意図調査は保留とし、今回のMozilla比較には含めない。上流への相談は、対象を絞った再現・解釈レビューと投稿の承認後に行う。

新規仕様欠陥の確定数を増やすことではなく、根拠・前提・再現性を揃えることを次段階への条件とする。
