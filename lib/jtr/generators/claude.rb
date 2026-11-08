# frozen_string_literal: true

require "anthropic"

module Jtr
  module Generators
    # Claude モデルを評価対象として候補出力を生成する。
    class Claude
      SYSTEM = "あなたは日本語で技術文書を書くアシスタントです。指示に従って回答してください。"

      def initialize(model:, client: nil, effort: nil, max_tokens: 8_000)
        @model = model
        @client = client || Anthropic::Client.new
        @effort = effort
        @max_tokens = max_tokens
      end

      def generate(task)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        params = {
          model: @model,
          max_tokens: @max_tokens,
          system_: [{ type: "text", text: SYSTEM }],
          messages: [{ role: "user", content: task.generation_prompt }],
          fallbacks: :default,
          betas: ["server-side-fallback-2026-07-01"]
        }
        params[:output_config] = { effort: @effort } if @effort
        message = @client.beta.messages.create(**params)

        text = message.content.select { |b| b.type == :text }.map(&:text).join
        {
          "text" => text,
          "model" => message.model.to_s,
          "stop_reason" => message.stop_reason.to_s,
          "usage" => {
            "input_tokens" => message.usage.input_tokens,
            "output_tokens" => message.usage.output_tokens
          },
          "latency_s" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
        }
      end
    end
  end
end
