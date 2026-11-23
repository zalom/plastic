# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../test_helpers/harness_record_fixtures"
require_relative "../../../lib/plastic/harnesses/run_record"

# The cost of a node run is the run's share of the session's running total, and only a main session holds a total.
class HarnessesRunRecordCostTest < Plastic::TestCase
  include Plastic::TestHelpers::HarnessRecordFixtures

  FROM = Time.utc(2026, 11, 12, 12, 0, 0)
  TO = Time.utc(2026, 11, 12, 12, 10, 0)

  def read = Plastic::Harnesses::RunRecord.new(home: @home).read(harness: "claude-code", session: "s-1", from: FROM, to: TO, claim: "1 n1")

  def test_a_run_that_starts_the_session_takes_the_first_total
    write_claude("s-1", jsonl(claude_turn("2026-11-12T12:01:00Z", id: "m1"), claude_cost(0.75)))

    assert_in_delta 0.75, read.cost_usd
  end

  def test_a_run_after_other_work_with_no_cost_state_before_it_takes_no_cost
    write_claude("s-1", jsonl(claude_turn("2026-11-12T11:59:00Z", id: "m0"), claude_turn("2026-11-12T12:01:00Z", id: "m1"), claude_cost(5.0)))
    usage = read

    assert_nil usage.cost_usd
    assert_includes usage.note, "other work before the run"
  end

  def test_a_run_after_other_work_since_the_last_cost_state_takes_no_cost
    write_claude("s-1", jsonl(claude_turn("2026-11-12T11:58:00Z", id: "m0"), claude_cost(0.5), claude_turn("2026-11-12T11:59:00Z", id: "m9"),
      claude_turn("2026-11-12T12:01:00Z", id: "m1"), claude_cost(5.0)))
    usage = read

    assert_nil usage.cost_usd
    assert_includes usage.note, "other work before the run"
  end

  def test_a_run_a_subagent_worked_takes_no_cost_because_the_harness_records_none_for_it
    write_claude("s-1", jsonl(claude_cost(1.0)))
    write_claude("agent-a1", jsonl(claude_claim_call("2026-11-12T12:00:05Z", "plastic node claim 1 n1 --agent x"),
      claude_turn("2026-11-12T12:03:00Z", id: "a2")), under: ["s-1", "subagents"])
    usage = read

    assert_nil usage.cost_usd
    assert_includes usage.note, "no cost for a subagent"
  end
end
