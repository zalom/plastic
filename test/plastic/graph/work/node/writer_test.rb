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

    assert_equal ["n2", "open", 0], [added.id, added.state, retrieval.structure.runs("1").size]
  end

  def test_a_claim_moves_an_open_node_and_opens_a_run
    add
    state, claimed = @work.claim_node(intent_id: "1", id: "n1", by: "executor")

    assert_equal [:claimed, "claimed", "executor", [1]], [state, claimed.state, claimed.claimed_by, retrieval.structure.runs("1").map(&:number)]
  end

  def test_a_claim_of_a_missing_node_is_refused_with_no_node
    assert_equal [:refused, nil], @work.claim_node(intent_id: "1", id: "n9", by: "executor")
  end

  def test_a_claim_of_a_claimed_node_is_held_with_the_node_as_it_stands
    add
    @work.claim_node(intent_id: "1", id: "n1", by: "a")
    state, current = @work.claim_node(intent_id: "1", id: "n1", by: "b")

    assert_equal [:held, "a"], [state, current.claimed_by]
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

    assert_nil @work.done_node(intent_id: "1", id: "n1", findings: "ok")
    assert_equal "open", node("n1").state
  end

  def test_the_third_claim_still_claims_and_leaves_no_question
    add
    2.times do
      @work.claim_node(intent_id: "1", id: "n1", by: "a")
      @work.release_node(intent_id: "1", id: "n1")
    end
    state, claimed = @work.claim_node(intent_id: "1", id: "n1", by: "a")

    assert_equal [:claimed, 3, nil], [state, retrieval.structure.runs("1").size, claimed.question]
  end

  def test_the_question_of_a_capped_node_reads_back_from_the_rows
    add
    3.times do
      @work.claim_node(intent_id: "1", id: "n1", by: "a")
      @work.release_node(intent_id: "1", id: "n1")
    end
    @work.claim_node(intent_id: "1", id: "n1", by: "a")

    assert_equal "claimed 3 times; the owner decides", node("n1").question
  end

  def test_a_release_of_a_node_that_is_not_claimed_returns_no_row_and_changes_nothing
    add

    assert_nil @work.release_node(intent_id: "1", id: "n1")
    assert_equal ["open", 0], [node("n1").state, retrieval.structure.runs("1").size]
  end

  def test_done_records_the_findings
    add
    @work.claim_node(intent_id: "1", id: "n1", by: "a")
    done = @work.done_node(intent_id: "1", id: "n1", findings: "green")

    assert_equal %w[done green], [done.state, done.findings]
  end

  def test_a_resolution_reopens_a_needs_info_node_with_its_answer
    add
    @work.claim_node(intent_id: "1", id: "n1", by: "a")
    @work.ask_node(intent_id: "1", id: "n1", question: "which?")
    answered = @work.resolve_node(intent_id: "1", id: "n1", answer: "this one")

    assert_equal ["open", "this one"], [answered.state, answered.answer]
  end

  def test_only_an_open_node_can_be_removed
    add
    @work.claim_node(intent_id: "1", id: "n1", by: "a")

    assert_nil @work.remove_node(intent_id: "1", id: "n1")
  end
end

# A claim is renewed only by the agent that holds it, in an intent in agent delivery; in guided work a call that names
# no agent renews the claims of its session as before.
class WorkNodeWriterRenewTest < Plastic::TestCase
  Clock = Struct.new(:now)

  START = Time.utc(2026, 11, 24, 9, 0, 0)
  CLAIMED = "2026-11-24T09:00:00Z"
  RENEWED = "2026-11-24T09:10:00Z"

  def work = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1", clock: @clock).work

  def delivery(mode)
    @clock = Clock.new(START)
    work.write_intent(title: "Alpha")
    work.activate_intent("1")
    work.drive_intent(intent_id: "1", by: "s-1", mode:)
    work.add_node(intent_id: "1", title: "Build", criterion: "it works")
    work.claim_node(intent_id: "1", id: "n1", by: "s-1", agent: "tester")
    @clock.now = START + 600
  end

  def seen_at = retrieval.node("1", "n1").seen_at

  def test_in_agent_delivery_the_agent_that_holds_the_claim_renews_it
    delivery("auto")
    work.renew_claims("s-1", agent: "tester")

    assert_equal RENEWED, seen_at
  end

  def test_in_agent_delivery_a_call_that_names_no_agent_leaves_the_claim_of_a_helper
    delivery("auto")
    work.renew_claims("s-1")

    assert_equal CLAIMED, seen_at
  end

  def test_in_agent_delivery_another_agent_of_the_session_leaves_the_claim
    delivery("auto")
    work.renew_claims("s-1", agent: "other")

    assert_equal CLAIMED, seen_at
  end

  def test_in_guided_work_a_call_that_names_no_agent_renews_the_claims_of_its_session
    delivery("guided")
    work.renew_claims("s-1")

    assert_equal RENEWED, seen_at
  end

  def test_in_guided_work_another_named_agent_leaves_the_claim
    delivery("guided")
    work.renew_claims("s-1", agent: "other")

    assert_equal CLAIMED, seen_at
  end

  def test_a_renewal_of_one_node_renews_that_node_alone
    delivery("auto")
    work.add_node(intent_id: "1", title: "Test", criterion: "it works")
    work.claim_node(intent_id: "1", id: "n2", by: "s-1", agent: "tester")
    work.renew_node(intent_id: "1", id: "n1", by: "s-1")

    assert_equal [RENEWED, "2026-11-24T09:10:00Z"], [seen_at, retrieval.node("1", "n2").seen_at]
  end

  def test_a_renewal_of_one_node_held_by_another_session_changes_nothing
    delivery("auto")
    work.renew_node(intent_id: "1", id: "n1", by: "s-2")

    assert_equal CLAIMED, seen_at
  end
end
