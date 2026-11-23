# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../test_helpers/harness_record_fixtures"
require_relative "../../../lib/plastic/harnesses/run_record"

# What Plastic reads of one node run from a Codex log, and what it does with a record it cannot read or does not know.
class HarnessesRunRecordCodexTest < Plastic::TestCase
  include Plastic::TestHelpers::HarnessRecordFixtures

  FROM = Time.utc(2026, 11, 12, 12, 0, 0)
  TO = Time.utc(2026, 11, 12, 12, 10, 0)

  def read(harness: "claude-code", session: "s-1", claim: "1 n1")
    Plastic::Harnesses::RunRecord.new(home: @home).read(harness:, session:, from: FROM, to: TO, claim:)
  end

  def figures(usage) = usage.to_h.values_at(:model, :input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens)

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

  def test_an_unreadable_codex_log_gives_a_note_and_names_the_session
    write_codex("s-1", "not json\n")
    usage = read(harness: "codex")

    assert_equal "s-1", usage.worker_session
    assert_includes usage.note, "unreadable"
  end

  def test_a_codex_log_with_no_token_count_inside_the_run_says_so
    write_codex("s-1", jsonl(codex_count("2026-11-12T11:00:00Z", input: 10, cached: 0, output: 1)))

    assert_includes read(harness: "codex").note, "no turn inside the run"
  end

  def test_a_line_with_no_time_and_a_blank_line_are_skipped_without_failing
    write_claude("s-1", "\n#{JSON.generate(type: "assistant", timestamp: "not a time", message: { id: "m0" })}\n[1]\n#{jsonl(claude_turn("2026-11-12T12:05:00Z", id: "m1"))}")

    assert_equal ["claude-sonnet-5-5", 2, 10], figures(read).values_at(0, 1, 2)
  end

  def test_a_record_file_that_cannot_be_read_as_text_is_unreadable
    write_claude("s-1", "\xFF\xFE\x00bad\n".b)

    assert_includes read.note, "unreadable"
  end

  def test_a_reader_that_raises_is_named_in_the_note_and_does_not_propagate
    record = Plastic::Harnesses::RunRecord.new(home: @home)
    record.instance_variable_set(:@readers, { "codex" => Object.new }.freeze)

    usage = record.read(harness: "codex", session: "s-1", from: FROM, to: TO, claim: "1 n1")

    assert_includes usage.note, "could not be read"
  end

  def test_a_harness_with_no_record_gives_a_note
    assert_includes read(harness: nil).note, "no harness record"
  end

  def test_a_harness_the_reader_does_not_know_gives_a_note
    assert_includes read(harness: "hermes").note, "no harness record"
  end
end
