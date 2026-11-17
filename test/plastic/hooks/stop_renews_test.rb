# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/stop"

# The stop hook renews the claims of its session, and only those.
class StopRenewsClaimsTest < Plastic::TestCase
  Clock = Struct.new(:now)

  START = Time.utc(2026, 11, 17, 8, 0, 0)

  def test_the_stop_hook_renews_the_claims_of_the_session
    clock = Clock.new(START)
    open_intent
    store_graphs.work.add_node(intent_id: "1", title: "Build", criterion: "it works")
    store_graphs.work.add_node(intent_id: "1", title: "Test", criterion: "it works")
    store_graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")
    store_graphs.work.claim_node(intent_id: "1", id: "n2", by: "s-2")
    clock.now = START + 600

    plastic("hook", "stop", input: "{}", env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE, clock:)

    refute_equal retrieval.node("1", "n1").seen_at, retrieval.node("1", "n2").seen_at
    assert_equal "2026-11-17T08:10:00Z", retrieval.node("1", "n1").seen_at
  end
end
