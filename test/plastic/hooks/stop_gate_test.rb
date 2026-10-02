# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/hooks/stop_gate"

class StopGateTest < Plastic::TestCase
  StopGate = Plastic::Hooks::StopGate

  def retrieval = store_graphs.retrieval

  def make_ready_node(intent_id)
    put(:work, :nodes, { intent_id:, id: "a", state: "open" })
  end

  def take_lock(intent_id, mode: "auto", live: true)
    at = live ? Plastic.now : (Time.now - 3600).iso8601
    put(:home, :locks, { store: "global", intent_id:, session_id: "s-1", mode:, taken_at: at, renewed_at: at })
  end

  def put(key, table, row) = store_graphs.databases[key].transaction { |batch| batch.put(table, row) }

  def gate(event: {}, stop_hook: true) = StopGate.new(event:, stop_hook:, retrieval:, session_id: "s-1")

  def test_blocks_when_every_condition_holds
    take_lock("1")
    make_ready_node("1")

    decision = gate.decision

    assert_equal "block", decision["decision"]
    assert_includes decision["reason"], "intent 1 still has ready work"
  end

  def test_permits_once_the_harness_reports_the_stop_hook_active
    take_lock("1")
    make_ready_node("1")

    assert_nil gate(event: { stop_hook_active: true }).decision
  end

  def test_permits_when_the_config_flag_is_off
    take_lock("1")
    make_ready_node("1")

    assert_nil gate(stop_hook: false).decision
  end

  def test_permits_when_there_is_no_live_lock
    make_ready_node("1")

    assert_nil gate.decision
  end

  def test_permits_when_the_locked_intent_has_no_ready_node
    take_lock("1")

    assert_nil gate.decision
  end

  def test_a_lapsed_lock_does_not_block
    take_lock("1", live: false)
    make_ready_node("1")

    assert_nil gate.decision
  end

  def test_an_error_permits
    broken = StopGate.new(event: {}, stop_hook: true, retrieval: nil, session_id: "s-1")

    assert_nil broken.decision
  end
end
