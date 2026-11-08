# frozen_string_literal: true

require "anthropic"

module Jtr
  # ペア比較の採点器。
  # 同じペアを提示順を入れ替えて2回判定し、両方で一致した場合だけ勝敗を採用する(不一致は tie)。
  class Judge
    DEFAULT_MODEL = "claude-opus-5-5"
    MAX_ATTEMPTS = 5

    attr_reader :model

    def initialize(model: DEFAULT_MODEL, effort: :high, client: nil, logger: $stderr)
      @model = model
      @effort = effort
      @client = client || Anthropic::Client.new
      @logger = logger
    end

    # 返り値: { "task_id", "a", "b", "overall", "criteria" => {id => winner(a|b|tie)},
    #           "coverage" => {"a_missing"=>[], "b_missing"=>[]}, "runs" => [raw1, raw2], "judge_model", "judge_usage" }
    # winner は候補の提示位置ではなく system 名(a/b)に正規化して返す。
    def compare(task, a_name, text_a, b_name, text_b)
      run1 = call(task, text_a, text_b)             # A=a, B=b
      run2 = call(task, text_b, text_a)             # A=b, B=a (入れ替え)

      norm1 = normalize(run1[:parsed], swap: false)
      norm2 = normalize(run2[:parsed], swap: true)

      {
        "task_id" => task.id,
        "category" => task.category,
        "a" => a_name,
        "b" => b_name,
        "overall" => agree(norm1["overall"], norm2["overall"]),
        "position_consistent" => norm1["overall"] == norm2["overall"],
        "criteria" => Rubric.criterion_ids.to_h { |id| [id, agree(norm1["criteria"][id], norm2["criteria"][id])] },
        "coverage" => {
          "a_missing" => (norm1["coverage"]["a_missing"] | norm2["coverage"]["a_missing"]),
          "b_missing" => (norm1["coverage"]["b_missing"] | norm2["coverage"]["b_missing"])
        },
        "runs" => [run1[:parsed], run2[:parsed]],
        "judge_model" => run1[:model],
        "judge_usage" => sum_usage(run1[:usage], run2[:usage]),
        "judged_at" => Time.now.utc.iso8601
      }
    end

    private

    def call(task, text_a, text_b)
      attempt = 0
      begin
        attempt += 1
        message = @client.beta.messages.create(
          model: @model,
          max_tokens: 16_000,
          system_: [{ type: "text", text: Rubric.system_prompt, cache_control: { type: "ephemeral" } }],
          messages: [{ role: "user", content: Rubric.user_prompt(task, text_a, text_b) }],
          output_config: { effort: @effort, format: { type: :json_schema, schema: JudgeSchema.schema } },
          fallbacks: :default,
          betas: ["server-side-fallback-2026-07-01"]
        )
        handle(message)
      rescue Anthropic::Errors::RateLimitError, Anthropic::Errors::InternalServerError,
             Anthropic::Errors::APIConnectionError => e
        raise if attempt >= MAX_ATTEMPTS

        wait = 2**attempt + rand
        @logger.puts("[judge] #{e.class}: #{e.message} -> #{wait.round(1)}s 後に再試行 (#{attempt}/#{MAX_ATTEMPTS})")
        sleep(wait)
        retry
      end
    end

    def handle(message)
      case message.stop_reason
      when :refusal
        detail = message.stop_details&.category
        raise Error, "採点器が応答を拒否しました (category=#{detail.inspect})"
      when :max_tokens
        raise Error, "採点器の出力が max_tokens で打ち切られました"
      end

      text = message.content.select { |b| b.type == :text }.map(&:text).join
      parsed = JudgeSchema.validate!(JSON.parse(text))
      {
        parsed: parsed,
        model: message.model.to_s,
        usage: {
          "input_tokens" => message.usage.input_tokens,
          "output_tokens" => message.usage.output_tokens,
          "cache_read_input_tokens" => message.usage.cache_read_input_tokens,
          "cache_creation_input_tokens" => message.usage.cache_creation_input_tokens
        }
      }
    end

    # A/B を system a/b に写像する。swap=true のときは A が b 側。
    def normalize(parsed, swap:)
      map = swap ? { "A" => "b", "B" => "a", "tie" => "tie" } : { "A" => "a", "B" => "b", "tie" => "tie" }
      cov = parsed["coverage"]
      {
        "overall" => map.fetch(parsed["overall"]),
        "criteria" => parsed["criteria"].to_h { |c| [c["id"], map.fetch(c["winner"])] },
        "coverage" => swap ? { "a_missing" => cov["b_missing"], "b_missing" => cov["a_missing"] } : cov
      }
    end

    def agree(w1, w2) = w1 == w2 ? w1 : "tie"

    def sum_usage(u1, u2)
      u1.merge(u2) { |_, x, y| (x || 0) + (y || 0) }
    end
  end
end
