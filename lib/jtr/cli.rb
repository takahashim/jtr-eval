# frozen_string_literal: true

require "optparse"

module Jtr
  class CLI
    USAGE = <<~USAGE
      使い方: bin/jtr <command> [options]

        tasks                         タスク一覧を表示
        generate --system NAME (--command CMD | --model MODEL) [--category C] [--ids a,b]
                                      評価対象の出力を outputs/NAME/ に保存
        judge --a NAME --b NAME [--judge-model M] [--stub] [--category C]
                                      2システムをペア比較し verdicts/ に追記 (既存タスクはスキップ)
        judge-all [--judge-model M] [--stub]
                                      outputs/ にある全システムの総当たり
        report [--out FILE]           verdicts/ を集計して Markdown を出力
        lint [--system NAME]          outputs/ の診断指標を表示
        selftest                      examples/ を使ってAPIなしで一通り動かす

      共通オプション: --root DIR (outputs/ と verdicts/ の置き場所を変える)
    USAGE

    def self.run(argv)
      new.run(argv)
    rescue Error, OptionParser::ParseError => e
      warn "エラー: #{e.message}"
      1
    end

    def run(argv)
      cmd = argv.shift
      case cmd
      when "tasks" then tasks(argv)
      when "generate" then generate(argv)
      when "judge" then judge(argv)
      when "judge-all" then judge_all(argv)
      when "report" then report(argv)
      when "lint" then lint(argv)
      when "selftest" then selftest
      else
        puts USAGE
        cmd.nil? ? 0 : 1
      end
    end

    private

    def tasks(argv)
      opts = parse(argv)
      set = select_tasks(opts)
      puts "ID | カテゴリ | タグ | 要点数"
      set.each { |t| puts "#{t.id} | #{t.category} | #{t.tags.join(",")} | #{t.must_cover.size}" }
      puts "合計 #{set.size} 件"
      0
    end

    def generate(argv)
      opts = parse(argv)
      raise Error, "--system を指定してください" unless opts[:system]

      generator =
        if opts[:command] then Generators::Command.new(opts[:command])
        elsif opts[:model] then Generators::Claude.new(model: opts[:model], effort: opts[:effort])
        else raise Error, "--command か --model のどちらかを指定してください"
        end

      set = select_tasks(opts)
      done = Store.output_task_ids(opts[:system], root: root)
      set.each do |task|
        if done.include?(task.id) && !opts[:force]
          puts "skip #{task.id} (既存)"
          next
        end
        result = generator.generate(task)
        Store.write_output(opts[:system], task.id, result.merge(
          "task_id" => task.id, "system" => opts[:system], "generated_at" => Time.now.utc.iso8601
        ), root: root)
        puts "ok   #{task.id} (#{result["text"].size}文字)"
      end
      0
    end

    def judge(argv)
      opts = parse(argv)
      raise Error, "--a と --b を指定してください" unless opts[:a] && opts[:b]

      run_pair(opts[:a], opts[:b], build_judge(opts), select_tasks(opts))
      0
    end

    def judge_all(argv)
      opts = parse(argv)
      systems = Store.systems(root: root)
      raise Error, "outputs/ に2つ以上のシステムが必要です" if systems.size < 2

      judge = build_judge(opts)
      set = select_tasks(opts)
      systems.combination(2).each { |a, b| run_pair(a, b, judge, set) }
      0
    end

    def report(argv)
      opts = parse(argv)
      md = Report.new(Store.all_verdicts(root: root)).to_markdown
      if opts[:out]
        FileUtils.mkdir_p(File.dirname(opts[:out]))
        File.write(opts[:out], md)
        puts "wrote #{opts[:out]}"
      else
        puts md
      end
      0
    end

    def lint(argv)
      opts = parse(argv)
      systems = opts[:system] ? [opts[:system]] : Store.systems(root: root)
      keys = %i[chars_prose sentences mean_sentence_len max_sentence_len max_commas kanji_ratio katakana_ratio
                latin_ratio style_mix bullet_ratio punct_mixed preamble boilerplate_closing]
      puts(["system", "task_id", *keys, "redundant"].join("\t"))
      systems.each do |sys|
        Store.output_task_ids(sys, root: root).each do |tid|
          d = Diagnostics.analyze(Store.read_output(sys, tid, root: root)["text"]).to_h
          puts([sys, tid, *keys.map { |k| d[k] }, d[:redundant].to_json].join("\t"))
        end
      end
      0
    end

    def selftest
      @root = File.join(ROOT, "examples")
      systems = Store.systems(root: root)
      covered = systems.map { |s| Store.output_task_ids(s, root: root) }.reduce(:&)
      set = TaskSet.load.filter(ids: covered)
      FileUtils.rm_rf(Store.verdicts_dir(root))
      judge = StubJudge.new
      systems.combination(2).each { |a, b| run_pair(a, b, judge, set) }
      puts
      puts Report.new(Store.all_verdicts(root: root)).to_markdown(bootstrap_samples: 100)
      0
    end

    def run_pair(a, b, judge, set)
      done = Store.read_verdicts(Store.verdict_path(a, b, root: root)).map { |v| v["task_id"] }
      set.each do |task|
        next if done.include?(task.id)

        oa = Store.read_output(a, task.id, root: root)
        ob = Store.read_output(b, task.id, root: root)
        unless oa && ob
          puts "skip #{task.id}: #{a}=#{oa ? "有" : "無"} #{b}=#{ob ? "有" : "無"}"
          next
        end
        verdict = judge.compare(task, a, oa["text"], b, ob["text"])
        Store.append_verdict(a, b, verdict, root: root)
        puts "#{a} vs #{b} #{task.id}: #{verdict["overall"]}#{verdict["position_consistent"] ? "" : " (順序不一致→tie)"}"
      end
    end

    def build_judge(opts)
      return StubJudge.new if opts[:stub]

      Judge.new(model: opts[:judge_model] || Judge::DEFAULT_MODEL, effort: opts[:effort] || :high)
    end

    def select_tasks(opts)
      set = TaskSet.load
      set.filter(category: opts[:category], tag: opts[:tag], ids: opts[:ids])
    end

    def root = @root || ROOT

    def parse(argv)
      opts = {}
      OptionParser.new do |o|
        o.on("--root DIR", "outputs/ と verdicts/ の親ディレクトリ (既定: プロジェクト直下)") { |v| @root = File.expand_path(v) }
        o.on("--system NAME") { |v| opts[:system] = v }
        o.on("--command CMD") { |v| opts[:command] = v }
        o.on("--model MODEL") { |v| opts[:model] = v }
        o.on("--effort LEVEL") { |v| opts[:effort] = v.to_sym }
        o.on("--a NAME") { |v| opts[:a] = v }
        o.on("--b NAME") { |v| opts[:b] = v }
        o.on("--judge-model MODEL") { |v| opts[:judge_model] = v }
        o.on("--stub") { opts[:stub] = true }
        o.on("--force") { opts[:force] = true }
        o.on("--category C") { |v| opts[:category] = v }
        o.on("--tag T") { |v| opts[:tag] = v }
        o.on("--ids LIST") { |v| opts[:ids] = v.split(",") }
        o.on("--out FILE") { |v| opts[:out] = v }
      end.parse!(argv)
      opts
    end
  end
end
