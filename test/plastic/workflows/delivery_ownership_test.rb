# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/delivery_ownership"

class WorkflowDeliveryOwnershipTest < Plastic::TestCase
  Context = Data.define(:retrieval, :intent_id, :session, :now)

  NOW = Time.parse(STAMP)

  def problem(session: "s-1", now: NOW) = Plastic::Workflows::DeliveryOwnership.problem(Context.new(retrieval, "1", session, now))

  def claim(session_id)
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build")
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: session_id)
  end

  def test_a_live_claim_of_another_session_is_the_problem
    claim("s-2")

    assert_equal "intent 1 has node n1 claimed by session s-2", problem(now: Time.now)
  end

  def test_a_claim_of_this_session_is_no_problem
    claim("s-1")

    assert_nil problem(now: Time.now)
  end

  def test_a_lapsed_claim_of_another_session_is_no_problem
    claim("s-2")

    assert_nil problem(now: Time.now + Plastic::Graph::Work::Node::LAPSE + 60)
  end

  def test_no_claim_is_no_problem
    open_intent

    assert_nil problem
  end
end
