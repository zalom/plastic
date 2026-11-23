# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../test_helpers/harness_record_fixtures"
require_relative "../../../lib/plastic/hooks/end"
require "plastic/commands/intent/end"

# Claude Code writes its cost-state line when the session stops, after the done command read the record. A run that ended
# with no cost takes the cost once the record holds it, when the session ends and when the intent closes.
module RunCostFillHelper
  include Plastic::TestHelpers::HarnessRecordFixtures

  TURN = "2026-11-23T19:51:29Z"

  def run_row = store_graphs.databases.fetch(:store).rows("SELECT harness, session_id, cost_usd, usage_note FROM runs WHERE node_id = 'n1'").first.values

  def costs = store_graphs.databases.fetch(:store).rows("SELECT cost_usd FROM runs ORDER BY node_id, number").map { |row| row.values.first }

  def stored_turns(session = "s-1") = write_claude(session, jsonl(claude_turn(TURN, id: "m1", output: 40)))

  def add_cost(path, total) = File.write(path, jsonl(claude_cost(total)), mode: "a")
end

class RunCostFillSessionEndTest < Plastic::TestCase
  include RunCostFillHelper

  Clock = Struct.new(:now)

  def setup
    super
    @clock = Clock.new(Time.utc(2026, 11, 23, 19, 51, 27.5r))
    alpha_with_node
  end

  def as_session(*argv) = plastic(*argv, env: { "CLAUDE_CODE_SESSION_ID" => "s-1" }, table: Plastic::CLI::TABLE, clock: @clock)

  def run_without_cost
    as_session("node", "claim", "1", "n1", "--agent", "w1")
    path = stored_turns
    @clock.now = Time.utc(2026, 11, 23, 19, 51, 31.5r)
    as_session("node", "done", "1", "n1", "ok")
    path
  end

  def end_session(session = "s-1") = plastic("hook", "end", input: JSON.generate(reason: "logout"), env: { "CLAUDE_CODE_SESSION_ID" => session }, table: Plastic::CLI::TABLE, clock: @clock)

  def test_a_run_with_no_cost_takes_it_when_the_session_ends_and_the_transcript_holds_it
    add_cost(run_without_cost, 1.25)
    result = end_session

    assert_equal [0, "", ""], [result.code, result.err, run_row[3]]
    assert_in_delta 1.25, run_row[2]
  end

  def test_a_session_end_with_no_cost_in_the_transcript_leaves_the_run_as_it_was
    run_without_cost
    before = run_row

    assert_equal 0, end_session.code
    assert_equal before, run_row
  end

  def test_the_end_of_another_session_leaves_the_run_with_no_cost
    add_cost(run_without_cost, 1.25)
    end_session("s-2")

    assert_nil run_row[2]
  end

  def test_a_cost_already_on_the_run_is_not_changed
    path = run_without_cost
    store_graphs.databases.fetch(:store).transaction { |batch| batch.add("UPDATE runs SET cost_usd = 9.5") }
    add_cost(path, 1.25)
    end_session

    assert_in_delta 9.5, run_row[2]
  end

  def test_a_codex_run_stays_with_no_cost_and_nothing_fails
    run_without_cost
    store_graphs.databases.fetch(:store).transaction { |batch| batch.add("UPDATE runs SET harness = 'codex'") }
    write_codex("s-1", jsonl(codex_context("2026-11-23T19:51:29Z", "gpt-5"), codex_count("2026-11-23T19:51:30Z", input: 10, cached: 2, output: 5)))
    result = end_session

    assert_equal [0, "", nil], [result.code, result.err, run_row[2]]
  end

  def test_a_run_a_subagent_worked_stays_with_no_cost_at_the_session_end
    path = run_without_cost
    store_graphs.databases.fetch(:store).transaction { |batch| batch.add("UPDATE runs SET worker_session = 'agent-w1'") }
    add_cost(path, 1.25)
    end_session

    assert_nil run_row[2]
  end

  def test_the_claims_of_the_session_are_released_when_the_fill_raises
    run_without_cost
    as_session("node", "add", "1", "Next", "--criterion", "tests-pass")
    as_session("node", "claim", "1", "n2", "--agent", "w1")
    store_graphs.databases.fetch(:store).transaction { |batch| batch.add("UPDATE runs SET started_at = 'junk' WHERE node_id = 'n1'") }
    result = end_session

    assert_equal [0, "open"], [result.code, retrieval.node("1", "n2").state]
    assert_includes result.err, "the cost was not filled"
  end

  def test_the_claim_turn_written_before_the_stored_start_does_not_count_as_other_work
    as_session("node", "claim", "1", "n1", "--agent", "w1")
    path = write_claude("s-1", jsonl(claude_claim_call("2026-11-23T19:51:26.6Z", "plastic node claim 1 n1 --agent w1"), claude_turn(TURN, id: "m1")))
    @clock.now = Time.utc(2026, 11, 23, 19, 51, 31.5r)
    as_session("node", "done", "1", "n1", "ok")
    add_cost(path, 0.9)
    end_session

    assert_in_delta 0.9, run_row[2]
  end

  def test_a_run_whose_transcript_has_no_turn_inside_the_run_stays_with_no_cost
    run_without_cost
    write_claude("s-1", jsonl(claude_turn("2026-11-23T18:00:00Z", id: "early"), claude_cost(3.0)))
    result = end_session

    assert_equal [0, nil], [result.code, run_row[2]]
  end

  def test_a_run_whose_transcript_is_missing_stays_with_no_cost_and_nothing_fails
    run_without_cost
    FileUtils.rm_f(Dir.glob(File.join(@home, ".claude", "projects", "*", "s-1.jsonl")))
    result = end_session

    assert_equal [0, "", nil], [result.code, result.err, run_row[2]]
  end
end

class RunCostFillIntentEndTest < Plastic::TestCase
  include LifecycleHelper
  include RunCostFillHelper

  def claude_run(path)
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.add("UPDATE runs SET harness = 'claude-code', session_id = 's-1', started_at = '2026-11-23T19:51:27Z', ended_at = '2026-11-23T19:51:31Z'")
    end
    add_cost(path, 2.5)
  end

  def test_the_intent_close_fills_the_cost_of_a_run_with_no_cost
    accepted_intent
    review_off
    claude_run(stored_turns)
    result = cli("intent", "end", "1")

    assert_equal [0, "done", [2.5]], [result.code, retrieval.intent("1").status, costs]
  end

  def test_the_intent_close_leaves_a_codex_run_with_no_cost
    accepted_intent
    review_off
    claude_run(stored_turns)
    store_graphs.databases.fetch(:store).transaction { |batch| batch.add("UPDATE runs SET harness = 'codex'") }
    result = cli("intent", "end", "1")

    assert_equal [0, "done", [nil]], [result.code, retrieval.intent("1").status, costs]
  end
end
