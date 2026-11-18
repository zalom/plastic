# frozen_string_literal: true

require_relative "../../../test_helper"

class WorkNodeTest < Plastic::TestCase
  def node(id, state, **fields) = Plastic::Graph::Work::Node.from_h(intent_id: "1", id:, state:, **fields)

  def test_a_refusal_names_the_node_its_state_and_the_move
    assert_equal "node n1 is done; it cannot move to claimed", node("n1", "done").refusal("claimed")
  end

  def test_an_open_node_missing_from_the_ready_nodes_is_waiting
    assert node("n2", "open").waiting?([node("n1", "open")])
  end

  def test_an_open_node_among_the_ready_nodes_is_not_waiting
    refute node("n1", "open").waiting?([node("n1", "open")])
  end

  def test_a_node_that_is_not_open_is_never_waiting
    refute node("n1", "claimed").waiting?([])
  end

  def test_a_node_with_findings_and_no_judge_is_verified
    assert_predicate node("n1", "done", findings: "green"), :verified?
  end

  def test_a_node_with_blank_findings_is_not_verified
    refute_predicate node("n1", "done", findings: " "), :verified?
  end

  def run_at(node_id, started_at) = Struct.new(:node_id, :started_at).new(node_id, started_at)

  def test_an_open_node_is_open
    assert_predicate node("n1", "open"), :open?
  end

  def test_a_claimed_node_is_held_and_any_other_state_is_refused
    assert_equal [:held, :refused], [node("n1", "claimed").claim_rejection, node("n1", "done").claim_rejection]
  end

  def test_an_open_node_has_no_rejection_at_any_time
    assert_nil node("n1", "open").rejection_at(Time.utc(2026, 1, 1))
  end

  def test_a_claim_renewed_within_the_lapse_is_rejected_as_held
    now = Time.utc(2026, 1, 1, 12)

    assert_equal :held, node("n1", "claimed", seen_at: Plastic.timestamp(now)).rejection_at(now)
  end

  def test_a_lapsed_claim_has_no_rejection
    now = Time.utc(2026, 1, 1, 12)

    assert_nil node("n1", "claimed", seen_at: Plastic.timestamp(now - Plastic::Graph::Work::Node::LAPSE - 1)).rejection_at(now)
  end

  def test_a_claim_note_pairs_the_word_with_the_text_and_has_none_for_other_statuses
    open = node("n1", "open", title: "Build", question: "Which?")

    assert_equal [["claimed", "Build"], ["capped", "Which?"], nil], [open.claim_note(:claimed), open.claim_note(:capped), open.claim_note(:held)]
  end

  def test_the_claim_key_names_the_node_and_its_holder
    assert_equal({ intent_id: "1", id: "n1", holder: "s1" }, node("n1", "claimed", claimed_by: "s1").claim_key)
  end

  def test_runs_after_the_answer_are_the_own_runs_that_started_later
    runs = [run_at("n1", "2026-01-01T10:00:00Z"), run_at("n1", "2026-01-01T12:00:00Z"), run_at("n2", "2026-01-01T12:00:00Z")]

    assert_equal ["2026-01-01T12:00:00Z"], node("n1", "open", answered_at: "2026-01-01T11:00:00Z").runs_after_answer(runs).map(&:started_at)
  end

  def test_an_unanswered_node_counts_all_its_own_runs
    runs = [run_at("n1", "2026-01-01T10:00:00Z"), run_at("n2", "2026-01-01T12:00:00Z")]

    assert_equal 1, node("n1", "open").runs_after_answer(runs).size
  end

  def test_an_open_node_is_capped_at_the_cap_and_a_claimed_one_never
    runs = [run_at("n1", "a"), run_at("n1", "b")]

    assert_equal [true, false, false], [node("n1", "open").capped?(runs, 2), node("n1", "open").capped?(runs, 3), node("n1", "claimed").capped?(runs, 1)]
  end

  def test_the_judge_list_is_gone
    refute Plastic::Graph::Work::Node.const_defined?(:JUDGES)
  end
end
