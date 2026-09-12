# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require "open3"
require "rbconfig"

require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/graph_measure"
require_relative "../scripts/lib/graph_measure_report"
require_relative "../scripts/lib/graph_measure_budget"
require_relative "../scripts/lib/graph_measure_models"
require_relative "../scripts/lib/graph_measure_cohorts"

# GraphMeasureFoldTest (intent 343, G10, n8): the fold of the v1 adversarial
# review (resources/review--v1-2026-09-12.md, in the intent store, outside
# this repo). Matrix rows 8.1-8.13 in nodes/n8.md.
#
# Rows 8.5-8.7, 8.9-8.11 and 8.13 each pin one specific v1 finding's fix
# against a hand-reproduced case (the fix site's own comment names how it
# was reproduced by hand before this file existed). Rows 8.1-8.4 check the
# FOLD's own discipline - reproduced first, red before fix, no weakened
# assertion, every finding accounted for - mechanically, against the
# repository's own history and content, rather than against one code path.
#
# 8.8 (row 2.6's missing test) lives in test/graph_measure_cli_test.rb next
# to the other CLI subprocess rows; 8.12 (row 7.3's false claim) lives in
# test/doctor_requalification_test.rb next to the rest of the
# re-qualification rule's own tests. Both corrected an EXISTING assertion,
# named in this node's return, never invented a new file for an old row.
class GraphMeasureFoldTest < Minitest::Test
  REPO_ROOT = File.expand_path("..", __dir__)
  FIXTURES = File.expand_path("fixtures/ledgers", __dir__)
  # The merge commit this fold started from (n7 landing, before any of n8's
  # commits): a fixed, permanent point in this repo's history, never this
  # node's own interim commits (which a later rebase or squash may reshape).
  BASE_SHA = "dabfeb0"

  RUNNING = { holder: "auto-1", expires: "2099-01-01T00:00:00Z", packet: "abc123" }.freeze

  def stage(ts, subject, text)
    "#{ts.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}  #{subject}  #{text}\n"
  end

  def transition(ts, subject, state, fields: {}, comment: nil)
    NodeLedger.transition_line(subject: subject, state: state, fields: fields, comment: comment, now: ts)
  end

  # --- 8.1: every blocker/major this fold closes names its own repro -----------

  # A mechanical proxy for "reproduced by hand before writing the fix": each
  # fix site's own comment must name the finding it closes AND the word
  # "reproduced", within the same paragraph. This survives a rebase or a
  # squash-merge (unlike grepping commit messages); the record lives in the
  # code itself, permanently.
  REPRODUCTION_MARKERS = {
    "scripts/lib/graph_measure.rb" => %w[B1 B2],
    "scripts/lib/graph_measure_report.rb" => ["B3"],
    "scripts/lib/graph_measure_budget.rb" => %w[B5 B6],
    "scripts/lib/graph_measure_models.rb" => ["B6"],
    "scripts/lib/graph_measure_cohorts.rb" => ["8.13"],
    "scripts/graph-measure" => ["M1"],
  }.freeze

  def test_each_blocker_reproduced_before_its_fix
    REPRODUCTION_MARKERS.each do |rel, tags|
      content = File.read(File.join(REPO_ROOT, rel))
      tags.each do |tag|
        occurrences = []
        start = 0
        while (idx = content.index(tag, start))
          occurrences << idx
          start = idx + tag.length
        end
        refute_empty occurrences, "#{rel} must name #{tag} at its own fix site"

        found = occurrences.any? { |idx| content[idx, 700].to_s.match?(/reproduced/i) }
        assert found,
               "#{rel}'s #{tag} fix must record how the defect was reproduced by hand somewhere near its " \
               "own tag, not just assert the corrected behaviour"
      end
    end
  end

  # --- 8.2: the fold's own tests are red against the pre-fold code -------------

  # Materializes BASE_SHA's scripts/ tree (the code exactly as n7 left it,
  # before any of this fold's fixes) into a throwaway directory, drops
  # THIS test file's current content on top of it, and runs only the
  # substantive rows (never 8.1-8.4, which are about the fold itself and
  # would otherwise recurse) against that pre-fold code. If they do not
  # fail there, they prove nothing about the fold - the fixed code and the
  # test would agree by coincidence, not by design.
  RED_AGAINST_BASE = %w[
    test_suite_growth_survives_an_unknown_suite_value
    test_open_clock_active_span_is_unavailable_not_zero
    test_absent_bucket_source_renders_unavailable
    test_no_ceiling_reported_when_budgets_were_merely_honored
    test_bad_byte_in_a_node_file_never_takes_a_verb_down
    test_cohorts_verb_resolves_the_config_chain
    test_hop_arms_exclude_open_intents_and_name_the_confound
  ].freeze

  def test_fold_tests_committed_red_first
    Dir.mktmpdir("fold-red-check") do |tmp|
      archive = File.join(tmp, "base.tar")
      _out, err, status = Open3.capture3("git", "-C", REPO_ROOT, "archive", BASE_SHA, "-o", archive)
      assert status.success?, "git archive #{BASE_SHA} must succeed: #{err}"

      _out, err, status = Open3.capture3("tar", "-xf", archive, "-C", tmp)
      assert status.success?, "extracting the pre-fold tree must succeed: #{err}"

      FileUtils.mkdir_p(File.join(tmp, "test"))
      FileUtils.cp_r(File.join(REPO_ROOT, "test", "fixtures"), File.join(tmp, "test", "fixtures"))
      FileUtils.cp(File.join(REPO_ROOT, "test", "graph_measure_fold_test.rb"),
                   File.join(tmp, "test", "graph_measure_fold_test.rb"))

      pattern = "/\\A(#{RED_AGAINST_BASE.join('|')})\\z/"
      out, err, status = Open3.capture3(
        RbConfig.ruby, File.join(tmp, "test", "graph_measure_fold_test.rb"), "-n", pattern
      )
      refute status.success?,
             "this fold's own substantive tests must FAIL against the pre-fold code at #{BASE_SHA}, " \
             "or they prove nothing was actually broken:\n#{out}\n#{err}"
    end
  end

  # --- 8.3: no existing test loses its assertion or gains a skip ---------------

  EXISTING_TEST_FILES = %w[
    test/graph_measure_test.rb test/graph_measure_report_test.rb
    test/graph_measure_budget_test.rb test/graph_measure_models_test.rb
    test/graph_measure_cohorts_test.rb test/graph_measure_cli_test.rb
    test/graph_measure_dogfood_test.rb test/doctor_requalification_test.rb
    test/install_sync_test.rb
  ].freeze

  # These two rows are corrected, not removed: their OLD assertion pinned
  # the very defect this fold fixes (row 8.7's dogfood test pinned B3's
  # zero; row 8.12's doctor test pinned M4's false "passes quietly" claim).
  # Both must still exist by name, just asserting the right thing now.
  CORRECTED_ASSERTIONS = {
    "test/graph_measure_dogfood_test.rb" => %w[test_337_model_hop_verify_cost_unavailable],
    "test/doctor_requalification_test.rb" => %w[test_current_store_passes_quietly],
  }.freeze

  def method_names_in(content)
    content.to_s.scan(/^\s*def (test_\w+)/).flatten
  end

  def file_at(sha, rel)
    out, _err, status = Open3.capture3("git", "-C", REPO_ROOT, "show", "#{sha}:#{rel}")
    status.success? ? out : nil
  end

  # One test method's own body (from its `def` line to the next `def ` or
  # the file's closing `end`), so a `skip` added inside a brand-NEW test
  # this fold writes (a portability guard, the same shape the dogfood
  # test's own `test_fixtures_are_verbatim_copies...` already uses) is never
  # confused with a `skip` added to weaken a test that already existed.
  def method_body(content, name)
    content.to_s[/^\s*def #{name}\b.*?(?=^\s*def test_|\z)/m].to_s
  end

  def test_no_existing_assertion_weakened_or_skipped
    EXISTING_TEST_FILES.each do |rel|
      base_content = file_at(BASE_SHA, rel)
      next if base_content.nil? # not part of this repo at BASE_SHA; nothing to preserve

      current_content = File.read(File.join(REPO_ROOT, rel))

      base_methods = method_names_in(base_content)
      current_methods = method_names_in(current_content)
      missing = base_methods - current_methods
      assert_empty missing, "#{rel} must not drop any test method while folding: #{missing.join(', ')}"

      base_methods.each do |name|
        base_skips = method_body(base_content, name).scan(/^\s*skip[\s(]/).length
        current_skips = method_body(current_content, name).scan(/^\s*skip[\s(]/).length
        assert_operator current_skips, :<=, base_skips,
                         "#{rel}##{name} must not gain a new skip while folding (was #{base_skips}, now #{current_skips})"
      end
    end

    CORRECTED_ASSERTIONS.each do |rel, methods|
      current_content = File.read(File.join(REPO_ROOT, rel))
      methods.each do |m|
        assert_match(/def #{m}\b/, current_content, "#{rel}##{m} must be corrected, not deleted")
      end
    end
  end

  # --- 8.4: every v1 finding is folded or recorded as residue ------------------

  REVIEW_PATH = "/Users/zlatko/.plastic/projects/plastic/store/343--graph-measurement/" \
                "resources/review--v1-2026-09-12.md"
  RESIDUE_PATH = "/Users/zlatko/.plastic/projects/plastic/store/343--graph-measurement/" \
                 "resources/residue--343-2026-09-12.md"

  def test_every_v1_finding_folded_or_recorded_as_residue
    skip "review file not present on this machine" unless File.exist?(REVIEW_PATH)
    skip "residue file not written yet" unless File.exist?(RESIDUE_PATH)

    review = File.read(REVIEW_PATH)
    residue = File.read(RESIDUE_PATH)

    labels = review.scan(/^\*\*([BM]\d+)\./).flatten.uniq
    refute_empty labels, "the review must name at least one blocker or major for this check to mean anything"

    labels.each do |label|
      assert_match(/\b#{label}\b/, residue,
                   "#{label} must be named as folded or residue in #{RESIDUE_PATH}; findings must not vanish silently")
    end

    minors_section = review[/## Minors\n(.*?)(?:\n##|\z)/m, 1].to_s
    minor_count = minors_section.lines.count { |l| l.strip.start_with?("- ") }
    assert_operator minor_count, :>, 0, "the review's Minors section must be non-empty for this check to mean anything"
    assert_match(/minor/i, residue, "the residue file must account for the review's minors, not only its blockers and majors")
  end

  # --- 8.5 (B1): suite_growth survives an unknown suite= form ------------------

  def test_suite_growth_survives_an_unknown_suite_value
    Dir.mktmpdir("fold-8-5") do |dir|
      t0 = Time.iso8601("2026-01-01T09:00:00Z")
      lines = [
        stage(t0, "Why", "spec.md created"),
        transition(t0 + 60, "n1", "done", fields: { gates: "suite", commit: "abc1234", suite: "16/0" }),
        # B1's real repro shape: intent 339's own savepoint.md carries
        # prose, not the bare slash-separated form parse_suite expects -
        # splitting on "/" yields one part, `form: :unknown`, every field
        # (including runs) set to :unavailable.
        transition(t0 + 120, "n2", "done",
                   fields: { gates: "suite", commit: "def5678",
                             suite: "3534 runs, 18483 assertions, 0 failures, 0 errors" }),
        stage(t0 + 180, "Done", "delivered"),
      ]
      File.write(File.join(dir, "savepoint.md"), lines.join)

      record = GraphMeasure.read(dir) # must not raise NoMethodError on Symbol#-
      history = record[:suite_history]
      assert_equal 2, history.length
      assert_equal :unknown, history.last[:suite][:form]
      growth = history.last[:growth]
      assert_equal :unavailable, growth[:runs]
      assert_equal :unavailable, growth[:failures]
    end
  end

  # --- 8.6 (B2): an open delivery clock reports unavailable, never 0.0 ---------

  def test_open_clock_active_span_is_unavailable_not_zero
    Dir.mktmpdir("fold-8-6") do |dir|
      t0 = Time.iso8601("2026-01-01T09:00:00Z")
      lines = [
        stage(t0, "Why", "spec.md created"),
        transition(t0 + 60, "n1", "running", fields: RUNNING.merge(model: "sonnet")),
        transition(t0 + 3600, "n1", "done", fields: RUNNING.merge(model: "sonnet", gates: "suite", commit: "abc1234")),
        # No Done stage line at all: the intent itself is still open, the
        # same shape this very intent's own live savepoint.md had while n8
        # was `running` (reproduced there: n4's closed attempt printed
        # "raw 1094.4 / active 0.0").
      ]
      File.write(File.join(dir, "savepoint.md"), lines.join)

      record = GraphMeasure.read(dir)
      attempt = record[:nodes]["n1"][:attempts].first
      refute_nil attempt[:raw_span_seconds], "n1's own attempt closed with a real, known span"
      assert_nil attempt[:active_span_seconds],
                 "an attempt's active span must be unavailable, never a fabricated 0.0, while the delivery " \
                 "clock itself has no end"

      text = GraphMeasureReport.render_text(record)
      row = text.lines.find { |l| l.strip.start_with?("| 1 |") }
      refute_nil row
      assert_includes row, "unavailable"
      refute_match(/\|\s*0\.0\s*\|/, row)
    end
  end

  # --- 8.7 (B3): a bucket with no measured source renders unavailable ---------

  def test_absent_bucket_source_renders_unavailable
    record = GraphMeasure.read(File.join(FIXTURES, "337--roadmap-graph"))
    m = GraphMeasureReport.model(record)
    %w[build verify fold].each do |key|
      assert_equal "unavailable", m[:buckets][key],
                   "337 has no `running` line anywhere, so #{key} has no measured source and must read " \
                   "unavailable, never 0.0"
    end
    assert_in_delta m[:buckets]["active_seconds"], m[:buckets]["lead"], 0.01,
                     "active time is still real here (the generic gap rule finds sessions); it must all " \
                     "land in lead, not be hidden behind a false zero elsewhere"

    Dir.mktmpdir("fold-8-7-open-verify") do |dir|
      FileUtils.mkdir_p(File.join(dir, "nodes"))
      File.write(File.join(dir, "nodes", "v1.md"), <<~MD)
        ---
        node: v1
        kind: verify
        files: []
        ---
        # v1
        body
      MD
      t0 = Time.iso8601("2026-01-01T09:00:00Z")
      File.write(File.join(dir, "savepoint.md"), [
        stage(t0, "Why", "spec.md created"),
        transition(t0 + 60, "v1", "running", fields: RUNNING.merge(model: "opus")),
        stage(t0 + 3600, "Done", "delivered"),
      ].join)

      r = GraphMeasure.read(dir)
      text = GraphMeasureReport.render_text(r)
      assert_includes text, "total active span: unavailable min",
                       "an open verify attempt (running_at with no terminal_at) must not report a " \
                       "measured 0.0 while it is still running"
    end
  end

  # --- 8.9 (B5): no ceiling when a candidate merely honored the budgets -------

  def test_no_ceiling_reported_when_budgets_were_merely_honored
    honored = {
      "n1" => { declared_budget: 2000, attempts: [{ effective_tokens: 1999 }] },
      "n2" => { declared_budget: 2000, attempts: [{ effective_tokens: 1998 }] },
    }
    ceiling = GraphMeasureBudget.send(:detect_ceiling, honored)
    refute ceiling[:detected], "1999 of a declared 2000 is honoring the budget, not evidence of a shared ceiling"
    assert_equal :not_well_below_declared_budgets, ceiling[:reason]

    # Pin the stated threshold (WELL_BELOW_RATIO = 0.5): a candidate must
    # use at most half of EVERY usable attempt's own declared budget.
    at_boundary = {
      "n1" => { declared_budget: 2000, attempts: [{ effective_tokens: 1000 }] },
      "n2" => { declared_budget: 2000, attempts: [{ effective_tokens: 999 }] },
    }
    boundary = GraphMeasureBudget.send(:detect_ceiling, at_boundary)
    assert boundary[:detected], "1000 of 2000 is exactly the 50% threshold and must still count as well below"

    just_over = {
      "n1" => { declared_budget: 2000, attempts: [{ effective_tokens: 1001 }] },
      "n2" => { declared_budget: 2000, attempts: [{ effective_tokens: 999 }] },
    }
    over = GraphMeasureBudget.send(:detect_ceiling, just_over)
    refute over[:detected], "the candidate (1001, just over 50% of 2000) must fall outside the threshold"

    # The real positive case (also pinned in test/graph_measure_budget_test.rb):
    # 340's declared budgets run 50000-160000; every effective count clusters
    # 3380-7717, so the candidate uses at most 7717/50000 = 15.4% of even the
    # smallest declared budget among the usable attempts - comfortably below
    # the 50% threshold.
    real = GraphMeasureBudget.read(File.join(FIXTURES, "340--runner-core-in-session"))
    assert real[:ceiling][:detected]
    assert_equal 7717, real[:ceiling][:value]
  end

  # --- 8.10 (B6): a bad byte in a node file never takes a verb down -----------

  def test_bad_byte_in_a_node_file_never_takes_a_verb_down
    Dir.mktmpdir("fold-8-10-real") do |store|
      intent_dir = File.join(store, "340--runner-core-in-session")
      FileUtils.cp_r(File.join(FIXTURES, "340--runner-core-in-session"), intent_dir)
      File.open(File.join(intent_dir, "nodes", "n1.md"), "ab") { |f| f.write("\xFF\xFE".b) }

      assert GraphMeasure.read(intent_dir)[:ok], "intent must survive one bad byte in a node file"
      assert GraphMeasureBudget.read(intent_dir)[:ok], "budget must survive one bad byte in a node file"
      assert GraphMeasureModels.read(store)[:ok], "cohorts' model half must survive one bad byte in a node file"
    end

    Dir.mktmpdir("fold-8-10-doctor") do |store|
      t0 = Time.iso8601("2026-01-01T09:00:00Z")
      node_md = <<~MD
        ---
        node: n1
        kind: work
        files: []
        ---
        # n1
        body
      MD

      good_dir = File.join(store, "1--good")
      FileUtils.mkdir_p(File.join(good_dir, "nodes"))
      File.write(File.join(good_dir, "nodes", "n1.md"), node_md)
      File.write(File.join(good_dir, "savepoint.md"), [
        transition(t0, "n1", "running", fields: RUNNING.merge(model: "opus")),
        transition(t0 + 600, "n1", "done", fields: RUNNING.merge(model: "opus", gates: "suite", commit: "abc1234")),
      ].join)

      bad_dir = File.join(store, "2--bad")
      FileUtils.mkdir_p(File.join(bad_dir, "nodes"))
      File.write(File.join(bad_dir, "nodes", "n1.md"), node_md)
      File.open(File.join(bad_dir, "nodes", "n1.md"), "ab") { |f| f.write("\xFF\xFE".b) }
      File.write(File.join(bad_dir, "savepoint.md"), [
        transition(t0, "n1", "running", fields: RUNNING.merge(model: "opus")),
        transition(t0 + 600, "n1", "done", fields: RUNNING.merge(model: "opus", gates: "suite", commit: "def5678")),
      ].join)

      # n1 recorded "opus" for a WORK node (executor role); the shipped
      # default executor is "sonnet", so this is real drift, in BOTH
      # intents - scripts/doctor.rb's model_requalification_checks reads
      # this record directly, so the corrupted intent's own drift must
      # still surface, not be swallowed by GraphMeasureModels raising and
      # the doctor's own `rescue StandardError; next` masking it.
      record = GraphMeasureModels.read(store)
      assert record[:ok]
      executor_intents = record[:drift][:executor].map { |r| r[:intent] }
      assert_includes executor_intents, "1--good"
      assert_includes executor_intents, "2--bad", "the corrupted intent's own drift must still be found"
    end
  end

  # --- 8.11 (M1): the cohorts verb resolves the real config chain ------------

  def test_cohorts_verb_resolves_the_config_chain
    Dir.mktmpdir("fold-8-11") do |home|
      store = File.join(home, "projects", "demo", "store")
      intent_dir = File.join(store, "1--demo")
      FileUtils.mkdir_p(File.join(intent_dir, "nodes"))
      File.write(File.join(intent_dir, "nodes", "n1.md"), <<~MD)
        ---
        node: n1
        kind: work
        files: []
        ---
        # n1
        body
      MD
      t0 = Time.iso8601("2026-01-01T09:00:00Z")
      File.write(File.join(intent_dir, "savepoint.md"), [
        transition(t0, "n1", "running", fields: RUNNING.merge(model: "sonnet")),
        transition(t0 + 600, "n1", "done", fields: RUNNING.merge(model: "sonnet", gates: "suite", commit: "abc1234")),
      ].join)

      File.write(File.join(home, "config.yml"), <<~YAML)
        agents:
          models:
            claude:
              plastic-executor: opus
      YAML

      script = File.expand_path("../scripts/graph-measure", __dir__)
      out, err, status = Open3.capture3({ "PLASTIC_HOME" => home }, RbConfig.ruby, script, "cohorts", store)
      assert status.success?, err
      assert_match(/-- executor --/, out)
      assert_includes out, "1--demo"
      assert_includes out, "opus", "the global config override must reach the cohorts verb's own model comparison"
    end
  end

  # --- 8.13 (M5): the hop arms exclude an open intent, and name the confound --

  def test_hop_arms_exclude_open_intents_and_name_the_confound
    Dir.mktmpdir("fold-8-13") do |store|
      t0 = Time.iso8601("2026-01-01T09:00:00Z")

      closed_dir = File.join(store, "1--closed")
      FileUtils.mkdir_p(closed_dir)
      File.write(File.join(closed_dir, "savepoint.md"), [
        stage(t0, "Why", "spec.md created"),
        transition(t0 + 60, "n1", "running", fields: RUNNING.merge(model: "sonnet", hop: "2000")),
        transition(t0 + 660, "n1", "done", fields: RUNNING.merge(model: "sonnet", hop: "2000", gates: "suite", commit: "abc1234")),
        transition(t0 + 720, "n2", "running", fields: RUNNING.merge(model: "sonnet")),
        transition(t0 + 780, "n2", "done", fields: RUNNING.merge(model: "sonnet", gates: "suite", commit: "def5678")),
        stage(t0 + 840, "Done", "delivered"),
      ].join)

      open_dir = File.join(store, "2--open")
      FileUtils.mkdir_p(open_dir)
      File.write(File.join(open_dir, "savepoint.md"), [
        stage(t0, "Why", "spec.md created"),
        transition(t0 + 60, "n1", "running", fields: RUNNING.merge(model: "sonnet", hop: "2000")),
        transition(t0 + 660, "n1", "failed_verification",
                   fields: { holder: "auto-1", model: "sonnet", hop: "2000", gates: "suite", reason: "suite_red" }),
        # No Done stage line: this intent is still open. Its own attempt is
        # real and closed, but before this fold it still leaked into the
        # hop-on arm and into the confound's intent set (M5's real repro:
        # 343's own open ledger inflating the set past one intent).
      ].join)

      record = GraphMeasureCohorts.read(store)
      assert_equal 1, record[:hop_cohorts][:on][:n],
                   "the open intent's own hop-on attempt must not inflate the on arm"
      assert_equal 1, record[:hop_cohorts][:off][:n]
      refute_nil record[:hop_cohorts][:confound],
                 "1--closed alone supplies both arms once the open intent is excluded; this must not be silent"
      assert_includes record[:hop_cohorts][:confound], "1--closed"
      refute_includes record[:hop_cohorts][:confound], "2--open"
    end
  end
end
