# frozen_string_literal: true

require_relative "../../../../test_helper"

# Releasing the claims of a session when it ends: the nodes it holds open again and their runs close as released.
class WorkDriverReleaseTest < Plastic::TestCase
  Clock = Struct.new(:now)

  START = Time.utc(2026, 11, 23, 8, 0, 0)

  def setup
    super
    @clock = Clock.new(START)
    store_graphs.work.write_intent(title: "Alpha")
    store_graphs.work.activate_intent("1")
  end

  def graphs(session) = Plastic::Graph.open(home: @plastic_home, store: "global", session:, clock: @clock)

  def work(session = "s-1") = graphs(session).work

  def at(minutes) = @clock.now = START + (minutes * 60)

  def claimed_node(session)
    node = work.add_node(intent_id: "1", title: "Build", criterion: "it works")
    work.claim_node(intent_id: "1", id: node.id, by: session)
    node
  end

  def test_releasing_the_claims_of_a_session_opens_its_claimed_nodes_and_closes_their_runs_as_released
    node = claimed_node("s-1")
    at(2)
    work.release_claims("s-1")

    assert_equal ["open", nil], retrieval.node("1", node.id).to_h.values_at(:state, :claimed_by)
    assert_equal ["released"], retrieval.structure.runs("1").map(&:result)
  end

  def test_releasing_the_claims_of_a_session_leaves_the_nodes_of_another_session
    node = claimed_node("s-2")
    work.release_claims("s-1")

    assert_equal ["claimed", "s-2"], retrieval.node("1", node.id).to_h.values_at(:state, :claimed_by)
  end
end
