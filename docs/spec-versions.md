# 固定した仕様・実装

取得・確認日: 2026-10-18 (Asia/Tokyo)。本文、モデル、テストは同じリポジトリで管理する。取得原文のSHA256と、Gitから取得した原文のGit blob SHA1は各 `specs/*/manifest.json` に記録し、`ruby scripts/check.rb` が照合する。

| 対象 | 固定版 | 状態・取得元 |
|---|---|---|
| Happy Eyeballs v3 | `draft-ietf-happy-happyeyeballs-v3-04` | [Datatracker](https://datatracker.ietf.org/doc/draft-ietf-happy-happyeyeballs-v3-04/)、Active Internet-Draft。文書日付2026-07-02 |
| 同版の編集原文 | `915b2e601dadce9e1eb0c6f7a6b8a7023dc9e790` | [版タグのコミット](https://github.com/ietf-wg-happy/draft-happy-eyeballs-v3/tree/915b2e601dadce9e1eb0c6f7a6b8a7023dc9e790)、`draft-ietf-happy-happyeyeballs-v3.md` |
| Mozilla Happy Eyeballs | `dec4cea08c26806b9c3c81a97884c81c54316762` | [固定実装](https://github.com/mozilla/happy-eyeballs/tree/dec4cea08c26806b9c3c81a97884c81c54316762)、READMEの宣言版は`-02`、ソースの一部は`-04`も参照 |
| Mozillaが宣言する旧draft | `draft-ietf-happy-happyeyeballs-v3-02` | [IETF公開原文](https://www.ietf.org/archive/id/draft-ietf-happy-happyeyeballs-v3-02.txt)、2025-10-20。全文をSHA256付きで保存 |
| ERC-8004 | `503591a6e80e6e1affdd6403341e25269141f046` | [ethereum/ERCsの本文](https://github.com/ethereum/ERCs/blob/503591a6e80e6e1affdd6403341e25269141f046/ERCS/erc-8004.md)、Draft。本文の最終変更2026-01-25 |
| ERC-8004公式実装 | `b9e466c250744a7e06b13dff9d3c2844ed64f825` | [erc-8004-contracts](https://github.com/erc-8004/erc-8004-contracts/tree/b9e466c250744a7e06b13dff9d3c2844ed64f825)、確認時のHEAD |
| Lean | `leanprover/lean4:v4.35.0` | [Leanリリース](https://github.com/leanprover/lean4/releases/tag/v4.35.0)、`lean-toolchain`で固定 |
| 方法の参考 | `336ca6191d9beba236d544c8dfa32502db880897` | [lean4-dom](https://github.com/takahashim/lean4-dom/tree/336ca6191d9beba236d544c8dfa32502db880897)、READMEで研究構成を調査 |

Happy Eyeballsの公開済み最新版が`-04`であることをDatatrackerで確認した。開発ブランチのHEAD `261574b7f92cdaf3a8bdf3643a65af8020471f2f` はその後の変更を含むため、モデルの規範根拠には使わない。保存したMarkdownのfront matterは版生成時に展開される`-latest`表記を含むが、内容の固定はタグのコミットSHAによる。公開された `-04` の節番号との対応を文書化する。

Mozilla比較はRust 1.98.1 / Cargo 1.98.1で実行した。上流ソースとテストを未変更保存し、アダプターのCargo.lockで依存を固定した。Mozillaから到達する依存が上流lockと同じであることをrunnerが検査する。宣言仕様版の違いを保ったまま、同じDNS・時刻・接続結果で比較する。[観測範囲と結果](mozilla-comparison.md)を参照。

ERCの公開ページは [EIPS](https://eips.ethereum.org/EIPS/eip-8004)、版固定の正本は移管先 `ethereum/ERCs` の `ERCS/erc-8004.md` である。公式実装との比較は保存したSolidityとテストに限定し、mainnet上のコントラクトや他の実装へ一般化しない。

EVM比較ではSolidity 0.8.24、Shanghai、optimizer有効/runs 200、viaIR true、Hardhat 3.0.6、ethers 6.15.0、OpenZeppelin両パッケージ5.4.0を固定した。上流lockから必要な依存を抽出し、freshなローカルUUPS proxyへ二段階で初期化する。[実行結果とデプロイ条件](evm-comparison.md)を参照。

Leanの追加ライブラリ依存はない。StdとLeanに同梱されるJSON／メタプログラミング機能を使う。初期PoCの自然数時刻、有限リスト、有限状態の性質にはMathlibを必要としない。

原文は上流の著作権・ライセンス条件を保持する。`specs/` は検証用の原文であり、本プロジェクト独自コードのライセンスを上書き適用しない。
