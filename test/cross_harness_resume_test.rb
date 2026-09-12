# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

require_relative "../scripts/lib/harness_adapter"
require_relative "../scripts/lib/node_ledger"

# HarnessAdapter.cross_harness_resume (intent 340b, G7c, n8). Matrix rows
# 8.1-8.8 in nodes/n8.md. `entries` here is always the shape
# NodeLedger.entries/entries_from_content returns; these tests build that
# shape from real ledger text through NodeLedger.entries_from_content rather
# than hand-rolling hashes, so a change to the parser's own shape breaks this
# suite too.
class CrossHarnessResumeTest < Minitest::Test
  def line(subject, state, fields = nil, ts: "2026-01-01T00:00:00Z", **kwfields)
    fields = (fields || {}).merge(kwfields)
    rendered = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
    rendered = " #{rendered}" unless rendered.empty?
    "#{ts}  #{subject}  #{state}#{rendered}\n"
  end

  def entries_for(content)
    NodeLedger.entries_from_content(content)
  end

  # --- row 8.1 ------------------------------------------------------------

  def test_reports_node_and_both_keys
    content = line("n1", "running", holder: "h1", expires: "2026-01-01T01:00:00Z",
                                     packet: "deadbeef", model: "sonnet", harness: "claude-code") +
              line("n1", "done", gates: "integrity", commit: "aaa1111", harness: "codex")

    result = HarnessAdapter.cross_harness_resume(entries_for(content))

    assert_equal 1, result.size
    assert_equal "n1", result.first[:node]
    assert_equal %w[claude-code codex], result.first[:harnesses]
  end

  # --- row 8.2 --------------------------------------------------------------

  def test_single_harness_reports_nothing
    content = line("n1", "running", holder: "h1", expires: "2026-01-01T01:00:00Z",
                                     packet: "deadbeef", model: "sonnet", harness: "claude-code") +
              line("n1", "done", gates: "integrity", commit: "aaa1111", harness: "claude-code")

    assert_empty HarnessAdapter.cross_harness_resume(entries_for(content))
  end

  # --- row 8.3 ----------------------------------------------------------------

  def test_ledger_without_harness_field_reports_nothing
    content = line("n1", "running", holder: "h1", expires: "2026-01-01T01:00:00Z",
                                     packet: "deadbeef", model: "sonnet") +
              line("n1", "done", gates: "integrity", commit: "aaa1111")

    assert_empty HarnessAdapter.cross_harness_resume(entries_for(content))
  end

  # --- row 8.4 ------------------------------------------------------------

  def test_torn_lines_ignored
    content = line("n1", "running", holder: "h1", expires: "2026-01-01T01:00:00Z",
                                     packet: "deadbeef", model: "sonnet", harness: "claude-code") +
              # torn: a running line missing the required packet=/model= fields
              line("n1", "running", holder: "h1", harness: "third-harness") +
              line("n1", "done", gates: "integrity", commit: "aaa1111", harness: "codex")

    result = HarnessAdapter.cross_harness_resume(entries_for(content))

    assert_equal 1, result.size
    assert_equal %w[claude-code codex], result.first[:harnesses]
  end

  # --- row 8.5 -----------------------------------------------------------

  def test_reports_landed_commits_per_harness
    content = line("n1", "running", holder: "h1", expires: "2026-01-01T01:00:00Z",
                                     packet: "deadbeef", model: "sonnet", harness: "claude-code") +
              line("n1", "failed_verification", gates: "integrity", reason: "call_budget",
                                                  commit: "aaa1111", harness: "claude-code") +
              line("n1", "reclaimed", holder: "h1", expired: "2026-01-01T02:00:00Z") +
              line("n1", "running", holder: "h2", expires: "2026-01-01T03:00:00Z",
                                     packet: "deadbeef", model: "sonnet", harness: "codex") +
              line("n1", "done", gates: "integrity", commit: "bbb2222", harness: "codex")

    result = HarnessAdapter.cross_harness_resume(entries_for(content))

    assert_equal({ "claude-code" => ["aaa1111"], "codex" => ["bbb2222"] }, result.first[:commits])
  end

  # --- row 8.6 --------------------------------------------------------------

  def test_starting_harness_reported_first
    content = line("n1", "running", holder: "h1", expires: "2026-01-01T01:00:00Z",
                                     packet: "deadbeef", model: "sonnet", harness: "codex") +
              line("n1", "failed_verification", gates: "integrity", reason: "call_budget",
                                                  harness: "codex") +
              line("n1", "running", holder: "h2", expires: "2026-01-01T02:00:00Z",
                                     packet: "deadbeef", model: "sonnet", harness: "claude-code") +
              line("n1", "done", gates: "integrity", commit: "ccc3333", harness: "claude-code")

    result = HarnessAdapter.cross_harness_resume(entries_for(content))

    assert_equal %w[codex claude-code], result.first[:harnesses]
  end

  # --- row 8.7 --------------------------------------------------------------

  def test_reads_across_reclaimed_line
    content = line("n1", "running", holder: "h1", expires: "2026-01-01T01:00:00Z",
                                     packet: "deadbeef", model: "sonnet", harness: "claude-code") +
              line("n1", "reclaimed", holder: "h1", expired: "2026-01-01T02:00:00Z") +
              line("n1", "running", holder: "h2", expires: "2026-01-01T03:00:00Z",
                                     packet: "deadbeef", model: "sonnet", harness: "codex") +
              line("n1", "done", gates: "integrity", commit: "ddd4444", harness: "codex")

    result = HarnessAdapter.cross_harness_resume(entries_for(content))

    assert_equal 1, result.size
    assert_equal %w[claude-code codex], result.first[:harnesses]
  end

  # --- row 8.8 -----------------------------------------------------------

  def test_scans_every_node
    content = line("n1", "running", holder: "h1", expires: "2026-01-01T01:00:00Z",
                                     packet: "deadbeef", model: "sonnet", harness: "claude-code") +
              line("n1", "done", gates: "integrity", commit: "aaa1111", harness: "claude-code") +
              line("n2", "running", holder: "h1", expires: "2026-01-01T01:00:00Z",
                                     packet: "deadbeef", model: "sonnet", harness: "claude-code") +
              line("n2", "done", gates: "integrity", commit: "bbb2222", harness: "codex")

    result = HarnessAdapter.cross_harness_resume(entries_for(content))

    assert_equal 1, result.size
    assert_equal "n2", result.first[:node]
  end
end
