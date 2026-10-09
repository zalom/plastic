# frozen_string_literal: true

require_relative "../../test_helper"

class IntentVerdictTest < Plastic::TestCase
  include LifecycleHelper

  def verdicts = work_rows("verdicts").sort_by { |row| row.fetch("round") }

  def verdict(*args) = cli("intent", "verdict", "1", *args)

  def setup
    super
    specified
    delivered_nodes
  end

  def test_an_unknown_verdict_exits_2_with_no_row
    assert_equal [2, []], [verdict("maybe", "x").code, verdicts]
  end

  def test_a_verdict_without_findings_exits_2_with_no_row
    assert_equal [2, []], [verdict("accept").code, verdicts]
  end

  def test_blank_findings_exit_2_with_no_row
    assert_equal [2, []], [verdict("accept", "  ").code, verdicts]
  end

  def test_an_accept_writes_round_1
    result = verdict("accept", "Every criterion holds")

    assert_equal 0, result.code
    assert_equal [[1, "accept", "Every criterion holds"]], verdicts.map { |row| row.values_at("round", "verdict", "findings") }
  end

  def test_an_accept_offers_the_end
    assert_match(/^next: plastic intent end 1/, verdict("accept", "fine").out)
  end

  def test_a_revise_names_the_fix_node_command
    result = verdict("revise", "The edge case fails")

    assert_equal 0, result.code
    assert_match(/^next: plastic node add 1/, result.out)
  end

  def test_a_second_revise_is_written_and_refused_with_exit_3
    verdict("revise", "one")
    result = verdict("revise", "two")

    assert_equal 3, result.code
    assert_equal [1, 2], verdicts.map { |row| row.fetch("round") }
    assert_includes result.err + result.out, "review round"
  end

  def test_a_third_verdict_is_refused_with_two_rows
    verdict("revise", "one")
    verdict("revise", "two")
    result = verdict("accept", "three")

    assert_equal [3, 2], [result.code, verdicts.size]
  end

  def test_a_judge_call_then_a_verdict_call_writes_the_row
    cli("intent", "judge", "1")
    verdict("accept", "fine")

    assert_equal 1, verdicts.size
  end

  def test_a_verdict_row_keeps_the_session
    verdict("accept", "fine")

    assert_equal "delivery", verdicts.first.fetch("session_id")
  end

  def test_the_verdicts_print_into_the_graph_file
    verdict("accept", "fine")

    graph = JSON.parse(File.read(store_path("store/1--alpha/graph.json")))

    assert_equal ["accept"], graph.fetch("verdicts").map { |row| row.fetch("verdict") }
  end
end

class IntentVerdictRefusalTest < Plastic::TestCase
  include LifecycleHelper

  def test_a_missing_intent_fails_with_no_row
    result = cli("intent", "verdict", "9", "accept", "x")

    assert_equal [1, []], [result.code, work_rows("verdicts")]
  end

  %w[done abandoned].each do |status|
    define_method(:"test_a_#{status}_intent_fails_with_no_row") do
      open_intent(status:)
      result = cli("intent", "verdict", "1", "accept", "x")

      assert_equal [1, []], [result.code, work_rows("verdicts")]
    end
  end
end
