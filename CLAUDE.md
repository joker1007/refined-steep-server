# refined-steep-server

Steepをライブラリとして利用して、Steep組込みと同等の機能を持ったlanguage server。
特にneovimとの親和性を意識している。
但しlanguage serverの実装はruby-lspを参考にする。

## 参照するソースコード

- Steep: /home/joker/ghq/github.com/soutaro/steep
- ruby-lsp: /home/joker/ghq/github.com/Shopify/ruby-lsp
- rbs-inline: /home/joker/ghq/github.com/soutaro/rbs-inline

## アーキテクチャ

- ruby-lsp方式のシングルプロセス・マルチスレッドモデル
  - メインスレッド: stdinからLSPメッセージ読み取り → incoming_queueへ
  - ワーカースレッド: incoming_queueから取り出し → process_message → Steepサービス呼び出し
  - ライタースレッド: outgoing_queueから取り出し → stdoutへJSON-RPC書き込み
- Steepのサービス群（TypeCheckService, HoverProvider, CompletionProvider, GotoService, SignatureHelpProvider）をライブラリとして直接利用
- PathAssignment.allで全ファイルを単一プロセスで処理

## 対応LSP機能

- textDocument/hover
- textDocument/completion (トリガー: `.`, `@`, `:`)
- textDocument/signatureHelp (トリガー: `(`)
- textDocument/definition
- textDocument/implementation
- textDocument/typeDefinition
- workspace/symbol
- textDocument/publishDiagnostics

## 型注釈

- rbs-inline方式で型注釈を記述
- 各Rubyファイル先頭に `# rbs_inline: enabled` マーカーを記述
- `sig/generated/` にrbs-inlineで生成したRBSを出力（.gitignore対象）
- `sig/external/steep.rbs` にsteep・language_server-protocol・parser gemの手書きスタブRBSを配置
  - steep gemはsig/をgemパッケージに含めていないため、RBS collectionでは型定義を取得できない
  - Steepの内部APIを新たに利用する場合はこのファイルにスタブを追加すること

## テスト・型チェック

- rspecを使用
- 実装時は各ステップでテスト通過を確認しながら進める
- steep checkはエラーなしの状態を維持する

## コマンド

- `bundle exec rspec` — テスト実行
- `bundle exec rbs-inline --output=sig/generated lib` — rbs-inlineでRBS生成
- `bundle exec steep check` — 型チェック
- 実装変更後のワークフロー: `rbs-inline生成 → steep check → rspec` の順に実行

## Commit Comment

Conventional Commitsの規約に従う。
