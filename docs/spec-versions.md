# 固定した仕様・実装

取得・確認日: 2026-10-18 (Asia/Tokyo)。本文、モデル、テストは同じリポジトリで管理する。取得原文のSHA256とGit blob SHA1は各 `specs/*/manifest.json` に記録し、`ruby scripts/check.rb` が照合する。

| 対象 | 固定版 | 状態・取得元 |
|---|---|---|
| Happy Eyeballs v3 | `draft-ietf-happy-happyeyeballs-v3-04` | [Datatracker](https://datatracker.ietf.org/doc/draft-ietf-happy-happyeyeballs-v3-04/)、Active Internet-Draft。文書日付2026-07-02 |
| 同版の編集原文 | `915b2e601dadce9e1eb0c6f7a6b8a7023dc9e790` | [版タグのコミット](https://github.com/ietf-wg-happy/draft-happy-eyeballs-v3/tree/915b2e601dadce9e1eb0c6f7a6b8a7023dc9e790)、`draft-ietf-happy-happyeyeballs-v3.md` |
| ERC-8004 | `503591a6e80e6e1affdd6403341e25269141f046` | [ethereum/ERCsの本文](https://github.com/ethereum/ERCs/blob/503591a6e80e6e1affdd6403341e25269141f046/ERCS/erc-8004.md)、Draft。本文の最終変更2026-01-25 |
| ERC-8004公式実装 | `b9e466c250744a7e06b13dff9d3c2844ed64f825` | [erc-8004-contracts](https://github.com/erc-8004/erc-8004-contracts/tree/b9e466c250744a7e06b13dff9d3c2844ed64f825)、確認時のHEAD |
| Lean | `leanprover/lean4:v4.35.0` | [Leanリリース](https://github.com/leanprover/lean4/releases/tag/v4.35.0)、`lean-toolchain`で固定 |
| 方法の参考 | `336ca6191d9beba236d544c8dfa32502db880897` | [lean4-dom](https://github.com/takahashim/lean4-dom/tree/336ca6191d9beba236d544c8dfa32502db880897)、READMEで研究構成を調査 |

Happy Eyeballsの公開済み最新版が`-04`であることをDatatrackerで確認した。開発ブランチのHEAD `261574b7f92cdaf3a8bdf3643a65af8020471f2f` はその後の変更を含むため、モデルの規範根拠には使わない。保存したMarkdownのfront matterは版生成時に展開される`-latest`表記を含むが、内容の固定はタグのコミットSHAによる。公開された `-04` の節番号との対応を文書化する。

ERCの公開ページは [EIPS](https://eips.ethereum.org/EIPS/eip-8004)、版固定の正本は移管先 `ethereum/ERCs` の `ERCS/erc-8004.md` である。公式実装との比較は保存したSolidityとテストに限定し、mainnet上のコントラクトや他の実装へ一般化しない。

EVM比較ではSolidity 0.8.24、Shanghai、optimizer有効/runs 200、viaIR true、Hardhat 3.0.6、ethers 6.15.0、OpenZeppelin両パッケージ5.4.0を固定した。上流lockから必要な依存を抽出し、freshなローカルUUPS proxyへ二段階で初期化する。[実行結果とデプロイ条件](evm-comparison.md)を参照。

Leanの追加ライブラリ依存はない。StdとLeanに同梱されるJSON／メタプログラミング機能を使う。初期PoCの自然数時刻、有限リスト、有限状態の性質にはMathlibを必要としない。

原文は上流の著作権・ライセンス条件を保持する。`specs/` は検証用の原文であり、本プロジェクト独自コードのライセンスを上書き適用しない。
