# frozen_string_literal: true

require_relative "../../../../test_helper"

# Every claim of a node is one row of runs; a claim lapses after 15 minutes without a renewal.
class WorkNodeRunCase < Plastic::TestCase
  Clock = Struct.new(:now)

  START = Time.utc(2026, 11, 17, 8, 0, 0)

  def setup
    super
    @clock = Clock.new(START)
    store_graphs.work.write_intent(title: "Alpha")
    store_graphs.work.activate_intent("1")
    graphs("s-1").work.add_node(intent_id: "1", title: "Build", criterion: "it works")
  end

  def graphs(session) = Plastic::Graph.open(home: @plastic_home, store: "global", session:, clock: @clock)

  def work(session = "s-1") = graphs(session).work

  def at(minutes) = @clock.now = START + (minutes * 60)

  def claim(session = "s-1") = work(session).claim_node(intent_id: "1", id: "n1", by: session)

  def runs = retrieval.structure.runs("1").select { |run| run.node_id == "n1" }
end

class WorkNodeRunTest < WorkNodeRunCase
  def test_a_claim_opens_a_run_of_the_session
    claim

    assert_equal [[1, "s-1", "2026-11-17T08:00:00Z", nil, nil]], runs.map { |run| run.to_h.values_at(:number, :session_id, :started_at, :ended_at, :result) }
  end

  def test_a_claim_sets_the_holder_and_its_times
    claim

    assert_equal ["s-1", "2026-11-17T08:00:00Z", "2026-11-17T08:00:00Z"], retrieval.node("1", "n1").to_h.values_at(:claimed_by, :claimed_at, :seen_at)
  end

  def test_a_finished_run_holds_the_agent_the_session_the_times_and_the_result
    work.claim_node(intent_id: "1", id: "n1", by: "s-1", agent: "plastic-executor")
    at(5)
    work.done_node(intent_id: "1", id: "n1", by: "s-1", findings: "checked")

    assert_equal ["plastic-executor", "s-1", "2026-11-17T08:00:00Z", "2026-11-17T08:05:00Z", "done"],
      runs.first.to_h.values_at(:agent, :session_id, :started_at, :ended_at, :result)
  end

  def test_a_finished_node_holds_no_claim
    claim
    work.done_node(intent_id: "1", id: "n1", by: "s-1", findings: "checked")

    assert_equal [nil, nil, nil], retrieval.node("1", "n1").to_h.values_at(:claimed_by, :claimed_at, :seen_at)
  end

  def test_a_release_closes_the_run_as_released
    claim
    work.release_node(intent_id: "1", id: "n1", by: "s-1")

    assert_equal ["released"], runs.map(&:result)
  end

  def test_each_other_move_closes_the_run_with_its_state
    claim
    work.ask_node(intent_id: "1", id: "n1", by: "s-1", question: "which way?")

    assert_equal ["needs_info"], runs.map(&:result)
  end

  def test_three_runs_reach_the_cap_and_the_fourth_claim_asks_the_owner
    3.times do
      claim
      work.release_node(intent_id: "1", id: "n1", by: "s-1")
    end
    state, node = claim

    assert_equal [:capped, "needs_info", 3], [state, node.state, runs.size]
  end

  def test_a_claim_renewed_16_minutes_ago_is_taken_and_its_run_is_closed_as_lapsed
    claim("s-1")
    at(16)
    state, node = claim("s-2")

    assert_equal [:claimed, "s-2"], [state, node.claimed_by]
    assert_equal [%w[s-1 lapsed], ["s-2", nil]], runs.map { |run| [run.session_id, run.result] }
  end

  def test_a_claim_renewed_14_minutes_ago_is_refused_and_still_held
    claim("s-1")
    at(14)
    state, node = claim("s-2")

    assert_equal [:held, "s-1", 1], [state, node.claimed_by, runs.size]
  end

  def test_a_lapsed_claim_nobody_took_completes_for_its_holder
    claim("s-1")
    at(40)
    node = work("s-1").done_node(intent_id: "1", id: "n1", by: "s-1", findings: "checked")

    assert_equal ["done", "done"], [node.state, runs.first.result]
  end

  def test_a_taken_claim_refuses_the_old_holder_and_changes_nothing
    claim("s-1")
    at(16)
    claim("s-2")
    refused = work("s-1").done_node(intent_id: "1", id: "n1", by: "s-1", findings: "late")

    assert_nil refused
    assert_equal ["claimed", "s-2"], retrieval.node("1", "n1").to_h.values_at(:state, :claimed_by)
    assert_equal %w[lapsed], runs.first(1).map(&:result)
  end

  def test_a_claim_that_loses_the_race_to_another_session_is_held
    stale = retrieval.node("1", "n1")
    claim("s-2")

    outcome, = Plastic::Graph::Work::Node::Claim.new(graphs("s-1").databases, retrieval, @clock).call(stale, by: "s-1", agent: "")

    assert_equal :held, outcome
  end
end

# A session renews its own claims of intents in progress.
class WorkNodeRenewalTest < WorkNodeRunCase
  def test_a_renewal_moves_the_lapse_out
    claim("s-1")
    at(10)
    work("s-1").renew_claims("s-1")
    at(20)

    assert_equal :held, claim("s-2").first
  end

  def test_a_renewal_leaves_out_the_claims_of_a_parked_intent
    claim("s-1")
    store_graphs.work.park_intent("1", "waits on review")
    at(10)
    work("s-1").renew_claims("s-1")

    assert_equal "2026-11-17T08:00:00Z", retrieval.node("1", "n1").seen_at
  end

  def test_a_renewal_touches_only_the_claims_of_its_session
    claim("s-1")
    at(10)
    work("s-2").renew_claims("s-2")

    assert_equal "2026-11-17T08:00:00Z", retrieval.node("1", "n1").seen_at
  end
end
