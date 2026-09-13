# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"

require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/runner_dispatch"
require_relative "../scripts/lib/graph_measure_cohorts"

# GraphMeasureCohortsTest (intent 343, G10, n6): the second half of the
# `cohorts` verb - approve-then-fix per verify model, hop on versus off,
# delivery latency, the evidence bar, and the two concurrency ceilings.
# Matrix rows 6.1-6.20 in nodes/n6.md; the subprocess row (6.21) lives in
# test/graph_measure_cli_test.rb and the install-sync row (6.22) in
# test/install_sync_test.rb.
#
# Rows 6.1, 6.9, 6.10, 6.11 and 6.19's "real ledger reports 1" half read the
# two real ledger fixtures (337, 340) copied into a synthetic store, never
# authored by this test (spec D18's rule the other way round). Every row
# that needs a case neither real ledger produces (the positive
# approve-then-fix follow-up, an out-of-order timestamp, a hop-off ledger, a
# concurrency count above one, an open intent) builds its own hermetic
# fixture in a Dir.mktmpdir, per D18.
class GraphMeasureCohortsTest < Minitest::Test
  FIXTURES = File.expand_path("fixtures/ledgers", __dir__)
  DIR_337 = File.join(FIXTURES, "337--roadmap-graph")
  DIR_340 = File.join(FIXTURES, "340--runner-core-in-session")

  RUNNING = { holder: "auto-1", expires: "2099-01-01T00:00:00Z", input: "abc123" }.freeze

  def with_store_dir
    Dir.mktmpdir("graph-measure-cohorts-test") { |dir| yield dir }
  end

  def stamp(str)
    Time.iso8601(str)
  end

  def stage(ts, subject, text)
    "#{ts}  #{subject}  #{text}\n"
  end

  def transition(ts, subject, state, fields: {}, comment: nil)
    NodeLedger.transition_line(subject: subject, state: state, fields: fields, comment: comment, now: stamp(ts))
  end

  def write_intent(store, id, transitions: [], extra_lines: [])
    dir = File.join(store, id)
    FileUtils.mkdir_p(dir)
    content = (Array(transitions).flatten + Array(extra_lines)).join
    File.write(File.join(dir, "savepoint.md"), content)
    dir
  end

  def copy_real_fixtures(store)
    FileUtils.cp_r(DIR_340, File.join(store, File.basename(DIR_340)))
    FileUtils.cp_r(DIR_337, File.join(store, File.basename(DIR_337)))
  end

  # --- 6.1: an accept followed only by a Done stage line is not a fix ----------

  def test_accept_followed_by_later_work_transition_counts
    with_store_dir do |store|
      copy_real_fixtures(store)

      record = GraphMeasureCohorts.read(store)
      opus = record[:approve_then_fix]["opus"]
      refute_nil opus
      assert_equal 1, opus[:accepted], "340's v3 is the store's one accepted verdict"
      assert_equal 0, opus[:fixed], "nothing but a Done stage line follows v3's accept"
      assert_equal 0.0, opus[:rate]
    end
  end

  # --- 6.2: the source is transition lines only, never Commit free text --------

  def test_approve_then_fix_source_is_transition_lines_only
    with_store_dir do |store|
      write_intent(store, "1--commit-noise",
                   transitions: [
                     transition("2026-01-01T09:00:00Z", "v1", "running", fields: RUNNING.merge(model: "opus")),
                     transition("2026-01-01T09:05:00Z", "v1", "done",
                                fields: RUNNING.merge(model: "opus", gates: "review", verdict: "accept")),
                   ],
                   extra_lines: [
                     stage("2026-01-01T09:06:00Z", "Commit", "abc1234 fixed n2, closes the accepted verify"),
                   ])

      record = GraphMeasureCohorts.read(store)
      opus = record[:approve_then_fix]["opus"]
      assert_equal 1, opus[:accepted]
      assert_equal 0, opus[:fixed], "a Commit line's free text must never be read as a follow-up"
    end
  end

  def test_module_never_shells_out_to_git
    source = File.read(File.expand_path("../scripts/lib/graph_measure_cohorts.rb", __dir__))
    refute_match(/`git |system\(.*git|IO\.popen.*git|Open3.*git/, source,
                 "GraphMeasureCohorts must never open a git working tree (spec D2)")
  end

  # --- 6.3: the positive case comes from a synthetic fixture (D18) -------------

  def test_approve_then_fix_positive_case_from_fixture
    with_store_dir do |store|
      write_intent(store, "1--fix-demo",
                   transitions: [
                     transition("2026-01-01T09:00:00Z", "v1", "running", fields: RUNNING.merge(model: "opus")),
                     transition("2026-01-01T09:05:00Z", "v1", "done",
                                fields: RUNNING.merge(model: "opus", gates: "review", verdict: "accept")),
                     transition("2026-01-01T09:06:00Z", "n2", "running", fields: RUNNING.merge(model: "sonnet")),
                     transition("2026-01-01T09:20:00Z", "n2", "done",
                                fields: RUNNING.merge(model: "sonnet", gates: "suite", commit: "abc1234")),
                   ])

      record = GraphMeasureCohorts.read(store)
      opus = record[:approve_then_fix]["opus"]
      assert_equal 1, opus[:accepted]
      assert_equal 1, opus[:fixed]
      assert_equal 1.0, opus[:rate]
    end
  end

  # --- 6.4: file order decides "later", never the timestamp --------------------

  def test_after_is_file_order_not_timestamp
    with_store_dir do |store|
      # n2's running line is written AFTER v1's accept in the file, but
      # carries an EARLIER timestamp. A timestamp-sorted reading would place
      # n2 "before" the accept and miss it; file order must not.
      transitions = [
        transition("2026-01-01T09:00:00Z", "v1", "running", fields: RUNNING.merge(model: "opus")),
        transition("2026-01-01T09:05:00Z", "v1", "done",
                   fields: RUNNING.merge(model: "opus", gates: "review", verdict: "accept")),
        transition("2026-01-01T09:01:00Z", "n2", "running", fields: RUNNING.merge(model: "sonnet")),
      ]
      write_intent(store, "1--out-of-order", transitions: transitions)

      record = GraphMeasureCohorts.read(store)
      opus = record[:approve_then_fix]["opus"]
      assert_equal 1, opus[:accepted]
      assert_equal 1, opus[:fixed], "n2's line is later in FILE order and must count despite its earlier stamp"
    end
  end

  # --- 6.5: the qualified n rides beside every rate -----------------------------

  def test_rate_carries_its_qualified_sample_size
    with_store_dir do |store|
      copy_real_fixtures(store)
      record = GraphMeasureCohorts.read(store)
      opus = record[:approve_then_fix]["opus"]
      assert_equal 1, opus[:accepted], "the rate's own sample size travels on the same row as the rate"

      rendered = GraphMeasureCohorts.render_text(record)
      assert_match(/opus.*n=1/, rendered)
    end
  end

  # --- 6.6: zero accepted verdicts renders unavailable, never 0 percent --------

  def test_no_accepted_verdicts_is_unavailable_not_zero_percent
    with_store_dir do |store|
      write_intent(store, "1--never-accepted",
                   transitions: [
                     transition("2026-01-01T09:00:00Z", "v1", "running", fields: RUNNING.merge(model: "haiku")),
                     transition("2026-01-01T09:05:00Z", "v1", "done",
                                fields: RUNNING.merge(model: "haiku", gates: "review", verdict: "revise")),
                   ])

      record = GraphMeasureCohorts.read(store)
      haiku = record[:approve_then_fix]["haiku"]
      refute_nil haiku
      assert_equal 0, haiku[:accepted]
      assert_equal :unavailable, haiku[:rate]
      refute_match(/haiku.*0\.0%/, GraphMeasureCohorts.render_text(record))
    end
  end

  # --- 6.7: hop cohorts split per ATTEMPT, using the real 340 ledger -----------

  def test_hop_cohorts_split_per_attempt
    with_store_dir do |store|
      copy_real_fixtures(store)
      record = GraphMeasureCohorts.read(store)

      # 340's n6 carries three attempts: attempt 1 (reclaimed) has no hop=,
      # attempts 2 (failed_verification) and 3 (done) both carry hop=2000.
      # A node-level split would misfile attempt 1.
      assert_equal 10, record[:hop_cohorts][:on][:n]
      assert_equal 6, record[:hop_cohorts][:off][:n]
    end
  end

  # --- 6.8: a ledger that never wrote hop= is unavailable, not hop-off --------

  def test_ledger_without_hop_field_is_unavailable_not_hop_off
    with_store_dir do |store|
      # 337 never writes hop= anywhere; it must contribute to NEITHER arm.
      FileUtils.cp_r(DIR_337, File.join(store, File.basename(DIR_337)))
      record = GraphMeasureCohorts.read(store)
      assert_equal 0, record[:hop_cohorts][:on][:n]
      assert_equal 0, record[:hop_cohorts][:off][:n]
      assert_equal :unavailable, record[:hop_cohorts][:off][:failed_verification_rate]
    end
  end

  # --- 6.9: the comparison uses ACTIVE spans and reports n per arm ------------

  def test_hop_comparison_uses_active_spans_and_reports_n
    with_store_dir do |store|
      copy_real_fixtures(store)
      record = GraphMeasureCohorts.read(store)

      on = record[:hop_cohorts][:on]
      off = record[:hop_cohorts][:off]
      assert_equal 10, on[:n]
      assert_in_delta 0.1, on[:failed_verification_rate], 0.0001
      assert_in_delta 1740.0, on[:median_active_span_seconds], 0.01

      assert_equal 6, off[:n]
      assert_in_delta 0.0, off[:failed_verification_rate], 0.0001
      assert_in_delta 544.5, off[:median_active_span_seconds], 0.01
    end
  end

  # --- 6.10: a single-intent comparison names its own confound ----------------

  def test_single_intent_hop_comparison_names_the_confound
    with_store_dir do |store|
      copy_real_fixtures(store)
      record = GraphMeasureCohorts.read(store)
      refute_nil record[:hop_cohorts][:confound]
      assert_includes record[:hop_cohorts][:confound], "340--runner-core-in-session"
    end
  end

  # --- 6.11: latency is Why-to-Done, scaffold reported separately -------------

  def test_latency_is_first_why_to_done_scaffold_separate
    with_store_dir do |store|
      copy_real_fixtures(store)
      record = GraphMeasureCohorts.read(store)

      row_340 = record[:latency][:rows].find { |r| r[:intent] == "340--runner-core-in-session" }
      refute_nil row_340
      assert_equal :why, row_340[:anchor]
      assert_in_delta 81_411.0, row_340[:wall_clock_seconds], 1.0
      assert_in_delta 241_240.0, row_340[:scaffold_gap_seconds], 1.0

      # 337 carries no Why line at all (spec D20): its clock falls back to
      # the first ledger line, so it is never presented as Why-anchored and
      # its scaffold gap is unavailable, not zero. The node input's "about 5h"
      # prose does not hold on real data: 337's real, fallback-anchored
      # number is pinned here instead of tuned to match that prose.
      row_337 = record[:latency][:rows].find { |r| r[:intent] == "337--roadmap-graph" }
      refute_nil row_337
      assert_equal :first_line, row_337[:anchor]
      assert_in_delta 269_770.0, row_337[:wall_clock_seconds], 1.0
      assert_nil row_337[:scaffold_gap_seconds]
    end
  end

  # --- 6.12: an intent with no Done line is excluded and named ----------------

  def test_open_intent_excluded_from_latency
    with_store_dir do |store|
      copy_real_fixtures(store)
      write_intent(store, "9--still-open",
                   extra_lines: [
                     stage("2026-01-01T09:00:00Z", "Why", "spec.md created"),
                     transition("2026-01-01T09:05:00Z", "n1", "running", fields: RUNNING.merge(model: "sonnet")),
                   ])

      record = GraphMeasureCohorts.read(store)
      assert_includes record[:latency][:excluded_no_done], "9--still-open"
      refute record[:latency][:rows].any? { |r| r[:intent] == "9--still-open" }
      assert_equal 2, record[:latency][:count], "only the two Done-carrying intents are ever counted"
    end
  end

  # --- 6.13: the distribution reports count, median, min and max -------------

  def test_latency_distribution_count_median_min_max
    with_store_dir do |store|
      copy_real_fixtures(store)
      record = GraphMeasureCohorts.read(store)
      latency = record[:latency]

      assert_equal 2, latency[:count]
      assert_in_delta 81_411.0, latency[:min_seconds], 1.0
      assert_in_delta 269_770.0, latency[:max_seconds], 1.0
      assert_in_delta((81_411.0 + 269_770.0) / 2.0, latency[:median_seconds], 1.0)
    end
  end

  # --- 6.14/6.15: the bar counts qualified deliveries per metric --------------

  def test_bar_counts_qualified_deliveries_per_metric
    qualified = { done: 223, running_holder: 8, model: 8, hop: 1 }
    with_store_dir do |store|
      record = GraphMeasureCohorts.read(store, qualified: qualified)
      bar = record[:bar]

      assert_equal 223, bar["done"][:qualified]
      assert_equal 30, bar["done"][:bar]
      assert_equal 0, bar["done"][:shortfall]
      assert bar["done"][:met]

      assert_equal 8, bar["running_holder"][:qualified]
      assert_equal 22, bar["running_holder"][:shortfall]
      refute bar["running_holder"][:met]

      assert_equal 1, bar["hop"][:qualified]
      assert_equal 29, bar["hop"][:shortfall]
      refute bar["hop"][:met]
    end
  end

  def test_bar_prints_count_bar_and_shortfall_per_metric
    qualified = { done: 223, running_holder: 8, model: 8, hop: 1 }
    with_store_dir do |store|
      record = GraphMeasureCohorts.read(store, qualified: qualified)
      rendered = GraphMeasureCohorts.render_text(record)
      assert_match(/hop: 1 qualified against a bar of 30 \(shortfall 29\)/, rendered)
      assert_match(/done: 223 qualified against a bar of 30 \(shortfall 0\)/, rendered)
    end
  end

  # --- 6.16: no recommendation below the bar ----------------------------------

  def test_no_recommendation_below_the_bar
    qualified = { done: 1, running_holder: 1, model: 1, hop: 0 }
    with_store_dir do |store|
      record = GraphMeasureCohorts.read(store, qualified: qualified)
      rendered = GraphMeasureCohorts.render_text(record)
      refute_match(/recommend/i, rendered)
    end
  end

  # --- 6.17: never a recommendation about concurrency, at any sample size ----

  def test_never_recommends_raising_concurrency
    qualified = { done: 500, running_holder: 500, model: 500, hop: 500 }
    with_store_dir do |store|
      record = GraphMeasureCohorts.read(store, qualified: qualified)
      rendered = GraphMeasureCohorts.render_text(record)
      refute_match(/recommend/i, rendered)
      refute_match(/raise.*concurrency|increase.*concurrency|increase.*limit/i, rendered)
      json = GraphMeasureCohorts.render_json(record)
      refute_match(/recommend/i, json)
    end
  end

  # --- 6.18: both concurrency ceilings are named, and named separately -------

  def test_both_concurrency_ceilings_named_separately
    with_store_dir do |store|
      record = GraphMeasureCohorts.read(store)
      concurrency = record[:concurrency]
      assert_equal RunnerDispatch::DEFAULT_LIMIT, concurrency[:dispatch_ceiling]
      refute_nil concurrency[:background_teams_ceiling]
      refute_equal concurrency[:dispatch_ceiling], concurrency[:background_teams_ceiling]
      assert_match(/no config source/i, concurrency[:background_teams_ceiling])

      rendered = GraphMeasureCohorts.render_text(record)
      assert_match(/RunnerDispatch::DEFAULT_LIMIT/, rendered)
      assert_match(/no config source/i, rendered)
    end
  end

  # --- 6.19: observed simultaneous running, real data plus a fixture above 1 -

  def test_observed_simultaneous_running_with_fixture_above_one
    with_store_dir do |store|
      copy_real_fixtures(store)
      write_intent(store, "1--overlap-demo",
                   transitions: [
                     transition("2026-01-01T09:00:00Z", "n1", "running", fields: RUNNING.merge(model: "sonnet")),
                     transition("2026-01-01T09:10:00Z", "n2", "running", fields: RUNNING.merge(model: "sonnet")),
                     transition("2026-01-01T09:20:00Z", "n1", "done",
                                fields: RUNNING.merge(model: "sonnet", gates: "suite", commit: "abc1234")),
                     transition("2026-01-01T09:25:00Z", "n2", "done",
                                fields: RUNNING.merge(model: "sonnet", gates: "suite", commit: "def5678")),
                   ])

      record = GraphMeasureCohorts.read(store)
      by_intent = record[:concurrency][:observed].each_with_object({}) { |r, m| m[r[:intent]] = r[:max_simultaneous_running] }

      assert_equal 2, by_intent["1--overlap-demo"]
      assert_equal 1, by_intent["340--runner-core-in-session"], "340 ran fully serialized"
      assert_equal :unavailable, by_intent["337--roadmap-graph"], "337 never wrote a running line at all"
    end
  end

  # --- 6.20: an empty store and empty cohorts never divide by zero -----------

  def test_empty_store_and_empty_cohorts_never_divide_by_zero
    with_store_dir do |store|
      record = GraphMeasureCohorts.read(store)

      assert_equal({}, record[:approve_then_fix])
      assert_equal 0, record[:hop_cohorts][:on][:n]
      assert_equal :unavailable, record[:hop_cohorts][:on][:failed_verification_rate]
      assert_equal :unavailable, record[:hop_cohorts][:on][:median_active_span_seconds]
      assert_nil record[:hop_cohorts][:confound]
      assert_equal 0, record[:latency][:count]
      assert_equal :unavailable, record[:latency][:median_seconds]
      assert_equal :unavailable, record[:latency][:min_seconds]
      assert_equal :unavailable, record[:latency][:max_seconds]
      assert_equal [], record[:concurrency][:observed]
      assert_equal 30, record[:bar]["done"][:shortfall]

      rendered = GraphMeasureCohorts.render_text(record)
      refute_empty rendered
      json = GraphMeasureCohorts.render_json(record)
      refute_empty json
    end
  end

  # A single-member arm's median must be that one value, never a crash.
  def test_single_member_median_never_raises
    with_store_dir do |store|
      write_intent(store, "1--one-attempt",
                   transitions: [
                     stage("2026-01-01T08:55:00Z", "Why", "spec.md created"),
                     transition("2026-01-01T09:00:00Z", "n1", "running", fields: RUNNING.merge(model: "sonnet", hop: "2000")),
                     transition("2026-01-01T09:10:00Z", "n1", "done",
                                fields: RUNNING.merge(model: "sonnet", hop: "2000", gates: "suite", commit: "abc1234")),
                     stage("2026-01-01T09:11:00Z", "Done", "delivered"),
                   ])

      record = GraphMeasureCohorts.read(store)
      assert_equal 1, record[:hop_cohorts][:on][:n]
      assert_in_delta 600.0, record[:hop_cohorts][:on][:median_active_span_seconds], 1.0
    end
  end
end
