# frozen_string_literal: true

require_relative "../../test_helper"

class IntentApproveTest < Plastic::TestCase
  include LifecycleHelper

  def test_approving_an_open_intent_writes_one_go_ahead_row
    open_intent

    result = cli("intent", "approve", "1")

    assert_equal [0, ""], [result.code, result.err]
    assert_equal ["1"], work_rows("approvals").map { |row| row.fetch("intent_id") }
  end

  def test_approving_twice_keeps_one_row_and_exits_0_both_times
    open_intent

    codes = [cli("intent", "approve", "1").code, cli("intent", "approve", "1").code]

    assert_equal [0, 0], codes
    assert_equal 1, work_rows("approvals").size
  end

  def test_the_go_ahead_row_names_the_session
    open_intent
    cli("intent", "approve", "1", session: "s-7")

    assert_equal "s-7", work_rows("approvals").first.fetch("session_id")
  end

  def test_a_missing_intent_fails_with_no_row
    result = cli("intent", "approve", "9")

    assert_equal 1, result.code
    assert_empty work_rows("approvals")
  end

  %w[done abandoned].each do |status|
    define_method(:"test_a_#{status}_intent_fails_with_no_row") do
      open_intent(status:)

      assert_equal 1, cli("intent", "approve", "1").code
      assert_empty work_rows("approvals")
    end
  end

  def test_the_go_ahead_prints_into_the_graph_file
    open_intent
    cli("intent", "approve", "1")

    graph = JSON.parse(File.read(store_path("store/1--alpha/graph.json")))

    assert_equal "1", graph.fetch("approval").fetch("intent_id")
  end
end

class IntentApproveCriterionTest < Plastic::TestCase
  include LifecycleHelper

  def test_an_intent_with_no_done_criterion_exits_1_with_no_row_and_offers_the_spec
    open_intent

    result = cli("intent", "approve", "1")

    assert_equal [1, []], [result.code, work_rows("approvals")]
    assert_match(/^next: plastic intent spec 1/, result.out)
    assert_includes result.err, "intent 1 names no done criterion"
  end

  def test_an_intent_with_a_done_criterion_is_approved_as_before
    specified

    result = cli("intent", "approve", "1")

    assert_equal [0, ["1"]], [result.code, work_rows("approvals").map { |row| row.fetch("intent_id") }]
  end
end
