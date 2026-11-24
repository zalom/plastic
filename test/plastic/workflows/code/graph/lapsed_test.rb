# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/graph/lapsed"

# The line and the restart command of one lapsed claim.
class LapsedGraphTest < Plastic::TestCase
  STAMP = "2026-11-24T09:00:00Z"

  def claim(**fields)
    Plastic::Graph::Work::LapsedClaim.new(store: "global", intent_id: "7", title: "Ship", claim: "node", node: "n2", node_title: "Build",
      agent: nil, session: "s-1", last_renewed: STAMP, **fields)
  end

  def workflow = Plastic::Workflows::Code::Graph::Lapsed

  def test_a_node_claim_whose_run_names_no_agent_says_so
    assert_equal "lapsed: store global, intent 7 Ship, node n2 Build, agent not recorded, session s-1, last renewed #{Plastic.local(STAMP)}", workflow.line(claim)
  end

  def test_a_node_claim_whose_run_names_no_agent_is_restarted_with_a_name_to_choose
    assert_equal "plastic node claim 7 n2 --agent NAME", workflow.restart(claim).first
  end

  def test_a_node_claim_is_restarted_by_the_agent_that_held_it
    assert_equal "plastic node claim 7 n2 --agent tester", workflow.restart(claim(agent: "tester")).first
  end
end
