# frozen_string_literal: true

require_relative "../../../test_helper"

class IntentGrantTest < Plastic::TestCase
  include LifecycleHelper

  def granted = work_rows("work_log").select { |row| row.fetch("kind") == "granted" }

  def verdicts = work_rows("verdicts")

  def grant(*args) = cli("intent", "grant", "1", *args)

  def used_up
    cli("intent", "verdict", "1", "revise", "one")
    cli("intent", "verdict", "1", "revise", "two")
  end

  def setup
    super
    specified
    delivered_nodes
  end

  def test_after_two_used_rounds_the_owner_grant_writes_one_work_log_line_with_the_reason
    used_up
    result = grant("Round two read stale records", "--owner")

    assert_equal 0, result.code
    assert_equal ["Granted by the owner: Round two read stale records"], granted.map { |row| row.fetch("text") }
  end

  def test_a_grant_without_owner_exits_2_with_no_line
    used_up
    result = grant("Round two read stale records")

    assert_equal [2, []], [result.code, granted]
    assert_includes result.err, "--owner"
  end

  def test_a_grant_with_rounds_left_exits_3_with_no_line
    cli("intent", "verdict", "1", "revise", "one")
    result = grant("Not needed yet", "--owner")

    assert_equal [3, []], [result.code, granted]
    assert_includes result.err, "still has a review round left"
  end

  def test_a_grant_on_a_missing_intent_exits_1_with_no_line
    result = cli("intent", "grant", "9", "Gone", "--owner")

    assert_equal [1, []], [result.code, granted]
  end

  def test_a_grant_without_a_reason_exits_2_with_no_line
    used_up

    assert_equal [2, []], [grant("--owner").code, granted]
  end

  def test_after_a_grant_a_third_verdict_is_written
    used_up
    grant("Round two read stale records", "--owner")
    result = cli("intent", "verdict", "1", "accept", "Every criterion holds")

    assert_equal [0, [1, 2, 3]], [result.code, verdicts.map { |row| row.fetch("round") }.sort]
  end

  def test_after_a_grant_the_judge_is_open_again
    used_up
    grant("Round two read stale records", "--owner")

    assert_equal 0, cli("intent", "judge", "1").code
  end

  def test_after_a_grant_a_fourth_verdict_is_refused_with_three_rows
    used_up
    grant("Round two read stale records", "--owner")
    cli("intent", "verdict", "1", "revise", "three")
    result = cli("intent", "verdict", "1", "accept", "four")

    assert_equal [3, 3], [result.code, verdicts.size]
  end

  def test_a_second_grant_while_the_extra_round_is_unused_exits_3_with_one_line
    used_up
    grant("Round two read stale records", "--owner")
    result = grant("Again", "--owner")

    assert_equal [3, 1], [result.code, granted.size]
  end

  def test_a_second_grant_after_the_extra_round_is_used_adds_one_more_round
    used_up
    grant("First", "--owner")
    cli("intent", "verdict", "1", "revise", "three")
    grant("Second", "--owner")
    result = cli("intent", "verdict", "1", "accept", "four")

    assert_equal [0, 2, 4], [result.code, granted.size, verdicts.size]
  end

  def close_with(status)
    store_graphs.databases.fetch(:store).transaction { |batch| batch.write(:intents, "UPDATE intents SET status = :status WHERE intent_id = '1'", status:) }
  end

  %w[done abandoned].each do |status|
    define_method(:"test_a_grant_on_a_#{status}_intent_with_its_rounds_used_exits_1_with_no_line") do
      used_up
      close_with(status)
      result = grant("Too late", "--owner")

      assert_equal [1, []], [result.code, granted]
    end
  end
end
