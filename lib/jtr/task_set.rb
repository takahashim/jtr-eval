# frozen_string_literal: true

module Jtr
  # 1件の評価タスク。tasks/*.yml から読み込む。
  Task = Struct.new(
    :id, :category, :audience, :prompt, :must_cover, :constraints, :tags, :source_file,
    keyword_init: true
  ) do
    # 評価対象モデルに渡す最終的な指示文。
    # 読者像と制約を prompt に添える。must_cover は採点器専用で、モデルには見せない。
    def generation_prompt
      parts = []
      parts << "【想定読者】#{audience}" if audience && !audience.empty?
      if constraints && constraints["max_chars"]
        parts << "【制約】#{constraints["max_chars"]}文字以内で日本語で書いてください。"
      end
      parts << prompt.strip
      parts.join("\n\n")
    end
  end

  class TaskSet
    REQUIRED = %w[id category prompt].freeze

    attr_reader :tasks

    def self.load(dir = File.join(ROOT, "tasks"))
      files = Dir.glob(File.join(dir, "*.yml")).sort
      raise Error, "タスク定義が見つかりません: #{dir}" if files.empty?

      tasks = files.flat_map do |file|
        data = YAML.safe_load_file(file, permitted_classes: [], aliases: true) || []
        raise Error, "#{file}: トップレベルは配列にしてください" unless data.is_a?(Array)

        data.map { |h| build(h, file) }
      end
      new(tasks)
    end

    def self.build(hash, file)
      missing = REQUIRED - hash.keys
      raise Error, "#{file}: 必須キーがありません #{missing.inspect} (#{hash["id"].inspect})" unless missing.empty?

      Task.new(
        id: hash["id"],
        category: hash["category"],
        audience: hash["audience"] || "日本語話者のITエンジニア",
        prompt: hash["prompt"],
        must_cover: Array(hash["must_cover"]),
        constraints: hash["constraints"] || {},
        tags: Array(hash["tags"]),
        source_file: file
      )
    end

    def initialize(tasks)
      ids = tasks.map(&:id)
      dup = ids.tally.select { |_, n| n > 1 }.keys
      raise Error, "タスクIDが重複しています: #{dup.inspect}" unless dup.empty?

      @tasks = tasks
    end

    def each(&block) = @tasks.each(&block)
    def size = @tasks.size
    def find(id) = @tasks.find { |t| t.id == id }
    def ids = @tasks.map(&:id)

    def filter(category: nil, tag: nil, ids: nil)
      sel = @tasks
      sel = sel.select { |t| t.category == category } if category
      sel = sel.select { |t| t.tags.include?(tag) } if tag
      sel = sel.select { |t| ids.include?(t.id) } if ids
      TaskSet.new(sel)
    end
  end
end
