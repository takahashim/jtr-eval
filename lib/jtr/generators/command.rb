# frozen_string_literal: true

require "open3"

module Jtr
  module Generators
    # 任意のコマンドで候補出力を生成する汎用アダプタ。
    # プロンプトを標準入力で渡し、標準出力を回答として記録する。
    # 例: bin/jtr generate --system my-service --command "python3 call_my_service.py"
    class Command
      def initialize(command, timeout: 300)
        @command = command
        @timeout = timeout
      end

      def generate(task)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        stdout, stderr, status = Open3.capture3(@command, stdin_data: task.generation_prompt)
        raise Error, "コマンドが失敗しました (#{status.exitstatus}): #{stderr.strip}" unless status.success?

        {
          "text" => stdout,
          "model" => @command,
          "stop_reason" => "ok",
          "usage" => nil,
          "latency_s" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
        }
      end
    end
  end
end
