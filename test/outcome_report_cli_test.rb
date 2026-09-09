# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../scripts/lib/outcome_guard"

# scripts/outcome-report - the CLI over OutcomeReport (intent 339, G6, n2).
class OutcomeReportCliTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  CLI = File.join(REPO, "scripts", "outcome-report")

  def setup
    @root = Dir.mktmpdir("outcome-report-cli")
    @dir = File.join(@root, "12--slug")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write(rel, body)
    path = File.join(@dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def make_real_intent
    write("12--slug.md", "---\nid: \"12\"\nintent: \"Demo\"\n---\n\n## Intent\nDemo\n")
    write("graph.md", <<~MD)
      # Graph: Demo

      ## Goal
      Demo goal.

      ## Decisions
      - D1 demo

      ## Graph
      - n1 needs nothing

      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
    write("nodes/n1.md", <<~MD)
      ---
      node: n1
      kind: work
      files: []
      budget: 1000
      ---
      # n1 - Demo unit

      ## n1 failure-mode matrix
      | Row | Operation | Failure mode | Test |
      | --- | --- | --- | --- |
      | 1.1 | a | b | c |
    MD
    write("savepoint.md", "2026-09-09T10:00:00Z  n1  done gates=tests commit=abc1234\n")
  end

  # --- 2.14 --------------------------------------------------------------------

  def test_generated_outcome_passes_outcome_guard
    make_real_intent
    out, err, status = Open3.capture3("ruby", CLI, @dir, "--write", "--disposition", "delivered")
    assert_equal 0, status.exitstatus, err
    assert_nil OutcomeGuard.reason(@dir, "delivered")
  end

  # --- 2.15 --------------------------------------------------------------------

  def test_generated_outcome_passes_hollow_report_gate
    make_real_intent
    Open3.capture3("ruby", CLI, @dir, "--write", "--disposition", "delivered")
    require_relative "../scripts/lib/report_screen"
    rows = ReportScreen.delivered_rows(@dir)
    refute_empty rows
    refute_equal ReportScreen::NOT_RECORDED, ReportScreen.proven_by(@dir, rows.first[:label])
  end

  # --- 2.16 --------------------------------------------------------------------

  def test_default_prints_and_write_flag_writes
    make_real_intent
    out, err, status = Open3.capture3("ruby", CLI, @dir, "--disposition", "delivered")
    assert_equal 0, status.exitstatus, err
    refute_empty out
    refute File.exist?(File.join(@dir, "outcome.md"))

    Open3.capture3("ruby", CLI, @dir, "--write", "--disposition", "delivered")
    assert File.exist?(File.join(@dir, "outcome.md"))
  end

  # --- v1f.9 (N3) --------------------------------------------------------------

  def test_unknown_disposition_exits_2
    make_real_intent
    _out, err, status = Open3.capture3("ruby", CLI, @dir, "--write", "--disposition", "banana")
    assert_equal 2, status.exitstatus
    assert_match(/disposition/, err)
    refute File.exist?(File.join(@dir, "outcome.md"))
  end

  # --- 2.17 --------------------------------------------------------------------

  def test_non_intent_dir_exits_2
    _out, err, status = Open3.capture3("ruby", CLI, @root, "--write")
    assert_equal 2, status.exitstatus
    refute_empty err
  end

  # --- 2.18 --------------------------------------------------------------------

  def test_exit_codes_distinguish_usage_from_model_failure
    _out, _err, usage_status = Open3.capture3("ruby", CLI, @root)
    assert_equal 2, usage_status.exitstatus

    write("12--slug.md", "---\nid: \"12\"\nintent: \"Demo\"\n---\n\n## Intent\nDemo\n")
    # A real intent dir with no graph.md: the model cannot be built.
    _out, _err, model_status = Open3.capture3("ruby", CLI, @dir)
    refute_equal usage_status.exitstatus, model_status.exitstatus
  end
end
