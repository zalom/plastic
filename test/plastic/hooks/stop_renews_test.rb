# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/stop"

# The stop hook renews the claims of its session, and only those.
class StopRenewsClaimsTest < Plastic::TestCase
  Clock = Struct.new(:now)

  START = Time.utc(2026, 11, 17, 8, 0, 0)

  def claim_for(session)
    node = store_graphs.work.add_node(intent_id: "1", title: session, criterion: "it works")
    store_graphs.work.claim_node(intent_id: "1", id: node.id, by: session)
  end

  def stop_after(seconds, session)
    clock = Clock.new(START + seconds)
    plastic("hook", "stop", input: "{}", env: { "PLASTIC_SESSION" => session }, table: Plastic::CLI::TABLE, clock:)
  end

  def seen_at(id) = retrieval.node("1", id).seen_at

  def setup
    super
    open_intent
    store_graphs.work.activate_intent("1")
    claim_for("s-1")
    claim_for("s-2")
  end

  def test_the_stop_hook_renews_the_claim_of_its_session
    stop_after(600, "s-1")

    assert_equal "2026-11-17T08:10:00Z", seen_at("n1")
  end

  def test_the_stop_hook_leaves_the_claim_of_another_session
    stop_after(600, "s-1")

    refute_equal seen_at("n1"), seen_at("n2")
  end
end

# The stop hook renews the driver claim of its session too.
class StopRenewsDriverTest < Plastic::TestCase
  Clock = Struct.new(:now)

  START = Time.utc(2026, 11, 23, 8, 0, 0)

  def setup
    super
    open_intent
    store_graphs.work.activate_intent("1")
    clock = Clock.new(START)
    Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1", clock:).work.drive_intent(intent_id: "1", by: "s-1")
  end

  def seen_at = store_graphs.databases.fetch(:store).row("SELECT seen_at FROM drivers WHERE intent_id = '1'")["seen_at"]

  def stop(session, seconds)
    plastic("hook", "stop", input: "{}", env: { "PLASTIC_SESSION" => session }, table: Plastic::CLI::TABLE, clock: Clock.new(START + seconds))
  end

  def test_the_stop_hook_renews_the_driver_claim_of_its_session
    stop("s-1", 600)

    assert_equal "2026-11-23T08:10:00Z", seen_at
  end

  def test_the_stop_hook_leaves_the_driver_claim_of_another_session
    stop("s-2", 600)

    assert_equal "2026-11-23T08:00:00Z", seen_at
  end
end
