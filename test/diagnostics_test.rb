# frozen_string_literal: true

require_relative "test_helper"

class DiagnosticsTest < Minitest::Test
  def test_sentence_metrics_exclude_code_blocks
    text = <<~T
      これは短い文です。これは、読点が、多い、文です。

      ```ruby
      puts "コードブロックの中。文として数えない。"
      ```
    T
    d = Jtr::Diagnostics.analyze(text)
    assert_equal 2, d.sentences
    assert_equal 3, d.max_commas
    assert_equal 1, d.code_blocks
  end

  def test_style_mix_detection
    mixed = "この処理は重要です。したがって注意が必要である。"
    assert Jtr::Diagnostics.analyze(mixed).style_mix
    refute Jtr::Diagnostics.analyze("この処理は重要です。注意してください。").style_mix
  end

  def test_redundant_and_boilerplate
    text = "はい、説明します。\n\n設定を変更することができます。\n\n以上が説明です。ご不明な点があればお知らせください。"
    d = Jtr::Diagnostics.analyze(text)
    assert d.preamble
    assert d.boilerplate_closing
    assert_equal 1, d.redundant["することができ"]
  end

  def test_bullet_ratio
    text = "- 一つ目\n- 二つ目\n本文です。"
    d = Jtr::Diagnostics.analyze(text)
    assert_equal 2, d.bullet_lines
    assert_in_delta 0.667, d.bullet_ratio, 0.01
  end
end
