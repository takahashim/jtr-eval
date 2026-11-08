# frozen_string_literal: true

require_relative "test_helper"

class BradleyTerryTest < Minitest::Test
  def test_dominant_system_gets_highest_rating
    comps = Array.new(10) { |i| { "task_id" => "t#{i}", "a" => "x", "b" => "y", "overall" => "a" } } +
            Array.new(10) { |i| { "task_id" => "t#{i}", "a" => "y", "b" => "z", "overall" => "a" } }
    r = Jtr::BradleyTerry.fit(comps)
    assert r["x"] > r["y"]
    assert r["y"] > r["z"]
    assert_in_delta 1000.0, r.values.sum / 3, 1e-6
  end

  def test_all_ties_are_equal
    comps = Array.new(6) { |i| { "task_id" => "t#{i}", "a" => "x", "b" => "y", "overall" => "tie" } }
    r = Jtr::BradleyTerry.fit(comps)
    assert_in_delta r["x"], r["y"], 1e-6
  end

  def test_bootstrap_returns_interval_per_system
    comps = Array.new(8) { |i| { "task_id" => "t#{i}", "a" => "x", "b" => "y", "overall" => i.even? ? "a" : "tie" } }
    ci = Jtr::BradleyTerry.bootstrap(comps, samples: 50)
    assert_equal %w[x y], ci.keys.sort
    assert ci["x"]["lo"] <= ci["x"]["hi"]
  end
end
