# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/report_screen"

# ReportScreen (intent 339, G6, n5): the delivered screen reads nodes,
# additively and only for an intent that has a graph.md (spec D8). An intent
# with no graph.md renders exactly the bytes it renders today.
class ReportScreenNodesTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("report-screen-nodes")
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

  def write_basics
    write("12--slug.md", "---\nid: \"12\"\nintent: \"Demo\"\n---\n\n## Intent\nDemo\n")
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

  def write_node(id, kind: "work", title: "Title")
    write("nodes/#{id}.md", <<~MD)
      ---
      node: #{id}
      kind: #{kind}
      files: []
      budget: 1000
      ---
      # #{id} - #{title}
    MD
  end

  # --- 5.1 -------------------------------------------------------------------

  def test_delivered_screen_shows_node_states
    write_basics
    write_graph("- n1 needs nothing\n")
    write_node("n1")
    write("savepoint.md", "2026-08-30T12:00:00Z  What  12--slug.md\n2026-09-09T10:00:00Z  n1  done gates=tests commit=aaa1111\n")
    out = ReportScreen.render_delivered(intent_dir: @dir)
    assert_includes out, "### Nodes"
    assert_includes out, "| n1 |"
    assert_includes out, "done"
  end

  # --- 5.2 -------------------------------------------------------------------

  def test_no_graph_output_matches_frozen_golden
    write_basics
    write("savepoint.md", "2026-08-30T12:00:00Z  What  12--slug.md\n")
    out = ReportScreen.render_delivered(intent_dir: @dir)
    golden = "## ✔ 12 · Demo · delivered\nnot recorded · not recorded · not recorded · not recorded\n\n" \
             "**Asked**\n  Demo\n  decisions not recorded\n\n**Delivered**\n| Row | Detail | Proven by |\n| --- | --- | --- |\n\n" \
             "**Evidence**\nnot recorded\n\n**Needs you**\nNone\n"
    assert_equal golden, out
  end

  # --- 5.4 -------------------------------------------------------------------

  def test_stale_node_marked_on_screen
    write_basics
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1")
    write_node("n2")
    write("savepoint.md", <<~SP)
      2026-08-30T12:00:00Z  What  12--slug.md
      2026-09-09T10:00:00Z  n2  done gates=tests commit=aaa1111
      2026-09-09T10:01:00Z  n1  superseded by=n1b
    SP
    out = ReportScreen.render_delivered(intent_dir: @dir)
    row = out.lines.find { |l| l.start_with?("| n2 |") }
    refute_nil row
    assert_includes row, "stale"
  end

  # --- 5.5 -------------------------------------------------------------------

  def test_findings_block_rendered
    write("12--slug.md", <<~MD)
      ---
      id: "12"
      intent: "Demo"
      ---

      ## Intent
      Demo

      ## Insights
      2026-09-09T10:00:00Z · Exec · someone (autonomous) - an insight

      ### Findings
      - A real finding worth keeping
    MD
    write_graph("- n1 needs nothing\n")
    write_node("n1")
    write("savepoint.md", "2026-08-30T12:00:00Z  What  12--slug.md\n2026-09-09T10:00:00Z  n1  done gates=tests commit=aaa1111\n")
    out = ReportScreen.render_delivered(intent_dir: @dir)
    assert_includes out, "### Findings"
    assert_includes out, "A real finding worth keeping"
  end

  # --- 5.6 -------------------------------------------------------------------

  def test_node_state_comes_from_ledger
    write_basics
    write_graph("- n1 needs nothing\n- n2 needs nothing\n")
    write_node("n1")
    write_node("n2")
    # n2 gets no ledger line at all, so its state reads "planned" - a second
    # node whose ledger state differs from n1's "done" (post-execution review
    # N6), so a hardcoded "done" cannot pass both rows.
    write("savepoint.md", "2026-08-30T12:00:00Z  What  12--slug.md\n2026-09-09T10:00:00Z  n1  done gates=tests commit=aaa1111\n")
    write("outcome.md", <<~MD)
      ---
      disposition: delivered
      ---
      # Outcome: Demo

      ## Summary
      hand-edited nonsense that disagrees with the ledger

      ## Delivered
      | Row | What |
      | --- | --- |
      | n1 | some other claim |
    MD
    out = ReportScreen.render_delivered(intent_dir: @dir)
    row1 = out.lines.find { |l| l.start_with?("| n1 |") && l.include?("work") }
    row2 = out.lines.find { |l| l.start_with?("| n2 |") && l.include?("work") }
    refute_nil row1
    refute_nil row2
    assert_includes row1, "done"
    assert_includes row2, "planned"
    refute_includes row2, "done"
  end

  # --- S9 (v1g), D17: a verify node is proven by its criteria -----------------

  def test_verify_node_proven_by_reads_criteria_count
    write_basics
    write_graph("- v1 needs nothing\n")
    write("nodes/v1.md", <<~MD)
      ---
      node: v1
      kind: verify
      files: []
      budget: 1000
      ---
      # v1 - Adversarial review

      The whole delivery is read by a fresh agent.

      ## Criteria
      - every matrix row has a test that fails before its fix
      - the suite is green with zero failures
      - the additive rule holds in every shared file
    MD
    assert_equal "3 criteria", ReportScreen.proven_by(@dir, "v1")
  end

  # Row 9.4: the criteria path is gated on the node file's own `kind:`
  # envelope field, never guessed from the label prefix and never by
  # sniffing the body for a criteria-shaped list - a work node whose body
  # happens to carry one must still read its matrix, not the list.
  def test_work_node_proven_by_still_reads_matrix_rows
    write_basics
    write_graph("- n1 needs nothing\n")
    write("nodes/n1.md", <<~MD)
      ---
      node: n1
      kind: work
      files: []
      budget: 1000
      ---
      # n1 - Demo unit

      ## Criteria
      - a criterion that happens to sit in a work node's body
      - a second one, so a sniffed count would read 2, not the matrix's 3

      ## n1 failure-mode matrix
      | Row | Operation | Failure mode | Test |
      | --- | --- | --- | --- |
      | 1.1 | a | b | c |
      | 1.2 | d | e | f |
      | 1.3 | g | h | i |
    MD
    assert_nil ReportScreen.verify_node_criteria_count(@dir, "n1"),
               "a work node's kind must gate the criteria path off, even though its body carries a criteria-shaped list"
    assert_equal "3 tests", ReportScreen.proven_by(@dir, "n1")
  end
end
