# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "time"

require_relative "../scripts/lib/node_ledger"

# GraphMeasureCliTest (intent 343, G10, n2): scripts/graph-measure, run as a
# real subprocess (Open3), the house pattern test/runner_cli_test.rb and
# test/ready_set_cli_test.rb already use (row 2.19: the module alone proves
# nothing about the script actually running). Matrix rows 2.1-2.6, 2.14,
# 2.17, 2.19, 2.22 in nodes/n2.md; the report's own content lives in
# test/graph_measure_report_test.rb.
class GraphMeasureCliTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/graph-measure", __dir__)

  def setup
    @home = Dir.mktmpdir("graph-measure-cli")
    @dir = File.join(@home, "1--demo")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    File.write(File.join(@dir, "1--demo.md"), "---\nid: \"1\"\nintent: t\n---\n\n## Intent\nbody\n")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  # --- fixture helpers ----------------------------------------------------------

  def stage(ts, subject, text)
    "#{ts}  #{subject}  #{text}\n"
  end

  def transition(ts, subject, state, fields: {}, comment: nil)
    NodeLedger.transition_line(subject: subject, state: state, fields: fields, comment: comment,
                                now: Time.iso8601(ts))
  end

  def write_savepoint(lines)
    File.write(File.join(@dir, "savepoint.md"), Array(lines).join)
  end

  def write_graph(edges_body)
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: fixture

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

  RUNNING = { holder: "auto-1", expires: "2099-01-01T00:00:00Z", packet: "abc123", model: "sonnet" }.freeze

  def write_happy_path_fixture
    write_graph("- n1 needs nothing\n")
    write_savepoint([
      stage("2026-01-01T09:00:00Z", "Why", "spec.md created"),
      transition("2026-01-01T09:01:00Z", "n1", "running", fields: RUNNING),
      transition("2026-01-01T09:20:00Z", "n1", "done",
                  fields: RUNNING.merge(gates: "suite", commit: "abc1234"), comment: "all green"),
      stage("2026-01-01T09:21:00Z", "Done", "delivered"),
    ])
  end

  def run_cli(*args)
    Open3.capture3(RbConfig.ruby, SCRIPT, *args)
  end

  # --- 2.1: no args ---------------------------------------------------------------

  def test_no_args_prints_usage_exit_2
    out, err, status = run_cli
    assert_equal 2, status.exitstatus
    assert_empty out
    assert_match(/usage/i, err)
  end

  # --- 2.2: unknown subcommand -----------------------------------------------------

  def test_unknown_subcommand_exit_2
    out, err, status = run_cli("bogus", @dir)
    assert_equal 2, status.exitstatus
    assert_empty out
    assert_match(/unknown subcommand/, err)
    assert_match(/"bogus"/, err)
  end

  # --- 2.3: unknown flag ------------------------------------------------------------

  def test_unknown_flag_refused_by_name
    write_happy_path_fixture
    out, err, status = run_cli("intent", @dir, "--formats", "json")
    assert_equal 2, status.exitstatus
    assert_empty out
    assert_match(/unknown flag/, err)
    assert_match(/--formats/, err)
  end

  # --- 2.4: not an intent directory --------------------------------------------------

  def test_non_intent_directory_exit_2
    Dir.mktmpdir("not-an-intent") do |not_intent|
      out, err, status = run_cli("intent", not_intent)
      assert_equal 2, status.exitstatus
      assert_empty out
      assert_match(/not an intent directory/, err)
      assert_includes err, not_intent
    end
  end

  # --- 2.5: intent directory with no savepoint.md ------------------------------------

  def test_missing_savepoint_exit_1
    # @dir is a real intent directory (1--demo.md exists) but savepoint.md
    # was never written.
    out, err, status = run_cli("intent", @dir)
    assert_equal 1, status.exitstatus
    assert_empty out
    assert_match(/savepoint\.md/, err)
  end

  # --- 2.6/8.8: an unlanded verb's module fails only itself ----------------------------

  # v1 review B4: row 2.6 named this test and nothing in test/ ever defined
  # it - the lazy-require branch at scripts/graph-measure:132-139 was
  # entirely untested. Every verb's module is delivered today, so this
  # exercises the branch the only way still possible: run the real script
  # against a COPY of scripts/ with one verb's own lib file removed.
  # Reproduced by hand first: copying scripts/ to a tmpdir, deleting
  # lib/graph_measure_budget.rb, then running that copy's own executable -
  # `budget` reported "graph-measure: budget is not yet delivered (its
  # module has not landed)" and exited 3, while `intent` (a different
  # verb, a different lib file, untouched) still exited 0 against the same
  # copy.
  def test_missing_module_fails_only_its_own_verb
    Dir.mktmpdir("graph-measure-missing-module") do |scripts_copy_home|
      scripts_copy = File.join(scripts_copy_home, "scripts")
      FileUtils.cp_r(File.expand_path("../scripts", __dir__), scripts_copy)
      FileUtils.rm(File.join(scripts_copy, "lib", "graph_measure_budget.rb"))
      copy_script = File.join(scripts_copy, "graph-measure")

      out, err, status = Open3.capture3(RbConfig.ruby, copy_script, "budget", @dir)
      assert_equal 3, status.exitstatus
      assert_empty out
      assert_match(/budget is not yet delivered/, err)

      write_happy_path_fixture
      out, err, status = Open3.capture3(RbConfig.ruby, copy_script, "intent", @dir)
      assert_equal 0, status.exitstatus, err
      assert_match(/== Wall clock ==/, out)
    end
  end

  # --- 5.14: the real cohorts verb's model section, in a subprocess, both formats -----

  def test_subprocess_cohorts_model_section_renders
    store = File.expand_path("fixtures/ledgers", __dir__)

    out, err, status = run_cli("cohorts", store)
    assert_equal 0, status.exitstatus, err
    assert_match(/== Population ==/, out)
    assert_match(/== Model drift ==/, out)

    out_json, err_json, status_json = run_cli("cohorts", store, "--format", "json")
    assert_equal 0, status_json.exitstatus, err_json
    parsed = JSON.parse(out_json)
    assert parsed.key?("population")
    assert parsed.key?("drift")
  end

  # --- 6.21: the full cohorts verb (n5's model section plus n6's rates, latency, --
  # bar and concurrency), in a subprocess, both formats -----------------------------

  def test_subprocess_cohorts_full_report_renders
    store = File.expand_path("fixtures/ledgers", __dir__)

    out, err, status = run_cli("cohorts", store)
    assert_equal 0, status.exitstatus, err
    assert_match(/== Population ==/, out)
    assert_match(/== Model drift ==/, out)
    assert_match(/== Approve-then-fix ==/, out)
    assert_match(/== Hop cohorts ==/, out)
    assert_match(/== Delivery latency ==/, out)
    assert_match(/== Evidence bar/, out)
    assert_match(/== Concurrency ==/, out)

    out_json, err_json, status_json = run_cli("cohorts", store, "--format", "json")
    assert_equal 0, status_json.exitstatus, err_json
    parsed = JSON.parse(out_json)
    assert parsed.key?("population")
    assert parsed.key?("drift")
    assert parsed.key?("approve_then_fix")
    assert parsed.key?("hop_cohorts")
    assert parsed.key?("latency")
    assert parsed.key?("bar")
    assert parsed.key?("concurrency")
  end

  # --- 5.15: cohorts refuses a path that is not a store, exit 2, naming it -----------

  def test_cohorts_non_store_path_exit_2
    not_store = File.join(@home, "does-not-exist")
    out, err, status = run_cli("cohorts", not_store)
    assert_equal 2, status.exitstatus
    assert_empty out
    assert_match(/not a store directory/, err)
    assert_includes err, not_store
  end

  # --- 2.14: anomalies still exit 0 --------------------------------------------------

  def test_anomalies_listed_exit_still_zero
    write_graph("- n1 needs nothing\n")
    write_savepoint([
      stage("2026-01-01T09:00:00Z", "Why", "spec.md created"),
      transition("2026-01-01T09:01:00Z", "n1", "running", fields: RUNNING),
      # Torn: a running line missing every required field.
      "2026-01-01T09:05:00Z  n1  running\n",
      transition("2026-01-01T09:20:00Z", "n1", "done", fields: RUNNING.merge(gates: "suite", commit: "abc1234")),
    ])
    out, err, status = run_cli("intent", @dir)
    assert_equal 0, status.exitstatus, err
    assert_match(/torn/i, out)
    assert_includes out, "n1  running"
  end

  # --- 2.17: --format json emits exactly one parseable document ----------------------

  def test_json_format_is_one_parseable_document
    write_happy_path_fixture
    out, err, status = run_cli("intent", @dir, "--format", "json")
    assert_equal 0, status.exitstatus, err
    assert_empty err

    lines = out.each_line.to_a
    assert_equal 1, lines.length, "expected exactly one line of stdout, got: #{out.inspect}"
    parsed = JSON.parse(out)
    assert_kind_of Hash, parsed
    assert parsed.key?("wall_clock")
  end

  # --- 2.19: the executable actually runs, in a subprocess ---------------------------

  def test_subprocess_intent_report_renders
    write_happy_path_fixture
    out, err, status = run_cli("intent", @dir)
    assert_equal 0, status.exitstatus, err
    assert_match(/== Wall clock ==/, out)
    assert_match(/== Nodes ==/, out)
    assert_match(/n1/, out)
    assert_match(/all green/, out)
  end

  # --- 4.15: the real budget verb, in a subprocess, both formats ---------------------

  def test_subprocess_budget_report_renders
    dir_340 = File.expand_path("fixtures/ledgers/340--runner-core-in-session", __dir__)

    out, err, status = run_cli("budget", dir_340)
    assert_equal 0, status.exitstatus, err
    assert_match(/== Budget ==/, out)
    assert_match(/n6/, out)
    assert_match(/== Suspected ceiling ==/, out)

    out_json, err_json, status_json = run_cli("budget", dir_340, "--format", "json")
    assert_equal 0, status_json.exitstatus, err_json
    parsed = JSON.parse(out_json)
    assert parsed.key?("nodes")
    assert parsed.key?("ceiling")
  end

  # --- 4.16: no packet activity at all still exits 0, with an explicit message -------

  def test_budget_without_packets_directory_exits_zero
    write_graph("- n1 needs nothing\n")
    write_savepoint([
      stage("2026-01-01T09:00:00Z", "Why", "spec.md created"),
      stage("2026-01-01T09:21:00Z", "Done", "delivered"),
    ])
    refute Dir.exist?(File.join(@dir, "packets"))

    out, err, status = run_cli("budget", @dir)
    assert_equal 0, status.exitstatus, err
    assert_match(/no packet attempts recorded/i, out)
  end

  # --- 2.22: malformed graph.md, a torn ledger, and invalid UTF-8 never raise ---------

  def test_malformed_inputs_never_raise
    # Malformed graph.md: no ## Graph section at all.
    File.write(File.join(@dir, "graph.md"), "not a graph file, no headings here\n")

    content = [
      stage("2026-01-01T09:00:00Z", "Why", "spec.md created"),
      transition("2026-01-01T09:01:00Z", "n1", "running", fields: RUNNING),
      # Torn line.
      "2026-01-01T09:05:00Z  n1  running\n",
      transition("2026-01-01T09:20:00Z", "n1", "done", fields: RUNNING.merge(gates: "suite", commit: "abc1234"),
                  comment: "bad byte next"),
    ].join

    # Invalid UTF-8: a stray continuation byte with no leading byte, appended
    # as its own line, never scrubbed on disk (GraphMeasure.read scrubs on
    # read, never mutates the file, spec D2).
    bytes = content.dup.force_encoding(Encoding::ASCII_8BIT)
    bytes << "\xFF\xFE not valid utf-8\n".b
    File.binwrite(File.join(@dir, "savepoint.md"), bytes)

    out, err, status = run_cli("intent", @dir)
    assert_equal 0, status.exitstatus, err
    refute_match(/\.rb:\d+:in/, err, "expected no raw Ruby backtrace, got: #{err}")
    assert_match(/== Wall clock ==/, out)
  end
end
