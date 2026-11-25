# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/stop"

class StopEventCaseTest < Plastic::TestCase
  def stop(input, session)
    plastic("hook", "stop", input:, env: { "CLAUDE_CODE_SESSION_ID" => session }, table: Plastic::CLI::TABLE)
  end

  def row(session) = store_graphs.retrieval.session(session)

  def test_an_empty_event_of_a_session_nobody_started_stamps_a_turn_with_no_harness_and_prints_nothing
    result = stop("{}", "s-9")

    assert_case result, code: 0, out: "", err: ""
    assert_equal [nil, true, nil], [row("s-9").harness, !row("s-9").last_turn_at.nil?, row("s-9").ended_at]
  end

  def test_an_event_that_is_not_json_is_read_as_empty_with_a_message_and_stamps_the_turn
    plastic("hook", "start", input: JSON.generate(source: "startup"), env: { "CLAUDE_CODE_SESSION_ID" => "s-1" }, table: Plastic::CLI::TABLE)
    result = stop("not json", "s-1")

    assert_case result, code: 0, out: "", err: ["plastic hook: the event is not a JSON object; read as empty"]
    assert_equal ["claude-code", true, nil], [row("s-1").harness, !row("s-1").last_turn_at.nil?, row("s-1").ended_at]
  end
end

class StopTest < Plastic::TestCase
  include ConfigHomes

  fixtures :empty

  def call(*args, env: { "PLASTIC_SESSION" => "s-1" }, input: "{}")
    plastic("hook", "stop", *args, input:, env:, table: Plastic::CLI::TABLE)
  end

  def put(table, row) = store_graphs.databases.fetch(:store).transaction { |batch| batch.put(table, row) }

  def claim_node(intent_id, session, at, id: "c#{session}")
    put(:intents, { intent_id:, slug: "i#{intent_id}", title: "Intent #{intent_id}", status: "in_progress" })
    put(:nodes, { intent_id:, id:, state: "claimed", claimed_by: session, claimed_at: at, seen_at: at, updated_at: at })
  end

  CLAUDE = { "CLAUDE_CODE_SESSION_ID" => "s-1" }.freeze

  def start_claude_session = plastic("hook", "start", input: JSON.generate(source: "startup"), env: CLAUDE, table: Plastic::CLI::TABLE)

  def session_row
    session = store_graphs.retrieval.session("s-1")
    [session.harness, !session.last_turn_at.nil?, session.ended_at.nil?]
  end

  def test_stop_stamps_the_last_turn_at
    start_claude_session
    result = call(env: CLAUDE)

    assert_call result, code: 0, out: "", err: ""
    assert_equal ["claude-code", true, true], session_row
  end

  def test_stop_renews_only_this_sessions_claims
    old = "2020-01-01T00:00:00Z"
    claim_node("1", "s-1", old)
    claim_node("2", "s-2", old)

    call

    refute_equal old, store_graphs.retrieval.node("1", "cs-1").seen_at
    assert_equal old, store_graphs.retrieval.node("2", "cs-2").seen_at
  end

  def test_a_lapsed_claim_still_naming_this_session_is_renewed
    lapsed = "2026-10-05T09:00:00Z"
    claim_node("1", "s-1", lapsed)

    call

    refute_equal lapsed, store_graphs.retrieval.node("1", "cs-1").seen_at
  end

  def test_a_permit_prints_nothing
    assert_call call, code: 0
  end

  def test_a_block_prints_the_decision_as_one_json_line
    seed_config(@plastic_home, "runner:\n  stop_hook: true\n")
    claim_node("1", "s-1", STAMP)
    put(:nodes, { intent_id: "1", id: "a", state: "open" })

    result = call(input: JSON.generate(stop_hook_active: false))

    assert_call result, code: 0, out: %({"decision":"block","reason":"Plastic: intent 1 still has ready work. Run plastic next for it and dispatch what it prints before stopping."}\n)
  end

  def test_with_no_session_row_the_global_section_turns_the_stop_gate_on
    seed_config(@plastic_home, "global:\n  runner:\n    stop_hook: true\n")
    claim_node("1", "s-9", STAMP)
    put(:nodes, { intent_id: "1", id: "a", state: "open" })

    result = call(env: { "PLASTIC_SESSION" => "s-9" }, input: JSON.generate(stop_hook_active: false))

    assert_match(/"decision":"block"/, result.out)
  end

  def test_help_prints_the_usage_and_reads_no_input
    reader = Class.new { def read(*) = raise("the hook read its input") }.new
    environment = Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => @plastic_home }, input: reader,
      out: StringIO.new, err: StringIO.new, home: @home, directory: @home)
    code = Plastic::CLI.bin_call(%w[help hook stop], environment:, table: Plastic::CLI::TABLE)

    assert_equal [0, ""], [code, environment.err.string]
    assert_equal "plastic hook stop", environment.out.string.lines.first.chomp
  end

  def test_the_harness_section_of_the_session_row_harness_turns_the_stop_gate_on
    seed_config(@plastic_home, "harnesses:\n  codex:\n    runner:\n      stop_hook: true\n")
    store_graphs.work.open_session("s-1", harness: "codex", directory: @home)
    claim_node("1", "s-1", STAMP)
    put(:nodes, { intent_id: "1", id: "a", state: "open" })

    assert_match(/"decision":"block"/, call(input: JSON.generate(stop_hook_active: false)).out)
  end

  def test_a_session_row_of_an_unregistered_harness_reads_the_global_section
    seed_config(@plastic_home, "harnesses:\n  codex:\n    runner:\n      stop_hook: true\n")
    store_graphs.work.open_session("s-1", harness: "unknown", directory: @home)
    claim_node("1", "s-1", STAMP)
    put(:nodes, { intent_id: "1", id: "a", state: "open" })

    assert_call call(input: JSON.generate(stop_hook_active: false)), code: 0, out: ""
  end

  def test_stop_keeps_the_harness_the_start_recorded
    store_graphs.work.open_session("s-1", harness: "codex", directory: @home)

    call

    assert_equal "codex", store_graphs.retrieval.session("s-1").harness
  end

  def test_stop_takes_no_harness_option
    start_claude_session

    assert_call call("--harness", "codex", env: CLAUDE), code: 0, err: "plastic: invalid option: --harness\nplastic hook stop\n"
    assert_equal ["claude-code", false, true], session_row
  end

  def test_a_call_with_no_session_prints_one_stderr_line
    start_claude_session
    result = call(env: {})

    assert_call result, code: 0, err: "plastic hook: the event names no session; nothing recorded\n"
    assert_equal ["claude-code", false, true], session_row
  end
end
