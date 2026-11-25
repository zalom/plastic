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

# In agent delivery the stop hook renews only the claims of the agent whose turn ends: the session's own agent, or the
# agent PLASTIC_AGENT names.
class StopRenewsAgentTest < Plastic::TestCase
  Clock = Struct.new(:now)

  START = Time.utc(2026, 11, 24, 8, 0, 0)
  CLAIMED = "2026-11-24T08:00:00Z"
  RENEWED = "2026-11-24T08:10:00Z"

  def setup
    super
    open_intent
    work = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1", clock: Clock.new(START)).work
    work.activate_intent("1")
    work.drive_intent(intent_id: "1", by: "s-1", mode: "auto")
    work.add_node(intent_id: "1", title: "Build", criterion: "it works")
    work.claim_node(intent_id: "1", id: "n1", by: "s-1", agent: "tester")
  end

  def stop(env)
    plastic("hook", "stop", input: "{}", env: { "PLASTIC_SESSION" => "s-1" }.merge(env), table: Plastic::CLI::TABLE, clock: Clock.new(START + 600))
  end

  def seen = [store_graphs.databases.fetch(:store).row("SELECT seen_at FROM drivers WHERE intent_id = '1'")["seen_at"], retrieval.node("1", "n1").seen_at]

  def test_the_turn_of_the_session_agent_renews_its_driver_claim_and_leaves_the_claim_of_a_helper
    stop({})

    assert_equal [RENEWED, CLAIMED], seen
  end

  def test_the_turn_of_a_helper_renews_its_node_claim_and_leaves_the_driver_claim
    stop({ "PLASTIC_AGENT" => "tester" })

    assert_equal [CLAIMED, RENEWED], seen
  end
end
