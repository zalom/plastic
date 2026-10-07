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
    put(:local, :locks, { store: "global", intent_id: "1", session_id: "s-1", mode: "auto", taken_at: old, renewed_at: old })
    put(:local, :locks, { store: "global", intent_id: "2", session_id: "s-2", mode: "auto", taken_at: old, renewed_at: old })

    call

    refute_equal old, store_graphs.retrieval.lock("1").renewed_at
    assert_equal old, store_graphs.retrieval.lock("2").renewed_at
  end

  def test_a_lapsed_lock_still_naming_this_session_is_renewed
    lapsed = "2026-10-05T09:00:00+02:00"
    put(:local, :locks, { store: "global", intent_id: "1", session_id: "s-1", mode: "auto", taken_at: lapsed, renewed_at: lapsed })

    call

    refute_equal lapsed, store_graphs.retrieval.lock("1").renewed_at
  end

  def test_end_sets_the_reason_and_not_the_turn
    call("--end", input: JSON.generate(reason: "clear"))

    session = store_graphs.retrieval.session("s-1")

    assert_equal "clear", session.end_reason
    assert_nil session.last_turn_at
  end

  def test_a_permit_prints_nothing
    assert_call call, code: 0
  end

  def test_a_block_prints_the_decision_as_one_json_line
    File.write(File.join(@plastic_home, "config.yml"), "runner:\n  stop_hook: true\n")
    put(:local, :locks, { store: "global", intent_id: "1", session_id: "s-1", mode: "auto", taken_at: STAMP, renewed_at: STAMP })
    put(:work, :nodes, { intent_id: "1", id: "a", state: "open" })

    result = call(input: JSON.generate(stop_hook_active: false))

    assert_call result, code: 0, out: %({"decision":"block","reason":"Plastic: intent 1 still has ready work. Run plastic next for it and dispatch what it prints before stopping."}\n)
  end

  def test_help_prints_the_usage_and_reads_no_input
    reader = Class.new { def read(*) = raise("the hook read its input") }.new
    environment = Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => @plastic_home }, input: reader,
      out: StringIO.new, err: StringIO.new, home: @home, directory: @home)
    code = Plastic::CLI.bin_call(%w[help hook record], environment:, table: Plastic::CLI::TABLE)

    assert_equal [0, ""], [code, environment.err.string]
    assert_equal "plastic hook record [--harness NAME] [--end]", environment.out.string.lines.first.chomp
  end

  def test_a_call_with_no_session_prints_one_stderr_line
    result = call(env: {})

    assert_call result, code: 0, err: "plastic hook: the event names no session; nothing recorded\n"
  end
end
