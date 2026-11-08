# frozen_string_literal: true

module Jtr
  # Bradley-Terry モデルによるレーティング推定。
  # 入力: [[winner, loser], ...] の対戦結果。tie は双方に 0.5 勝ずつとして扱う。
  # 出力: system => rating (平均 1000、1 ロジット = 400 点のスケール)。
  module BradleyTerry
    module_function

    # comparisons: [{ "a" => name, "b" => name, "overall" => "a"|"b"|"tie" }]
    def fit(comparisons, iterations: 200, tol: 1e-6)
      systems = comparisons.flat_map { |c| [c["a"], c["b"]] }.uniq.sort
      return {} if systems.size < 2

      wins = Hash.new(0.0)      # [i, j] => i が j に勝った回数(tie は 0.5)
      games = Hash.new(0.0)     # [i, j] => 対戦回数
      comparisons.each do |c|
        a = c["a"]
        b = c["b"]
        games[[a, b]] += 1
        games[[b, a]] += 1
        case c["overall"]
        when "a" then wins[[a, b]] += 1
        when "b" then wins[[b, a]] += 1
        else
          wins[[a, b]] += 0.5
          wins[[b, a]] += 0.5
        end
      end

      # MM アルゴリズム (Hunter 2004)。全勝・全敗で発散しないよう、各ペアに 0.5 試合分の擬似対戦を足す。
      eps = 0.25
      systems.combination(2).each do |i, j|
        wins[[i, j]] += eps
        wins[[j, i]] += eps
        games[[i, j]] += 2 * eps
        games[[j, i]] += 2 * eps
      end

      p = systems.to_h { |s| [s, 1.0] }
      iterations.times do
        new_p = {}
        systems.each do |i|
          w = systems.sum { |j| j == i ? 0.0 : wins[[i, j]] }
          denom = systems.sum { |j| j == i ? 0.0 : games[[i, j]] / (p[i] + p[j]) }
          new_p[i] = denom.zero? ? p[i] : w / denom
        end
        geo = Math.exp(new_p.values.sum { |v| Math.log(v) } / systems.size)
        new_p.transform_values! { |v| v / geo }
        delta = systems.sum { |s| (new_p[s] - p[s]).abs }
        p = new_p
        break if delta < tol
      end

      p.transform_values { |v| 1000.0 + 400.0 * Math.log(v) }
    end

    # タスク単位のブートストラップで信頼区間を出す。
    def bootstrap(comparisons, samples: 500, seed: 42)
      rng = Random.new(seed)
      by_task = comparisons.group_by { |c| c["task_id"] }.values
      ratings = Hash.new { |h, k| h[k] = [] }
      samples.times do
        resampled = Array.new(by_task.size) { by_task[rng.rand(by_task.size)] }.flatten
        fit(resampled).each { |s, r| ratings[s] << r }
      end
      ratings.transform_values do |arr|
        sorted = arr.sort
        { "lo" => sorted[(sorted.size * 0.025).floor], "hi" => sorted[[(sorted.size * 0.975).floor, sorted.size - 1].min] }
      end
    end
  end
end
