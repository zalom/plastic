# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require "json"

require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/graph_measure"
require_relative "../scripts/lib/graph_measure_report"

# GraphMeasureReportTest (intent 343, G10, n2): GraphMeasureReport, the two
# renderers over one `GraphMeasure.read` record. Matrix rows 2.7-2.13,
# 2.15, 2.16, 2.18 in nodes/n2.md. Hermetic: every fixture lives in its own
# Dir.mktmpdir, authored by this test (spec D18); rows 2.9 and 2.10 build the
# synthetic declared-vs-ledger mismatch neither real ledger produces.
class GraphMeasureReportTest < Minitest::Test
  # n4's verify-cost rows (4.12-4.14) read the real intent 340 and 337
  # fixtures the n3 dogfood already copied in (spec D18: a row a real ledger
  # produces is checked against that real ledger, never a stand-in).
  FIXTURES = File.expand_path("fixtures/ledgers", __dir__)
  DIR_340 = File.join(FIXTURES, "340--runner-core-in-session")
  DIR_337 = File.join(FIXTURES, "337--roadmap-graph")

  def with_intent_dir
    Dir.mktmpdir("graph-measure-report-test") do |dir|
      yield dir
    end
  end

  def write_savepoint(dir, lines)
    File.write(File.join(dir, "savepoint.md"), Array(lines).join)
  end

  def write_graph(dir, edges_body)
    File.write(File.join(dir, "graph.md"), <<~MD)
      # Graph: test fixture

      ## Goal
      fixture

      ## Decisions
      - none

      ## Graph
      #{edges_body}

      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
  end

  def stamp(str)
    Time.iso8601(str)
  end

  def stage(ts, subject, text)
    "#{ts.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}  #{subject}  #{text}\n"
  end

  def transition(ts, subject, state, fields: {}, comment: nil)
    NodeLedger.transition_line(subject: subject, state: state, fields: fields, comment: comment, now: ts)
  end

  RUNNING = { holder: "auto-1", expires: "2099-01-01T00:00:00Z", packet: "abc123", model: "sonnet" }.freeze

  # --- 2.7: the wall-clock block separates the scaffold gap --------------------

  def test_wall_clock_block_separates_scaffold_gap
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_savepoint(dir, [
        stage(t0 - 7200, "What", "spec.md scaffolded"), # 2h before Why
        stage(t0, "Why", "spec.md created"),
        transition(t0 + 60, "n1", "running", fields: RUNNING),
        transition(t0 + 600, "n1", "done", fields: RUNNING.merge(gates: "suite", commit: "abc1234")),
        stage(t0 + 600, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      text = GraphMeasureReport.render_text(record)

      # Delivery total is Why-to-Done, 10 minutes; the What-to-Why gap is 2h,
      # reported separately and never counted inside the total.
      assert_match(/delivery total: 10\.0 min/, text)
      assert_match(/scaffold gap.*: 120\.0 min/, text)
      refute_match(/delivery total: 130\.0 min/, text)

      m = GraphMeasureReport.model(record)
      assert_in_delta 600.0, m[:wall_clock]["delivery_total_seconds"], 0.001
      assert_in_delta 7200.0, m[:wall_clock]["scaffold_gap_seconds"], 0.001
    end
  end

  # --- 2.8: session rows name their boundary evidence ---------------------------

  def test_session_rows_name_their_boundary_evidence
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_savepoint(dir, [
        stage(t0, "Why", "spec.md created"),
        stage(t0 + 600, "Report", "PAUSED waiting on owner"),
        "#{(t0 + 4200).utc.strftime('%Y-%m-%dT%H:%M:%SZ')}  Lock  takeover: session-2 by auto-2\n",
        stage(t0 + 4800, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      m = GraphMeasureReport.model(record)
      sessions = m[:sessions]

      assert_equal 2, sessions.length
      assert_equal "why line (delivery start)", sessions[0]["start_evidence"]
      assert_equal "pause opened by paused_report", sessions[0]["end_evidence"]
      # The Lock takeover line's own branch would name closed_by :lock_takeover,
      # but here it immediately follows the PAUSED report line with nothing
      # between them, so the PAUSED report's own candidate (open at its own
      # stamp, close at the next ledger line) is the one that survives the
      # merge (spec D5.3's two evidence kinds bound the SAME gap here).
      assert_equal "pause closed by next_line", sessions[1]["start_evidence"]
      assert_equal "done line (delivery end)", sessions[1]["end_evidence"]

      text = GraphMeasureReport.render_text(record)
      assert_match(/why line \(delivery start\)/, text)
      assert_match(/pause opened by paused_report/, text)
      assert_match(/pause closed by next_line/, text)
      assert_match(/done line \(delivery end\)/, text)
    end
  end

  # --- 2.9: a declared node the ledger never names still renders (D18) ---------

  def test_declared_node_without_ledger_line_still_renders
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_graph(dir, "- n1 needs nothing\n- n2 needs n1\n")
      write_savepoint(dir, [
        stage(t0, "Why", "spec.md created"),
        transition(t0 + 60, "n1", "running", fields: RUNNING),
        transition(t0 + 600, "n1", "done", fields: RUNNING.merge(gates: "suite", commit: "abc1234")),
        stage(t0 + 600, "Done", "delivered"),
      ])
      # graph.md declares n2, but no ledger line ever names it: on both real
      # ledgers (340, 337) the declared set exactly equals the named set, so
      # without this fixture the row would pass vacuously.
      record = GraphMeasure.read(dir)
      assert_empty record[:nodes]["n2"][:attempts]

      nodes = GraphMeasureReport.model(record)[:nodes]
      n2 = nodes.find { |n| n["id"] == "n2" }
      refute_nil n2, "expected declared-only node n2 to appear in the report"
      assert_equal "planned", n2["status"]
      assert_equal "unavailable", n2["model"]
      assert_empty n2["attempts"]

      text = GraphMeasureReport.render_text(record)
      assert_match(/\|\s*n2\s*\|.*\|\s*planned\s*\|\s*unavailable\s*\|/, text)
    end
  end

  # --- 2.10: a ledger-named node graph.md never declares still renders (D18) --

  def test_undeclared_ledger_node_still_renders
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_graph(dir, "- n1 needs nothing\n")
      write_savepoint(dir, [
        stage(t0, "Why", "spec.md created"),
        transition(t0 + 60, "n1", "running", fields: RUNNING),
        transition(t0 + 600, "n1", "done", fields: RUNNING.merge(gates: "suite", commit: "abc1234")),
        # n2 ran and completed but was never declared in graph.md's ## Graph
        # section (a hand-written node): on both real ledgers this never
        # happens, so without this fixture the row would pass vacuously.
        transition(t0 + 700, "n2", "running", fields: RUNNING),
        transition(t0 + 900, "n2", "done", fields: RUNNING.merge(gates: "suite", commit: "def5678")),
        stage(t0 + 900, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      nodes = GraphMeasureReport.model(record)[:nodes]
      n2 = nodes.find { |n| n["id"] == "n2" }
      refute_nil n2, "expected undeclared ledger node n2 to appear in the report"
      assert_equal "done", n2["status"]
      refute_empty n2["attempts"]

      text = GraphMeasureReport.render_text(record)
      assert_match(/\|\s*n2\s*\|/, text)
    end
  end

  # --- 2.11: an attempt's active span and raw span both render, side by side --

  def test_active_and_raw_span_both_rendered
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_savepoint(dir, [
        stage(t0, "Why", "spec.md created"),
        transition(t0 + 60, "n1", "running", fields: RUNNING),
        stage(t0 + 300, "Report", "PAUSED waiting on owner"), # pause opens 5 min in
        "#{(t0 + 3900).utc.strftime('%Y-%m-%dT%H:%M:%SZ')}  Lock  takeover: session-2 by auto-2\n", # closes 60 min later
        transition(t0 + 4200, "n1", "done", fields: RUNNING.merge(gates: "suite", commit: "abc1234")),
        stage(t0 + 4260, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      node = GraphMeasureReport.model(record)[:nodes].find { |n| n["id"] == "n1" }
      attempt = node["attempts"].first

      # raw: running (t0+60) to done (t0+4200) = 69 minutes.
      assert_in_delta 4140.0, attempt["raw_span_seconds"], 0.001
      # active: (t0+60..t0+300) + (t0+3900..t0+4200) = 4 + 5 = 9 minutes.
      assert_in_delta 540.0, attempt["active_span_seconds"], 0.001
      refute_equal attempt["raw_span_seconds"], attempt["active_span_seconds"]

      text = GraphMeasureReport.render_text(record)
      # Two leading spaces distinguish an attempt sub-table row from a
      # top-level session row, which also starts "| 1 | ...".
      row = text.lines.find { |l| l.start_with?("  | 1 |") }
      refute_nil row, "expected an attempt row in: #{text}"
      columns = row.split("|").map(&:strip).reject(&:empty?)
      assert_equal "69.0", columns[3], "raw span column: #{row.inspect}"
      assert_equal "9.0", columns[4], "active span column: #{row.inspect}"
    end
  end

  # --- 2.12: a measure with no source prints "unavailable", never blank/zero -

  def test_unavailable_printed_not_blank_not_zero
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_savepoint(dir, [
        stage(t0, "Why", "spec.md created"),
        # A terminal line with no preceding running line: "done" does not
        # require model=, so this attempt carries no model at all.
        transition(t0 + 60, "n1", "done", fields: { gates: "suite", commit: "abc1234" }),
        stage(t0 + 60, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      node = GraphMeasureReport.model(record)[:nodes].find { |n| n["id"] == "n1" }
      assert_equal "unavailable", node["model"]

      text = GraphMeasureReport.render_text(record)
      row = text.lines.find { |l| l.strip.start_with?("| n1 |") }
      refute_nil row
      assert_includes row, "unavailable"
      refute_match(/\|\s*0\s*\|/, row)
      refute_match(/\|\s*\|/, row) # no empty cell
    end
  end

  # --- 2.13: buckets sum to active time, and the report states that ----------

  def test_buckets_sum_to_active_time
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_graph(dir, "- v1 needs nothing\n- n1 needs nothing\n- n2 needs v1\n")
      write_savepoint(dir, [
        stage(t0, "Why", "spec.md created"),
        transition(t0 + 60, "v1", "running", fields: RUNNING),
        transition(t0 + 600, "v1", "done", fields: RUNNING.merge(gates: "suite", verdict: "approve")),
        transition(t0 + 660, "n1", "running", fields: RUNNING),
        transition(t0 + 1800, "n1", "done", fields: RUNNING.merge(gates: "suite", commit: "aaa1111")),
        transition(t0 + 1860, "n2", "running", fields: RUNNING),
        transition(t0 + 3000, "n2", "done", fields: RUNNING.merge(gates: "suite", commit: "bbb2222")),
        stage(t0 + 3060, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      buckets = GraphMeasureReport.model(record)[:buckets]

      assert_in_delta 540.0, buckets["verify"], 0.001   # v1: 60..600
      assert_in_delta 1140.0, buckets["build"], 0.001   # n1: 660..1800, not a review fix
      assert_in_delta 1140.0, buckets["review_fix"], 0.001 # n2: 1860..3000, needs v1
      assert_in_delta 240.0, buckets["lead"], 0.001      # the four terminal-to-running gaps, 60s each
      assert_equal true, buckets["sums_to_active"]
      sum = buckets["build"] + buckets["verify"] + buckets["review_fix"] + buckets["lead"]
      assert_in_delta buckets["active_seconds"], sum, 0.001

      text = GraphMeasureReport.render_text(record)
      assert_match(/sum equals active time.*: true/, text)
    end
  end

  # --- 9.3 (v2 NEW-3): an absent kind renders zero, an unmeasured kind renders unavailable --

  # v2's review (NEW-3): `contributed` could only track whether a bucket
  # HAD a measured span, so it could not tell "no node of this kind exists
  # in this intent at all" from "nodes of this kind exist, none of their
  # attempts ever carried a measured span" - both rendered "unavailable".
  # Reproduced by hand before this fix, against a hermetic one-node
  # work-only intent with no verify node and no review-fix node anywhere:
  # the build bucket read 30.0 minutes while the other two both read
  # unavailable, though the report's own node table proves neither of those
  # two kinds exists at all.
  def test_absent_kind_renders_zero_and_unmeasured_renders_unavailable
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T09:00:00Z")
      write_savepoint(dir, [
        stage(t0, "Why", "spec.md created"),
        transition(t0 + 60, "n1", "running", fields: RUNNING),
        transition(t0 + 1860, "n1", "done", fields: RUNNING.merge(gates: "suite", commit: "abc1234")),
        stage(t0 + 1920, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      buckets = GraphMeasureReport.model(record)[:buckets]
      assert_equal 0.0, buckets["verify"], "no verify node exists anywhere in this intent; that is a real zero"
      assert_equal 0.0, buckets["review_fix"],
                   "no review-fix node exists anywhere in this intent; that is a real zero"
    end

    record = GraphMeasure.read(DIR_337)
    buckets = GraphMeasureReport.model(record)[:buckets]
    assert_equal "unavailable", buckets["verify"],
                 "337 has a verify node (v1) whose only attempt never carries a running line, so its " \
                 "span was never measured - unmeasured, never absent"
    assert_equal "unavailable", buckets["build"],
                 "337's work nodes exist but none of them ever carries a running line either"
  end

  # --- 9.5 (owner ruling): the node and bucket keys are exactly the named set --

  # Asserted positively (a complete, sorted key set), never by grepping a
  # source file for the retired word: the renamed key is proved present,
  # and the retired key is proved gone because it is absent from the set.
  def test_bucket_and_node_keys_are_exactly_the_named_set
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_graph(dir, "- v1 needs nothing\n- n1 needs nothing\n- n2 needs v1\n")
      write_savepoint(dir, [
        stage(t0, "Why", "spec.md created"),
        transition(t0 + 60, "v1", "running", fields: RUNNING),
        transition(t0 + 600, "v1", "done", fields: RUNNING.merge(gates: "suite", verdict: "approve")),
        transition(t0 + 660, "n1", "running", fields: RUNNING),
        transition(t0 + 1800, "n1", "done", fields: RUNNING.merge(gates: "suite", commit: "aaa1111")),
        transition(t0 + 1860, "n2", "running", fields: RUNNING),
        transition(t0 + 3000, "n2", "done", fields: RUNNING.merge(gates: "suite", commit: "bbb2222")),
        stage(t0 + 3060, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      m = GraphMeasureReport.model(record)

      assert_equal %w[active_seconds build lead review_fix sums_to_active verify].sort, m[:buckets].keys.sort
      node = m[:nodes].find { |n| n["id"] == "n2" }
      assert_equal %w[attempts hop id kind kind_source model review_fix status].sort, node.keys.sort
      assert_equal true, node["review_fix"], "n2 needs v1 directly and must be classified a review fix"
    end
  end

  # --- 2.15: a pipe in a comment does not break the table -----------------------

  def test_pipe_in_comment_does_not_break_the_table
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_savepoint(dir, [
        stage(t0, "Why", "spec.md created"),
        transition(t0 + 60, "n1", "running", fields: RUNNING),
        transition(t0 + 600, "n1", "done", fields: RUNNING.merge(gates: "suite", commit: "abc1234"),
                   comment: "result: a|b|c pipe test"),
        stage(t0 + 600, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      node = GraphMeasureReport.model(record)[:nodes].find { |n| n["id"] == "n1" }
      comment = node["attempts"].first["comment"]
      refute_includes comment, "|"
      assert_includes comment, "a/b/c"

      text = GraphMeasureReport.render_text(record)
      row = text.lines.find { |l| l.include?("a/b/c") }
      refute_nil row
      assert_equal 7, row.count("|"), "a pipe in the comment must not add extra table columns: #{row.inspect}"
    end
  end

  # --- 2.16: a very long comment renders safely ---------------------------------

  def test_long_comment_is_rendered_safely
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      long_comment = "x" * 310
      write_savepoint(dir, [
        stage(t0, "Why", "spec.md created"),
        transition(t0 + 60, "n1", "running", fields: RUNNING),
        transition(t0 + 600, "n1", "failed_verification",
                   fields: RUNNING.merge(gates: "suite", reason: "cap-test"), comment: long_comment),
        stage(t0 + 600, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)

      text = nil
      assert_silent_of_exception { text = GraphMeasureReport.render_text(record) }

      node = GraphMeasureReport.model(record)[:nodes].find { |n| n["id"] == "n1" }
      comment = node["attempts"].first["comment"]
      assert_operator comment.length, :<=, 200
      assert comment.end_with?("..."), "expected the capped comment to end with an ellipsis"

      row = text.lines.find { |l| l.include?(comment) }
      refute_nil row
      assert_operator row.length, :<=, 260, "expected the comment to be capped, not left as one unwrapped line"
    end
  end

  def assert_silent_of_exception
    yield
  rescue StandardError => e
    flunk "expected no exception, got #{e.class}: #{e.message}"
  end

  # --- 2.18: JSON and text carry the same numbers, from the one record ---------

  def test_json_and_text_share_one_record
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_savepoint(dir, [
        stage(t0, "Why", "spec.md created"),
        transition(t0, "n1", "running", fields: RUNNING),
        transition(t0 + 600, "n1", "done", fields: RUNNING.merge(gates: "suite", commit: "abc1234")),
        stage(t0 + 600, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      text = GraphMeasureReport.render_text(record)
      json = JSON.parse(GraphMeasureReport.render_json(record))

      assert_in_delta 600.0, json["wall_clock"]["delivery_total_seconds"], 0.001
      assert_match(/delivery total: 10\.0 min/, text)

      json_attempt = json["nodes"].find { |n| n["id"] == "n1" }["attempts"].first
      assert_in_delta 600.0, json_attempt["raw_span_seconds"], 0.001

      # Both renderings are built from the exact same model, never recomputed
      # independently: the model itself is the single source both read.
      assert_equal JSON.generate(GraphMeasureReport.model(record)), GraphMeasureReport.render_json(record)
    end
  end

  # --- 4.12: verify cost, the verify nodes' total active span and share ---------

  def test_verify_cost_span_and_share
    record = GraphMeasure.read(DIR_340)
    vc = GraphMeasureReport.model(record)[:verify_cost]

    assert_in_delta 3903.0, vc["total_active_span_seconds"], 0.001
    assert_in_delta 65.05, vc["total_active_span_seconds"] / 60.0, 0.01
    assert_in_delta 0.1271, vc["share_of_active_time"], 0.001

    text = GraphMeasureReport.render_text(record)
    assert_match(/== Verify cost ==/, text)
    assert_match(/65\.1? ?min|65\.0 min/, text)
  end

  # --- 4.13: verify cost is unavailable without a single running line -----------

  def test_verify_cost_unavailable_without_running_lines
    record = GraphMeasure.read(DIR_337)
    vc = GraphMeasureReport.model(record)[:verify_cost]

    assert_equal "unavailable", vc["total_active_span_seconds"]
    assert_equal "unavailable", vc["share_of_active_time"]

    text = GraphMeasureReport.render_text(record)
    assert_match(/== Verify cost ==/, text)
    assert_match(/unavailable/, text)
  end

  # --- 4.14: each verify node's verdict is shown beside its cost -----------------

  def test_verify_verdicts_beside_cost
    record = GraphMeasure.read(DIR_340)
    nodes = GraphMeasureReport.model(record)[:verify_cost]["nodes"]

    v1 = nodes.find { |n| n["id"] == "v1" }
    assert_equal "revise", v1["verdict"]
    assert_operator v1["active_span_seconds"], :>, 0

    v3 = nodes.find { |n| n["id"] == "v3" }
    assert_equal "accept", v3["verdict"]

    # 337 has no running line anywhere, so v1's cost is unavailable, but its
    # verdict (written on the terminal line alone) still shows beside it -
    # the cost of a review is never shown without what the review found.
    record_337 = GraphMeasure.read(DIR_337)
    nodes_337 = GraphMeasureReport.model(record_337)[:verify_cost]["nodes"]
    v1_337 = nodes_337.find { |n| n["id"] == "v1" }
    assert_equal "blockers_found", v1_337["verdict"]
    assert_equal "unavailable", v1_337["active_span_seconds"]
  end
end
