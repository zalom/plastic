# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/outcome_report"

# OutcomeReport (intent 339, G6): the report model over graph.md, nodes/, and
# the node ledger (n1), the generator and its command (n2), the plan-versus-
# delivered diff and stale computation (n3), and findings (n4). Every rendered
# cell traces to graph.md, a node file, or a ledger line; an absent source
# renders as the named reason, never a guess (spec D1).
class OutcomeReportTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("outcome-report")
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

  def write_graph(graph_body)
    write("graph.md", <<~MD)
      # Graph: Test

      ## Goal
      Test goal.

      ## Decisions
      - D1 test

      ## Graph
      #{graph_body}

      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
  end

  def write_node(id, kind: "work", title: nil, body_extra: "")
    heading = title ? "# #{id} - #{title}" : "(no title heading)"
    write("nodes/#{id}.md", <<~MD)
      ---
      node: #{id}
      kind: #{kind}
      files: []
      budget: 1000
      ---
      #{heading}

      #{body_extra}
    MD
  end

  def write_ledger(lines)
    write("savepoint.md", lines.join)
  end

  # --- 1.1 -----------------------------------------------------------------

  def test_malformed_graph_returns_errors_not_raise
    write_graph("- n1 needs\n")
    model = OutcomeReport.model(@dir)
    refute model[:ok]
    refute_empty model[:errors]
  end

  # --- 1.2 -----------------------------------------------------------------

  def test_missing_title_falls_back_to_node_id
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: nil)
    model = OutcomeReport.model(@dir)
    assert_equal "n1", model[:nodes]["n1"][:title]
  end

  # --- 1.3 -----------------------------------------------------------------

  def test_node_without_ledger_line_reads_planned
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: "Title")
    model = OutcomeReport.model(@dir)
    assert_equal "planned", model[:nodes]["n1"][:state]
  end

  # --- 1.4 -----------------------------------------------------------------

  def test_evidence_comes_from_last_done_line
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: "Title")
    write_ledger([
      "2026-09-09T10:00:00Z  n1  done gates=tests commit=aaa1111\n",
      "2026-09-09T10:05:00Z  n1  failed_verification gates=tests reason=broke\n",
      "2026-09-09T10:10:00Z  n1  done gates=tests commit=bbb2222\n",
    ])
    model = OutcomeReport.model(@dir)
    assert_equal "bbb2222", model[:nodes]["n1"][:fields]["commit"]
  end

  # --- 1.5 -----------------------------------------------------------------

  def test_retry_count_from_failed_verification_lines
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: "Title")
    write_ledger([
      "2026-09-09T10:00:00Z  n1  running holder=h expires=2026-09-09T11:00:00Z packet=A model=sonnet\n",
      "2026-09-09T10:01:00Z  n1  failed_verification gates=tests reason=broke\n",
      "2026-09-09T10:02:00Z  n1  running holder=h expires=2026-09-09T11:00:00Z packet=A model=sonnet\n",
      "2026-09-09T10:03:00Z  n1  failed_verification gates=tests reason=broke\n",
      "2026-09-09T10:04:00Z  n1  running holder=h expires=2026-09-09T11:00:00Z packet=A model=sonnet\n",
      "2026-09-09T10:05:00Z  n1  done gates=tests commit=ccc3333\n",
    ])
    model = OutcomeReport.model(@dir)
    assert_equal 2, model[:nodes]["n1"][:retries]
  end

  # --- 1.6 -----------------------------------------------------------------

  def test_absent_graph_returns_named_reason
    model = OutcomeReport.model(@dir)
    refute model[:ok]
    assert(model[:errors].any? { |e| e.include?("graph.md") })
    assert_equal({}, model[:nodes])
  end

  # --- 1.7 -----------------------------------------------------------------

  def test_undeclared_node_file_is_recorded
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: "Title")
    write_node("n9", title: "Undeclared")
    model = OutcomeReport.model(@dir)
    refute model[:nodes]["n9"][:declared]
  end

  # --- 1.8 -----------------------------------------------------------------

  def test_declared_node_without_file_still_listed
    write_graph("- n1 needs nothing\n- n3 needs n1\n")
    write_node("n1", title: "Title")
    model = OutcomeReport.model(@dir)
    entry = model[:nodes]["n3"]
    refute_nil entry
    assert entry[:declared]
    refute entry[:file_present]
    assert_equal "work", entry[:kind]
    assert_equal "n3", entry[:title]
  end

  # --- 1.9 -----------------------------------------------------------------

  def test_torn_line_excluded_from_state
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: "Title")
    write_ledger([
      "2026-09-09T10:00:00Z  n1  done gates=tests commit=aaa1111\n",
      "2026-09-09T10:05:00Z  n1  running holder=h\n", # torn: missing expires/packet/model
    ])
    model = OutcomeReport.model(@dir)
    assert_equal "done", model[:nodes]["n1"][:state]
  end

  # --- 1.10 ----------------------------------------------------------------

  def test_invalid_utf8_byte_does_not_raise
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: "Title")
    bad = "2026-09-09T10:00:00Z  n1  done gates=tests commit=\xFF\xFEbad\n".dup.force_encoding("UTF-8")
    write("savepoint.md", bad)
    model = OutcomeReport.model(@dir)
    refute_nil model
  end

  # --- 1.11 ------------------------------------------------------------------

  def test_library_source_reads_no_clock_or_environment
    source = File.read(File.join(__dir__, "..", "scripts", "lib", "outcome_report.rb"))
    refute_match(/\bTime\./, source)
    refute_match(/ENV\[/, source)
  end

  # --- 1.12 --------------------------------------------------------------------

  def test_model_does_not_call_needs_from_graph
    source = File.read(File.join(__dir__, "..", "scripts", "lib", "outcome_report.rb"))
    refute_includes source, "needs_from_graph"
  end
end
