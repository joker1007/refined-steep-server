rbs-inline生成、steep型チェック、rspecテストを順に実行して結果を報告して。

1. `bundle exec rbs-inline --output=sig/generated lib` でRBSを再生成
2. `bundle exec steep check` で型チェック
3. `bundle exec rspec` でテスト実行

いずれかが失敗した場合はその時点で止めて、エラー内容を報告して。
