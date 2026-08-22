# Greenroom

エージェントが書いたコードをマージし、動くかどうかは夜のあいだに確かめます。

greenroom が受け入れる pull request は、既存のメソッド本体を [Scientist](https://github.com/github/scientist) ブロックで囲み、候補を新しい private method として追加します。
Scientist はデフォルトでは候補を実行しないため、マージしてもユーザーが到達できる動作は変わりません。
その後、census job がテーブルの全行についてラップしたメソッドを一度ずつ呼び出し、古い結果と新しい結果を比較して件数を報告します。
judge はその件数を読み、promote、revert、retire のいずれかを行う次の pull request を作成します。

```ruby
class Pricing
  def compute(order)
    Scientist.run "price-v2" do |e|
      e.use { the_original_body }
      e.try { compute_v2(order) }
      e.compare { |a, b| a == b }
    end
  end

  private

  def compute_v2(order)
    # the candidate, as a plain private method
  end
end
```

二つの待ち時間がなくなります。
機械が数分で diff の形を読み取るため、マージはレビュー担当者の予定を待たずに済みます。
census はチームが管理するスケジュールですべての行を読み取るため、証拠はトラフィックを待たずに集まります。

## Scientist だけを使わない理由

Scientist は古いパスと候補のパスを実行し、結果を比較して observation を公開します。
それでもチームは、証拠の取得元、実行コンテキスト、意思決定プロセスを選ぶ必要があります。

一般的な Scientist の構成では、live traffic から証拠を得ます。
アクセスの少ないパスでは、十分な observation が集まるまで数か月かかることがあります。
experiment を有効にすると、live request の処理中に候補も実行されます。
Scientist がデータを公開し、それをどう扱うかは人が決めます。

Greenroom は、対象となる全行で両方のパスを比較する nightly census を追加します。
これにより、証拠はトラフィック量や運ではなく、管理されたスケジュールに従って集まります。
census はスキャンした行と比較した行をそれぞれ数え、二つの件数を分けて保持します。
両者の差は、experiment に到達する前に guard clause が処理を終了した行の数を示します。
これにより、空の検査を問題のない結果と誤認することを防ぎます。

`greenroom check` は diff の形を検査し、自動マージが安全かどうかを判断します。
`greenroom judge` は件数を分類し、次の pull request に適用できる patch を作成します。

Scientist の experiment は、`Scientist::Default#enabled?` が false を返すため、デフォルトで無効です。
Greenroom は、アプリケーションが experiment を有効にする方法を変更します。
Greenroom の `enabled?` method は、現在の thread に recorder がある場合に true を返します。
nightly census はその recorder を設定しますが、live request は設定しません。
一般的な Scientist の構成では、代わりにこの切り替えを sampling rule に接続します。

### Scientist だけで十分な場合

パスに十分な live traffic があり、証拠をすぐに集められる場合は、Scientist だけを使います。
この場合、live traffic は census よりも適切な input distribution を提供します。
Scientist は、request parameter や session から得る入力にも適しています。
census が構築できる入力はテーブルの行から得られるものなので、request だけに存在する入力は評価できません。
experiment が一つか二つなら、census job、middleware、threshold、judge、CI wiring のコストが、削減できるコストを上回ることがあります。

Greenroom は、エージェントが experiment を作る速度に人間のレビューが追いつかない場合に役立ちます。
Greenroom が対象とするのは一つの experiment ではなく、レビュー待ちの列です。

## このリポジトリの内容

| ディレクトリ | 内容 |
|---|---|
| `gems/greenroom` | Rails application が読み込む gem。experiment method、recorder、census core、boot assertion、`greenroom` command を含む |
| `gems/rubocop-greenroom` | 一つのファイルを読み、エージェントが書くべきではない形を拒否する cops |
| `skills` | この仕組みを教える skills |
| `docs` | architecture と decision records |

## 状態

初期段階です。
gem は構築中で、上記の各部分は記載した順序で追加されます。

## ライセンス

MIT です。
[LICENSE.txt](LICENSE.txt) を参照してください。
