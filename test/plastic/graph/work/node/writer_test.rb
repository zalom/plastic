# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkNodeWriterTest < Plastic::TestCase
  def setup
    super
    @work = store_graphs.work
    @work.write_intent(title: "Alpha")
  end

  def node(id) = retrieval.node("1", id)

  def add(title = "Build") = @work.add_node(intent_id: "1", title:, criterion: "it works")

  def test_a_new_node_gets_the_next_id_and_starts_open
    add
    added = add("Test")

    assert_equal ["n2", "open", 0], [added.id, added.state, added.retries]
  end

  def test_a_claim_moves_an_open_node_and_counts_the_try
    add
    state, claimed = @work.claim_node(intent_id: "1", id: "n1", by: "executor")

    assert_equal [:claimed, "claimed", "executor", 1], [state, claimed.state, claimed.by, claimed.retries]
  end

  def test_a_claim_of_a_missing_node_is_refused_with_no_node
    assert_equal [:refused, nil], @work.claim_node(intent_id: "1", id: "n9", by: "executor")
  end

  def test_a_claim_of_a_claimed_node_is_refused_with_the_node_as_it_stands
    add
    @work.claim_node(intent_id: "1", id: "n1", by: "a")
    state, current = @work.claim_node(intent_id: "1", id: "n1", by: "b")

    assert_equal [:refused, "a"], [state, current.by]
  end

  def test_a_claim_waits_while_a_needed_node_is_not_done
    add
    add("Test")
    @work.add_edge(intent_id: "1", from: "n1", to: "n2")

    assert_equal :blocked, @work.claim_node(intent_id: "1", id: "n2", by: "a").first
  end

  def test_a_fourth_claim_moves_the_node_to_needs_info_for_the_owner
    add
    3.times do
      @work.claim_node(intent_id: "1", id: "n1", by: "a")
      @work.release_node(intent_id: "1", id: "n1")
    end
    state, held = @work.claim_node(intent_id: "1", id: "n1", by: "a")

    assert_equal [:capped, "needs_info", "claimed 3 times; the owner decides"], [state, held.state, held.question]
  end

  def test_a_move_from_a_state_it_does_not_leave_writes_nothing
    add

    assert_nil @work.done_node(intent_id: "1", id: "n1", judge: "tests", findings: "ok")
    assert_equal "open", node("n1").state
  end

  def test_done_records_the_judge_and_findings
    add
    @work.claim_node(intent_id: "1", id: "n1", by: "a")
    done = @work.done_node(intent_id: "1", id: "n1", judge: "tests", findings: "green")

    assert_equal %w[done tests green], [done.state, done.judge, done.findings]
  end

  def test_a_resolution_reopens_a_needs_info_node_with_its_tries_reset
    add
    @work.claim_node(intent_id: "1", id: "n1", by: "a")
    @work.ask_node(intent_id: "1", id: "n1", question: "which?")
    answered = @work.resolve_node(intent_id: "1", id: "n1", answer: "this one")

    assert_equal ["open", 0, "this one"], [answered.state, answered.retries, answered.answer]
  end

  def test_only_an_open_node_can_be_removed
    add
    @work.claim_node(intent_id: "1", id: "n1", by: "a")

    assert_nil @work.remove_node(intent_id: "1", id: "n1")
  end
end
