Steepの内部APIを新たに利用するコードが追加された場合に、`sig/external/steep.rbs` に不足しているスタブRBSを追加して。

手順:
1. `bundle exec steep check` を実行してUnknownConstantやUnknownTypeNameエラーを確認
2. エラーに対応するSteepの内部クラス・メソッドの実際のシグネチャを参照ソース（/home/joker/ghq/github.com/soutaro/steep）から調査
3. `sig/external/steep.rbs` に必要最小限のスタブを追加
4. 再度 `bundle exec steep check` を実行してエラーが解消されたことを確認
