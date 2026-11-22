# frozen_string_literal: true

require_relative "../../../../test_helper"

# The driver claim of an intent works like a node claim: one live holder, a lapse after 15 minutes without a renewal,
# a release when the session ends, and a take-over that the work log records.
class WorkDriverWriterTest < Plastic::TestCase
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

  def drive(session = "s-1", **fields) = work(session).drive_intent(intent_id: "1", by: session, **fields)

  def driver_row = store_graphs.databases.fetch(:store).row("SELECT * FROM drivers WHERE intent_id = '1'")

  def driver_lines = retrieval.structure.work_log("1").select { |line| line.kind == "driver" }.map(&:text)

  def test_the_first_call_makes_its_session_the_driver
    status, = drive

    assert_equal [:driving, "s-1", "2026-11-23T08:00:00Z"], [status, driver_row["session_id"], driver_row["claimed_at"]]
  end

  def test_the_first_call_logs_the_new_driver
    drive

    assert_equal ["Driver s-1"], driver_lines
  end

  def test_the_driver_calling_again_logs_nothing_more
    drive
    at(5)
    drive

    assert_equal ["Driver s-1"], driver_lines
  end

  def test_another_session_is_held_while_the_driver_is_live
    drive
    at(14)
    status, holder = drive("s-2")

    assert_equal [:held, "s-1", "s-1"], [status, holder, driver_row["session_id"]]
  end

  def test_the_problem_of_a_held_call_names_the_live_driver
    drive

    assert_includes work("s-2").driver_problem("1", "s-2"), "intent 1 is driven by session s-1"
  end

  def test_the_driver_has_no_problem_with_its_own_intent
    drive

    assert_nil work.driver_problem("1", "s-1")
  end

  def test_a_driver_not_renewed_for_15_minutes_lapses_and_another_session_takes_over
    drive
    at(16)
    status, = drive("s-2")

    assert_equal [:driving, "s-2"], [status, driver_row["session_id"]]
  end

  def test_a_renewal_keeps_the_claim_live
    drive
    at(10)
    work.renew_claims("s-1")
    at(20)

    assert_equal :held, drive("s-2").first
  end

  def test_a_renewal_of_another_session_leaves_the_claim
    drive
    at(10)
    work("s-2").renew_claims("s-2")

    assert_equal "2026-11-23T08:00:00Z", driver_row["seen_at"]
  end

  def test_a_driver_whose_session_ended_is_released_at_once
    drive
    at(1)
    work.end_session("s-1", reason: "logout")
    work.release_claims("s-1")

    assert_nil driver_row
  end

  def test_a_driver_whose_session_ended_without_a_release_does_not_hold_the_intent
    drive
    at(1)
    work.end_session("s-1", reason: "logout")

    assert_equal :driving, drive("s-2").first
  end

  def test_a_take_over_with_a_reason_takes_a_live_claim
    drive
    at(1)
    status, = drive("s-2", take_over: "the owner asked for Codex")

    assert_equal [:took_over, "s-2"], [status, driver_row["session_id"]]
  end

  def test_a_take_over_logs_the_old_and_the_new_driver_and_the_reason
    drive
    drive("s-2", take_over: "the owner asked for Codex")

    assert_equal ["Driver s-1", "Driver s-2 took over from s-1: the owner asked for Codex"], driver_lines
  end

  def test_a_take_over_of_a_free_intent_is_a_plain_claim
    status, = drive("s-2", take_over: "the owner asked")

    assert_equal [:driving, ["Driver s-2"]], [status, driver_lines]
  end

  def test_a_lapsed_claim_taken_by_another_session_logs_the_old_and_the_new_driver
    drive
    at(16)
    drive("s-2")

    assert_equal ["Driver s-1", "Driver s-2 took over from s-1: the claim lapsed"], driver_lines
  end

  def test_releasing_the_claims_of_a_session_opens_its_claimed_nodes_and_closes_their_runs_as_released
    node = work.add_node(intent_id: "1", title: "Build", criterion: "it works")
    work.claim_node(intent_id: "1", id: node.id, by: "s-1")
    at(2)
    work.release_claims("s-1")

    assert_equal [["open", nil], ["released"]], [retrieval.node("1", node.id).to_h.values_at(:state, :claimed_by), retrieval.structure.runs("1").map(&:result)]
  end

  def test_releasing_the_claims_of_a_session_leaves_the_nodes_of_another_session
    node = work.add_node(intent_id: "1", title: "Build", criterion: "it works")
    work.claim_node(intent_id: "1", id: node.id, by: "s-2")
    work.release_claims("s-1")

    assert_equal ["claimed", "s-2"], retrieval.node("1", node.id).to_h.values_at(:state, :claimed_by)
  end
end
