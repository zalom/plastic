# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkVerdictWriterTest < Plastic::TestCase
  include LifecycleHelper

  def setup
    super
    open_intent
    @graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
  end

  def writer = @graphs.work

  def verdict(kind) = writer.add_verdict(intent_id: "1", verdict: kind, findings: "checked", at: LATE)

  def test_the_first_verdict_is_round_1_with_the_session
    row = verdict("revise")

    assert_equal [1, "revise", "s-1"], [row.round, row.verdict, row.session_id]
  end

  def test_the_second_verdict_is_round_2
    verdict("revise")

    assert_equal 2, verdict("accept").round
  end

  def test_a_third_verdict_writes_nothing_and_answers_nil
    verdict("revise")
    verdict("revise")

    assert_nil verdict("accept")
    assert_equal 2, retrieval.verdicts("1").size
  end

  def test_rounds_are_left_until_two_verdicts_exist
    verdict("revise")

    assert writer.rounds_left?("1")
    verdict("revise")

    refute writer.rounds_left?("1")
  end
end
