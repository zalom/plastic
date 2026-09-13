# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "time"

require_relative "../scripts/lib/runner_watch"
require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/runner_sweep"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/worktree"

# RunnerWatch (intent 340a, G7b, n1): one tick over disk truth. Matrix rows
# 1.1-1.18 in nodes/n1.md. Hermetic: every fixture lives under Dir.mktmpdir,
# every git call goes through an injected fake runner, no real ~/.plastic is
# ever touched.
class RunnerWatchTest < Minitest::Test
  INTENT_ID = "340a"
  INTENT_SLUG = "watch-fixture"

  # A fake ShellRunner, same shape as RunnerSweepTest's: records every call
  # and answers via a block, defaulting to "not found" (exit 1).
  class FakeRunner
    attr_reader :calls

    def initialize(&block)
      @calls = []
      @responder = block
    end

    def run(*args)
      @calls << args.map(&:to_s)
      r = @responder ? @responder.call(args.map(&:to_s)) : nil
      r || Worktree::ShellRunner::Result.new(1, "", "")
    end
  end

  # A sweep double that proves D3: it delegates abort_if_merging and reclaim
  # to the real RunnerSweep, but raises if anything ever calls #run - the
  # heartbeating composed entry point RunnerWatch must never touch.
  module RunGuardSweep
    module_function

    def abort_if_merging(context, runner:)
      RunnerSweep.abort_if_merging(context, runner: runner)
    end

    def reclaim(context, runner:, skip: [], now: Time.now)
      RunnerSweep.reclaim(context, runner: runner, skip: skip, now: now)
    end

    def run(*)
      raise "RunnerWatch must never call RunnerSweep.run"
    end
  end

  def setup
    @dir = Dir.mktmpdir("watch-intent")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  # --- fixture helpers -----------------------------------------------------------

  def build_context(worktree: nil, graph: { ok: true, edges: { "n1" => [] }, nodes: { "n1" => { kind: "work", files: [] } }, errors: [] })
    RunnerCore::Context.new(
      intent_dir: @dir, intent_id: INTENT_ID, intent_slug: INTENT_SLUG,
      store: nil, plastic_home: @dir, session: nil,
      worktree: worktree, worktree_branch: "plastic/#{INTENT_ID}--#{INTENT_SLUG}",
      graph: graph, errors: []
    )
  end

  def write_savepoint(content)
    File.write(File.join(@dir, "savepoint.md"), content)
  end

  def line(subject, state, fields = nil, ts: "2026-09-13T00:00:00Z", **kwfields)
    fields = (fields || {}).merge(kwfields)
    rendered = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
    rendered = " #{rendered}" unless rendered.empty?
    "#{ts}  #{subject}  #{state}#{rendered}\n"
  end

  def running_fields(expires:, holder: "auto-abc", packet: "deadbeef", model: "sonnet")
    { holder: holder, expires: expires, packet: packet, model: model }
  end

  def write_state(fingerprint:, quiet_ticks:, tick:, at: "2026-09-13T00:00:00Z")
    File.write(File.join(@dir, "watch.state"),
               JSON.generate("fingerprint" => fingerprint, "quiet_ticks" => quiet_ticks, "tick" => tick, "at" => at))
  end

  def read_state
    JSON.parse(File.read(File.join(@dir, "watch.state")))
  end

  def state_path
    File.join(@dir, "watch.state")
  end

  def record_path
    File.join(@dir, "watch.record")
  end

  def one_node_graph
    { ok: true, edges: { "n1" => [] }, nodes: { "n1" => { kind: "work", files: [] } }, errors: [] }
  end

  def blocked_graph
    { ok: true, edges: { "n1" => ["n2"], "n2" => [] },
      nodes: { "n1" => { kind: "work", files: [] }, "n2" => { kind: "work", files: [] } }, errors: [] }
  end

  # --- 1.1: the tick lock ----------------------------------------------------------

  def test_concurrent_tick_is_busy_and_writes_nothing
    write_savepoint("")
    other = File.open(File.join(@dir, "watch.lock"), File::CREAT | File::RDWR, 0o644)
    other.flock(File::LOCK_EX)

    begin
      ctx = build_context(graph: one_node_graph)
      result = RunnerWatch.tick(ctx, runner: FakeRunner.new)

      assert result[:busy]
      refute File.exist?(state_path)
      refute File.exist?(record_path)
    ensure
      other.flock(File::LOCK_UN)
      other.close
    end
  end

  # --- 1.2: never heartbeats -------------------------------------------------------

  def test_tick_never_heartbeats_the_lock
    write_savepoint("")
    ctx = build_context(graph: one_node_graph)

    result = RunnerWatch.tick(ctx, runner: FakeRunner.new, sweep: RunGuardSweep)

    refute result[:busy]
  end

  # --- 1.3: refuses on a merge in progress ------------------------------------------

  def test_merge_in_progress_refuses_the_tick
    write_savepoint("")
    runner = FakeRunner.new { |args| Worktree::ShellRunner::Result.new(0, "abcd1234\n", "") if args.include?("MERGE_HEAD") }
    ctx = build_context(worktree: "/fake/worktree", graph: one_node_graph)

    result = RunnerWatch.tick(ctx, runner: runner)

    assert_equal "merge_in_progress", result[:class]
    assert(result[:blockers].any? { |b| b.include?("merge is in progress") })
    refute File.exist?(state_path)
    refute File.exist?(record_path)
  end

  # --- 1.4: reclaim goes through RunnerSweep.reclaim --------------------------------

  def test_expired_lease_is_reclaimed_through_runner_sweep
    write_savepoint(line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z")))
    ctx = build_context(graph: one_node_graph)

    result = RunnerWatch.tick(ctx, runner: FakeRunner.new, now: Time.iso8601("2026-09-13T00:00:00Z"))

    assert_equal ["n1"], result[:reclaimed]
    assert_match(/n1\s+reclaimed/, File.read(File.join(@dir, "savepoint.md")))
  end

  # --- 1.5: closed -------------------------------------------------------------------

  def test_done_line_classifies_closed
    write_savepoint(line("Intent", "blocked", reason: "irrelevant") + "2026-09-13T00:00:00Z  Done  delivered\n")
    ctx = build_context(graph: one_node_graph)

    result = RunnerWatch.tick(ctx, runner: FakeRunner.new)

    assert_equal "closed", result[:class]
  end

  # --- 1.6: done_unreported -----------------------------------------------------------

  def test_all_terminal_without_done_is_done_unreported
    write_savepoint(line("n1", "done", gates: "g1", commit: "c1"))
    ctx = build_context(graph: one_node_graph)

    result = RunnerWatch.tick(ctx, runner: FakeRunner.new)

    assert_equal "done_unreported", result[:class]
  end

  # --- 1.7: first tick is moving -------------------------------------------------------

  def test_first_tick_is_moving
    write_savepoint("")
    ctx = build_context(graph: one_node_graph)

    result = RunnerWatch.tick(ctx, runner: FakeRunner.new)

    assert_equal "moving", result[:class]
    assert_equal ["n1"], result[:ready]
    assert_equal 1, read_state["tick"]
    assert_equal 0, read_state["quiet_ticks"]
  end

  # --- 1.8: changed fingerprint resets quiet -------------------------------------------

  def test_changed_ledger_is_moving_and_resets_quiet
    write_savepoint("")
    write_state(fingerprint: "stale-fingerprint", quiet_ticks: 5, tick: 5)
    ctx = build_context(graph: one_node_graph)

    result = RunnerWatch.tick(ctx, runner: FakeRunner.new)

    assert_equal "moving", result[:class]
    assert_equal 0, read_state["quiet_ticks"]
    assert_equal 6, read_state["tick"]
  end

  # --- 1.9: unchanged once is quiet -----------------------------------------------------

  def test_unchanged_once_is_quiet
    write_savepoint(line("n1", "running", running_fields(expires: "2026-09-13T01:00:00Z")))
    ctx = build_context(graph: one_node_graph)
    fingerprint = RunnerWatch.fingerprint(ctx, runner: FakeRunner.new)
    write_state(fingerprint: fingerprint, quiet_ticks: 0, tick: 1)

    result = RunnerWatch.tick(ctx, runner: FakeRunner.new, now: Time.iso8601("2026-09-13T00:30:00Z"))

    assert_equal "quiet", result[:class]
    assert_equal 1, read_state["quiet_ticks"]
  end

  # --- 1.10: unchanged twice, no live lease, is stalled ----------------------------------

  def test_unchanged_twice_without_live_lease_is_stalled
    write_savepoint(line("n1", "failed_verification", gates: "g1", reason: "broke"))
    ctx = build_context(graph: one_node_graph)
    fingerprint = RunnerWatch.fingerprint(ctx, runner: FakeRunner.new)
    write_state(fingerprint: fingerprint, quiet_ticks: 1, tick: 2)

    result = RunnerWatch.tick(ctx, runner: FakeRunner.new)

    assert_equal "stalled", result[:class]
  end

  # --- 1.11: an unexpired lease keeps it quiet ----------------------------------------

  def test_live_lease_keeps_a_quiet_intent_quiet
    write_savepoint(line("n1", "running", running_fields(expires: "2026-09-13T02:00:00Z")))
    ctx = build_context(graph: one_node_graph)
    fingerprint = RunnerWatch.fingerprint(ctx, runner: FakeRunner.new)
    write_state(fingerprint: fingerprint, quiet_ticks: 1, tick: 2)

    result = RunnerWatch.tick(ctx, runner: FakeRunner.new, now: Time.iso8601("2026-09-13T00:30:00Z"))

    assert_equal "quiet", result[:class]
  end

  # --- 1.12: blocked graph is stalled with blockers ------------------------------------

  def test_blocked_graph_is_stalled_with_blockers
    write_savepoint("")
    ctx = build_context(graph: blocked_graph)

    result = RunnerWatch.tick(ctx, runner: FakeRunner.new)

    assert_equal "stalled", result[:class]
    assert_equal [], result[:ready]
    refute_empty result[:blockers]
    assert(result[:blockers].any? { |b| b.include?("n1") })
  end

  # --- 1.13: the branch head joins the fingerprint --------------------------------------

  def test_branch_commit_counts_as_movement
    write_savepoint("")
    ctx = build_context(worktree: "/fake/worktree", graph: one_node_graph)
    runner_a = FakeRunner.new { |args| Worktree::ShellRunner::Result.new(0, "sha-one\n", "") if args.include?("HEAD") }
    RunnerWatch.tick(ctx, runner: runner_a)

    runner_b = FakeRunner.new { |args| Worktree::ShellRunner::Result.new(0, "sha-two\n", "") if args.include?("HEAD") }
    result = RunnerWatch.tick(ctx, runner: runner_b)

    assert_equal "moving", result[:class]
  end

  # --- 1.14: watch.state is git-ignored -------------------------------------------------

  def test_snapshot_is_git_ignored
    write_savepoint("")
    ctx = build_context(graph: one_node_graph)

    RunnerWatch.tick(ctx, runner: FakeRunner.new)

    gitignore = File.read(File.join(@dir, ".gitignore"))
    assert_includes gitignore.each_line.map(&:strip), "watch.state"
  end

  # --- 1.15: the record line's field order -----------------------------------------------

  def test_record_line_carries_class_ready_and_dispatched
    write_savepoint("")
    ctx = build_context(graph: one_node_graph)

    RunnerWatch.tick(ctx, runner: FakeRunner.new, now: Time.iso8601("2026-09-13T03:00:00Z"))

    lines = File.read(record_path).each_line.to_a
    assert_equal 1, lines.length
    assert_match(
      /\A2026-09-13T03:00:00Z {2}tick=1 class=moving reclaimed=- ready=n1 dispatched=- harness=- meter=- lock=held\n\z/,
      lines.first
    )
  end

  # --- 1.16: record: false writes nothing -------------------------------------------------

  def test_unrecorded_tick_writes_no_snapshot_or_record
    write_savepoint("")
    ctx = build_context(graph: one_node_graph)

    result = RunnerWatch.tick(ctx, runner: FakeRunner.new, record: false)

    assert_equal "moving", result[:class]
    refute File.exist?(state_path)
    refute File.exist?(record_path)
  end

  # --- 1.17: an unparsable snapshot is replaced -------------------------------------------

  def test_unparsable_snapshot_is_replaced
    write_savepoint("")
    File.write(state_path, "{not json")
    ctx = build_context(graph: one_node_graph)

    result = RunnerWatch.tick(ctx, runner: FakeRunner.new)

    assert_equal "moving", result[:class]
    assert_equal 1, read_state["tick"]
    assert_equal 0, read_state["quiet_ticks"]
  end

  # --- 1.18: a malformed graph.md is stalled with the graph error -------------------------

  def test_malformed_graph_is_stalled_with_the_error
    write_savepoint("")
    ctx = build_context(graph: { ok: false, edges: {}, nodes: {}, errors: ["missing ## Graph section"] })

    result = RunnerWatch.tick(ctx, runner: FakeRunner.new)

    assert_equal "stalled", result[:class]
    assert_equal ["missing ## Graph section"], result[:blockers]
  end
end
