# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/hooks/record"

class RecordTest < Plastic::TestCase
  fixtures :empty

  def call(*args, env: { "PLASTIC_SESSION" => "s-1" }, input: "{}")
    plastic("hook", "record", *args, input:, env:, table: Plastic::CLI::TABLE)
  end

  def put(key, table, row) = store_graphs.databases[key].transaction { |batch| batch.put(table, row) }

  def test_stop_stamps_the_last_turn_at
    call

    refute_nil store_graphs.retrieval.session("s-1").last_turn_at
  end

  def test_stop_renews_only_this_sessions_locks
    old = "2020-01-01T00:00:00+00:00"
    put(:home, :locks, { store: "global", intent_id: "1", session_id: "s-1", mode: "auto", taken_at: old, renewed_at: old })
    put(:home, :locks, { store: "global", intent_id: "2", session_id: "s-2", mode: "auto", taken_at: old, renewed_at: old })

    call

    refute_equal old, store_graphs.retrieval.lock("1").renewed_at
    assert_equal old, store_graphs.retrieval.lock("2").renewed_at
  end

  def test_a_lapsed_lock_still_naming_this_session_is_renewed
    lapsed = (Time.now - 3600).iso8601
    put(:home, :locks, { store: "global", intent_id: "1", session_id: "s-1", mode: "auto", taken_at: lapsed, renewed_at: lapsed })

    call

    assert_predicate store_graphs.retrieval.lock("1"), :live?
  end

  def test_end_sets_the_reason_and_not_the_turn
    call("--end", input: JSON.generate(reason: "clear"))

    session = store_graphs.retrieval.session("s-1")

    assert_equal "clear", session.end_reason
    assert_nil session.last_turn_at
  end

  def test_a_permit_prints_nothing
    assert_equal "", call.out
  end

  def test_a_block_prints_the_decision_as_one_json_line
    File.write(File.join(@plastic_home, "config.yml"), "runner:\n  stop_hook: true\n")
    put(:home, :locks, { store: "global", intent_id: "1", session_id: "s-1", mode: "auto", taken_at: Plastic.now, renewed_at: Plastic.now })
    put(:work, :nodes, { intent_id: "1", id: "a", state: "open" })

    result = call(input: JSON.generate(stop_hook_active: false))

    assert_equal({ "decision" => "block", "reason" => "Plastic: intent 1 still has ready work. Run plastic next for it and " \
                                                       "dispatch what it prints before stopping." }, JSON.parse(result.out))
  end

  def test_a_call_with_no_session_prints_one_stderr_line
    result = call(env: {})

    assert_equal ["", 0], [result.out, result.code]
    assert_includes result.err, "plastic hook: the event names no session; nothing recorded"
  end
end
