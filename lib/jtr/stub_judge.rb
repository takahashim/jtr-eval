# frozen_string_literal: true

module Jtr
  # API を呼ばない採点器。パイプラインの動作確認と単体テスト用。
  # 診断指標から機械的に勝敗を決めるだけで、評価結果として意味はない。
  class StubJudge
    def model = "stub"

    def compare(task, a_name, text_a, b_name, text_b)
      da = Diagnostics.analyze(text_a)
      db = Diagnostics.analyze(text_b)
      criteria = {
        "comprehension" => pick(da.mean_sentence_len, db.mean_sentence_len),
        "clarity" => pick(da.max_commas, db.max_commas),
        "terminology" => pick(da.katakana_ratio + (da.style_mix ? 1 : 0), db.katakana_ratio + (db.style_mix ? 1 : 0)),
        "structure" => pick((da.bullet_ratio - 0.4).abs, (db.bullet_ratio - 0.4).abs),
        "concision" => pick(da.redundant.values.sum + (da.preamble ? 1 : 0), db.redundant.values.sum + (db.preamble ? 1 : 0))
      }
      votes = criteria.values.tally
      overall = if (votes["a"] || 0) > (votes["b"] || 0) then "a"
                elsif (votes["b"] || 0) > (votes["a"] || 0) then "b"
                else "tie"
                end
      {
        "task_id" => task.id,
        "category" => task.category,
        "a" => a_name,
        "b" => b_name,
        "overall" => overall,
        "position_consistent" => true,
        "criteria" => criteria,
        # 網羅性は意味の判定が必要なので、スタブでは欠落なしとして扱う。
        "coverage" => { "a_missing" => [], "b_missing" => [] },
        "runs" => [],
        "judge_model" => "stub",
        "judge_usage" => {},
        "judged_at" => Time.now.utc.iso8601
      }
    end

    private

    # 小さい方が良い指標。差が小さければ tie。
    def pick(a, b)
      return "tie" if (a - b).abs < 1e-9 || (a - b).abs / [a.abs, b.abs, 1e-9].max < 0.1

      a < b ? "a" : "b"
    end
  end
end
