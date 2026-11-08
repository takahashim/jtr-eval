# frozen_string_literal: true

module Jtr
  # outputs/<system>/<task_id>.json と verdicts/<a>__vs__<b>.jsonl の読み書き。
  module Store
    module_function

    def outputs_dir(root = ROOT) = File.join(root, "outputs")
    def verdicts_dir(root = ROOT) = File.join(root, "verdicts")

    def write_output(system, task_id, record, root: ROOT)
      dir = File.join(outputs_dir(root), system)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "#{task_id}.json"), JSON.pretty_generate(record))
    end

    def read_output(system, task_id, root: ROOT)
      path = File.join(outputs_dir(root), system, "#{task_id}.json")
      return nil unless File.exist?(path)

      JSON.parse(File.read(path))
    end

    def systems(root: ROOT)
      Dir.children(outputs_dir(root)).select { |d| File.directory?(File.join(outputs_dir(root), d)) }.sort
    rescue Errno::ENOENT
      []
    end

    def output_task_ids(system, root: ROOT)
      Dir.glob(File.join(outputs_dir(root), system, "*.json")).map { |f| File.basename(f, ".json") }.sort
    end

    def verdict_path(a, b, root: ROOT) = File.join(verdicts_dir(root), "#{a}__vs__#{b}.jsonl")

    def append_verdict(a, b, record, root: ROOT)
      FileUtils.mkdir_p(verdicts_dir(root))
      File.open(verdict_path(a, b, root: root), "a") { |f| f.puts(JSON.generate(record)) }
    end

    def read_verdicts(path)
      return [] unless File.exist?(path)

      File.readlines(path, chomp: true).reject(&:empty?).map { |l| JSON.parse(l) }
    end

    def all_verdicts(root: ROOT)
      Dir.glob(File.join(verdicts_dir(root), "*.jsonl")).sort.flat_map { |p| read_verdicts(p) }
    end
  end
end
