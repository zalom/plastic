# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/node/renew"

class WorkflowRenewNodeTest < Plastic::TestCase
  def setup
    super
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it runs")
  end

  def harness(session, agent) = scoped_harness(session:).tap { |running| running.agent = agent }

  def renew(id = "n1", session: "s-1", agent: "") = run_workflow(Plastic::Workflows::Code::Node::Renew, harness: harness(session, agent), intent_id: "1", id:).first

  def refusal(id = "n1", session: "s-1", agent: "")
    stop_workflow(Plastic::Workflows::Code::Node::Renew, Plastic::Refused, harness: harness(session, agent), intent_id: "1", id:).first
  end

  def test_a_node_claimed_by_the_session_is_renewed
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")

    assert_equal :done, renew
  end

  def test_an_unknown_node_is_refused
    assert_equal "no node n9 in intent 1", refusal("n9").message
  end

  def test_an_open_node_holds_no_claim_to_renew
    assert_equal "node n1 is open; it holds no claim", refusal.message
  end

  def test_a_node_held_by_another_session_is_refused
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-2")

    assert_equal "node n1 is held by session s-2", refusal.message
  end

  def driven_by_agents
    work = store_graphs.work
    work.activate_intent("1")
    work.drive_intent(intent_id: "1", by: "s-1", mode: "auto")
    work.claim_node(intent_id: "1", id: "n1", by: "s-1", agent: "tester")
  end

  def test_in_agent_delivery_the_agent_that_holds_the_claim_renews_it
    driven_by_agents

    assert_equal :done, renew(agent: "tester")
  end

  def test_in_agent_delivery_another_agent_of_the_session_is_refused
    driven_by_agents

    assert_equal "node n1 is held by agent tester of session s-1", refusal(agent: "other").message
  end

  def test_in_agent_delivery_the_session_itself_leaves_the_claim_of_its_helper
    driven_by_agents

    assert_equal "node n1 is held by agent tester of session s-1", refusal.message
  end

  OLD = "2026-01-01T00:00:00Z"

  def two_claims_seen_long_ago
    work = store_graphs.work
    work.add_node(intent_id: "1", title: "Test", criterion: "it runs")
    %w[n1 n2].each { |id| work.claim_node(intent_id: "1", id:, by: "s-1") }
    store_graphs.databases.fetch(:store).transaction { |batch| batch.add("UPDATE nodes SET seen_at = :old", old: OLD) }
  end

  def seen_at(id) = retrieval.node("1", id).seen_at

  def test_a_renewal_renews_only_the_node_it_names
    two_claims_seen_long_ago
    renew

    assert_equal [true, OLD], [seen_at("n1") > OLD, seen_at("n2")]
  end
end
