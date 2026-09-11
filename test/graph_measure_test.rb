# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"

require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/graph_measure"

# Intent 343 (G10), n1: the ledger reader. Matrix rows 1.1-1.32 in
# nodes/n1.md. Hermetic: every fixture lives in its own Dir.mktmpdir, shaped
# like the real intent 340 and 337 ledgers but authored by the test, never
# copied from the store (spec D18).
class GraphMeasureTest < Minitest::Test
  LIB_PATH = File.expand_path("../scripts/lib/graph_measure.rb", __dir__)

  def with_intent_dir
    Dir.mktmpdir("graph-measure-test") do |dir|
      yield dir
    end
  end

  def write_savepoint(dir, lines)
    File.write(File.join(dir, "savepoint.md"), lines.join)
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

  def write_node_file(dir, id, kind)
    FileUtils.mkdir_p(File.join(dir, "nodes"))
    File.write(File.join(dir, "nodes", "#{id}.md"), <<~MD)
      ---
      node: #{id}
      kind: #{kind}
      files: []
      budget: 1000
      ---
      # #{id}
      body
    MD
  end

  # -- fixture line builders, delegating to NodeLedger's own writer ------------

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

  # --- 1.1: delegation to NodeLedger -------------------------------------------

  def test_parsing_delegates_to_node_ledger
    with_intent_dir do |dir|
      write_savepoint(dir, [
        stage(stamp("2026-01-01T00:00:00Z"), "Why", "spec.md created"),
        transition(stamp("2026-01-01T00:01:00Z"), "n1", "running", fields: RUNNING),
        transition(stamp("2026-01-01T00:05:00Z"), "n1", "done",
                   fields: RUNNING.merge(gates: "suite", reason: "two  spaces value")),
      ])
      record = GraphMeasure.read(dir)
      attempt = record[:nodes]["n1"][:attempts].first
      # A hand-rolled second parser using a naive key=value split would either
      # keep the surrounding quotes or truncate at the first embedded space; a
      # correct reader agrees with NodeLedger's own quote-and-escape-aware scan.
      assert_equal "two  spaces value", attempt[:fields]["reason"]
    end
  end

  # --- 1.2 / 1.3: the clock and the scaffold gap -------------------------------

  def test_clock_starts_at_the_first_why_line
    with_intent_dir do |dir|
      what_at = stamp("2026-01-01T00:00:00Z")
      why_at = what_at + (67 * 3600)
      done_at = why_at + 3600
      write_savepoint(dir, [
        stage(what_at, "What", "intent.md"),
        stage(why_at, "Why", "spec.md created"),
        stage(done_at, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      assert_equal why_at, record[:clock][:start]
      refute_equal what_at, record[:clock][:start]
    end
  end

  def test_scaffold_gap_reported_separately
    with_intent_dir do |dir|
      what_at = stamp("2026-01-01T00:00:00Z")
      why_at = what_at + (67 * 3600)
      done_at = why_at + 3600
      write_savepoint(dir, [
        stage(what_at, "What", "intent.md"),
        stage(why_at, "Why", "spec.md created"),
        stage(done_at, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      assert_in_delta 67 * 3600, record[:scaffold][:gap_seconds], 0.001
      # The wall clock excludes the scaffold gap entirely: it is Why-to-Done,
      # not What-to-Done, so it must read 3600s, not 3600 + 67h.
      assert_in_delta 3600, record[:clock][:wall_clock_seconds], 0.001
    end
  end

  # --- 1.4-1.9: attempt spans ---------------------------------------------------

  def test_attempt_span_is_running_to_terminal
    with_intent_dir do |dir|
      why_at = stamp("2026-01-01T00:00:00Z")
      running_at = why_at + 600
      done_at = running_at + 900
      write_savepoint(dir, [
        stage(why_at, "Why", "spec.md created"),
        transition(running_at, "n1", "running", fields: RUNNING),
        transition(done_at, "n1", "done", fields: RUNNING.merge(gates: "suite")),
      ])
      record = GraphMeasure.read(dir)
      attempt = record[:nodes]["n1"][:attempts].first
      assert_in_delta 900, attempt[:span_seconds], 0.001
    end
  end

  def test_all_attempts_recorded
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_savepoint(dir, [
        transition(t0, "n6", "running", fields: RUNNING),
        transition(t0 + 60, "n6", "reclaimed", fields: { holder: "auto-1", expired: "2026-01-01T00:00:30Z" }),
        transition(t0 + 120, "n6", "running", fields: RUNNING),
        transition(t0 + 180, "n6", "failed_verification", fields: RUNNING.merge(gates: "suite", reason: "suite_red")),
        transition(t0 + 240, "n6", "running", fields: RUNNING),
        transition(t0 + 300, "n6", "done", fields: RUNNING.merge(gates: "suite")),
      ])
      record = GraphMeasure.read(dir)
      attempts = record[:nodes]["n6"][:attempts]
      assert_equal 3, attempts.length
      assert_equal %w[reclaimed failed_verification done], attempts.map { |a| a[:terminal_state] }
    end
  end

  def test_reclaimed_closes_an_attempt_without_completing_it
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_savepoint(dir, [
        transition(t0, "n6", "running", fields: RUNNING),
        transition(t0 + 60, "n6", "reclaimed", fields: { holder: "auto-1", expired: "2026-01-01T00:00:30Z" }),
      ])
      record = GraphMeasure.read(dir)
      attempt = record[:nodes]["n6"][:attempts].first
      refute attempt[:completing]
      assert_in_delta 60, attempt[:span_seconds], 0.001
    end
  end

  def test_terminal_without_running_has_no_span
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_savepoint(dir, [
        transition(t0, "n1", "done", fields: { gates: "suite" }),
      ])
      record = GraphMeasure.read(dir)
      attempt = record[:nodes]["n1"][:attempts].first
      assert_nil attempt[:span_seconds]
      assert_equal :no_running, attempt[:span_note]
    end
  end

  def test_two_consecutive_terminals_for_one_subject
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_savepoint(dir, [
        transition(t0, "v1", "done", fields: { gates: "review", verdict: "blockers_found" }),
        transition(t0 + 60, "v1", "done", fields: { holder: "reviewer-1", gates: "review", verdict: "blockers_found" }),
      ])
      record = GraphMeasure.read(dir)
      attempts = record[:nodes]["v1"][:attempts]
      assert_equal 2, attempts.length
      assert(attempts.all? { |a| a[:span_seconds].nil? && a[:span_note] == :no_running })
    end
  end

  def test_open_attempt_excluded_and_named
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_savepoint(dir, [
        transition(t0, "n1", "running", fields: RUNNING),
      ])
      record = GraphMeasure.read(dir, now: t0 + 3600)
      attempt = record[:nodes]["n1"][:attempts].first
      assert_equal :open, attempt[:span_note]
      assert_nil attempt[:span_seconds]
      assert_nil attempt[:active_span_seconds]
    end
  end

  # --- 1.10 / 1.11: torn and unattributed lines --------------------------------

  def test_torn_lines_counted_listed_excluded
    with_intent_dir do |dir|
      torn_line = "2026-01-01T00:00:00Z  n1  running holder=auto-1\n"
      write_savepoint(dir, [torn_line])
      record = GraphMeasure.read(dir)
      assert_equal 1, record[:anomalies][:torn].length
      assert_equal torn_line.chomp, record[:anomalies][:torn].first[:line]
      assert_empty record[:nodes].fetch("n1", { attempts: [] })[:attempts]
    end
  end

  def test_unattributed_counted_separately_from_torn
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_savepoint(dir, [
        transition(t0, "v1", "done", fields: { gates: "review", verdict: "blockers_found" }),
      ])
      record = GraphMeasure.read(dir)
      assert_equal 1, record[:anomalies][:unattributed].length
      assert_empty record[:anomalies][:torn]
    end
  end

  # --- 1.12-1.17: pauses, sessions, reconciliation -----------------------------

  def test_gap_inside_a_running_attempt_is_not_a_pause
    with_intent_dir do |dir|
      why_at = stamp("2026-01-01T00:00:00Z")
      running_at = why_at + 60
      done_at = running_at + (3 * 3600) # a 3-hour gap, well over the 45-minute default
      write_savepoint(dir, [
        stage(why_at, "Why", "spec.md created"),
        transition(running_at, "n1", "running", fields: RUNNING),
        transition(done_at, "n1", "done", fields: RUNNING.merge(gates: "suite")),
        stage(done_at + 60, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      assert_empty record[:pauses]
      assert_in_delta 0, record[:paused_seconds], 0.001
    end
  end

  def test_paused_report_opens_a_pause_at_its_own_stamp
    with_intent_dir do |dir|
      why_at = stamp("2026-01-01T00:00:00Z")
      paused_at = why_at + 600
      resumed_at = paused_at + 7200
      done_at = resumed_at + 60
      write_savepoint(dir, [
        stage(why_at, "Why", "spec.md created"),
        stage(paused_at, "Report", "PAUSED by the orchestrator at the owner's request"),
        transition(resumed_at, "n2", "running", fields: RUNNING),
        stage(done_at, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      pause = record[:pauses].first
      refute_nil pause
      assert_equal paused_at, pause[:start]
      assert_equal resumed_at, pause[:end]
    end
  end

  def test_lock_takeover_closes_a_pause_opened_at_the_previous_line
    with_intent_dir do |dir|
      why_at = stamp("2026-01-01T00:00:00Z")
      prev_at = why_at + 60
      takeover_at = prev_at + 7200
      done_at = takeover_at + 60
      write_savepoint(dir, [
        stage(why_at, "Why", "spec.md created"),
        transition(prev_at, "n4", "running", fields: RUNNING),
        stage(takeover_at, "Lock", "takeover: auto-2 reclaimed delivery lock from auto-1"),
        transition(takeover_at + 30, "n4", "done", fields: RUNNING.merge(gates: "suite")),
        stage(done_at, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      pause = record[:pauses].first
      refute_nil pause
      assert_equal prev_at, pause[:start]
      assert_equal takeover_at, pause[:end]
    end
  end

  def test_gap_threshold_is_named_and_injectable
    with_intent_dir do |dir|
      why_at = stamp("2026-01-01T00:00:00Z")
      t1 = why_at + 60
      t2 = t1 + 600 # a 10-minute gap, under the 45-minute default
      done_at = t2 + 60
      write_savepoint(dir, [
        stage(why_at, "Why", "spec.md created"),
        transition(t1, "n1", "done", fields: { gates: "suite" }),
        transition(t2, "n2", "done", fields: { gates: "suite" }),
        stage(done_at, "Done", "delivered"),
      ])
      default_record = GraphMeasure.read(dir)
      assert_empty default_record[:pauses]

      tight_record = GraphMeasure.read(dir, gap_threshold_minutes: 5)
      refute_empty tight_record[:pauses]
      assert_equal 5.0, tight_record[:gap_threshold_minutes]
    end
  end

  def test_bucket_span_intersects_active_intervals_raw_kept
    with_intent_dir do |dir|
      why_at = stamp("2026-01-01T00:00:00Z")
      n4_running = why_at + 300
      paused_at = n4_running + 600            # 10 minutes into n4's attempt
      n9_running = paused_at + 3600           # closes the pause, 70 minutes into n4's attempt
      n4_done = n9_running + 600              # 80 minutes total raw span for n4
      n9_done = n4_done + 60
      done_at = n9_done + 60
      write_savepoint(dir, [
        stage(why_at, "Why", "spec.md created"),
        transition(n4_running, "n4", "running", fields: RUNNING),
        stage(paused_at, "Report", "PAUSED for the night"),
        transition(n9_running, "n9", "running", fields: RUNNING),
        transition(n4_done, "n4", "done", fields: RUNNING.merge(gates: "suite")),
        transition(n9_done, "n9", "done", fields: RUNNING.merge(gates: "suite")),
        stage(done_at, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      n4_attempt = record[:nodes]["n4"][:attempts].first
      assert_in_delta 80 * 60, n4_attempt[:raw_span_seconds], 0.001
      assert_in_delta 20 * 60, n4_attempt[:active_span_seconds], 0.001
    end
  end

  def test_active_plus_paused_equals_delivery_wall_clock
    with_intent_dir do |dir|
      why_at = stamp("2026-01-01T00:00:00Z")
      paused_at = why_at + 600
      resumed_at = paused_at + 7200
      done_at = resumed_at + 60
      write_savepoint(dir, [
        stage(why_at, "Why", "spec.md created"),
        stage(paused_at, "Report", "PAUSED by the orchestrator"),
        transition(resumed_at, "n2", "running", fields: RUNNING),
        transition(resumed_at + 30, "n2", "done", fields: RUNNING.merge(gates: "suite")),
        stage(done_at, "Done", "delivered"),
      ])
      record = GraphMeasure.read(dir)
      assert_in_delta record[:clock][:wall_clock_seconds], record[:active_seconds] + record[:paused_seconds], 0.001
    end
  end

  # --- 1.18-1.20: kind and foldness ---------------------------------------------

  def test_kind_comes_from_the_node_file
    with_intent_dir do |dir|
      # A node file's declared kind wins even where it conflicts with what the
      # id's own prefix would suggest: the id-prefix guesser would call "v2"
      # verification, but the envelope says work.
      write_node_file(dir, "v2", "work")
      write_graph(dir, "- v2 needs nothing")
      write_savepoint(dir, [
        transition(stamp("2026-01-01T00:00:00Z"), "v2", "done", fields: { gates: "suite" }),
      ])
      record = GraphMeasure.read(dir)
      assert_equal "work", record[:nodes]["v2"][:kind]
      assert_equal :node_file, record[:nodes]["v2"][:kind_source]
    end
  end

  def test_kind_fallback_reuses_node_file_prefix_and_is_flagged
    with_intent_dir do |dir|
      write_graph(dir, "- n1 needs nothing\n- v3 needs nothing\n- d2 needs nothing\n- r4 needs nothing")
      write_savepoint(dir, [])
      record = GraphMeasure.read(dir)
      assert_equal ["work", :fallback], [record[:nodes]["n1"][:kind], record[:nodes]["n1"][:kind_source]]
      assert_equal ["verify", :fallback], [record[:nodes]["v3"][:kind], record[:nodes]["v3"][:kind_source]]
      assert_equal ["decision", :fallback], [record[:nodes]["d2"][:kind], record[:nodes]["d2"][:kind_source]]
      assert_equal ["research", :fallback], [record[:nodes]["r4"][:kind], record[:nodes]["r4"][:kind_source]]
      # The fallback table is reused, never restated as a second literal map.
      assert_includes File.read(LIB_PATH), "NodeFile::KIND_PREFIX"
    end
  end

  def test_fold_classification_is_transitive
    with_intent_dir do |dir|
      write_graph(dir, <<~GRAPH)
        - n9 needs v1
        - n10 needs n9
        - n11 needs nothing
        - v1 needs nothing
      GRAPH
      write_savepoint(dir, [])
      record = GraphMeasure.read(dir)
      assert record[:nodes]["n9"][:fold], "n9 needs v1 directly and must fold"
      assert record[:nodes]["n10"][:fold], "n10 reaches v1 transitively through n9 and must fold"
      refute record[:nodes]["n11"][:fold], "n11 never reaches a verify node and must not fold"
    end
  end

  # --- 1.21-1.24: suite parsing --------------------------------------------------

  def test_four_field_suite_parses_as_runs_assertions_failures_errors
    with_intent_dir do |dir|
      write_savepoint(dir, [
        transition(stamp("2026-01-01T00:00:00Z"), "n1", "done", fields: { gates: "suite", suite: "100/200/1/2" }),
      ])
      record = GraphMeasure.read(dir)
      suite = record[:nodes]["n1"][:attempts].first[:suite]
      assert_equal({ runs: 100, assertions: 200, failures: 1, errors: 2, form: :four_field }, suite)
    end
  end

  def test_two_field_suite_parses_as_runs_and_failures
    with_intent_dir do |dir|
      write_savepoint(dir, [
        transition(stamp("2026-01-01T00:00:00Z"), "n1", "done", fields: { gates: "suite", suite: "16/0" }),
      ])
      record = GraphMeasure.read(dir)
      suite = record[:nodes]["n1"][:attempts].first[:suite]
      assert_equal 16, suite[:runs]
      assert_equal 0, suite[:failures]
      assert_equal :unavailable, suite[:assertions]
    end
  end

  def test_done_without_suite_is_unavailable_not_zero
    with_intent_dir do |dir|
      write_savepoint(dir, [
        transition(stamp("2026-01-01T00:00:00Z"), "n1", "done", fields: { gates: "suite" }),
      ])
      record = GraphMeasure.read(dir)
      assert_equal :unavailable, record[:nodes]["n1"][:attempts].first[:suite]
    end
  end

  def test_suite_growth_skips_done_lines_without_suite
    with_intent_dir do |dir|
      t0 = stamp("2026-01-01T00:00:00Z")
      write_savepoint(dir, [
        transition(t0, "n1", "done", fields: { gates: "suite" }),
        transition(t0 + 60, "n2", "done", fields: { gates: "suite" }),
        transition(t0 + 120, "n3", "done", fields: { gates: "suite", suite: "3886/19751/0/0" }),
        transition(t0 + 180, "n4", "done", fields: { gates: "suite", suite: "3921/19893/0/0" }),
      ])
      record = GraphMeasure.read(dir)
      history = record[:suite_history]
      assert_equal 2, history.length
      assert_equal :unavailable, history[0][:growth]
      assert_equal({ runs: 35, failures: 0, assertions: 142, errors: 0 }, history[1][:growth])
    end
  end

  # --- 1.25 / 1.26: model and hop -------------------------------------------------

  def test_absent_model_is_unavailable_not_blank
    with_intent_dir do |dir|
      write_savepoint(dir, [
        transition(stamp("2026-01-01T00:00:00Z"), "v1", "done", fields: { gates: "review", verdict: "blockers_found" }),
      ])
      record = GraphMeasure.read(dir)
      assert_equal :unavailable, record[:nodes]["v1"][:model]
    end
  end

  def test_absent_hop_is_unavailable_not_hop_off
    with_intent_dir do |dir|
      # Ledger A: hop= never appears anywhere - this whole intent predates the
      # field, so the node's hop status is unavailable, never "off".
      write_savepoint(dir, [
        transition(stamp("2026-01-01T00:00:00Z"), "n1", "running", fields: RUNNING),
        transition(stamp("2026-01-01T00:10:00Z"), "n1", "done", fields: RUNNING.merge(gates: "suite")),
      ])
      record_a = GraphMeasure.read(dir)
      assert_equal :unavailable, record_a[:nodes]["n1"][:hop]
    end

    with_intent_dir do |dir|
      # Ledger B: hop= appears elsewhere in this intent, so n1's own running
      # line lacking it is genuinely hop off, not unavailable.
      write_savepoint(dir, [
        transition(stamp("2026-01-01T00:00:00Z"), "n1", "running", fields: RUNNING),
        transition(stamp("2026-01-01T00:10:00Z"), "n1", "done", fields: RUNNING.merge(gates: "suite")),
        transition(stamp("2026-01-01T00:20:00Z"), "n2", "running", fields: RUNNING.merge(hop: "2000")),
        transition(stamp("2026-01-01T00:30:00Z"), "n2", "done", fields: RUNNING.merge(gates: "suite", hop: "2000")),
      ])
      record_b = GraphMeasure.read(dir)
      assert_equal false, record_b[:nodes]["n1"][:hop]
      assert_equal 2000, record_b[:nodes]["n2"][:hop]
    end
  end

  # --- 1.27: file order, never timestamp order ------------------------------------

  def test_file_order_not_timestamp_order
    with_intent_dir do |dir|
      # The second "Why" line's own timestamp is EARLIER than the first, but it
      # appears LATER in the file - mirroring 337's stage lines following its
      # first node lines. The clock must use the first Why line IN THE FILE.
      first_why = stamp("2026-01-01T10:00:00Z")
      second_why_earlier_stamp = stamp("2026-01-01T09:00:00Z")
      write_savepoint(dir, [
        stage(first_why, "Why", "started"),
        stage(second_why_earlier_stamp, "Why", "spec.md created"),
      ])
      record = GraphMeasure.read(dir)
      assert_equal first_why, record[:clock][:start]
    end
  end

  # --- 1.28: frozen record ---------------------------------------------------------

  def test_record_is_frozen
    with_intent_dir do |dir|
      write_savepoint(dir, [
        transition(stamp("2026-01-01T00:00:00Z"), "n1", "running", fields: RUNNING),
      ])
      record = GraphMeasure.read(dir)
      assert record.frozen?
      assert record[:nodes].frozen?
      assert record[:nodes]["n1"][:attempts].frozen?
      assert record[:nodes]["n1"][:attempts].first.frozen?
      assert_raises(FrozenError) { record[:extra] = 1 }
      assert_raises(FrozenError) { record[:nodes]["extra"] = 1 }
    end
  end

  # --- 1.29: no environment read, every seam injected -------------------------------

  def test_no_environment_read_every_seam_injected
    refute_match(/ENV\[/, File.read(LIB_PATH), "GraphMeasure must read no environment variable")

    with_intent_dir do |dir|
      write_savepoint(dir, [
        transition(stamp("2026-01-01T00:00:00Z"), "n1", "running", fields: RUNNING),
      ])
      before = ENV["GRAPH_MEASURE_TEST_POISON"]
      ENV["GRAPH_MEASURE_TEST_POISON"] = "poisoned"
      ENV["PLASTIC_HOME"] = "/nonexistent/poisoned/home"
      begin
        record = GraphMeasure.read(dir, now: stamp("2026-01-01T00:05:00Z"))
        assert_equal :open, record[:nodes]["n1"][:attempts].first[:span_note]
      ensure
        ENV.delete("PLASTIC_HOME")
        if before
          ENV["GRAPH_MEASURE_TEST_POISON"] = before
        else
          ENV.delete("GRAPH_MEASURE_TEST_POISON")
        end
      end
    end
  end

  # --- 1.30: invalid UTF-8 in graph.md and node files ----------------------------

  def test_invalid_utf8_in_graph_and_node_files_never_raises
    with_intent_dir do |dir|
      FileUtils.mkdir_p(File.join(dir, "nodes"))
      bad_byte = "\xFF".dup.force_encoding("UTF-8")
      File.write(File.join(dir, "graph.md"), <<~MD.dup.force_encoding("UTF-8"))
        # Graph: test fixture

        ## Graph
        - n1 needs nothing#{bad_byte}
      MD
      File.write(File.join(dir, "nodes", "n1.md"), <<~MD.dup.force_encoding("UTF-8"))
        ---
        node: n1
        kind: work
        files: []
        budget: 1000
        ---
        # n1
        bad byte here -> #{bad_byte} <-
      MD
      write_savepoint(dir, [
        transition(stamp("2026-01-01T00:00:00Z"), "n1", "done", fields: { gates: "suite" }),
      ])

      record = GraphMeasure.read(dir)
      assert record[:ok]
      assert_equal "work", record[:nodes]["n1"][:kind]
    end
  end

  # --- 1.31: missing or empty savepoint.md ----------------------------------------

  def test_missing_savepoint_returns_empty_record
    with_intent_dir do |dir|
      record = GraphMeasure.read(dir)
      assert record[:ok]
      assert_empty record[:nodes]
      assert_nil record[:clock][:start]
    end

    with_intent_dir do |dir|
      File.write(File.join(dir, "savepoint.md"), "")
      record = GraphMeasure.read(dir)
      assert record[:ok]
      assert_empty record[:nodes]
    end
  end
end
