# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/work/lapsed_claims"

# The lapsed claims of one store's agent deliveries, read straight from the rows.
class WorkLapsedClaimsTest < Plastic::TestCase
  START = Time.utc(2026, 11, 24, 9, 0, 0)
  STAMP = "2026-11-24T09:00:00Z"

  def setup
    super
    work = store_graphs.work
    work.write_intent(title: "Alpha")
    work.activate_intent("1")
    work.drive_intent(intent_id: "1", by: "s-1", mode: "auto")
    work.add_node(intent_id: "1", title: "Build")
  end

  def claimed_with_no_run
    sql = "UPDATE nodes SET state = 'claimed', claimed_by = 's-2', claimed_at = :at, seen_at = NULL WHERE id = 'n1'"
    store_graphs.databases.fetch(:store).transaction { |batch| batch.add(sql, at: STAMP) }
  end

  def lapsed(minutes) = Plastic::Graph::Work::LapsedClaims.new(store_graphs.retrieval, store: "global", now: START + (minutes * 60)).to_a

  def test_a_claimed_node_with_no_open_run_names_no_agent_and_its_claim_time_as_the_last_renewal
    claimed_with_no_run

    node = lapsed(16).find { |claim| claim.claim == "node" }

    assert_equal ["n1", "Build", nil, "s-2", STAMP], [node.node, node.node_title, node.agent, node.session, node.last_renewed]
  end

  def test_a_lapsed_driver_claim_names_the_agent_that_took_it
    store_graphs.work.drive_intent(intent_id: "1", by: "s-1", mode: "auto", agent: "deliver")
    store_graphs.databases.fetch(:store).transaction { |batch| batch.add("UPDATE drivers SET seen_at = :at", at: STAMP) }

    assert_equal "deliver", lapsed(16).find(&:driver?).agent
  end
end
