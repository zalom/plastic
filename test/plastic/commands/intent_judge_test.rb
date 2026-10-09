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

  def test_a_call_writes_no_row_and_names_the_verdict_command
    result = judge

    assert_equal [0, []], [result.code, verdicts]
    assert_includes result.out, "plastic intent verdict 1 accept|revise TEXT"
  end

  def test_a_call_names_no_kind_of_judge
    out = judge.out.downcase

    %w[tests jev].each { |kind| refute_includes out, kind }
  end

  def test_an_option_exits_2
    assert_equal [2, []], [judge("--verdict", "accept").code, verdicts]
  end

  def test_a_call_after_two_verdicts_exits_3
    cli("intent", "verdict", "1", "revise", "one")
    cli("intent", "verdict", "1", "revise", "two")

    assert_equal 3, judge.code
  end

  def test_a_call_after_an_accept_says_accepted_and_offers_the_end
    cli("intent", "verdict", "1", "accept", "fine")
    result = judge

    assert_equal 0, result.code
    assert_includes result.out, "accepted"
    assert_match(/^next: plastic intent end 1/, result.out)
  end

  def test_an_accept_older_than_a_node_prints_the_judge_steps_again
    put_verdict(1, "accept", EARLY)
    set_node_times(LATE)
    result = judge

    assert_equal 0, result.code
    assert_includes result.out, "plastic intent verdict 1 accept|revise TEXT"
  end

  def test_a_revise_then_a_stale_accept_exits_3_with_the_round_used
    put_verdict(1, "revise", EARLY)
    put_verdict(2, "accept", MIDDLE)
    set_node_times(LATE)
    result = judge

    assert_equal 3, result.code
    assert_includes result.err, "the judge's review round of intent 1 is used"
    assert_includes result.err, "abandoning the intent"
  end

  def test_a_third_verdict_after_a_revise_and_a_stale_accept_exits_3_with_two_rows
    put_verdict(1, "revise", EARLY)
    put_verdict(2, "accept", MIDDLE)
    set_node_times(LATE)
    result = cli("intent", "verdict", "1", "accept", "again")

    assert_equal [3, 2], [result.code, verdicts.size]
  end

  def test_two_judge_calls_write_no_row
    judge
    judge

    assert_equal [], verdicts
  end
end

class IntentJudgeRefusalTest < Plastic::TestCase
  include LifecycleHelper

  def test_a_missing_intent_fails
    assert_equal 1, cli("intent", "judge", "9").code
  end

  %w[done abandoned].each do |status|
    define_method(:"test_a_#{status}_intent_fails") do
      open_intent(status:)

      assert_equal 1, cli("intent", "judge", "1").code
    end
  end
end
