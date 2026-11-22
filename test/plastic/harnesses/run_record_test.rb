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

    assert_equal ["agent-a1", "claude-haiku-5-5", 80], [usage.worker_session, usage.model, usage.output_tokens + 40]
    assert_equal 50, usage.output_tokens
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

  def test_codex_tokens_are_the_growth_of_the_running_total_and_the_model_is_the_turn_model
    write_codex("s-1", jsonl(
      codex_context("2026-11-12T11:58:00Z", "gpt-6-astra"),
      codex_count("2026-11-12T11:59:00Z", input: 1000, cached: 800, output: 50),
      codex_count("2026-11-12T12:05:00Z", input: 3000, cached: 2000, output: 150, written: 10),
      codex_count("2026-11-12T12:20:00Z", input: 9000, cached: 9000, output: 900)
    ))
    usage = read(harness: "codex")

    assert_equal ["gpt-6-astra", 800, 100, 1200, 10], figures(usage)
    assert_nil usage.cost_usd
    assert_includes usage.note, "cost"
  end

  def test_a_missing_codex_log_gives_a_note
    assert_includes read(harness: "codex").note, "no Codex session log for session s-1"
  end

  def test_a_harness_with_no_record_gives_a_note
    assert_includes read(harness: nil).note, "no harness record"
  end

  def test_a_harness_the_reader_does_not_know_gives_a_note
    assert_includes read(harness: "hermes").note, "no harness record"
  end
end
