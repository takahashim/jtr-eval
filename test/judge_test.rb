# frozen_string_literal: true

require_relative "test_helper"

# API を呼ばずに Judge の正規化ロジックを確認する。client に偽物を渡す。
class JudgeTest < Minitest::Test
  FakeUsage = Struct.new(:input_tokens, :output_tokens, :cache_read_input_tokens, :cache_creation_input_tokens)
  FakeBlock = Struct.new(:type, :text)
  FakeMessage = Struct.new(:stop_reason, :stop_details, :content, :model, :usage)

  class FakeMessages
    attr_reader :calls

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    def create(**params)
      @calls << params
      body = @responses.shift
      FakeMessage.new(:end_turn, nil, [FakeBlock.new(:text, JSON.generate(body))], "claude-opus-5-5", FakeUsage.new(100, 50, 0, 0))
    end
  end

  FakeClient = Struct.new(:beta) do
    def self.with(messages) = new(Struct.new(:messages).new(messages))
  end

  # y_slot: 2回目の呼び出しでは y が A 側に来るので、欠落の報告位置も入れ替わる。
  def judgment(overall, winner, y_slot: "b")
    cov = y_slot == "b" ? { "a_missing" => [], "b_missing" => ["要点X"] } : { "a_missing" => ["要点X"], "b_missing" => [] }
    {
      "criteria" => Jtr::Rubric.criterion_ids.map { |id| { "id" => id, "winner" => winner, "reason" => "r", "evidence_a" => "", "evidence_b" => "" } },
      "coverage" => cov,
      "overall" => overall,
      "overall_reason" => "r"
    }
  end

  def task
    Jtr::Task.new(id: "t1", category: "concept", audience: "eng", prompt: "p", must_cover: ["要点X"], constraints: {}, tags: [])
  end

  def test_consistent_verdict_maps_positions_back_to_systems
    # 1回目: A=x が勝ち。2回目(入れ替え): B=x が勝ち。どちらも x の勝ち。
    fake = FakeMessages.new([judgment("A", "A"), judgment("B", "B", y_slot: "a")])
    judge = Jtr::Judge.new(client: FakeClient.with(fake))
    v = judge.compare(task, "x", "text-x", "y", "text-y")

    assert_equal "a", v["overall"]
    assert v["position_consistent"]
    assert_equal "a", v["criteria"]["clarity"]
    # 1回目は b(y) が要点X を欠き、2回目は入れ替わって a 側 (= y) が欠く。y に正規化される。
    assert_equal [], v["coverage"]["a_missing"]
    assert_equal ["要点X"], v["coverage"]["b_missing"]
    assert_equal 2, fake.calls.size
    assert_equal :default, fake.calls.first[:fallbacks]
    assert_equal :json_schema, fake.calls.first.dig(:output_config, :format, :type)
  end

  def test_position_bias_becomes_tie
    # どちらの提示順でも「A が勝ち」と言う採点器 = 位置バイアス。tie に落とす。
    fake = FakeMessages.new([judgment("A", "A"), judgment("A", "A", y_slot: "a")])
    v = Jtr::Judge.new(client: FakeClient.with(fake)).compare(task, "x", "tx", "y", "ty")

    assert_equal "tie", v["overall"]
    refute v["position_consistent"]
    assert_equal "tie", v["criteria"]["comprehension"]
  end

  def test_refusal_raises
    refusing = Class.new do
      def create(**) = FakeMessage.new(:refusal, Struct.new(:category).new(:general_harms), [], "m", FakeUsage.new(0, 0, 0, 0))
    end.new
    err = assert_raises(Jtr::Error) { Jtr::Judge.new(client: FakeClient.with(refusing)).compare(task, "x", "a", "y", "b") }
    assert_match(/拒否/, err.message)
  end
end
