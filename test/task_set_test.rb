# frozen_string_literal: true

require_relative "test_helper"

class TaskSetTest < Minitest::Test
  def test_bundled_tasks_load_and_are_well_formed
    set = Jtr::TaskSet.load
    assert_equal 105, set.size
    set.tasks.group_by(&:category).each { |cat, ts| assert_equal 15, ts.size, "#{cat} は15件のはず" }
    set.each do |t|
      assert_match(/\A[a-z_]+-\d{3}\z/, t.id)
      refute_empty t.must_cover, "#{t.id} に must_cover がありません"
      assert t.prompt.strip.size > 20
    end
    assert_equal 7, set.tasks.map(&:category).uniq.size
  end

  def test_generation_prompt_hides_must_cover
    t = Jtr::TaskSet.load.find("concept-001")
    assert_includes t.generation_prompt, "想定読者"
    assert_includes t.generation_prompt, "1200文字以内"
    t.must_cover.each { |m| refute_includes t.generation_prompt, m }
  end

  def test_filter
    set = Jtr::TaskSet.load
    assert_equal 15, set.filter(category: "review").size
    assert_equal 1, set.filter(ids: ["error-001"]).size
  end
end
