# frozen_string_literal: true

module Jtr
  # 採点器の structured outputs 用 JSON スキーマ。
  # 制約: 全オブジェクトに additionalProperties: false、数値/文字列長の制約は使わない。
  module JudgeSchema
    WINNER = { "type" => "string", "enum" => %w[A B tie] }.freeze

    def self.schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[criteria coverage overall overall_reason],
        "properties" => {
          "criteria" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "additionalProperties" => false,
              "required" => %w[id winner reason evidence_a evidence_b],
              "properties" => {
                "id" => { "type" => "string", "enum" => Rubric.criterion_ids },
                "winner" => WINNER,
                "reason" => { "type" => "string" },
                "evidence_a" => { "type" => "string" },
                "evidence_b" => { "type" => "string" }
              }
            }
          },
          "coverage" => {
            "type" => "object",
            "additionalProperties" => false,
            "required" => %w[a_missing b_missing],
            "properties" => {
              "a_missing" => { "type" => "array", "items" => { "type" => "string" } },
              "b_missing" => { "type" => "array", "items" => { "type" => "string" } }
            }
          },
          "overall" => WINNER,
          "overall_reason" => { "type" => "string" }
        }
      }
    end

    # スキーマは配列要素の網羅を強制できないので、観点が全部揃っているか後段で確認する。
    def self.validate!(parsed)
      ids = parsed.fetch("criteria").map { |c| c.fetch("id") }
      missing = Rubric.criterion_ids - ids
      raise Error, "採点結果に観点が不足しています: #{missing.inspect}" unless missing.empty?

      parsed
    end
  end
end
