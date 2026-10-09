# frozen_string_literal: true

require_relative "../../test_helper"

class IntentJudgeTest < Plastic::TestCase
  include LifecycleHelper

  def verdicts = work_rows("verdicts").sort_by { |row| row.fetch("round") }

  def judge(*args) = cli("intent", "judge", "1", *args)

  def setup
    super
    specified
    delivered_nodes
  end

  def test_a_bare_call_writes_no_row_and_names_the_two_verdicts
    result = judge

    assert_equal [0, []], [result.code, verdicts]
    assert_includes result.out, "--verdict accept|revise"
  end

  def test_a_bare_call_names_no_kind_of_judge
    out = judge.out.downcase

    %w[tests jev].each { |kind| refute_includes out, kind }
  end

  def test_an_unknown_verdict_exits_2_with_no_row
    assert_equal [2, []], [judge("--verdict", "maybe", "--findings", "x").code, verdicts]
  end

  def test_a_verdict_without_findings_exits_2_with_no_row
    assert_equal [2, []], [judge("--verdict", "accept").code, verdicts]
  end

  def test_findings_without_a_verdict_exit_2_with_no_row
    assert_equal [2, []], [judge("--findings", "x").code, verdicts]
  end

  def test_an_accept_writes_round_1
    result = judge("--verdict", "accept", "--findings", "Every criterion holds")

    assert_equal 0, result.code
    assert_equal [[1, "accept", "Every criterion holds"]], verdicts.map { |row| row.values_at("round", "verdict", "findings") }
  end

  def test_a_revise_names_the_fix_node_command
    result = judge("--verdict", "revise", "--findings", "The edge case fails")

    assert_equal 0, result.code
    assert_match(/^next: plastic node add 1/, result.out)
  end

  def test_a_second_revise_is_written_and_refused_with_exit_3
    judge("--verdict", "revise", "--findings", "one")
    result = judge("--verdict", "revise", "--findings", "two")

    assert_equal 3, result.code
    assert_equal [1, 2], verdicts.map { |row| row.fetch("round") }
    assert_includes result.err + result.out, "review round"
  end

  def test_a_third_verdict_is_refused_with_two_rows
    judge("--verdict", "revise", "--findings", "one")
    judge("--verdict", "revise", "--findings", "two")
    result = judge("--verdict", "accept", "--findings", "three")

    assert_equal [3, 2], [result.code, verdicts.size]
  end

  def test_a_bare_call_after_two_verdicts_exits_3
    judge("--verdict", "revise", "--findings", "one")
    judge("--verdict", "revise", "--findings", "two")

    assert_equal 3, judge.code
  end

  def test_a_bare_call_after_an_accept_says_accepted_and_offers_the_end
    judge("--verdict", "accept", "--findings", "fine")
    result = judge

    assert_equal 0, result.code
    assert_includes result.out, "accepted"
    assert_match(/^next: plastic intent end 1/, result.out)
  end

  def test_a_bare_call_then_a_verdict_call_writes_the_row
    judge
    judge("--verdict", "accept", "--findings", "fine")

    assert_equal 1, verdicts.size
  end

  def test_a_verdict_row_keeps_the_session
    judge("--verdict", "accept", "--findings", "fine")

    assert_equal "delivery", verdicts.first.fetch("session_id")
  end

  def test_the_verdicts_print_into_the_graph_file
    judge("--verdict", "accept", "--findings", "fine")

    graph = JSON.parse(File.read(store_path("store/1--alpha/graph.json")))

    assert_equal ["accept"], graph.fetch("verdicts").map { |row| row.fetch("verdict") }
  end
end

class IntentJudgeRefusalTest < Plastic::TestCase
  include LifecycleHelper

  def test_a_missing_intent_fails_with_no_row
    result = cli("intent", "judge", "9", "--verdict", "accept", "--findings", "x")

    assert_equal [1, []], [result.code, work_rows("verdicts")]
  end

  %w[done abandoned].each do |status|
    define_method(:"test_a_#{status}_intent_fails_with_no_row") do
      open_intent(status:)
      result = cli("intent", "judge", "1", "--verdict", "accept", "--findings", "x")

      assert_equal [1, []], [result.code, work_rows("verdicts")]
    end
  end
end
