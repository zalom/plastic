# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require "time"
require "yaml"
require "json"
require "stringio"

require_relative "../scripts/lib/runner_until_empty"
require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/runner_absorb"

# RunnerUntilEmpty (intent 340b, G7c, n7): the Codex loop. Matrix rows
# 7.1-7.5 and 7.7-7.11 and 7.15 in nodes/n7.md (7.6, 7.12, 7.13 live in
# runner_cli_test.rb and runner_install_test.rb; 7.14 lives in
# install_sync_test.rb).
#
# Rows about the loop's own stop conditions and its "absorb before the next
# dispatch" ordering drive #run directly with an injected `step:` double, no
# repository at all - the fastest, most deterministic way to prove a pure
# control-flow claim. Rows that need a real dispatch to prove something
# lands on the ledger (--harness threading, serial absorb against a real
# graph, the index.lock collision) drive the REAL #step_once against a
# throwaway git repo, with a fake `node_run_spawner`/`node_run_waiter` that
# never spawns a real subprocess. Only 7.1 (real concurrency) and 7.15 (the
# CLI arm) drive a real `node-run` subprocess, against a stub `codex` on
# PATH - never the real binary: no network, no API key, no live model call
# anywhere in this file.
class RunnerUntilEmptyTest < Minitest::Test
  INTENT_ID = "1"
  INTENT_SLUG = "demo"
  PROJECT_SLUG = "demo-proj"
  SCRIPT = File.expand_path("../scripts/runner", __dir__)

  def setup
    @home = Dir.mktmpdir("until-empty-home")
    @store = File.join(@home, ".plastic", "projects", PROJECT_SLUG, "store")
    @dir = File.join(@store, "#{INTENT_ID}--#{INTENT_SLUG}")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    File.write(File.join(@dir, "#{INTENT_ID}--#{INTENT_SLUG}.md"),
               "---\nid: \"#{INTENT_ID}\"\nintent: t\n---\n\n## Intent\nbody\n")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
    FileUtils.remove_entry(@repo) if @repo && Dir.exist?(@repo)
    Array(@scratch_dirs).each { |d| FileUtils.remove_entry(d) if d && Dir.exist?(d) }
  end

  # --- fixture helpers -----------------------------------------------------------

  def write_graph(graph_body, decisions: "- D1 pick approach", goal: "Ship it.")
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: Demo

      ## Goal
      #{goal}

      ## Decisions
      #{decisions}

      ## Graph
      #{graph_body}
      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
  end

  # A 3-column fixture table (Operation, Failure mode, Test), never the
  # real 4-column (Row, Operation, Failure mode, Test) matrix shape - the
  # same fixture runner_cli_test.rb and node_run_cli_test.rb both use.
  # RunnerAbsorb's own named_tests check reads the FOURTH cell of each row
  # (the real matrix's own Test column), so this 3-column table always
  # reads as blank there and never demands a test file that does not exist,
  # while still satisfying WorkGraphValidator's has_valid_matrix? (a table
  # under a heading naming the node, with at least one row).
  MATRIX = <<~MD
    | Operation | Failure mode | Test |
    | --- | --- | --- |
    | op | mode | a test |
  MD

  def write_node(filename, node:, kind:, files: [], budget: 100_000, body: nil)
    body ||= "# #{node} - a node\n\n## #{node} failure-mode matrix\n#{MATRIX}\n## Steps\n1. do it\n\n" \
             "## Proven by\n(filled at close)\n"
    File.write(File.join(@dir, "nodes", filename), <<~MD)
      ---
      node: #{node}
      kind: #{kind}
      files: #{files.inspect}
      budget: #{budget}
      ---
      #{body}
    MD
  end

  def write_work_nodes(*ids)
    ids.each { |id| write_node("#{id}.md", node: id, kind: "work") }
  end

  def savepoint_path
    File.join(@dir, "savepoint.md")
  end

  def write_lock(owner:)
    File.write(File.join(@dir, "delivery.lock"),
               JSON.generate("type" => "delivery", "owner_session" => owner, "delegates" => []))
  end

  def git(*args, dir: @repo)
    out, err, status = Open3.capture3("git", "-C", dir, *args.map(&:to_s))
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  # A real throwaway git repo, registered in projects.yml, with the intent
  # worktree already checked out on the intent branch - the same fixture
  # node_run_cli_test.rb and runner_cli_test.rb both use, the only honest
  # way to let RunnerDispatch actually provision a work node's own worktree
  # and let RunnerAbsorb actually merge it back.
  def setup_real_repo
    @repo = Dir.mktmpdir("ue-repo")
    git("init", "-q", "-b", "alpha")
    git("config", "user.email", "ue@example.com")
    git("config", "user.name", "UE Test")
    git("config", "gc.auto", "0")
    File.write(File.join(@repo, "README.md"), "hi\n")
    git("add", "README.md")
    git("commit", "-q", "-m", "init")

    FileUtils.mkdir_p(File.join(@home, ".plastic"))
    File.write(File.join(@home, ".plastic", "projects.yml"),
               YAML.dump("projects" => { PROJECT_SLUG => { "path" => @repo } }))

    @intent_worktree = File.join(@repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}")
    @intent_branch = "plastic/#{INTENT_ID}--#{INTENT_SLUG}"
    FileUtils.mkdir_p(File.dirname(@intent_worktree))
    git("worktree", "add", @intent_worktree, "-b", @intent_branch)
  end

  def context_for(session: "sess-1")
    RunnerCore.context(intent_dir: @dir, home: @home, env: session)
  end

  # A fake node_run_spawner/waiter pair: no real subprocess, no real codex -
  # each "spawn" writes a return file straight to disk and hands back a
  # handle a fake waiter can serve later. `bodies` maps node id to either a
  # Hash (dumped as the YAML return document) or a literal String (written
  # verbatim - the shape a genuinely unparsable return takes).
  def fake_node_run(bodies: {}, stderrs: {})
    scratch = Dir.mktmpdir("ue-fake-returns")
    (@scratch_dirs ||= []) << scratch

    spawner = lambda do |_context, node:, harness: nil|
      path = File.join(scratch, "#{node}-#{rand(1_000_000)}.return")
      body = bodies[node] || { "status" => "done", "commit" => "c-#{node}" }
      body = body.is_a?(Hash) ? YAML.dump({ "node" => node }.merge(body)) : body
      File.write(path, body)
      { node: node, return_path: path, stderr: stderrs[node].to_s }
    end
    waiter = ->(active) { [active.values.first] }
    [spawner, waiter]
  end

  # A stand-in `codex` binary, never the real one: derives its own node id
  # from `-C <worktree>` (a node worktree's own basename is always
  # `<intent_id>--<intent_slug>--<node>`, NodeWorktree's own naming rule),
  # reads and discards stdin, optionally records a concurrency snapshot
  # (row 7.1) before a short sleep, then writes a `done` return.
  def write_concurrency_stub(bin_dir, marker_dir: nil, sleep_for: 0)
    path = File.join(bin_dir, "codex")
    File.write(path, <<~'RUBY')
      #!/usr/bin/env ruby
      def opt(args, *names)
        i = args.index { |a| names.include?(a) }
        i && args[i + 1]
      end

      args = ARGV.dup
      out_path = opt(args, "-o", "--output-last-message")
      cdir = opt(args, "-C", "--cd")
      $stdin.read

      node = File.basename(cdir.to_s).split("--").last
      marker_dir = ENV["UE_MARKER_DIR"]

      if marker_dir && !marker_dir.empty?
        own_marker = File.join(marker_dir, "active-#{node}-#{Process.pid}")
        File.write(own_marker, "1")
        count = Dir.glob(File.join(marker_dir, "active-*")).length
        File.open(File.join(marker_dir, "snapshots.log"), "a") { |f| f.puts(count) }
      end

      sleep(ENV["UE_SLEEP_FOR"].to_f) if ENV["UE_SLEEP_FOR"] && !ENV["UE_SLEEP_FOR"].empty?
      File.delete(own_marker) if marker_dir && own_marker && File.exist?(own_marker)

      File.write(out_path, "node: #{node}\nstatus: done\ncommit: c-#{node}\nsummary: ok\n") if out_path
    RUBY
    FileUtils.chmod(0o755, path)
    path
  end

  def with_stub_path(bin_dir, extra_env = {})
    original_path = ENV["PATH"]
    extra_env.each { |k, v| ENV[k] = v }
    ENV["PATH"] = "#{bin_dir}#{File::PATH_SEPARATOR}#{original_path}"
    yield
  ensure
    ENV["PATH"] = original_path
    extra_env.each_key { |k| ENV.delete(k) }
  end

  # === 7.7-7.11: the four stop conditions, plus a refused step ============
  # Driven entirely off an injected `step:` double - pure control flow, no
  # repository, no ledger.

  def test_stops_on_complete
    out = StringIO.new
    step = ->(*, **) { { ok: true, status: "complete", dispatched: [], absorbed: [] } }

    result = RunnerUntilEmpty.run(nil, step: step, node_run_spawner: ->(*, **) { flunk "must not spawn" },
                                        node_run_waiter: ->(*) { flunk "must not wait" }, out: out)

    assert_equal "complete", result[:status]
    assert_match(/\bcomplete\b/, out.string)
  end

  def test_stops_on_stalled
    out = StringIO.new
    blockers = ["n2: needs target n1"]
    step = ->(*, **) { { ok: true, status: "stalled", dispatched: [], blockers: blockers, absorbed: [] } }

    result = RunnerUntilEmpty.run(nil, step: step, node_run_spawner: ->(*, **) { flunk "must not spawn" },
                                        node_run_waiter: ->(*) { flunk "must not wait" }, out: out)

    assert_equal "stalled", result[:status]
    assert_equal blockers, result[:blockers]
    assert_match(/blocked: n2/, out.string)
  end

  def test_stops_on_needs_decision
    out = StringIO.new
    stop = { node: "d1", question: "Which approach should this take?",
             answer_command: "runner answer /x --node d1 --answer \"<your answer>\"" }
    step = ->(*, **) { { ok: true, status: "needs_decision", dispatched: [], stop: stop, absorbed: [] } }

    result = RunnerUntilEmpty.run(nil, step: step, node_run_spawner: ->(*, **) { flunk "must not spawn" },
                                        node_run_waiter: ->(*) { flunk "must not wait" }, out: out)

    assert_equal "needs_decision", result[:status]
    assert_equal stop, result[:stop]
    assert_match(/needs_decision: d1/, out.string)
    assert_match(/runner answer/, out.string)
  end

  def test_stops_at_iteration_cap
    out = StringIO.new
    step = ->(*, **) { { ok: true, status: "dispatched", dispatched: ["n1"], absorbed: [] } }
    spawner = ->(*, **) { { node: "n1" } }
    waiter = ->(_active) { [{ node: "n1", return_path: nil, stderr: "" }] }

    result = RunnerUntilEmpty.run(nil, max_iterations: 3, step: step, node_run_spawner: spawner,
                                        node_run_waiter: waiter, out: out)

    assert_equal "iteration_cap", result[:status]
    assert_equal 3, result[:iterations]
    assert_match(/iteration cap/, out.string)
  end

  def test_stops_on_a_refused_step
    out = StringIO.new
    calls = 0
    step = lambda do |*, **|
      calls += 1
      { ok: false, reason: "merge_in_progress" }
    end

    result = RunnerUntilEmpty.run(nil, step: step, node_run_spawner: ->(*, **) { flunk "must not spawn" },
                                        node_run_waiter: ->(*) { flunk "must not wait" }, out: out)

    assert_equal "refused", result[:status]
    assert_equal "merge_in_progress", result[:reason]
    assert_equal 1, calls, "a refused step must stop the loop immediately, never retry it as an empty dispatch"
    assert_match(/step refused/, out.string)
  end

  # === 7.5: --harness threads into EVERY step, not only the first ==========

  def test_harness_flag_threads_into_each_step
    setup_real_repo
    write_graph("- verify: none reason=fixture\n- n1 needs nothing\n- n2 needs n1\n")
    write_work_nodes("n1", "n2")
    write_lock(owner: "sess-1")
    context = context_for

    spawner, waiter = fake_node_run
    result = RunnerUntilEmpty.run(context, harness: "codex", node_run_spawner: spawner, node_run_waiter: waiter,
                                            out: StringIO.new)

    assert_equal "complete", result[:status]
    %w[n1 n2].each do |node|
      running = NodeLedger.entries(savepoint_path).select { |e| e[:subject] == node && e[:state] == "running" }.last
      refute_nil running, "#{node} must have dispatched at all"
      assert_equal "codex", running[:fields]["harness"],
                   "--harness must thread into #{node}'s own dispatch, not only the first node's"
    end
  end

  # === 7.2: absorb never runs re-entrantly, even when two returns land in
  # the same turn ============================================================

  def test_absorbs_serially
    setup_real_repo
    write_graph("- verify: none reason=fixture\n- n1 needs nothing\n- n2 needs nothing\n")
    write_work_nodes("n1", "n2")
    write_lock(owner: "sess-1")
    context = context_for

    in_progress = false
    reentrant = false
    instrumented = Object.new
    instrumented.define_singleton_method(:absorb) do |*args, **kwargs|
      reentrant = true if in_progress
      in_progress = true
      result = RunnerAbsorb.absorb(*args, **kwargs)
      in_progress = false
      result
    end

    step = lambda do |ctx, harness:, returns:|
      RunnerUntilEmpty.step_once(ctx, harness: harness, returns: returns, absorb: instrumented)
    end

    spawner, _waiter = fake_node_run
    both_at_once = ->(active) { active.values }

    result = RunnerUntilEmpty.run(context, step: step, node_run_spawner: spawner, node_run_waiter: both_at_once,
                                            out: StringIO.new)

    refute reentrant, "absorb must never be called re-entrantly - a parallel absorb is purely loop-scheduling risk"
    assert_equal "complete", result[:status]
    assert_equal "done", NodeLedger.status_for(savepoint_path, "n1")
    assert_equal "done", NodeLedger.status_for(savepoint_path, "n2")
  end

  # === 7.3: every return is absorbed before the next dispatch, and the
  # ready set advances ========================================================

  def test_absorbs_each_return
    setup_real_repo
    write_graph("- verify: none reason=fixture\n- n1 needs nothing\n- n2 needs nothing\n- n3 needs n1 n2\n")
    write_work_nodes("n1", "n2", "n3")
    write_lock(owner: "sess-1")
    context = context_for

    spawner, waiter = fake_node_run
    result = RunnerUntilEmpty.run(context, max_iterations: 20, node_run_spawner: spawner, node_run_waiter: waiter,
                                             out: StringIO.new)

    assert_equal "complete", result[:status]
    entries = NodeLedger.entries(savepoint_path)
    %w[n1 n2 n3].each { |n| assert_equal "done", NodeLedger.status_for(savepoint_path, n) }

    n3_running_idx = entries.index { |e| e[:subject] == "n3" && e[:state] == "running" }
    n1_done_idx = entries.rindex { |e| e[:subject] == "n1" && e[:state] == "done" }
    n2_done_idx = entries.rindex { |e| e[:subject] == "n2" && e[:state] == "done" }
    refute_nil n3_running_idx
    assert_operator n1_done_idx, :<, n3_running_idx,
                     "n3 must never dispatch before n1's return was actually absorbed"
    assert_operator n2_done_idx, :<, n3_running_idx,
                     "n3 must never dispatch before n2's return was actually absorbed"
  end

  # === 7.4: a shared index.lock collision is recorded, never used to
  # serialize the two executors ==============================================

  def test_index_lock_collision_is_recorded
    setup_real_repo
    write_graph("- verify: none reason=fixture\n- n1 needs nothing\n- n2 needs nothing\n")
    write_work_nodes("n1", "n2")
    write_lock(owner: "sess-1")
    context = context_for

    collision_body = "node-run - codex exec for n2 failed: fatal: Unable to create " \
                      "'.git/index.lock': File exists.\n"
    spawner, waiter = fake_node_run(bodies: { "n2" => collision_body },
                                     stderrs: { "n2" => "fatal: Unable to create '.git/index.lock': File exists." })

    dispatch_log = []
    step = lambda do |ctx, harness:, returns:|
      result = RunnerUntilEmpty.step_once(ctx, harness: harness, returns: returns)
      dispatch_log << result[:dispatched]
      result
    end

    out = StringIO.new
    result = RunnerUntilEmpty.run(context, max_iterations: 20, step: step, node_run_spawner: spawner,
                                             node_run_waiter: waiter, out: out)

    assert_equal %w[n1 n2], dispatch_log.first.sort,
                 "both independent nodes must dispatch together in the same turn - the loop never serializes them"
    assert_match(/index\.lock collision recorded for n2/, out.string)

    assert_equal "done", NodeLedger.status_for(savepoint_path, "n1"),
                 "n1's own outcome must be unaffected by n2's collision"
    refute_equal "done", NodeLedger.status_for(savepoint_path, "n2")
    assert_includes %w[stalled needs_decision], result[:status]
  end

  # === 7.1: real concurrency, capped at two ================================

  def test_at_most_two_subprocesses
    skip "git not available" unless system("git", "--version", out: File::NULL, err: File::NULL)

    setup_real_repo
    ids = %w[n1 n2 n3 n4]
    graph = "- verify: none reason=fixture\n" + ids.map { |i| "- #{i} needs nothing\n" }.join
    write_graph(graph)
    write_work_nodes(*ids)
    write_lock(owner: "sess-1")
    context = context_for

    bin_dir = Dir.mktmpdir("ue-codex-stub")
    marker_dir = Dir.mktmpdir("ue-markers")
    (@scratch_dirs ||= []).concat([bin_dir, marker_dir])
    write_concurrency_stub(bin_dir)

    result = with_stub_path(bin_dir, "UE_MARKER_DIR" => marker_dir, "UE_SLEEP_FOR" => "0.3") do
      RunnerUntilEmpty.run(context, max_iterations: 30, out: StringIO.new)
    end

    assert_equal "complete", result[:status]
    log_path = File.join(marker_dir, "snapshots.log")
    assert File.exist?(log_path), "the stub codex must have recorded at least one concurrency snapshot"
    snapshots = File.readlines(log_path).map(&:to_i)
    assert_operator snapshots.max, :<=, 2, "must never run more than two node-run subprocesses at once"
    assert_includes snapshots, 2, "the loop must actually run two node-run subprocesses concurrently at least once"
  end

  # === 7.15: the CLI arm - `scripts/runner until-empty` as a real subprocess ===

  def test_subprocess_until_empty_runs
    skip "git not available" unless system("git", "--version", out: File::NULL, err: File::NULL)

    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_work_nodes("n1")
    write_lock(owner: "sess-1")

    bin_dir = Dir.mktmpdir("ue-cli-stub")
    (@scratch_dirs ||= []) << bin_dir
    write_concurrency_stub(bin_dir)

    env = { "CLAUDE_CODE_SESSION_ID" => "sess-1", "PATH" => "#{bin_dir}#{File::PATH_SEPARATOR}#{ENV['PATH']}" }
    out, err, status = Open3.capture3(env, RbConfig.ruby, SCRIPT, "until-empty", @dir)

    assert status.success?, out + err
    assert_equal "done", NodeLedger.status_for(savepoint_path, "n1")
  end
end
