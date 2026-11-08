# jtr-eval: 日本語技術文書の読みやすさ評価 (生成モデル比較用)

生成モデルやサービスが書いた日本語技術文書を、日本語話者の IT エンジニアにとっての読みやすさで比較するための雛形です。
固定のタスクセットに対して各システムの出力を集め、Claude を採点者としたペア比較で勝敗を付け、Bradley-Terry でレーティング化します。

## 構成

```
bin/jtr                  CLI
tasks/*.yml              タスクセット (7カテゴリ × 15件 = 105件。tasks/README.md 参照)
lib/jtr/
  task_set.rb            タスク読み込み
  rubric.rb              採点観点と採点器プロンプト
  judge_schema.rb        採点結果の JSON スキーマ (structured outputs)
  judge.rb               ペア比較採点器 (提示順を入れ替えて2回判定)
  stub_judge.rb          API を呼ばない採点器 (動作確認用)
  diagnostics.rb         決定論的な診断指標 (文長、漢字率、敬体常体混在など)
  bradley_terry.rb       レーティング推定とブートストラップ信頼区間
  report.rb              Markdown レポート
  generators/command.rb  任意コマンドで出力を生成する汎用アダプタ
  generators/claude.rb   Claude モデルを評価対象にするアダプタ
outputs/<system>/<task_id>.json   評価対象の出力 (git 管理外)
verdicts/<a>__vs__<b>.jsonl       判定結果 (git 管理外、追記型で再開可能)
examples/                selftest 用のサンプル出力
```

## セットアップ

```bash
bundle install
export ANTHROPIC_API_KEY=...   # 採点と Claude 生成に必要。selftest と lint は不要
bin/jtr selftest               # API なしで一通り動くことを確認
```

テスト:

```bash
ruby -Ilib -Itest -e 'Dir["test/*_test.rb"].each { |f| require_relative f }'
```

## 使い方

### 1. 評価対象の出力を集める

どんなサービスでも、標準入力でプロンプトを受け取り標準出力に回答を返すコマンドがあれば評価できます。

```bash
bin/jtr generate --system my-service --command "python3 scripts/call_my_service.py"
```

Claude を評価対象にする場合:

```bash
bin/jtr generate --system opus-5-5 --model claude-opus-5-5
bin/jtr generate --system sonnet-5-5 --model claude-sonnet-5-5 --category concept
```

既に出力があるタスクはスキップします。作り直すときは `--force` を付けます。

### 2. ペア比較で採点する

```bash
bin/jtr judge --a opus-5-5 --b my-service
bin/jtr judge-all                           # outputs/ にある全システムの総当たり
bin/jtr judge --a x --b y --stub            # API を呼ばずにパイプラインだけ確認
```

採点器の既定は `claude-opus-5-5`、effort は `high` です。`--judge-model` と `--effort` で変えられます。
判定は `verdicts/` に追記されるので、途中で止めても再実行すれば続きから進みます。

### 3. レポートを出す

```bash
bin/jtr report                    # 標準出力に Markdown
bin/jtr report --out reports/latest.md
bin/jtr lint                      # 診断指標を TSV で出力
```

## 採点の設計

- **ペア比較**: 絶対評価より判定が安定するため、2出力を比べて観点ごとに A / B / tie を返させます。
- **提示順の入れ替え**: 同じペアを A/B を入れ替えて2回判定し、一致した場合だけ勝敗を採用します。不一致は tie です。レポートの「採点の安定性」で一致率を確認できます。
- **観点**: 一読理解性、曖昧さの排除、用語と日本語の自然さ、構造の適切さ、冗長性のなさ。定義は `lib/jtr/rubric.rb` にあります。
- **情報網羅性 (coverage)**: タスクの `must_cover` に対する欠落を別軸で記録します。総合判定には入れません。短くして読みやすく見せているだけの出力を見つけるための指標です。
- **長さバイアス対策**: 採点器に「長さは評価しない」と明示しています。それでも `lint` の文字数と勝率を突き合わせて、長さと勝率の相関を定期的に確認してください。
- **自己選好バイアス**: 評価対象に採点器と同系列のモデルが含まれる場合は、採点器を変えて結果が変わらないか確認してください。
- **structured outputs**: 採点結果は JSON スキーマで固定し、パース失敗をなくしています。スキーマでは観点の網羅を強制できないので、`JudgeSchema.validate!` で後段チェックしています。
- **拒否時の扱い**: 採点器が `refusal` を返した場合はエラーにします。`fallbacks: :default` を付けているので、安全分類器による拒否は代替モデルに自動で振り替わります。

## 次にやること

1. **タスクを増やす**: 現在は各カテゴリ15件、計105件です。カテゴリあたり30〜40件まで増やすと差の検出力が上がります。公開用と検証用を分けます。
2. **人手評価で較正する**: ペア比較の一部 (200〜300ペア) を日本語話者のエンジニア2〜3人に判定してもらい、採点器との一致率を測ります。人間同士の一致率が上限の目安です。ズレが大きい観点のルーブリックを書き直します。
3. **診断指標の重みを決める**: `lint` の指標のうち人手評価と相関するものだけを残し、レポートに載せます。
4. **採点器を版管理する**: 採点モデル、ルーブリック、スキーマを変えたら全ペアを再判定し、旧結果とは混ぜないでください。

## 出力ファイルの形式

`outputs/<system>/<task_id>.json`:

```json
{ "task_id": "concept-001", "system": "opus-5-5", "text": "...", "model": "claude-opus-5-5",
  "stop_reason": "end_turn", "usage": {"input_tokens": 1, "output_tokens": 2}, "latency_s": 3.2,
  "generated_at": "2026-11-08T00:00:00Z" }
```

`verdicts/<a>__vs__<b>.jsonl` の1行:

```json
{ "task_id": "concept-001", "category": "concept", "a": "opus-5-5", "b": "my-service",
  "overall": "a", "position_consistent": true,
  "criteria": {"comprehension": "a", "clarity": "tie", "terminology": "a", "structure": "tie", "concision": "a"},
  "coverage": {"a_missing": [], "b_missing": ["..."]},
  "runs": [ {...1回目の生の採点結果...}, {...2回目(入れ替え)...} ],
  "judge_model": "claude-opus-5-5", "judge_usage": {...}, "judged_at": "..." }
```
