<!-- ABOUTME: Documents the independent, pinned Solidity comparison harness and its verification status. -->
<!-- ABOUTME: Records reproduced EVM differences separately from unresolved specification interpretation. -->
# ERC-8004 の独立 EVM 比較

## 現在の確認範囲

**固定版のコントラクトをローカル EVM で実行し、5 fixture の差分比較を完了した。**

- `prepare.rb` の実行、仕様・上流ソースの SHA256 検査、必要な依存の lock 閉包生成。
- `npm ci --ignore-scripts --offline --dry-run` による lock 整合性確認。これはインストール成功を意味しない。
- JavaScript と Ruby の構文検査。
- Solidity 0.8.24 による全 4 source file のコンパイル、3 Registry proxy の初期化とデプロイ。
- 4 fixture の一致、value-cap fixture の不一致、各 1 操作を削除した 2 候補の一致。

必要な依存と compiler は通常のターミナルで取得し、以降の実行をこの workspace で確認した。Node.js は `v24.14.1`。`node tests/erc8004/evm/run.mjs` は exit 0 で終了した。これは以下の限定された操作列の比較結果であり、上流の全 test suite や任意の操作列の一致を確認したわけではない。

2026-10-18 に実行。5 fixture は合計 28 操作、最小化の削除検査は追加 2 操作列。詳細な観測結果は ignored な `.tools/erc8004-evm/differential-report.json` に保存し、公開する再現材料は fixture、runner、固定ソース、本文の結果とする。

| 実行したコマンド | 作業ディレクトリ | 結果 |
| --- | --- | --- |
| `ruby tests/erc8004/evm/prepare.rb` | リポジトリ直下 | exit 0、source hash 検査と依存 lock 抽出 |
| `npm ci --ignore-scripts --offline --dry-run --cache /private/tmp/lean-standardization-npm-cache` | `.tools/erc8004-evm` | exit 0、導入前の lock 整合性確認のみ |
| `npm exec -- hardhat clean` | `.tools/erc8004-evm` | exit 0 |
| `npm exec -- hardhat compile` | `.tools/erc8004-evm` | exit 0、Solidity 0.8.24 / shanghai、4 source files |
| `node tests/erc8004/evm/run.mjs` | リポジトリ直下 | exit 0、4 一致・1 不一致、削除最小 2 操作 |

上記の実行 Node.js は `v24.14.1`。通常の `npm ci --ignore-scripts` による実パッケージ取得はユーザーのターミナルで行い、runner が導入された package の固定版を再検査した。

## 固定した対象と環境

| 項目 | 固定値 |
| --- | --- |
| 仕様 | `ethereum/ERCs@503591a6e80e6e1affdd6403341e25269141f046`、Draft |
| コントラクト | `erc-8004/erc-8004-contracts@b9e466c250744a7e06b13dff9d3c2844ed64f825` |
| Compiler | Solidity `0.8.24` |
| EVM target / runtime | `shanghai` / ローカル Hardhat EDR、chain ID `31337` |
| Optimizer | 有効、`runs = 200`、`viaIR = true` |
| OpenZeppelin | `contracts` / `contracts-upgradeable` とも `5.4.0` |
| Runner | Hardhat `3.0.6`、ethers `6.15.0` |
| 依存の固定 | 上流 `package-lock.json` から必要な推移的依存を抽出。94 エントリーには他 OS 向け optional package も含む |
| 時刻 | genesis の `initialDate = 2026-10-18T00:00:00Z`、以降のブロック時刻は EDR が生成 |
| アカウント | ローカル EDR が生成する公開のテスト用アカウント。抽象アドレス `1` が最初のアカウント、`0` は zero address |

上流の `hardhat.config.ts` からコンパイラ設定を抽出した。元の config は実行せず、ローカル専用 config を使う。`.env`、外部 RPC、実ウォレットの鍵は不要。

`prepare.rb` は生成物を `.tools/erc8004-evm/` に配置する。Registry 3 ファイルは snapshot をそのまま使う。独自 `Bootstrap.sol` は `OwnableUpgradeable` の所有者と slot 0 の identity address を初期化するためだけの補助コントラクトで、Registry のガードや状態遷移を再実装しない。同じファイルの `RegistryProxy` は OZ `ERC1967Proxy` の constructor を呼ぶだけの派生クラス。Hardhat 3 が project contract のデプロイ用 artifact を生成するために使う。

デプロイ手順は上流の `test/upgradeable.ts` と同じ二段階の初期化方式。

1. `Bootstrap` implementation をデプロイする。
2. `ERC1967Proxy` をデプロイし、`initialize(address)` で initializer version 1 と所有者を設定する。
3. 固定版の Registry implementation をデプロイする。
4. プロキシの所有者が `upgradeToAndCall` を実行し、Registry の `reinitializer(2)` を呼ぶ。
5. Reputation / Validation の identity address を作成した Identity proxy に設定する。

implementation の直接初期化や、別の Registry mock による置き換えは行わない。補助 Bootstrap 自体は上流ファイルのコピーではないので、ここにも信頼境界がある。production の CREATE2 / vanity address / Safe によるデプロイ経路は比較対象外。

## 再現コマンド

Lean のビルドが完了しており、Node.js が Hardhat 3 の要件を満たし、依存取得が可能なターミナルで実行する。

```bash
# リポジトリ直下
lake build
ruby tests/erc8004/evm/prepare.rb

cd .tools/erc8004-evm
npm ci --ignore-scripts
npm exec -- hardhat clean
npm exec -- hardhat compile
cd ../..

node tests/erc8004/evm/run.mjs
```

依存取得と初回の compiler 取得にはネットワークが必要。runner 自体はローカル EVM 内で実行し、listen socket や外部 RPC を使わない。生成する `differential-report.json` は `.tools/erc8004-evm/` に保存される。通常 CI の成功はこの optional EVM runner の成功を意味しない。

`hardhat clean` は生成された artifact / cache を消してから再コンパイルするために使う。source を変更して部分コンパイルした場合に古い build-info が残り、runner の source hash 検査と衝突することを避ける。

runner は package version、snapshot の hash、compiler input、compiler settings を検査してから比較する。完了時に source commit、compiler 設定、依存の版、Lean executable と build-info の hash、両方の観測結果を保存する。途中で失敗した場合の report は `complete = false` であり、完了した case までしか含まない。

## 比較するもの

Lean の `.lake/build/bin/oracle erc8004 -` と Solidity に**同じ JSON 操作列**を入力する。JavaScript adapter が行うのはアドレス・ハッシュ・ABI の変換、署名の用意、呼び出し、観測値の収集。Lean の認可判定や遷移関数を JavaScript に移植していない。

| Fixture | 比較目的 | 実行結果 |
| --- | --- | --- |
| `transfer-wallet.json` | 承認済み操作者による wallet 設定と transfer、承認解除後の再設定拒否 | 一致 |
| `self-feedback.json` | owner / token approval / operator による feedback と decimals 境界 | 一致 |
| `former-owner-feedback.json` | transfer 後の元 owner は現在の認可主体ではなくなる | 一致 |
| `validation-race.json` | request 認可、重複 hash、validator、response 0/100/101、所有権変更 | 一致 |
| `value-cap-witness.json` | `int128` 内の `10^38 + 1` | 不一致: Lean が受理、Solidity が `value too large` で拒否 |

比較は操作ごとの accept/reject と最終状態（owner、wallet、token approval、feedback、validation）に限る。エラーの文言を同一仕様とはみなさず、既知の value-cap witness 以外では理由文字列を比較しない。event は登録 ID、feedback index、request hash と response 有無の列挙に使い、値は public view から再取得する。全 event の一致、gas、storage layout の証明は対象外。

`setWallet` の `proofValid = true` ではテスト用 EOA で実際に EIP-712 署名を作る。`false` は空署名に対応させる。Lean の抽象的な proof boolean と任意の ECDSA / ERC-1271 入力との同値性を証明したわけではない。

比較ドメインは fixture の小さな整数 ID / hash、ローカルアカウント、ERC-721 の一部操作に限定する。zero address からの送信、uint 上限、再入、悪意ある ERC-721 receiver、ERC-1271 contract wallet、upgrade 権限や永続 chain は対象外。ABI 変換エラー・インフラ障害は「プロトコルが拒否した」として数えず、runner を失敗させる。

## value-cap witness の証拠と限界

snapshot の `giveFeedback` は `MAX_ABS_VALUE = 1e38` を使って値域を制限する。仕様の `int128` は `[-2^127, 2^127 - 1]` であり、`10^38 + 1` はその範囲内。`value-cap-witness.json` は登録と第三者 feedback の 2 操作からなる。

これは**仕様に明記されない狭い値域を、実装ソースと EVM 差分実行の両方から確認した不一致**。Lean は feedback を追加し、Solidity は `value too large` で拒否して feedback を追加しなかった。仕様の意図、上流での既存議論、許容される追加制約かどうかは別に確認が必要。runner は EVM 側が該当する理由で拒否することまで要求するので、無関係な例外を期待した不一致として扱わない。

runner は各操作を削除した候補を両側で再実行し、不一致が残る限り削除を続ける。今回、登録を削除すると双方が feedback を拒否し、feedback を削除すると双方が登録のみを受理した。両削除候補で観測が一致し、元の 2 操作列は操作削除に関して最小だった。削除検査の観測結果を report に、縮小後の操作列を `.tools/erc8004-evm/value-cap-minimized.json` に保存した。これは操作削除に関する最小化であり、数値や初期条件の最小化ではない。

他の scenario で不一致を見つけた場合は、まず adapter、初期化、版の誤りを除外し、独立して操作列を縮小する。differential fuzzing は未実装。
