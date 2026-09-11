# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require "open3"

require_relative "../scripts/lib/runner_absorb"
require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/guarded_append"
require_relative "../scripts/lib/outcome_report"
require_relative "../scripts/lib/runner_proposals"
require_relative "../scripts/lib/node_worktree"
require_relative "../scripts/lib/runner_answer"
require_relative "../scripts/lib/atomic_write"

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

    def changed_paths(_context, node:, kind:, runner:)
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

  # --- a configurable RunnerProposals double for rows 10.2/10.3 ---------------

  class ProposalsSpy
    attr_reader :calls

    def initialize(result: { ok: true, minted: ["n9"], validator: { ok: true, errors: [] }, errors: [] })
      @calls = []
      @result = result
    end

    def accept(_context, proposer:, proposed_nodes: [], proposed_edges: [], now: Time.now)
      @calls << { proposer: proposer, proposed_nodes: proposed_nodes, proposed_edges: proposed_edges }
      @result
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

  def build_context(node: "n4", kind: "work", files: ["scripts/lib/foo.rb"], worktree: @dir,
                     worktree_branch: "plastic/x", plastic_home: @home)
    RunnerCore::Context.new(
      intent_dir: @dir, intent_id: INTENT_ID, intent_slug: INTENT_SLUG,
      store: nil, plastic_home: plastic_home, session: nil,
      worktree: worktree, worktree_branch: worktree_branch,
      graph: { ok: true, edges: {}, nodes: { node => { kind: kind, files: files } } },
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

  # Row 10.17: writes a fixture test FILE that also defines the named METHOD,
  # not just a comment - `missing_named_tests?` now proves the method exists,
  # so a fixture carrying only "# fixture" would wrongly read as missing for
  # every test in this file that expects the named-tests gate to pass.
  def touch_named_test(basename = "runner_absorb_fixture_test", method: "test_ok")
    path = File.join(@node_wt, "test", "#{basename}.rb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, <<~RUBY)
      # fixture
      class RunnerAbsorbFixtureTest < Minitest::Test
        def #{method}
        end
      end
    RUBY
  end

  def write_return(node: "n4", status: "done", commit: "exec1234", extra: {})
    doc = { "node" => node, "status" => status }
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

  # ============================================================================
  # n9: the post-execution review's four blockers plus two majors
  # ============================================================================

  # --- 9.1/9.4: the return's own status governs, not just the schema gate --------

  def test_needs_decision_return_writes_needs_decision
    write_savepoint(running_line)
    write_node_file
    fake_wt = FakeWorktree.new(paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = build_context
    return_path = write_return(status: "needs_decision", commit: nil,
                                extra: { question: "should scripts/lib/foo.rb keep its old name?" })

    result = RunnerAbsorb.absorb(context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
                                  worktree: fake_wt)

    assert_equal "needs_decision", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "needs_decision", entry[:state]
    refute_equal "done", entry[:state], "an unfinished return must never unblock downstream nodes as done"
  end

  # --- 9.2: the needs_decision line carries the question --------------------------

  def test_needs_decision_line_carries_the_question
    write_savepoint(running_line)
    write_node_file
    context = build_context
    return_path = write_return(status: "needs_decision", commit: nil,
                                extra: { question: "does scripts/lib/foo.rb need a second reviewer?" })

    RunnerAbsorb.absorb(context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
                         worktree: FakeWorktree.new)

    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "does scripts/lib/foo.rb need a second reviewer?", entry[:fields]["question"]
  end

  # --- 9.3: blocked and failed_verification write their own state and reason -----

  def test_self_reported_failure_writes_its_own_state_and_reason
    write_savepoint(running_line)
    write_node_file
    context = build_context
    blocked_path = write_return(status: "blocked", commit: nil, extra: { reason: "waiting on an owner decision" })

    blocked_result = RunnerAbsorb.absorb(context, node: "n4", return_path: blocked_path,
                                          integrity_checker: ok_integrity, worktree: FakeWorktree.new)

    assert_equal "blocked", blocked_result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "blocked", entry[:state]
    assert_equal "waiting on an owner decision", entry[:fields]["reason"]

    write_savepoint(running_line)
    failed_path = write_return(status: "failed_verification", commit: nil,
                                extra: { reason: "the executor could not make the suite pass" })

    failed_result = RunnerAbsorb.absorb(context, node: "n4", return_path: failed_path,
                                         integrity_checker: ok_integrity, worktree: FakeWorktree.new)

    assert_equal "failed_verification", failed_result[:state]
    entry2 = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "failed_verification", entry2[:state]
    assert_equal "the executor could not make the suite pass", entry2[:fields]["reason"]
  end

  # --- 9.4: checks 3-6 never run for a non-done return -----------------------------

  def test_mechanical_checks_run_only_for_a_done_return
    write_savepoint(running_line)
    write_node_file
    fake_wt = FakeWorktree.new(paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = build_context
    return_path = write_return(status: "blocked", commit: nil, extra: { reason: "waiting on an owner decision" })

    result = RunnerAbsorb.absorb(context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
                                  worktree: fake_wt, suite_runner: ok_suite, project_reader: command_reader)

    assert_equal "blocked", result[:state]
    assert_empty fake_wt.calls, "scope, named_tests and merge must never run for a non-done return"
    assert_equal "integrity+schema", result[:gates]
  end

  # --- 9.6: RunnerProposals' template dir resolves under the corrected home ------

  def test_proposals_template_dir_resolves_under_dot_plastic
    plastic_home = File.join(@home, ".plastic")
    templates_dir = File.join(plastic_home, "templates")
    FileUtils.mkdir_p(templates_dir)
    File.write(File.join(templates_dir, "node-work.md"), <<~MD)
      ---
      node: n1
      kind: work
      files: []
      budget: 1000
      ---
      # n1 - template

      ## n1 failure-mode matrix
      | Row | Operation | Failure mode | Test |
      | --- | --- | --- | --- |

      ## Steps
      1. do it

      ## Proven by
      (filled at close)
    MD

    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: Fixture

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      - n4 needs nothing

      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD

    context = build_context(plastic_home: plastic_home)
    result = RunnerProposals.accept(
      context, proposer: "n4",
      proposed_nodes: [{ "kind" => "work", "title" => "New work", "needs" => [] }],
      proposed_edges: [],
      validator: ->(_dir) { { ok: true, errors: [] } }
    )

    assert result[:ok], "scaffolding must reach templates/node-work.md under the CORRECTED .plastic dir: #{result.inspect}"
    assert_equal 1, result[:minted].length
    minted_id = result[:minted].first
    assert File.exist?(File.join(@dir, "nodes", "#{minted_id}.md")),
           "the proposed node's file must be scaffolded from the real template"
  end

  # --- 9.10: a real commit on the intent branch fails a verify node's scope ------

  def test_verify_node_with_a_diff_fails_scope
    repo = Dir.mktmpdir("absorb-real-repo")
    begin
      real_git("init", "-q", "-b", "alpha", dir: repo)
      real_git("config", "user.email", "absorb@example.com", dir: repo)
      real_git("config", "user.name", "Absorb Test", dir: repo)
      real_git("config", "gc.auto", "0", dir: repo)
      File.write(File.join(repo, "README.md"), "hi\n")
      real_git("add", "README.md", dir: repo)
      real_git("commit", "-q", "-m", "init", dir: repo)

      intent_worktree = File.join(repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}")
      intent_branch = "plastic/#{INTENT_ID}--#{INTENT_SLUG}"
      FileUtils.mkdir_p(File.dirname(intent_worktree))
      real_git("worktree", "add", intent_worktree, "-b", intent_branch, dir: repo)

      # The reviewer's own reproduction: a verify node's executor edits the
      # code it is reviewing and commits it directly onto the intent branch -
      # there is no node branch of its own for a verify node to isolate that
      # commit on, which is exactly what the fix must still catch.
      File.write(File.join(intent_worktree, "reviewed.rb"), "# edited by the reviewer\n")
      real_git("add", "reviewed.rb", dir: intent_worktree)
      real_git("commit", "-q", "-m", "v1 edits the code it is reviewing", dir: intent_worktree)

      write_savepoint(running_line(node: "v1"))
      write_node_file("v1")
      context = build_context(node: "v1", kind: "verify", files: [], worktree: intent_worktree,
                               worktree_branch: intent_branch)
      return_path = write_return(node: "v1", status: "done", commit: "shouldnotmatter")

      result = RunnerAbsorb.absorb(context, node: "v1", return_path: return_path, integrity_checker: ok_integrity,
                                    worktree: NodeWorktree, suite_runner: ok_suite, project_reader: command_reader)

      assert_equal "failed_verification", result[:state]
      entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
      assert_equal "diff_on_verify_node", entry[:fields]["reason"]
    ensure
      FileUtils.remove_entry(repo) if repo && Dir.exist?(repo)
    end
  end

  # --- 9.11: an unmeasurable diff fails verification, never passes ---------------

  def test_unmeasurable_diff_fails_verification
    write_savepoint(running_line)
    result, = absorb_happy(changed: nil)

    assert_equal "failed_verification", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "scope_unmeasurable", entry[:fields]["reason"]
    assert_equal "integrity+schema+scope", entry[:fields]["gates"]
  end

  # --- 9.14: a project.yml that fails to parse blocks, never reads as absent -----

  def test_unparsable_project_record_blocks_with_verify_command_unreadable
    slug = "demo-project"
    @dir = File.join(@root, "projects", slug, "store", "#{INTENT_ID}--#{INTENT_SLUG}")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    write_savepoint(running_line)
    write_node_file
    touch_named_test

    File.write(File.join(@root, "projects", slug, "project.yml"), "release:\n  verify: \"unterminated\n")

    fake_wt = FakeWorktree.new(changed: ["scripts/lib/foo.rb"],
                                paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = build_context
    return_path = write_return(status: "done", commit: "exec1234")

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
      worktree: fake_wt, project_reader: RunnerAbsorb.method(:default_project_reader)
    )

    assert_equal "blocked", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "verify_command_unreadable", entry[:fields]["reason"]
  end

  # --- 9.15: gates= claims a merge only when a merge actually ran ------------------

  def test_gates_records_merge_only_for_a_work_node
    write_savepoint(running_line)
    result, = absorb_happy(kind: "work")
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_includes entry[:fields]["gates"].split("+"), "merge"
    refute_includes entry[:fields]["gates"].split("+"), "merge:none"

    write_savepoint(running_line)
    write_node_file("n4", tests: [])
    context = build_context(kind: "research", files: [])
    fake_wt = FakeWorktree.new(changed: [], paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    return_path = write_return(status: "done", commit: "r1")

    result2 = RunnerAbsorb.absorb(
      context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
      worktree: fake_wt, suite_runner: ok_suite, project_reader: command_reader
    )

    assert_equal "done", result2[:state]
    entry2 = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_includes entry2[:fields]["gates"].split("+"), "merge:none"
    refute_includes entry2[:fields]["gates"].split("+"), "merge"
  end

  def real_git(*args, dir:)
    out, err, status = Open3.capture3("git", "-C", dir, *args.map(&:to_s))
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  # --- 10.2: a proposal is accepted from production, not just validated -------

  def test_absorb_accepts_a_proposed_node
    write_savepoint(running_line)
    write_node_file
    touch_named_test
    fake_wt = FakeWorktree.new(paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = build_context
    return_path = write_return(
      extra: { "proposed_nodes" => [{ "kind" => "work", "title" => "New work", "needs" => [] }] }
    )
    proposals = ProposalsSpy.new

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
      worktree: fake_wt, suite_runner: ok_suite, project_reader: command_reader, proposals: proposals
    )

    assert_equal "done", result[:state]
    assert_equal 1, proposals.calls.length, "RunnerProposals.accept must be called in production, not merely tested alone"
    assert_equal "n4", proposals.calls.first[:proposer]
    assert_equal 1, proposals.calls.first[:proposed_nodes].length
  end

  # --- 10.3: a refused proposal is surfaced in the step report ----------------

  def test_refused_proposal_is_reported
    write_savepoint(running_line)
    write_node_file
    touch_named_test
    fake_wt = FakeWorktree.new(paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = build_context
    return_path = write_return(
      extra: { "proposed_nodes" => [{ "kind" => "work", "title" => "New work", "needs" => [] }] }
    )
    proposals = ProposalsSpy.new(
      result: { ok: false, minted: [], validator: nil,
                errors: ["edge n9->n10 refused (would_cycle): would make the graph cyclic"] }
    )

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
      worktree: fake_wt, suite_runner: ok_suite, project_reader: command_reader, proposals: proposals
    )

    assert_equal "done", result[:state]
    refute_nil result[:proposal], "a refused proposal must land in absorb's own result, not be silently dropped"
    refute result[:proposal][:ok]
    assert_includes result[:proposal][:errors].join, "would_cycle"
  end

  # --- 10.5: a superseded node releases its own worktree (M5) -----------------

  def test_superseded_node_releases_its_worktree
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: Fixture

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      - n1 needs nothing

      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
    write_node_file("n1")
    write_savepoint(
      running_line(node: "n1", holder: "h") +
      line("n1", "running", holder: "h", expires: "2026-01-01T02:00:00Z", packet: "p2", model: "sonnet") +
      line("n1", "running", holder: "h", expires: "2026-01-01T03:00:00Z", packet: "p3", model: "sonnet") +
      line("n1", "needs_decision", question: "capped")
    )
    fake_wt = FakeWorktree.new(paths: { "path" => @node_wt, "branch" => "plastic/x--n1", "repo" => @dir })
    context = build_context(node: "n1", kind: "work")

    result = RunnerAnswer.answer(context, node: "n1", text: "retry it", worktree: fake_wt)

    assert result[:ok], result.inspect
    refute_nil result[:respun_to], "a hard-capped node at needs_decision must respin, superseding itself"
    assert_includes fake_wt.released, ["n1", "superseded"],
                     "RunnerAnswer.respin must release the superseded node's own worktree (D7)"
  end

  # --- 10.15: findings land through GuardedAppend, keeping the trailing newline (M12) ---

  def test_findings_are_appended_under_the_guard
    write_savepoint(running_line)
    record_path = File.join(@dir, "#{INTENT_ID}--#{INTENT_SLUG}.md")
    File.write(record_path, <<~MD)
      ---
      id: "#{INTENT_ID}"
      intent: t
      ---

      ## Intent
      body

      ## Insights
      (observations captured throughout)

      ### Findings
      - [n1] existing finding
    MD

    result, = absorb_happy(return_extra: { "findings" => ["a brand new finding"] })
    assert_equal "done", result[:state]

    content = File.read(record_path)
    assert content.end_with?("\n"), "the intent record must keep its trailing newline: #{content.inspect}"
    refute_match(/\n\n- \[n4\] a brand new finding/, content,
                 "the new bullet must not land after a spurious blank line")
    assert_match(/- \[n4\] a brand new finding\n\z/, content)
  end

  # --- 10.17: the named-tests gate checks the method, not only the file -------

  def test_named_tests_gate_checks_the_method_not_the_file
    write_savepoint(running_line)
    write_node_file("n4", tests: ["runner_absorb_fixture_test#test_ok"])
    touch_named_test("runner_absorb_fixture_test", method: "test_something_else")
    fake_wt = FakeWorktree.new(paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = build_context

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: write_return, integrity_checker: ok_integrity,
      worktree: fake_wt, suite_runner: ok_suite, project_reader: command_reader
    )

    assert_equal "failed_verification", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "named_test_missing", entry[:fields]["reason"],
                 "the file exists but the exact named method does not - the gate must still refuse"
  end

  # === n11: what the fold broke (v2 review) ===================================

  # A ledger double whose FIRST call raises ArgumentError (standing in for
  # any return prose the ledger refuses to write, whatever it is) and whose
  # every later call delegates to the real NodeLedger - proving
  # write_transition's own fallback actually lands a real, valid line.
  class UnwritableOnceLedger
    def initialize
      @calls = 0
    end

    def append_transition(*args, **kwargs)
      @calls += 1
      raise ArgumentError, "value must not contain a tab or a newline (fixture)" if @calls == 1

      NodeLedger.append_transition(*args, **kwargs)
    end
  end

  def write_malformed_graph
    bad = "# Graph: Demo\n\n## Goal\nG\n\n## Decisions\n- D1 x\n\n## Graph\n" \
          "- n4 needs nothing\n\xFF\xFE bad bytes\n\n## Status\n| Node | State | Detail |\n| --- | --- | --- |\n"
    File.binwrite(File.join(@dir, "graph.md"), bad)
  end

  # --- 11.1: a multi-line question is squashed into one ledger field (v2 NEW-1) --

  def test_multiline_question_is_normalized_into_one_field
    write_savepoint(running_line)
    write_node_file
    touch_named_test
    fake_wt = FakeWorktree.new(paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = build_context
    return_path = write_return(status: "needs_decision", commit: nil,
                                extra: { "question" => "Line one?\nLine two, with detail." })

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
      worktree: fake_wt, suite_runner: ok_suite, project_reader: command_reader
    )

    assert_equal "needs_decision", result[:state]
    assert result[:written], result.inspect
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    refute_match(/[\t\n]/, entry[:raw], "the ledger line itself must never carry a raw tab or newline")
    assert_equal "Line one? Line two, with detail.", entry[:fields]["question"]
  end

  # --- 11.2: a return whose prose the ledger still refuses blocks, never raises (v2 NEW-1) --

  def test_unwritable_return_prose_blocks_rather_than_raises
    write_savepoint(running_line)
    write_node_file
    touch_named_test
    fake_wt = FakeWorktree.new(paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = build_context
    return_path = write_return(status: "needs_decision", commit: nil, extra: { "question" => "a real question" })
    ledger = UnwritableOnceLedger.new

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
      worktree: fake_wt, suite_runner: ok_suite, project_reader: command_reader, ledger: ledger
    )

    assert_equal "blocked", result[:state]
    assert result[:written], result.inspect
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "blocked", entry[:state]
    assert_equal "return_unwritable", entry[:fields]["reason"]
  end

  # --- 11.3: an unresolvable kind blocks rather than writing done (v2 NEW-2) ----

  def test_unresolvable_kind_blocks_rather_than_writing_done
    write_savepoint(running_line)
    write_node_file
    touch_named_test
    fake_wt = FakeWorktree.new(paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = RunnerCore::Context.new(
      intent_dir: @dir, intent_id: INTENT_ID, intent_slug: INTENT_SLUG,
      store: nil, plastic_home: @home, session: nil,
      worktree: @dir, worktree_branch: "plastic/x",
      graph: { ok: false, edges: {}, nodes: {}, errors: ["graph.md could not be read"] },
      errors: []
    )
    return_path = write_return(status: "done", commit: "exec1234")

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
      worktree: fake_wt, suite_runner: ok_suite, project_reader: command_reader
    )

    refute_equal "done", result[:state],
                 "an unresolvable kind must never let done land on unverified work"
    assert_equal "blocked", result[:state]
    assert_empty fake_wt.calls, "no worktree call must happen once the graph is unresolvable"
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "blocked", entry[:state]
    assert_equal "invalid_graph", entry[:fields]["reason"]
  end

  # --- 11.4: an unmerged commit can never land on done, proven against a real branch (v2 NEW-2) --

  def test_done_requires_the_commit_to_be_merged
    repo = Dir.mktmpdir("absorb-real-repo")
    begin
      real_git("init", "-q", "-b", "alpha", dir: repo)
      real_git("config", "user.email", "t@example.com", dir: repo)
      real_git("config", "user.name", "Test", dir: repo)
      real_git("config", "gc.auto", "0", dir: repo)
      File.write(File.join(repo, "README.md"), "hi\n")
      real_git("add", "README.md", dir: repo)
      real_git("commit", "-q", "-m", "init", dir: repo)

      # A real intent worktree, the shape NodeWorktree itself expects
      # (`<repo>/.claude/worktrees/<id>--<slug>`) - the ONLY honest way to
      # drive absorb's own scope/merge machinery for real, rather than a
      # bare repo path a fixture merely hands it.
      intent_branch = "plastic/#{INTENT_ID}--#{INTENT_SLUG}"
      intent_worktree = File.join(repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}")
      FileUtils.mkdir_p(File.dirname(intent_worktree))
      real_git("worktree", "add", intent_worktree, "-b", intent_branch, dir: repo)

      # A commit that genuinely exists in the repo but is NOT reachable from
      # the intent branch - exactly the shape an executor's self-reported
      # commit takes when NEW-2's merge is skipped entirely.
      real_git("checkout", "-q", "-b", "off-branch-work", dir: repo)
      File.write(File.join(repo, "unmerged.txt"), "x\n")
      real_git("add", "unmerged.txt", dir: repo)
      real_git("commit", "-q", "-m", "never merged", dir: repo)
      unmerged_commit = real_git("rev-parse", "HEAD", dir: repo).strip

      write_savepoint(running_line)
      # No named tests declared: with `kind` unresolvable, the named-tests
      # gate would otherwise check the wrong directory (the intent worktree,
      # never a per-node one that was never provisioned for this node) and
      # refuse for an unrelated reason before ever reaching the merge this
      # row is actually about.
      write_node_file("n4", tests: [])

      # graph.md is unresolvable (context.graph[:ok] is false) - NEW-2's
      # exact reproduction - so absorb must refuse before it ever reaches a
      # merge or a `done` write.
      context = RunnerCore::Context.new(
        intent_dir: @dir, intent_id: INTENT_ID, intent_slug: INTENT_SLUG,
        store: nil, plastic_home: @home, session: nil,
        worktree: intent_worktree, worktree_branch: intent_branch,
        graph: { ok: false, edges: {}, nodes: {}, errors: ["graph.md could not be read"] },
        errors: []
      )
      return_path = write_return(status: "done", commit: unmerged_commit)

      result = RunnerAbsorb.absorb(
        context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
        worktree: NodeWorktree, suite_runner: ok_suite, project_reader: command_reader
      )

      refute_equal "done", result[:state],
                   "an unresolvable kind must never let an unmerged, self-reported commit land as done: #{result.inspect}"
      entries = NodeLedger.entries(File.join(@dir, "savepoint.md"))
      refute(entries.any? { |e| e[:subject] == "n4" && e[:state] == "done" },
             "no done line may ever be written for this commit")

      _out, _err, status = Open3.capture3("git", "-C", repo, "merge-base", "--is-ancestor", unmerged_commit,
                                           intent_branch)
      refute status.success?,
             "fixture sanity: the commit must genuinely NOT be an ancestor of the intent branch"
    ensure
      FileUtils.remove_entry(repo) if repo && Dir.exist?(repo)
    end
  end

  # --- 11.5: gates= says suite:unreadable on that state, never a bare suite (v2 NEW-3) --

  def test_gates_says_suite_unreadable_on_that_state
    slug = "demo-project-unreadable"
    @dir = File.join(@root, "projects", slug, "store", "#{INTENT_ID}--#{INTENT_SLUG}")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    write_savepoint(running_line)
    write_node_file
    touch_named_test
    File.write(File.join(@root, "projects", slug, "project.yml"), "release:\n  verify: \"unterminated\n")

    fake_wt = FakeWorktree.new(changed: ["scripts/lib/foo.rb"],
                                paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = build_context
    return_path = write_return(status: "done", commit: "exec1234")

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
      worktree: fake_wt, project_reader: RunnerAbsorb.method(:default_project_reader)
    )

    assert_equal "blocked", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    gates = entry[:fields]["gates"].split("+")
    assert_includes gates, "suite:unreadable"
    refute_includes gates, "suite"
  end

  # --- 11.6: the findings append no longer claims a guard it lacks (v2 NEW-4) --

  def test_finding_append_does_not_claim_a_guard_it_lacks
    record_path = File.join(@dir, "#{INTENT_ID}--#{INTENT_SLUG}.md")
    File.write(record_path, <<~MD)
      ---
      id: "#{INTENT_ID}"
      intent: t
      ---

      ## Intent
      body

      ## Insights
      (observations captured throughout)
    MD

    # A concurrent flock held on the SAME path, exactly the hold
    # GuardedAppend itself would take under the old shape - the previous
    # code took this same lock and, on contention, retried for ~100ms and
    # then silently dropped the finding. Proving append_findings now lands
    # its write regardless is proof the false guard is gone.
    holder = File.open(record_path, File::RDWR)
    holder.flock(File::LOCK_EX)
    begin
      write_savepoint(running_line)
      result, = absorb_happy(return_extra: { "findings" => ["a concurrent finding"] })
      assert_equal "done", result[:state]
    ensure
      holder.flock(File::LOCK_UN)
      holder.close
    end

    content = File.read(record_path)
    assert_match(/- \[n4\] a concurrent finding/, content,
                 "append_findings must land its write even while another session holds the old flock")
  end

  # --- 11.7: the findings append stays atomic without the false guard (v2 NEW-4) --

  def test_finding_append_stays_atomic
    record_path = File.join(@dir, "#{INTENT_ID}--#{INTENT_SLUG}.md")
    original = <<~MD
      ---
      id: "#{INTENT_ID}"
      intent: t
      ---

      ## Intent
      body

      ## Insights
      (observations captured throughout)
    MD
    File.write(record_path, original)

    failing_renamer = ->(_from, _to) { raise Errno::EACCES, "fixture: rename refused" }

    result = RunnerAbsorb.send(:append_findings, @dir, "n4", ["a finding that never lands"], now: Time.now,
                                renamer: failing_renamer)

    assert_nil result, "a failed append is best-effort, D16 - it must never raise into absorb"
    assert_equal original, File.read(record_path),
                 "a failed rename must never leave a half-written or truncated intent record"
    refute(Dir.glob(File.join(@dir, ".*.tmp.*")).any?,
           "AtomicWrite must clean up its own temp file on a failed rename")
  end

  # --- 11.8: the proposal path refuses a malformed graph without raising (v2 NEW-5) --

  def test_proposal_path_refuses_a_malformed_graph_without_raising
    write_savepoint(running_line)
    write_node_file
    touch_named_test
    # graph.md on disk is malformed even though the context resolved before
    # this step started still says ok: true (it was parsed once, earlier) -
    # RunnerProposals re-reads graph.md fresh from disk on its own, never
    # trusting context.graph, and that fresh read hits the real invalid byte
    # sequence.
    write_malformed_graph
    fake_wt = FakeWorktree.new(paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = build_context
    return_path = write_return(
      extra: { "proposed_nodes" => [{ "kind" => "work", "title" => "New work", "needs" => [] }] }
    )

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
      worktree: fake_wt, suite_runner: ok_suite, project_reader: command_reader
    )

    assert_equal "done", result[:state]
    refute_nil result[:proposal], "a malformed graph.md must still report a proposal refusal, never raise"
    refute result[:proposal][:ok]
    assert_match(/unreadable/i, result[:proposal][:errors].join)
  end

  # --- 11.13: an accepted proposal's own validator verdict is reported (v2 minor 8) --

  def test_proposal_validator_verdict_is_reported
    write_savepoint(running_line)
    write_node_file
    touch_named_test
    record_path = File.join(@dir, "#{INTENT_ID}--#{INTENT_SLUG}.md")
    File.write(record_path, <<~MD)
      ---
      id: "#{INTENT_ID}"
      intent: t
      ---

      ## Intent
      body
    MD
    fake_wt = FakeWorktree.new(paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = build_context
    return_path = write_return(
      extra: { "proposed_nodes" => [{ "kind" => "work", "title" => "New work", "needs" => [] }] }
    )
    proposals = ProposalsSpy.new(
      result: { ok: true, minted: ["n9"],
                validator: { ok: false, missing: [], errors: ["cyclic graph, cannot validate: n9 > n9"] },
                errors: [] }
    )

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
      worktree: fake_wt, suite_runner: ok_suite, project_reader: command_reader, proposals: proposals
    )

    assert_equal "done", result[:state]
    content = File.read(record_path)
    assert_match(/\[n4\].*invalidates the graph/, content)
    assert_match(/cyclic graph/, content)
  end

  # --- 11.14: a proposal is applied only on a done return (v2 minor 11) --------

  def test_proposals_are_not_applied_on_a_failing_return
    write_savepoint(running_line)
    write_node_file
    touch_named_test
    fake_wt = FakeWorktree.new(paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = build_context
    return_path = write_return(
      status: "failed_verification", commit: nil,
      extra: { "reason" => "broke ci", "proposed_nodes" => [{ "kind" => "work", "title" => "New work", "needs" => [] }] }
    )
    proposals = ProposalsSpy.new

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
      worktree: fake_wt, suite_runner: ok_suite, project_reader: command_reader, proposals: proposals
    )

    assert_equal "failed_verification", result[:state]
    assert_empty proposals.calls, "a failing return must never grow the graph"
    assert_nil result[:proposal]
  end

  # --- 11.15: a project.yml that parses to a non-Hash is unreadable, not absent (v2 minor 13) --

  def test_non_hash_project_record_is_unreadable
    slug = "demo-project-non-hash"
    @dir = File.join(@root, "projects", slug, "store", "#{INTENT_ID}--#{INTENT_SLUG}")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    write_savepoint(running_line)
    write_node_file
    touch_named_test
    File.write(File.join(@root, "projects", slug, "project.yml"), "- just\n- an\n- array\n")

    fake_wt = FakeWorktree.new(changed: ["scripts/lib/foo.rb"],
                                paths: { "path" => @node_wt, "branch" => "x", "repo" => @dir })
    context = build_context
    return_path = write_return(status: "done", commit: "exec1234")

    result = RunnerAbsorb.absorb(
      context, node: "n4", return_path: return_path, integrity_checker: ok_integrity,
      worktree: fake_wt, project_reader: RunnerAbsorb.method(:default_project_reader)
    )

    assert_equal "blocked", result[:state]
    entry = NodeLedger.entries(File.join(@dir, "savepoint.md")).last
    assert_equal "verify_command_unreadable", entry[:fields]["reason"]
  end

  # --- 11.17: the suite counts come from the LAST summary line (v1 minor 7) ----

  def test_suite_counts_come_from_the_last_summary
    dir = Dir.mktmpdir("absorb-suite-fixture")
    script = File.join(dir, "fake_suite.rb")
    File.write(script, <<~RUBY)
      puts "3 runs, 3 assertions, 1 failures, 0 errors"
      puts "10 runs, 20 assertions, 0 failures, 0 errors"
    RUBY

    result = RunnerAbsorb.default_suite_runner(dir: dir, command: "ruby #{script}")

    assert result[:ok], result.inspect
    assert_equal 10, result[:runs]
    assert_equal 20, result[:assertions]
    assert_equal 0, result[:failures]
    assert_equal 0, result[:errors]
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end
end
