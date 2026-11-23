# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../test_helpers/harness_record_fixtures"
require_relative "../../../lib/plastic/harnesses/run_record"

# What Plastic reads of one node run from the harness's own local record: the model, the tokens and the cost.
class HarnessesRunRecordTest < Plastic::TestCase
  include Plastic::TestHelpers::HarnessRecordFixtures

  FROM = Time.utc(2026, 11, 12, 12, 0, 0)
  TO = Time.utc(2026, 11, 12, 12, 10, 0)

  def read(harness: "claude-code", session: "s-1", claim: "1 n1")
    Plastic::Harnesses::RunRecord.new(home: @home).read(harness:, session:, from: FROM, to: TO, claim:)
  end

  def figures(usage) = usage.to_h.values_at(:model, :input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens)

  def test_claude_turns_inside_the_run_are_summed_and_the_model_is_named
    write_claude("s-1", jsonl(
      claude_turn("2026-11-12T11:59:00Z", id: "m0", input: 90, output: 90, cache_read: 90, cache_write: 90),
      claude_turn("2026-11-12T12:01:00Z", id: "m1", input: 2, output: 10, cache_read: 100, cache_write: 1000),
      claude_turn("2026-11-12T12:02:00Z", id: "m2", input: 3, output: 20, cache_read: 200, cache_write: 0),
      claude_turn("2026-11-12T12:11:00Z", id: "m3", input: 90, output: 90, cache_read: 90, cache_write: 90)
    ))

    assert_equal ["claude-sonnet-5-5", 5, 30, 300, 1000], figures(read)
  end

  def test_a_turn_written_as_several_lines_of_one_message_counts_once
    write_claude("s-1", jsonl(
      claude_turn("2026-11-12T12:01:00Z", id: "m1", output: 10),
      claude_turn("2026-11-12T12:01:01Z", id: "m1", output: 10)
    ))

    assert_equal 10, read.output_tokens
  end

  def test_the_cost_is_the_growth_of_the_cost_state_over_the_run
    write_claude("s-1", jsonl(
      claude_turn("2026-11-12T11:59:00Z", id: "m0"), claude_cost(0.5),
      claude_turn("2026-11-12T12:01:00Z", id: "m1"), claude_cost(0.75),
      claude_turn("2026-11-12T12:11:00Z", id: "m2"), claude_cost(2.0)
    ))

    assert_in_delta 0.25, read.cost_usd
  end

  def test_a_cost_state_written_before_the_run_gives_no_cost
    write_claude("s-1", jsonl(claude_cost(4.0), claude_turn("2026-11-12T12:01:00Z", id: "m1")))
    usage = read

    assert_nil usage.cost_usd
    assert_includes usage.note, "cost not found"
  end

  def test_a_record_with_no_cost_state_names_the_cost_as_not_found
    write_claude("s-1", jsonl(claude_turn("2026-11-12T12:01:00Z", id: "m1")))
    usage = read

    assert_nil usage.cost_usd
    assert_includes usage.note, "cost"
  end

  def test_a_subagent_that_ran_the_claim_is_the_worker_and_its_own_turns_are_the_usage
    write_claude("s-1", jsonl(claude_turn("2026-11-12T12:01:00Z", id: "p1", output: 7)))
    write_claude("agent-a1", jsonl(
      claude_claim_call("2026-11-12T12:00:05Z", "plastic node claim 1 n1 --agent plastic-executor --project plastic"),
      claude_turn("2026-11-12T12:03:00Z", id: "a2", output: 40, model: "claude-haiku-5-5")
    ), under: ["s-1", "subagents"])
    usage = read

    assert_equal ["agent-a1", "claude-haiku-5-5"], [usage.worker_session, usage.model]
    assert_equal 50, usage.output_tokens
  end

  def test_a_subagent_that_claimed_just_before_the_run_started_is_the_worker
    write_claude("s-1", jsonl(claude_turn("2026-11-23T17:32:00Z", id: "p1", output: 7)))
    write_claude("agent-a1", jsonl(
      claude_claim_call("2026-11-23T17:32:55.306Z", "plastic node claim 1 n1 --agent plastic-executor --project plastic"),
      claude_turn("2026-11-23T17:33:10Z", id: "a2", output: 40, model: "claude-haiku-5-5")
    ), under: ["s-1", "subagents"])
    usage = Plastic::Harnesses::RunRecord.new(home: @home).read(harness: "claude-code", session: "s-1", from: Time.utc(2026, 11, 23, 17, 32, 57),
      to: Time.utc(2026, 11, 23, 17, 33, 21), claim: "1 n1")

    assert_equal ["agent-a1", "claude-haiku-5-5", 50], [usage.worker_session, usage.model, usage.output_tokens]
  end

  def test_a_subagent_that_claimed_long_before_the_run_and_still_works_is_the_worker
    write_claude("s-1", jsonl(claude_turn("2026-11-12T12:01:00Z", id: "p1")))
    write_claude("agent-a1", jsonl(claude_claim_call("2026-11-12T10:00:00Z", "plastic node claim 1 n1 --agent plastic-executor"),
      claude_turn("2026-11-12T12:03:00Z", id: "a2")), under: ["s-1", "subagents"])

    assert_equal "agent-a1", read.worker_session
  end

  def test_a_subagent_turn_with_only_text_is_not_the_claimant
    write_claude("s-1", jsonl(claude_turn("2026-11-12T12:01:00Z", id: "p1")))
    write_claude("agent-a1", jsonl(claude_turn("2026-11-12T12:03:00Z", id: "a2", block: { type: "text", text: "hello" })), under: ["s-1", "subagents"])

    assert_equal "s-1", read.worker_session
  end

  def test_with_no_subagent_holding_the_claim_the_worker_is_the_session_itself
    write_claude("s-1", jsonl(claude_turn("2026-11-12T12:01:00Z", id: "m1")))

    assert_equal "s-1", read.worker_session
  end

  def test_a_missing_claude_record_gives_a_note_and_no_numbers
    usage = read

    assert_equal [nil, nil, nil], [usage.model, usage.input_tokens, usage.cost_usd]
    assert_includes usage.note, "no Claude Code transcript for session s-1"
  end

  def test_an_unreadable_claude_record_gives_a_note_and_never_raises
    write_claude("s-1", "not json at all\n{\n")
    usage = read

    assert_nil usage.model
    assert_includes usage.note, "unreadable"
  end

  def test_a_record_with_no_turn_inside_the_run_says_so
    write_claude("s-1", jsonl(claude_turn("2026-11-12T11:00:00Z", id: "m0")))

    assert_includes read.note, "no turn inside the run"
  end
end
