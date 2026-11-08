# frozen_string_literal: true

module Jtr
  # verdicts/*.jsonl を集計して Markdown レポートを作る。
  class Report
    def initialize(verdicts)
      @verdicts = verdicts
    end

    def to_markdown(bootstrap_samples: 500)
      return "判定結果がありません。" if @verdicts.empty?

      ratings = BradleyTerry.fit(@verdicts)
      ci = BradleyTerry.bootstrap(@verdicts, samples: bootstrap_samples)
      systems = ratings.keys.sort_by { |s| -ratings[s] }

      out = []
      out << "# 読みやすさ評価レポート"
      out << ""
      out << "判定数: #{@verdicts.size} / タスク数: #{@verdicts.map { |v| v["task_id"] }.uniq.size} / 採点モデル: #{@verdicts.map { |v| v["judge_model"] }.uniq.join(", ")}"
      out << ""
      out << "## 総合レーティング (Bradley-Terry、平均1000)"
      out << ""
      out << "| 順位 | システム | レーティング | 95%区間 | 勝 | 分 | 敗 |"
      out << "|---:|---|---:|---|---:|---:|---:|"
      systems.each_with_index do |s, i|
        w, t, l = record(s)
        band = ci[s] ? "#{ci[s]["lo"].round} – #{ci[s]["hi"].round}" : "-"
        out << "| #{i + 1} | #{s} | #{ratings[s].round} | #{band} | #{w} | #{t} | #{l} |"
      end
      out << ""
      out << "## 観点別の勝率 (tie を 0.5 として集計)"
      out << ""
      out << "| システム | " + Rubric.criteria.map(&:name).join(" | ") + " |"
      out << "|---|" + Rubric.criteria.map { "---:" }.join("|") + "|"
      systems.each do |s|
        cells = Rubric.criterion_ids.map { |id| format("%.2f", criterion_rate(s, id)) }
        out << "| #{s} | #{cells.join(" | ")} |"
      end
      out << ""
      out << "## 情報網羅性 (要点の欠落数 / 判定数)"
      out << ""
      out << "| システム | 欠落合計 | 1判定あたり |"
      out << "|---|---:|---:|"
      systems.each do |s|
        miss, n = coverage(s)
        out << "| #{s} | #{miss} | #{n.zero? ? "-" : format("%.2f", miss.fdiv(n))} |"
      end
      out << ""
      consistent = @verdicts.count { |v| v["position_consistent"] }
      out << "## 採点の安定性"
      out << ""
      out << "提示順を入れ替えても総合判定が一致した割合: #{format("%.1f%%", 100.0 * consistent / @verdicts.size)}"
      out << ""
      out << "## カテゴリ別の総合判定"
      out << ""
      out << "| カテゴリ | 判定数 | " + systems.map { |s| "#{s} 勝率" }.join(" | ") + " |"
      out << "|---|---:|" + systems.map { "---:" }.join("|") + "|"
      @verdicts.group_by { |v| v["category"] }.sort.each do |cat, vs|
        cells = systems.map { |s| format("%.2f", overall_rate(s, vs)) }
        out << "| #{cat} | #{vs.size} | #{cells.join(" | ")} |"
      end
      out.join("\n")
    end

    private

    def record(system)
      w = t = l = 0
      @verdicts.each do |v|
        side = side_of(system, v) or next
        case v["overall"]
        when "tie" then t += 1
        when side then w += 1
        else l += 1
        end
      end
      [w, t, l]
    end

    def side_of(system, verdict)
      return "a" if verdict["a"] == system
      return "b" if verdict["b"] == system

      nil
    end

    def criterion_rate(system, id)
      score = n = 0.0
      @verdicts.each do |v|
        side = side_of(system, v) or next
        n += 1
        w = v["criteria"][id]
        score += w == "tie" ? 0.5 : (w == side ? 1.0 : 0.0)
      end
      n.zero? ? 0.0 : score / n
    end

    def overall_rate(system, verdicts)
      score = n = 0.0
      verdicts.each do |v|
        side = side_of(system, v) or next
        n += 1
        score += v["overall"] == "tie" ? 0.5 : (v["overall"] == side ? 1.0 : 0.0)
      end
      n.zero? ? 0.0 : score / n
    end

    def coverage(system)
      miss = n = 0
      @verdicts.each do |v|
        side = side_of(system, v) or next
        n += 1
        miss += v["coverage"]["#{side}_missing"].size
      end
      [miss, n]
    end
  end
end
