# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"

require_relative "../scripts/lib/runner_absorb"
require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/guarded_append"
require_relative "../scripts/lib/outcome_report"

# RunnerAbsorb (intent 340, G7, n4): the gate that turns one executor return
# into exactly one node ledger transition. Matrix rows 4.13-4.36, 4.39-4.44 in
# nodes/n4.md (4.45 lives in install_sync_test.rb; 4.1-4.12, 4.37, 4.38 live
# in node_return_test.rb).
#
# Every git/suite/integrity side effect is an injected double; RunnerAbsorb's
# own job is the gate's ORDER and ROUTING, not re-proving NodeWorktree's git
# mechanics (n3 already does that) or a real test suite's own correctness.
class RunnerAbsorbTest < Minitest::Test
  INTENT_ID = "340"
  INTENT_SLUG = "absorb-fixture"

  # --- a configurable worktree double ------------------------------------------

  class FakeWorktree
    attr_reader :calls, :released

    def initialize(changed: [], merge_result: { ok: true, commit: "c0ffee00", conflicted: [], error: nil },
                   paths: { "path" => nil, "branch" => nil, "repo" => nil })
      @changed = changed
      @merge_result = merge_result
      @paths_value = paths
      @calls = []
      @released = []
    end

    def paths(_context, node:)
      @paths_value
    end

    def changed_paths(_context, node:, runner:)
      @calls << :changed_paths
      @changed
    end

    def merge(_context, node:, runner:)
      @calls << :merge
      @merge_result
    end

    def release(_context, node:, state:, runner:)
      @released << [node, state]
      { ok: true, removed: true }
    end
  end

  # --- an intercepting ledger for row 4.40 -------------------------------------

  class UnavailableLedger
    def append_transition(*)
      raise GuardedAppend::Unavailable, "lock contention (fixture)"
    end
  end

  def setup
    @root = Dir.mktmpdir("absorb-intent")
    @dir = File.join(@root, "#{INTENT_ID}--#{INTENT_SLUG}")
    FileUtils.mkdir_p(@dir)
    @home = Dir.mktmpdir("absorb-home")
    @node_wt = Dir.mktmpdir("absorb-node-wt")
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
    FileUtils.remove_entry(@node_wt) if @node_wt && Dir.exist?(@node_wt)
  end

  # --- fixture helpers -----------------------------------------------------------

  def build_context(kind: "work", files: ["scripts/lib/foo.rb"], worktree: @dir, worktree_branch: "plastic/x")
    RunnerCore::Context.new(
      intent_dir: @dir, intent_id: INTENT_ID, intent_slug: INTENT_SLUG,
      store: nil, plastic_home: @home, session: nil,
      worktree: worktree, worktree_branch: worktree_branch,
      graph: { ok: true, edges: {}, nodes: { "n4" => { kind: kind, files: files } } },
      errors: []
    )
  end

  def line(subject, state, fields = nil, ts: "2026-01-01T00:00:00Z", **kwfields)
    fields = (fields || {}).merge(kwfields)
    rendered = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
    rendered = " #{rendered}" unless rendered.empty?
    "#{ts}  #{subject}  #{state}#{rendered}\n"
  end

  def write_savepoint(content)
    File.write(File.join(@dir, "savepoint.md"), content)
  end

  def savepoint_content
    File.read(File.join(@dir, "savepoint.md"))
  end

  def running_line(node: "n4", holder: "auto-abc")
    line(node, "running", holder: holder, expires: "2026-01-01T01:00:00Z", packet: "deadbeef", model: "sonnet")
  end

  def write_node_file(node = "n4", tests: ["runner_absorb_fixture_test#test_ok"])
    path = File.join(@dir, "nodes", "#{node}.md")
    FileUtils.mkdir_p(File.dirname(path))
    rows = tests.each_with_index.map { |t, i| "| #{i + 1} | op | fail | `#{t}` |" }
    File.write(path, <<~MD)
      ---
      node: #{node}
      kind: work
      files: [scripts/lib/foo.rb]
      budget: 1000
      ---
      # #{node} - fixture

      ## #{node} failure-mode matrix
      | Row | Operation | Failure mode | Test |
      | --- | --- | --- | --- |
      #{rows.join("\n")}
    MD
  end

  def touch_named_test(basename = "runner_absorb_fixture_test")
    path = File.join(@node_wt, "test", "#{basename}.rb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# fixture\n")
  end

  def write_return(status: "done", commit: "exec1234", extra: {})
    doc = { "node" => "n4", "status" => status }
    doc["commit"] = commit if commit
    doc.merge!(extra.transform_keys(&:to_s))
    path = File.join(@root, "return-#{rand(1_000_000)}.yaml")
    require "yaml"
    File.write(path, YAML.dump(doc))
    path
  end

  def ok_integrity
    ->(plastic_home:) { { ok: true, drifted: [], missing: [], reason: nil } }
  end

  def drifted_integrity(drifted: ["scripts/lib/x.rb"], missing: [])
    ->(plastic_home:) { { ok: false, drifted: drifted, missing: missing, reason: "hash mismatch" } }
  end

  def ok_suite(runs: 10, assertions: 20)
    ->(dir:, command:) { { ok: true, runs: runs, assertions: assertions, failures: 0, errors: 0 } }
  end

  def red_suite(runs: 5, assertions: 5, failures: 1, errors: 0)
    ->(dir:, command:) { { ok: false, runs: runs, assertions: assertions, failures: failures, errors: errors } }
  end

  def command_reader(cmd = "ruby -e 1")
    ->(_intent_dir) { cmd }
  end

  def no_command_reader
    ->(_intent_dir) { nil }
  end

  # A fully wired happy-path call: integrity ok, named test present, scope
  # in-files, clean merge, green suite -> done. Every keyword can be
  # overridden per test.
  def absorb_happy(node: "n4", kind: "work", files: ["scripts/lib/foo.rb"], changed: ["scripts/lib/foo.rb"],
                    merge_result: { ok: true, commit: "c0ffee00", conflicted: [], error: nil },
                    integrity: ok_integrity, allow_core_drift: false,
                    suite: ok_suite, project_reader: command_reader,
                    return_status: "done", return_commit: "exec1234", return_extra: {},
                    ledger: NodeLedger, now: Time.utc(2026, 1, 2))
    write_node_file(node)
    touch_named_test
    fake_wt = FakeWorktree.new(changed: changed, merge_result: merge_result,
                                paths: { "path" => @node_wt, "branch" => "plastic/x--n4", "repo" => @dir })
    context = build_context(kind: kind, files: files)
    return_path = write_return(status: return_status, commit: return_commit, extra: return_extra)

    result = RunnerAbsorb.absorb(
      context, node: node, return_path: return_path, now: now, allow_core_drift: allow_core_drift,
      integrity_checker: integrity, worktree: fake_wt, ledger: ledger,
      suite_runner: suite, project_reader: project_reader
    )
    [result, fake_wt, return_path]
  end

  # --- 4.13 / 4.14: integrity checked first, blocked on drift ---------------------

  def test_integrity_checked_before_transition
    write_savepoint(running_line)
    write_node_file
    fake_wt = FakeWorktree.new
    context = build_context

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: write_return, integrity_checker: drifted_integrity,
      worktree: fake_wt, suite_runner: ok_suite, project_reader: command_reader
    )

    assert_equal "blocked", result[:state]
    assert_empty fake_wt.calls, "no worktree call must happen before integrity is checked"
    assert_equal "integrity", result[:gates]
  end

  def test_drift_blocks_and_records_reason
    write_savepoint(running_line)
    write_node_file
    context = build_context

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: write_return, integrity_checker: drifted_integrity,
      worktree: FakeWorktree.new
    )

    assert_equal "blocked", result[:state]
    assert result[:written]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "core_integrity", entry[:fields]["reason"]
  end

  # --- 4.15: --allow-core-drift is recorded on the line --------------------------

  def test_allow_core_drift_is_recorded
    write_savepoint(running_line)
    result, = absorb_happy(integrity: drifted_integrity, allow_core_drift: true)

    assert_equal "done", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "true", entry[:fields]["allow_core_drift"]
  end

  # --- 4.16: diff outside declared files: ----------------------------------------

  def test_diff_outside_files_fails_verification
    write_savepoint(running_line)
    result, fake_wt = absorb_happy(files: ["scripts/lib/foo.rb"], changed: ["scripts/lib/foo.rb", "scripts/other.rb"])

    assert_equal "failed_verification", result[:state]
    assert_equal "integrity+schema+scope", result[:gates]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "diff_outside_files", entry[:fields]["reason"]
    refute_includes fake_wt.calls, :merge
  end

  # --- 4.17 / 4.18: any diff at all on verify/research is refused ----------------

  def test_any_diff_on_verify_fails_verification
    write_savepoint(running_line)
    result, = absorb_happy(kind: "verify", files: [], changed: ["scripts/some_review.md"])

    assert_equal "failed_verification", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "diff_on_verify_node", entry[:fields]["reason"]
  end

  def test_any_diff_on_research_fails_verification
    write_savepoint(running_line)
    result, = absorb_happy(kind: "research", files: [], changed: ["notes.md"])

    assert_equal "failed_verification", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "diff_on_research_node", entry[:fields]["reason"]
  end

  # --- 4.19: a named test file that does not exist --------------------------------

  def test_named_test_missing_fails_verification
    write_savepoint(running_line)
    write_node_file("n4", tests: ["missing_fixture_test#test_never_written"])
    # deliberately never touch test/missing_fixture_test.rb
    fake_wt = FakeWorktree.new(paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = build_context

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: write_return, integrity_checker: ok_integrity,
      worktree: fake_wt, suite_runner: ok_suite, project_reader: command_reader
    )

    assert_equal "failed_verification", result[:state]
    assert_equal "integrity+schema+scope+named_tests", result[:gates]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "named_test_missing", entry[:fields]["reason"]
  end

  # --- 4.20: a clean merge records its commit -------------------------------------

  def test_clean_merge_records_commit
    write_savepoint(running_line)
    result, = absorb_happy(merge_result: { ok: true, commit: "abc123def", conflicted: [], error: nil })

    assert_equal "done", result[:state]
    assert_equal "abc123def", result[:commit]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "abc123def", entry[:fields]["commit"]
  end

  # --- 4.21: a conflict entirely inside files: --------------------------------

  def test_conflict_inside_files_fails_verification
    write_savepoint(running_line)
    result, = absorb_happy(
      files: ["scripts/lib/foo.rb"],
      merge_result: { ok: false, commit: nil, conflicted: ["scripts/lib/foo.rb"], error: "conflict" }
    )

    assert_equal "failed_verification", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "merge_conflict", entry[:fields]["reason"]
  end

  # --- 4.22: a conflict outside files: needs a decision, names the paths ---------

  def test_conflict_outside_files_needs_decision_with_paths
    write_savepoint(running_line)
    result, = absorb_happy(
      files: ["scripts/lib/foo.rb"],
      merge_result: { ok: false, commit: nil, conflicted: ["scripts/other/unrelated.rb"], error: "conflict" }
    )

    assert_equal "needs_decision", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_includes entry[:fields]["question"], "scripts/other/unrelated.rb"
  end

  # --- 4.36: the synthesized question always carries the paths -------------------

  def test_conflict_needs_decision_carries_question
    write_savepoint(running_line)
    result, = absorb_happy(
      files: ["scripts/lib/foo.rb"],
      merge_result: { ok: false, commit: nil, conflicted: ["scripts/lib/other_dir/x.rb"], error: "conflict" }
    )

    assert_equal "needs_decision", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    refute_nil entry[:fields]["question"]
    assert_includes entry[:fields]["question"], "scripts/lib/other_dir/x.rb"
  end

  # --- 4.23: done carries the runner-measured suite --------------------------------

  def test_done_line_carries_runner_measured_suite
    write_savepoint(running_line)
    result, = absorb_happy(suite: ok_suite(runs: 42, assertions: 108))

    assert_equal "done", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "42/108/0/0", entry[:fields]["suite"]
  end

  # --- 4.24: a red suite fails verification -----------------------------------------

  def test_red_suite_fails_verification
    write_savepoint(running_line)
    result, = absorb_happy(suite: red_suite(runs: 5, assertions: 5, failures: 1, errors: 0))

    assert_equal "failed_verification", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "suite_red", entry[:fields]["reason"]
    assert_equal "5/5/1/0", entry[:fields]["suite"]
    assert_equal "integrity+schema+scope+named_tests+merge+suite", entry[:fields]["gates"]
  end

  # --- 4.25: the suite runs only after a clean merge --------------------------------

  def test_suite_runs_on_merged_tree
    write_savepoint(running_line)
    suite_calls = []
    spy_suite = ->(dir:, command:) { suite_calls << dir; { ok: true, runs: 1, assertions: 1, failures: 0, errors: 0 } }

    result, = absorb_happy(
      merge_result: { ok: false, commit: nil, conflicted: ["scripts/lib/foo.rb"], error: "x" },
      suite: spy_suite
    )

    assert_equal "failed_verification", result[:state]
    assert_empty suite_calls, "the suite must never run when the merge itself failed"
  end

  # --- 4.26: exactly one transition per return --------------------------------------

  def test_one_transition_per_return
    write_savepoint(running_line)
    before = NodeLedger.entries(File.join(@dir, "savepoint.md")).length
    absorb_happy
    after = NodeLedger.entries(File.join(@dir, "savepoint.md")).length

    assert_equal before + 1, after
  end

  # --- 4.27: findings land as one capped bullet -------------------------------------

  def test_findings_append_one_capped_line
    write_savepoint(running_line)
    long_findings = (1..10).map { |i| "finding number #{i} is a fairly long sentence about something durable" }

    absorb_happy(return_extra: { findings: long_findings })

    findings = OutcomeReport.findings(@dir)
    assert_equal 1, findings.length
    assert findings.first.length <= 200
  end

  # --- 4.28: the rest of the return is discarded ------------------------------------

  def test_return_body_is_not_recorded
    write_savepoint(running_line)
    absorb_happy(return_extra: { summary: "THIS SUMMARY MUST NEVER LAND ANYWHERE ON DISK" })

    refute_includes savepoint_content, "THIS SUMMARY"
    record = File.read(File.join(@dir, "#{File.basename(@dir)}.md")) rescue ""
    refute_includes record, "THIS SUMMARY"
  end

  # --- 4.29: a failing absorb keeps the node worktree --------------------------------

  def test_failing_absorb_keeps_worktree
    write_savepoint(running_line)
    _result, fake_wt = absorb_happy(files: ["scripts/lib/foo.rb"], changed: ["scripts/lib/foo.rb", "scripts/other.rb"])

    assert_empty fake_wt.released
  end

  # --- 4.30: absorbing a return for a node that is not running is refused ----------

  def test_return_for_non_running_node_is_refused
    write_savepoint(line("n4", "done", holder: "auto-abc", gates: "integrity+schema+scope+named_tests+merge+suite",
                          commit: "abc123"))
    before = NodeLedger.entries(File.join(@dir, "savepoint.md")).length

    context = build_context
    result = RunnerAbsorb.absorb(context, node: "n4", return_path: write_return, integrity_checker: ok_integrity,
                                  worktree: FakeWorktree.new)

    assert_equal "refused", result[:state]
    assert_equal "node_not_running", result[:reason]
    after = NodeLedger.entries(File.join(@dir, "savepoint.md")).length
    assert_equal before, after, "nothing must be written for a stale return"
  end

  # --- 4.31 / 4.32 / 4.33: gates= on both terminal outcomes, only what ran ---------

  def test_done_line_carries_gates
    write_savepoint(running_line)
    absorb_happy
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "integrity+schema+scope+named_tests+merge+suite", entry[:fields]["gates"]
  end

  def test_failed_verification_line_carries_gates
    write_savepoint(running_line)
    absorb_happy(files: ["scripts/lib/foo.rb"], changed: ["scripts/other.rb"])
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "failed_verification", entry[:state]
    refute_nil entry[:fields]["gates"]
  end

  def test_gates_lists_only_checks_that_ran
    write_savepoint(running_line)
    absorb_happy(files: ["scripts/lib/foo.rb"], changed: ["scripts/other.rb"])
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "integrity+schema+scope", entry[:fields]["gates"]
  end

  # --- 4.34: holder= on every written line --------------------------------------

  def test_every_written_line_carries_holder
    write_savepoint(running_line(holder: "auto-holder-1"))
    result, = absorb_happy
    assert_equal "done", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "auto-holder-1", entry[:fields]["holder"]

    write_savepoint(running_line(holder: "auto-holder-2"))
    result2, = absorb_happy(files: ["scripts/lib/foo.rb"], changed: ["scripts/other.rb"])
    entry2 = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "failed_verification", result2[:state]
    assert_equal "auto-holder-2", entry2[:fields]["holder"]
  end

  # --- 4.35: the ### Findings subsection is created when absent ----------------------

  def test_findings_subsection_created_when_absent
    write_savepoint(running_line)
    record_path = File.join(@dir, "#{File.basename(@dir)}.md")
    File.write(record_path, "# fixture\n\n## Insights\n(observations)\n")

    absorb_happy(return_extra: { findings: ["a durable discovery"] })

    body = File.read(record_path)
    assert_includes body, "### Findings"
    assert_equal ["[n4] a durable discovery"], OutcomeReport.findings(@dir)
  end

  # --- 4.39: an absent verify command writes suite=none, gates records suite:absent -

  def test_absent_verify_command_writes_suite_none
    write_savepoint(running_line)
    result, = absorb_happy(project_reader: no_command_reader)

    assert_equal "done", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "none", entry[:fields]["suite"]
    assert_equal "integrity+schema+scope+named_tests+merge+suite:absent", entry[:fields]["gates"]
  end

  # --- 4.40: an append failure after a landed merge still reports the commit --------

  def test_append_failure_after_merge_reports_commit
    write_savepoint(running_line)
    result, = absorb_happy(merge_result: { ok: true, commit: "landed999", conflicted: [], error: nil },
                            ledger: UnavailableLedger.new)

    assert_equal "append_failed", result[:state]
    refute result[:written]
    assert_equal "landed999", result[:commit]
  end

  # --- 4.41: the node worktree is removed only after the done line lands -------------

  def test_worktree_removed_after_done_line_lands
    write_savepoint(running_line)
    result, fake_wt = absorb_happy

    assert_equal "done", result[:state]
    assert_equal [["n4", "done"]], fake_wt.released
  end

  # --- 4.42: the return file is kept beside the packet ------------------------------

  def test_return_file_kept_beside_packet
    write_savepoint(running_line)
    _result, _fake_wt, original_return_path = absorb_happy

    kept = File.join(@dir, "packets", "n4--a1.return")
    assert File.exist?(kept), "the return must be copied to packets/n4--a1.return"
    assert_equal File.read(original_return_path), File.read(kept)
  end

  # --- 4.43: drift is recorded under the field key core_drift -----------------------

  def test_core_drift_field_key
    write_savepoint(running_line)
    write_node_file
    context = build_context

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: write_return,
      integrity_checker: drifted_integrity(drifted: ["scripts/lib/x.rb"], missing: ["scripts/lib/y.rb"]),
      worktree: FakeWorktree.new
    )

    assert_equal "blocked", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert entry[:fields].key?("core_drift")
    assert_includes entry[:fields]["core_drift"], "scripts/lib/x.rb"
    assert_includes entry[:fields]["core_drift"], "scripts/lib/y.rb"
  end

  # --- 4.44: absorb re-renders graph.md's ## Status ------------------------------------

  def test_absorb_rerenders_graph_status
    write_savepoint(running_line)
    graph_path = File.join(@dir, "graph.md")
    File.write(graph_path, <<~MD)
      # Graph

      ## Graph
      - n4 needs nothing

      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
      | n4 | planned |  |
    MD

    absorb_happy

    body = File.read(graph_path)
    refute_match(/\| n4 \| planned \|/, body)
    assert_match(/\| n4 \| done \|/, body)
  end
end
