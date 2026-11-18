# frozen_string_literal: true

require_relative "../../../../test_helper"

# A claim that loses the race to another session answers with the rejection of the node as it stands now.
class WorkNodeClaimTest < Plastic::TestCase
  Clock = Struct.new(:now)

  def setup
    super
    @clock = Clock.new(Time.utc(2026, 11, 17, 8, 0, 0))
    store_graphs.work.write_intent(title: "Alpha")
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it works")
  end

  def graphs(session) = Plastic::Graph.open(home: @plastic_home, store: "global", session:, clock: @clock)

  def test_a_claim_on_a_node_another_session_took_meanwhile_is_held_by_that_session
    stale = graphs("s-1").retrieval.node("1", "n1")
    graphs("s-2").work.claim_node(intent_id: "1", id: "n1", by: "s-2")
    claim = Plastic::Graph::Work::Node::Claim.new(graphs("s-1").databases, graphs("s-1").retrieval, @clock)

    status, node = claim.call(stale, by: "s-1", agent: "")

    assert_equal [:held, "s-2"], [status, node.claimed_by]
  end

  def test_a_claim_on_an_open_node_is_won
    node = graphs("s-1").retrieval.node("1", "n1")
    claim = Plastic::Graph::Work::Node::Claim.new(graphs("s-1").databases, graphs("s-1").retrieval, @clock)

    assert_equal [:claimed, "s-1"], claim.call(node, by: "s-1", agent: "").then { |status, held| [status, held.claimed_by] }
  end
end
