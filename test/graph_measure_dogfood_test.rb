# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "digest"
require "json"
require "open3"
require "time"

require_relative "../scripts/lib/graph_measure"
require_relative "../scripts/lib/graph_measure_report"

# GraphMeasureDogfoodTest (intent 343, G10, n3): the try-out. Runs the real
# `scripts/graph-measure` command, through `GraphMeasure.read` and through the
# subprocess, against two real delivery ledgers copied verbatim into
# test/fixtures/ledgers/ (intent 340, G7 of the graph-ready plan, and intent
# 337, the roadmap graph model). Matrix rows 3.1-3.24 in nodes/n3.md.
#
# Unlike test/graph_measure_test.rb and test/graph_measure_report_test.rb,
# this file's fixtures are NOT authored by the test (spec D18's synthetic
# rows live in their own future node): every number asserted here is a real
# number from a real ledger, checked by hand against the raw file before it
# became an assertion (see the dogfood transcript at
# resources/dogfood--graph-measure-2026-09-11.md for the arithmetic).
class GraphMeasureDogfoodTest < Minitest::Test
  FIXTURES = File.expand_path("fixtures/ledgers", __dir__)
  DIR_340 = File.join(FIXTURES, "340--runner-core-in-session")
  DIR_337 = File.join(FIXTURES, "337--roadmap-graph")
  SCRIPT = File.expand_path("../scripts/graph-measure", __dir__)

  # GraphMeasure.read is pure and side-effect free (spec D2); reading the same
  # real fixture twice across many tests is cheap and there is no seam to
  # inject, so each test re-reads rather than sharing mutable state.
  def record_340
    GraphMeasure.read(DIR_340)
  end

  def record_337
    GraphMeasure.read(DIR_337)
  end

  def minutes(seconds)
    seconds / 60.0
  end

  # --- 3.1: the fixtures themselves --------------------------------------------

  def test_fixtures_are_verbatim_copies_with_packets_and_nodes
    src_340 = "/Users/zlatko/.plastic/projects/plastic/store/340--runner-core-in-session"
    src_337 = "/Users/zlatko/.plastic/projects/plastic/store/337--roadmap-graph"
    skip "source store 340 not present on this machine" unless Dir.exist?(src_340)
    skip "source store 337 not present on this machine" unless Dir.exist?(src_337)

    assert_equal File.read(File.join(src_340, "savepoint.md")), File.read(File.join(DIR_340, "savepoint.md"))
    assert_equal File.read(File.join(src_340, "graph.md")), File.read(File.join(DIR_340, "graph.md"))
    assert_equal File.read(File.join(src_337, "savepoint.md")), File.read(File.join(DIR_337, "savepoint.md"))

    assert Dir.exist?(File.join(DIR_340, "packets")), "340's packets/ must be copied in (n4's budget rows need it)"
    assert_operator Dir.glob(File.join(DIR_340, "packets", "*")).length, :>, 0
    src_packets = Dir.glob(File.join(src_340, "packets", "*")).map { |f| File.basename(f) }.sort
    dst_packets = Dir.glob(File.join(DIR_340, "packets", "*")).map { |f| File.basename(f) }.sort
    assert_equal src_packets, dst_packets

    assert Dir.exist?(File.join(DIR_337, "nodes")), "337's nodes/ must be copied in (its only kind: research node)"
    research_files = Dir.glob(File.join(DIR_337, "nodes", "*.md")).select { |f| File.read(f).include?("kind: research") }
    assert_equal 1, research_files.length, "337's nodes/ must carry exactly one kind: research node (r1.md)"
    assert_equal "r1.md", File.basename(research_files.first)
  end

  # --- 3.2: 340's delivery wall clock -------------------------------------------

  def test_340_delivery_clock_and_scaffold_gap
    r = record_340
    assert_equal :why, r[:clock][:anchor]
    assert_equal Time.iso8601("2026-09-10T05:43:13Z"), r[:clock][:start]
    assert_equal Time.iso8601("2026-09-11T04:20:04Z"), r[:clock][:end]
    # 22h 36m 51s, not the 89.63h a What-anchored clock would read.
    assert_in_delta 81_411.0, r[:clock][:wall_clock_seconds], 0.01
    assert_in_delta 22 * 3600 + 36 * 60 + 51, r[:clock][:wall_clock_seconds], 0.01

    # The 67-hour What-to-Why scaffold gap, reported separately, never folded
    # into the delivery total above.
    assert_in_delta 67.0, r[:scaffold][:gap_seconds] / 3600.0, 0.02
  end

  # --- 3.3: three sessions, two pauses ------------------------------------------

  def test_340_three_sessions_two_pauses
    r = record_340
    assert_equal 3, r[:sessions].length
    assert_equal 2, r[:pauses].length
    # None of the gap rule's known trip points (inside n6's own attempt span,
    # inside n9, inside n10) produced an extra pause: a running attempt spans
    # each of them and the generic gap rule stays silent there.
    total_active = r[:sessions].sum { |s| s[:end] - s[:start] }
    assert_in_delta total_active, r[:active_seconds], 0.01
    # 182 minutes of n6's own busiest attempt (raw span) must NOT all land in
    # "paused": its active (session-intersected) span is a small fraction of
    # its raw span, not zero.
    n6_attempt1 = r[:nodes]["n6"][:attempts][0]
    assert_operator n6_attempt1[:active_span_seconds], :<, n6_attempt1[:raw_span_seconds]
  end

  # --- 3.4: name the evidence and the end it bounded ----------------------------

  def test_340_boundaries_name_evidence_and_which_end
    r = record_340
    lock_takeover_pause = r[:pauses].find { |p| p[:closed_by] == :lock_takeover }
    refute_nil lock_takeover_pause, "the Lock takeover: pause must be present"
    assert_equal Time.iso8601("2026-09-10T13:01:47Z"), lock_takeover_pause[:end]

    paused_report_pause = r[:pauses].find { |p| p[:opened_by] == :paused_report }
    refute_nil paused_report_pause, "the PAUSED report pause must be present"
    assert_equal Time.iso8601("2026-09-10T13:50:47Z"), paused_report_pause[:start]

    m = GraphMeasureReport.model(r)
    session2 = m[:sessions][1]
    assert_equal "pause closed by lock_takeover", session2["start_evidence"]
    session2_end = m[:sessions][1]["end_evidence"]
    assert_equal "pause opened by paused_report", session2_end
  end

  # --- 3.5: sixteen attempts, fourteen subjects ---------------------------------

  def test_340_sixteen_attempts_fourteen_subjects
    r = record_340
    assert_equal 14, r[:nodes].keys.length
    assert_equal 16, r[:nodes].values.sum { |n| n[:attempts].length }
  end

  # --- 3.6: n6's three attempts, closed by reclaimed, failed_verification, done -

  def test_340_n6_has_three_attempts
    attempts = record_340[:nodes]["n6"][:attempts]
    assert_equal 3, attempts.length
    assert_equal %w[reclaimed failed_verification done], attempts.map { |a| a[:terminal_state] }
    # The PAUSED report says no work exists under the reclaimed attempt: its
    # active span must be near zero, not its full raw span.
    assert_operator attempts[0][:active_span_seconds], :<, 15 * 60
  end

  # --- 3.7: reclaim and failed_verification evidence ----------------------------

  def test_340_reclaim_and_failed_verification_reported
    attempts = record_340[:nodes]["n6"][:attempts]
    reclaimed = attempts.find { |a| a[:terminal_state] == "reclaimed" }
    failed = attempts.find { |a| a[:terminal_state] == "failed_verification" }

    assert_equal Time.iso8601("2026-09-10T22:12:01Z"), reclaimed[:terminal_at]
    assert_equal "2026-09-10T16:43:35Z", reclaimed[:fields]["expired"]

    assert_equal Time.iso8601("2026-09-10T23:14:10Z"), failed[:terminal_at]
    assert_equal "suite_red", failed[:fields]["reason"]

    # The reclaim is not absorbed into a bigger attempt's active span as work.
    assert_operator reclaimed[:active_span_seconds], :<, reclaimed[:raw_span_seconds]
  end

  # --- 3.8: suite growth 3886 to 4017, n1-n3 carry none -------------------------

  def test_340_suite_growth_3886_to_4017_three_nodes_without_suite
    history = record_340[:suite_history]
    assert_equal 8, history.length
    assert_equal "n4", history.first[:subject]
    assert_equal 3886, history.first[:suite][:runs]
    assert_equal :unavailable, history.first[:growth]

    assert_equal "n11", history.last[:subject]
    assert_equal 4017, history.last[:suite][:runs]

    growth_entries = history.reject { |h| h[:growth] == :unavailable }
    assert_equal 7, growth_entries.length
    growth_entries.each { |h| assert_equal 0, h[:growth][:failures] }

    %w[n1 n2 n3].each do |id|
      refute history.any? { |h| h[:subject] == id }, "#{id} must not appear in suite_history: its done line carries no suite="
      assert_nil record_340[:nodes][id][:attempts].first[:fields]["suite"]
    end
  end

  # --- 3.9: three verify verdicts, verify cost 65.0 minutes ---------------------

  def test_340_verify_verdicts_and_65_minute_cost
    r = record_340
    verdicts = %w[v1 v2 v3].map { |id| r[:nodes][id][:attempts].first[:fields]["verdict"] }
    assert_equal %w[revise revise accept], verdicts

    verify_seconds = %w[v1 v2 v3].sum { |id| r[:nodes][id][:attempts].first[:active_span_seconds] }
    assert_in_delta 65.0, minutes(verify_seconds), 0.5

    m = GraphMeasureReport.model(r)
    assert_in_delta 65.0, m[:buckets]["verify"] / 60.0, 0.5
  end

  # --- 3.10: hop cohorts split at n6 attempt 2, not at n6 ------------------------

  def test_340_hop_split_is_at_n6_attempt_2
    attempts = record_340[:nodes]["n6"][:attempts]
    # Attempt 1's own running line (13:43:35Z) predates hop=; a node-level
    # hop reading would smear that hop-off attempt into the hop-on arm.
    assert_nil attempts[0][:fields]["hop"]
    assert_equal "2000", attempts[1][:fields]["hop"]
    assert_equal "2000", attempts[2][:fields]["hop"]
  end

  # --- 3.11: review-fix bucket, transitive, about 160 minutes ---------------------

  def test_340_review_fix_bucket_is_transitive_and_largest
    r = record_340
    assert_equal true, r[:nodes]["n9"][:review_fix]
    assert_equal true, r[:nodes]["n10"][:review_fix]
    assert_equal true, r[:nodes]["n11"][:review_fix]
    # n1-n8 need nothing that needs a verify node (v1 needs THEM, not the
    # reverse), so none of them can be classified a review fix under the
    # transitive rule.
    %w[n1 n2 n3 n4 n5 n6 n7 n8].each { |id| assert_equal false, r[:nodes][id][:review_fix], id }

    m = GraphMeasureReport.model(r)
    review_fix_min = m[:buckets]["review_fix"] / 60.0
    assert_in_delta 160.0, review_fix_min, 5.0
    assert_operator review_fix_min, :>, m[:buckets]["verify"] / 60.0
    assert_operator review_fix_min, :>, m[:buckets]["lead"] / 60.0
    # Pinned difference (row 3.22): against this real ledger, the transitive
    # review-fix bucket (about 160 min) is the SECOND-largest bucket, not
    # the largest overall; "build" (n1-n8's own active spans) is larger, at
    # about 200.6 min. The plan review's "larger than any other bucket"
    # holds against verify and lead, the two buckets the
    # non-transitive-vs-transitive contrast (93.2 min, 62 to 46 percent)
    # was actually about; it does not hold against build, and this test
    # does not force that comparison to pass by miscounting build.
    assert_operator m[:buckets]["build"] / 60.0, :>, review_fix_min
  end

  # --- 3.12: 337's three holders --------------------------------------------------

  def test_337_three_holders
    r = record_337
    holders = r[:nodes].values.flat_map { |n| n[:attempts].map { |a| a[:holder] } }.compact.uniq.sort
    assert_equal %w[executor:337 lead:337 reviewer:337], holders
  end

  # --- 3.13: 337's one unattributed line, listed as anomaly not torn -----------

  def test_337_one_unattributed_line_listed
    r = record_337
    assert_empty r[:anomalies][:torn]
    assert_equal 1, r[:anomalies][:unattributed].length
    line = r[:anomalies][:unattributed].first[:line]
    assert_includes line, "2026-09-10T13:36:49Z"
    assert_includes line, "v1"
    refute_includes line, "holder="
  end

  # --- 3.14: 337's gate tally ------------------------------------------------------

  def test_337_gate_tally
    tally = Hash.new(0)
    record_337[:nodes].each_value do |node|
      node[:attempts].each do |a|
        (a[:fields]["gates"] || "").split("+").each { |g| tally[g] += 1 }
      end
    end
    assert_equal({ "suite" => 8, "review" => 2, "deposit" => 1 }, tally)
  end

  # --- 3.15: 337's v1 two done lines, no running line between them -------------

  def test_337_v1_two_done_lines_no_running
    attempts = record_337[:nodes]["v1"][:attempts]
    assert_equal 2, attempts.length
    assert_equal %w[done done], attempts.map { |a| a[:terminal_state] }
    assert_equal [:no_running, :no_running], attempts.map { |a| a[:span_note] }
    assert_nil attempts[0][:holder]
    assert_equal "reviewer:337", attempts[1][:holder]
  end

  # --- 3.16: no span for any of 337's ten nodes ----------------------------------

  def test_337_no_node_has_a_span
    r = record_337
    assert_equal 10, r[:nodes].keys.length
    r[:nodes].each_value do |node|
      node[:attempts].each do |a|
        assert_nil a[:span_seconds], "#{node} attempt has no running line, so it must carry no span"
        assert_equal :no_running, a[:span_note]
      end
    end
  end

  # --- 3.17: 337's model, hop, verify cost unavailable ---------------------------

  # Corrected by the v1 review fix (B3, n8 row 8.7): this test used to pin
  # `assert_equal 0.0, m[:buckets]["verify"]` with a comment rationalizing
  # it as "every gate bucket nets to 0.0" - that IS the defect the review
  # found (a bucket with no measured source read as a false, indistinguishable
  # zero rather than "unavailable"), not a fact worth pinning. No node in
  # 337 has a `running` line at all, so NONE of the three gate buckets ever
  # receives a single measured span; build and verify render "unavailable".
  # active_seconds is still a real number (the sessions the generic gap
  # rule still finds inside 337's own file-ordered lines), so that whole
  # span lands in "lead", the one bucket that is always a real number by
  # construction.
  #
  # Corrected again by n9 row 9.3 (v2 NEW-3): the review-fix bucket is a
  # real zero here, not unavailable - 337 has no graph.md at all, so no
  # node is ever classified a review fix in the first place, distinct from
  # build/verify, whose nodes exist but never carried a measured span.
  def test_337_model_hop_verify_cost_unavailable
    r = record_337
    r[:nodes].each do |id, node|
      assert_equal :unavailable, node[:model], id
      assert_equal :unavailable, node[:hop], id
    end
    m = GraphMeasureReport.model(r)
    assert_equal "unavailable", m[:buckets]["build"]
    assert_equal "unavailable", m[:buckets]["verify"]
    assert_equal 0.0, m[:buckets]["review_fix"]
    assert_in_delta m[:buckets]["active_seconds"], m[:buckets]["lead"], 0.01
  end

  # --- 3.18: 337's two-field suite -----------------------------------------------

  def test_337_two_field_suite_is_runs_and_failures
    suite = record_337[:nodes]["n1"][:attempts].first[:suite]
    assert_equal 16, suite[:runs]
    assert_equal 0, suite[:failures]
    assert_equal :unavailable, suite[:assertions]
    assert_equal :unavailable, suite[:errors]
    assert_equal :two_field, suite[:form]
  end

  # --- 3.19: 337's kinds come from its copied nodes/, not from the id prefix ----

  def test_337_kinds_come_from_its_node_files
    r = record_337
    assert_equal "research", r[:nodes]["r1"][:kind]
    assert_equal :node_file, r[:nodes]["r1"][:kind_source]
    assert_equal "verify", r[:nodes]["v1"][:kind]
    assert_equal :node_file, r[:nodes]["v1"][:kind_source]
    # r1's id prefix "r" is not in NodeFile::KIND_PREFIX at all (work "n",
    # verify "v"), so a prefix-fallback reader could not even guess
    # "research" for it; only reading nodes/r1.md gets this right.
    %w[n1 n2 n3 n4 n5 n6 n7 n9].each { |id| assert_equal "work", r[:nodes][id][:kind], id }
  end

  # --- 3.20: 337's out-of-position How/Exec stage lines ---------------------------

  def test_337_stage_lines_out_of_position
    r = record_337
    # savepoint.md's real line order: What, n1 done, n2 done, How, Exec, ...
    # A stamp-ordered reader would not change the session split (both stage
    # lines land inside the same session the file-order reader finds), but a
    # reader that starts the clock at the first NODE line, rather than the
    # first LEDGER line, would miss the three days of scaffold gap this
    # ledger has no Why line to separate out.
    assert_equal 2, r[:sessions].length
    assert_equal 2, r[:pauses].length
    assert_equal Time.iso8601("2026-09-07T10:42:33Z"), r[:clock][:start]
  end

  # --- 3.21: both fixtures through the real subprocess, both formats -----------

  def test_both_fixtures_through_the_subprocess_both_formats
    [DIR_340, DIR_337].each do |dir|
      before = checksum_tree(dir)

      %w[text json].each do |format|
        out, err, status = Open3.capture3(SCRIPT, "intent", dir, "--format", format)
        assert status.success?, "graph-measure intent #{dir} --format #{format} failed: #{err}"
        refute_empty out
        if format == "json"
          parsed = JSON.parse(out)
          assert parsed.key?("wall_clock")
          assert parsed.key?("nodes")
        else
          assert_includes out, "== Wall clock =="
          assert_includes out, "== Nodes =="
        end
      end

      # D2: read-only. The fixture directory is byte-identical after both runs.
      assert_equal before, checksum_tree(dir), "graph-measure must never write into the intent directory it reads"
    end
  end

  # --- 3.22: known differences from the hand-built 2026-09-11 report, pinned ---

  def test_known_differences_pinned_with_their_cause
    r340 = record_340
    r337 = record_337

    # 340: the ledger alone gives the true delivery clock (why line to done
    # line); the hand-built report's session 1 start, pause 1 start, and its
    # 03:56Z end came from the roadmap ledger and git, which this reader
    # never opens (spec D19). This reader's own numbers are internally
    # consistent (sessions plus pauses reconstruct the full clock span) even
    # though they differ from the hand-built report's.
    reconstructed = r340[:sessions].sum { |s| s[:end] - s[:start] } + r340[:pauses].sum { |p| p[:end] - p[:start] }
    assert_in_delta r340[:clock][:wall_clock_seconds], reconstructed, 0.01

    # 337: no Why line exists, so D20's fallback anchors on the first ledger
    # line (the What line, dated 2026-09-07, three days before any node
    # work). This reader reports that whole span honestly (about 74.9 hours)
    # rather than guessing at a "real" session 1 start the way the hand-built
    # report's outside sources (git, the roadmap ledger) could.
    assert_equal :first_line, r337[:clock][:anchor]
    assert_in_delta 74.9, r337[:clock][:wall_clock_seconds] / 3600.0, 0.1

    # The plan review's D7 "review-fix bucket is larger than any other
    # bucket" note does not hold against "build" for 340 (see
    # test_340_review_fix_bucket_is_transitive_and_largest); pinned there,
    # not here, because it is a difference in a DERIVED bucket comparison,
    # not in a field the ledger states directly.
  end

  # --- 3.23: 337's clock anchor and the anchor label -----------------------------

  def test_337_clock_falls_back_to_the_first_ledger_line_and_names_the_anchor
    r = record_337
    assert_equal :first_line, r[:clock][:anchor]
    assert_equal Time.iso8601("2026-09-07T10:42:33Z"), r[:clock][:start]
    assert_nil r[:scaffold][:gap_seconds]

    m = GraphMeasureReport.model(r)
    assert_equal "first_line", m[:wall_clock]["clock_anchor"]
    assert_equal "unavailable", m[:wall_clock]["scaffold_gap_seconds"]
    text = GraphMeasureReport.render_text(r)
    assert_includes text, "clock anchor: first ledger line"
  end

  # --- 3.24: a direct pause survives an open running attempt spanning it --------

  def test_direct_pause_evidence_survives_an_open_running_attempt
    r = record_340
    # n4's running line (07:17:49Z) opens before the Lock takeover (13:01:47Z)
    # and n4 does not close (done) until AFTER it (13:08:30Z): a running
    # attempt spans this pause end to end. The generic gap rule alone would
    # suppress a pause here (an active running interval covers the whole
    # gap); the Lock takeover is direct evidence and must survive that
    # suppression.
    n4 = r[:nodes]["n4"][:attempts].first
    assert_equal Time.iso8601("2026-09-10T07:17:49Z"), n4[:running_at]
    assert_equal Time.iso8601("2026-09-10T13:08:30Z"), n4[:terminal_at]

    lock_pause = r[:pauses].find { |p| p[:closed_by] == :lock_takeover }
    refute_nil lock_pause, "the Lock takeover pause must survive even though n4's running attempt spans it"
    assert_operator n4[:running_at], :<, lock_pause[:end]
    assert_operator n4[:terminal_at], :>, lock_pause[:start]
  end

  private

  def checksum_tree(dir)
    Dir.glob(File.join(dir, "**", "*")).select { |f| File.file?(f) }.sort.to_h do |f|
      [f, Digest::SHA256.file(f).hexdigest]
    end
  end
end
