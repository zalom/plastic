# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "time"

require_relative "../scripts/lib/runner_sweep"
require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/node_input"
require_relative "../scripts/lib/worktree"

# RunnerSweep (intent 340, G7, n2): the merge abort, the reclaim, and the
# extension. Matrix rows 2.1-2.21 in actions/ACTION_2.md n2 (2.21 lives in
# install_sync_test.rb).
#
# Rows that need a real commit timestamp (extend vs. reclaim) build a real
# throwaway git repo under Dir.mktmpdir and read the branch's actual
# committer time back out of git - the only honest way to test that decision.
# Rows about the merge-abort check alone use a FakeRunner (no real git call
# needed to prove refusal/ordering).
class RunnerSweepTest < Minitest::Test
  INTENT_ID = "340"
  INTENT_SLUG = "sweep-fixture"

  # A fake ShellRunner. Records every `run(*args)` and answers via a block;
  # defaults to "not found" (exit 1), the safe default for both the
  # MERGE_HEAD probe and a branch `log` call.
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

  def setup
    @home = Dir.mktmpdir("sweep-home")
    @dir = Dir.mktmpdir("sweep-intent", @home)
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
    FileUtils.remove_entry(@repo) if @repo && Dir.exist?(@repo)
  end

  # --- fixture helpers -----------------------------------------------------------

  def build_context(intent_dir: @dir, worktree: nil, session: nil,
                     intent_id: INTENT_ID, intent_slug: INTENT_SLUG)
    RunnerCore::Context.new(
      intent_dir: intent_dir, intent_id: intent_id, intent_slug: intent_slug,
      store: nil, plastic_home: @home, session: session,
      worktree: worktree, worktree_branch: "plastic/#{intent_id}--#{intent_slug}",
      graph: { ok: true, edges: {}, nodes: {} }, errors: []
    )
  end

  def write_savepoint(content, dir: @dir)
    File.write(File.join(dir, "savepoint.md"), content)
  end

  def line(subject, state, fields = {}, ts: "2026-01-01T00:00:00Z")
    rendered = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
    rendered = " #{rendered}" unless rendered.empty?
    "#{ts}  #{subject}  #{state}#{rendered}\n"
  end

  def running_fields(expires:, holder: "auto-abc", input: "deadbeef", model: "sonnet")
    { holder: holder, expires: expires, input: input, model: model }
  end

  def extensions_path(node, attempt)
    File.join(@dir, "attempts", "#{node}--a#{attempt}.extensions")
  end

  # --- real git fixture (branch head + commit time) -------------------------------

  def git(*args)
    out, err, status = Open3.capture3("git", "-C", @repo, *args.map(&:to_s))
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  def init_repo
    @repo = Dir.mktmpdir("sweep-repo")
    git("init", "-q", "-b", "main")
    git("config", "user.email", "sweep@example.com")
    git("config", "user.name", "Sweep Test")
    File.write(File.join(@repo, "README.md"), "hi\n")
    git("add", "README.md")
    git("commit", "-q", "-m", "init")
    @repo
  end

  def node_branch(node, intent_id: INTENT_ID, intent_slug: INTENT_SLUG)
    "plastic/#{intent_id}--#{intent_slug}--#{node}"
  end

  # Creates a commit on the node's own branch and returns its real committer
  # time (read back from git, never assumed).
  def commit_on_node_branch(node, filename: "#{node}.txt")
    branch = node_branch(node)
    git("checkout", "-q", "-b", branch)
    File.write(File.join(@repo, filename), "work\n")
    git("add", filename)
    git("commit", "-q", "-m", "#{node} work")
    git("checkout", "-q", "main")
    Time.iso8601(git("log", "-1", "--format=%cI", branch).strip)
  end

  # --- 2.1/2.3: the merge-head abort check -----------------------------------------

  def test_merge_head_aborts_step
    runner = FakeRunner.new { |args| Worktree::ShellRunner::Result.new(0, "abcd1234\n", "") if args.include?("MERGE_HEAD") }
    ctx = build_context(worktree: "/fake/worktree")

    result = RunnerSweep.abort_if_merging(ctx, runner: runner)

    refute result[:ok]
    assert_match(/merge is in progress/, result[:error])
    assert_equal "git -C /fake/worktree merge --abort", result[:recovery_command]
  end

  def test_clean_tree_does_not_abort
    runner = FakeRunner.new # default: exit 1, no MERGE_HEAD
    ctx = build_context(worktree: "/fake/worktree")

    result = RunnerSweep.abort_if_merging(ctx, runner: runner)

    assert result[:ok]
    assert_nil result[:error]
  end

  # --- 2.2: nothing lands when the abort fires -------------------------------------

  def test_merge_head_abort_leaves_ledger_and_graph_unchanged
    write_savepoint(line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z")))
    graph_path = File.join(@dir, "graph.md")
    File.write(graph_path, "# Graph\n")
    before_savepoint = File.read(File.join(@dir, "savepoint.md"))
    before_graph = File.read(graph_path)

    runner = FakeRunner.new { |args| Worktree::ShellRunner::Result.new(0, "sha\n", "") if args.include?("MERGE_HEAD") }
    ctx = build_context(worktree: "/fake/worktree")

    result = RunnerSweep.run(ctx, runner: runner, now: Time.iso8601("2030-01-01T00:00:00Z"))

    refute result[:ok]
    assert_empty result[:reclaimed]
    assert_empty result[:extended]
    assert_equal before_savepoint, File.read(File.join(@dir, "savepoint.md"))
    assert_equal before_graph, File.read(graph_path)
  end

  # --- 2.17: the recovery command is printed ---------------------------------------

  def test_merge_head_abort_prints_recovery_command
    runner = FakeRunner.new { |args| Worktree::ShellRunner::Result.new(0, "sha\n", "") if args.include?("MERGE_HEAD") }
    ctx = build_context(worktree: "/fake/worktree")

    _out, err = capture_io { RunnerSweep.abort_if_merging(ctx, runner: runner) }

    assert_match(%r{git -C /fake/worktree merge --abort}, err)
  end

  # --- 2.16: the heartbeat runs after the abort check, never before it ------------

  def test_heartbeat_runs_after_abort_check
    order = []
    runner = FakeRunner.new do |args|
      order << :abort_check if args.include?("MERGE_HEAD")
      nil
    end
    heartbeat = lambda { |*_args, **_kwargs| order << :heartbeat; true }
    write_savepoint("")
    ctx = build_context(worktree: "/fake/worktree", session: "auto-xyz")

    RunnerSweep.run(ctx, runner: runner, heartbeat: heartbeat)

    assert_equal [:abort_check, :heartbeat], order
  end

  # --- 2.4/2.5: expired vs. unexpired -----------------------------------------------

  def test_expired_node_with_no_commits_is_reclaimed
    init_repo
    write_savepoint(line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z", holder: "auto-1")))
    ctx = build_context(worktree: @repo)

    result = RunnerSweep.reclaim(ctx, now: Time.iso8601("2030-01-01T00:00:00Z"))

    assert_equal 1, result[:reclaimed].length
    assert_equal "n1", result[:reclaimed].first[:node]
    assert_equal "auto-1", result[:reclaimed].first[:holder]
    assert_equal "planned", NodeLedger.status_for(File.join(@dir, "savepoint.md"), "n1")
  end

  def test_unexpired_node_is_not_reclaimed
    init_repo
    future = (Time.now + 3600).utc.iso8601
    write_savepoint(line("n1", "running", running_fields(expires: future)))
    ctx = build_context(worktree: @repo)

    result = RunnerSweep.reclaim(ctx, now: Time.now)

    assert_empty result[:reclaimed]
    assert_empty result[:extended]
    assert_equal "running", NodeLedger.status_for(File.join(@dir, "savepoint.md"), "n1")
  end

  # --- 2.6/2.7/2.8: extension mechanics ---------------------------------------------

  def test_expired_node_with_new_commits_is_extended
    init_repo
    commit_time = commit_on_node_branch("n1")
    expires = (commit_time - 60).utc.iso8601
    write_savepoint(line("n1", "running", running_fields(expires: expires)))
    ctx = build_context(worktree: @repo)

    result = RunnerSweep.reclaim(ctx, now: commit_time + 3600)

    assert_empty result[:reclaimed]
    assert_equal 1, result[:extended].length
    assert_equal "n1", result[:extended].first[:node]
    assert_equal "running", NodeLedger.status_for(File.join(@dir, "savepoint.md"), "n1")
    assert File.exist?(extensions_path("n1", 1))
  end

  def test_third_expiry_reclaims_despite_new_commits
    init_repo
    commit_time = commit_on_node_branch("n1")
    expires = (commit_time - 60).utc.iso8601
    write_savepoint(line("n1", "running", running_fields(expires: expires)))
    ctx = build_context(worktree: @repo)

    now = commit_time + 3600
    RunnerSweep.reclaim(ctx, now: now)
    RunnerSweep.reclaim(ctx, now: now)
    result = RunnerSweep.reclaim(ctx, now: now)

    assert_equal 1, result[:reclaimed].length
    assert_equal "n1", result[:reclaimed].first[:node]
    assert_equal 2, File.read(extensions_path("n1", 1)).each_line.count
  end

  def test_extension_count_resets_per_attempt
    init_repo
    commit_time = commit_on_node_branch("n1")
    expires_1 = (commit_time - 3600).utc.iso8601
    FileUtils.mkdir_p(File.join(@dir, "attempts"))
    File.write(extensions_path("n1", 1), "2026-01-01T00:00:00Z  head=aaaa\n2026-01-01T00:01:00Z  head=bbbb\n")

    expires_2 = (commit_time - 60).utc.iso8601
    write_savepoint(
      line("n1", "running", running_fields(expires: expires_1), ts: "2026-01-01T00:00:00Z") +
      line("n1", "reclaimed", { holder: "auto-1", expired: expires_1 }, ts: "2026-01-01T01:00:00Z") +
      line("n1", "running", running_fields(expires: expires_2), ts: "2026-01-01T02:00:00Z")
    )
    ctx = build_context(worktree: @repo)

    result = RunnerSweep.reclaim(ctx, now: commit_time + 3600)

    assert_empty result[:reclaimed]
    assert_equal 1, result[:extended].length
    assert File.exist?(extensions_path("n1", 2))
    refute_equal File.read(extensions_path("n1", 1)), File.read(extensions_path("n1", 2))
  end

  def test_extension_line_records_head_sha_and_time
    init_repo
    commit_time = commit_on_node_branch("n1")
    expected_sha = git("rev-parse", node_branch("n1")).strip
    expires = (commit_time - 60).utc.iso8601
    write_savepoint(line("n1", "running", running_fields(expires: expires)))
    ctx = build_context(worktree: @repo)

    now = commit_time + 3600
    RunnerSweep.reclaim(ctx, now: now)

    written = File.read(extensions_path("n1", 1)).strip
    assert_match(/\Ahead=#{Regexp.escape(expected_sha)}\z|head=#{Regexp.escape(expected_sha)}\z/, written)
    assert_match(/#{Regexp.escape(now.utc.iso8601)}/, written)
  end

  # --- 338a n3, 3.6: extensions are written and counted under attempts/ ---------

  def test_extensions_file_lives_under_attempts
    init_repo
    commit_time = commit_on_node_branch("n1")
    expires = (commit_time - 60).utc.iso8601
    write_savepoint(line("n1", "running", running_fields(expires: expires)))
    ctx = build_context(worktree: @repo)

    now = commit_time + 3600
    result = RunnerSweep.reclaim(ctx, now: now)

    expected = File.join(@dir, "attempts", "n1--a1.extensions")
    assert_equal 1, result[:extended].length
    assert File.exist?(expected), "extension file must live under attempts/, not the retired directory"
    assert_equal 1, File.read(expected).each_line.count
  end

  # --- 2.10/2.11: the reclaim line's required fields and node-input integration --

  def test_reclaim_line_carries_required_fields
    init_repo
    write_savepoint(line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z", holder: "auto-9")))
    ctx = build_context(worktree: @repo)

    RunnerSweep.reclaim(ctx, now: Time.iso8601("2030-01-01T00:00:00Z"))

    entries = NodeLedger.entries(File.join(@dir, "savepoint.md"))
    reclaimed_entry = entries.find { |e| e[:subject] == "n1" && e[:state] == "reclaimed" }
    refute_nil reclaimed_entry
    refute reclaimed_entry[:torn], "the reclaimed line must satisfy NodeLedger's own required fields"
    assert_equal "auto-9", reclaimed_entry[:fields]["holder"]
    assert_equal "2000-01-01T00:00:00Z", reclaimed_entry[:fields]["expired"]
  end

  def test_reclaim_records_landed_commits
    init_repo # the node branch is never created: this is the plain "no new commits" reclaim path
    write_savepoint(line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z")))
    ctx = build_context(worktree: @repo)

    before = NodeInput.landed_commits_block(
      intent_dir: @dir, node: "n1", files: ["n1.txt"], repo_dir: @repo,
      git_runner: ->(repo_dir:, files:) { "stub landed commits for #{files.join(',')}" }
    )
    assert_nil before, "no reclaimed line yet, so node-input must show nothing landed"

    RunnerSweep.reclaim(ctx, now: Time.iso8601("2030-01-01T00:00:00Z"))

    after = NodeInput.landed_commits_block(
      intent_dir: @dir, node: "n1", files: ["n1.txt"], repo_dir: @repo,
      git_runner: ->(repo_dir:, files:) { "stub landed commits for #{files.join(',')}" }
    )
    assert_equal "stub landed commits for n1.txt", after
  end

  # --- 2.12: a done node is never reclaimed -----------------------------------------

  def test_done_node_is_never_reclaimed
    init_repo
    write_savepoint(
      line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z"), ts: "2026-01-01T00:00:00Z") +
      line("n1", "done", { gates: "integrity+suite", commit: "abc123" }, ts: "2026-01-01T01:00:00Z")
    )
    ctx = build_context(worktree: @repo)

    result = RunnerSweep.reclaim(ctx, now: Time.iso8601("2030-01-01T00:00:00Z"))

    assert_empty result[:reclaimed]
    assert_equal "done", NodeLedger.status_for(File.join(@dir, "savepoint.md"), "n1")
  end

  # --- 2.13: a missing branch or worktree never raises ------------------------------

  def test_missing_node_branch_does_not_raise
    init_repo # no commit_on_node_branch call: the branch simply does not exist
    write_savepoint(
      line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z"), ts: "2026-01-01T00:00:00Z") +
      line("n2", "running", running_fields(expires: "2000-01-01T00:00:00Z"), ts: "2026-01-01T00:00:00Z")
    )
    ctx = build_context(worktree: @repo)

    result = nil
    assert_silent_of_exception { result = RunnerSweep.reclaim(ctx, now: Time.iso8601("2030-01-01T00:00:00Z")) }

    reclaimed_ids = result[:reclaimed].map { |r| r[:node] }
    assert_includes reclaimed_ids, "n1"
    assert_includes reclaimed_ids, "n2"
  end

  def assert_silent_of_exception
    yield
  rescue StandardError => e
    flunk "expected no exception, got #{e.class}: #{e.message}"
  end

  # --- 2.14: a torn running line is skipped, not raised on -------------------------

  def test_torn_running_line_is_skipped
    init_repo
    torn = "2026-01-01T00:00:00Z  n1  running holder=auto-1\n" # missing expires/input/model
    healthy = line("n2", "running", running_fields(expires: "2000-01-01T00:00:00Z"))
    write_savepoint(torn + healthy)
    ctx = build_context(worktree: @repo)

    result = RunnerSweep.reclaim(ctx, now: Time.iso8601("2030-01-01T00:00:00Z"))

    reclaimed_ids = result[:reclaimed].map { |r| r[:node] }
    refute_includes reclaimed_ids, "n1"
    assert_includes reclaimed_ids, "n2"
    assert_equal "planned", NodeLedger.status_for(File.join(@dir, "savepoint.md"), "n1")
  end

  # --- 2.15: the report lists every reclaim and extension ---------------------------

  def test_report_lists_reclaims_and_extensions
    init_repo
    commit_time = commit_on_node_branch("n1")
    write_savepoint(
      line("n1", "running", running_fields(expires: (commit_time - 60).utc.iso8601), ts: "2026-01-01T00:00:00Z") +
      line("n2", "running", running_fields(expires: "2000-01-01T00:00:00Z"), ts: "2026-01-01T00:00:01Z")
    )
    ctx = build_context(worktree: @repo)

    result = RunnerSweep.run(ctx, now: commit_time + 3600)

    assert result[:ok]
    assert_equal ["n2"], result[:reclaimed].map { |r| r[:node] }
    assert_equal ["n1"], result[:extended].map { |r| r[:node] }
  end

  # --- 2.18: the extension attempt number comes from the ledger, not the caller ---

  def test_extension_attempt_number_comes_from_ledger
    init_repo
    commit_time = commit_on_node_branch("n1")
    write_savepoint(
      line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z"), ts: "2026-01-01T00:00:00Z") +
      line("n1", "reclaimed", { holder: "auto-1", expired: "2000-01-01T00:00:00Z" }, ts: "2026-01-01T01:00:00Z") +
      line("n1", "running", running_fields(expires: (commit_time - 60).utc.iso8601), ts: "2026-01-01T02:00:00Z")
    )
    ctx = build_context(worktree: @repo)

    RunnerSweep.reclaim(ctx, now: commit_time + 3600)

    refute File.exist?(extensions_path("n1", 1))
    assert File.exist?(extensions_path("n1", 2))
  end

  # --- 2.19: a returned node is spared from this step's reclaim pass ---------------

  def test_returned_node_is_not_reclaimed
    init_repo
    write_savepoint(line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z")))
    ctx = build_context(worktree: @repo)

    result = RunnerSweep.reclaim(ctx, skip: ["n1"], now: Time.iso8601("2030-01-01T00:00:00Z"))

    assert_empty result[:reclaimed]
    assert_equal "running", NodeLedger.status_for(File.join(@dir, "savepoint.md"), "n1")
  end

  # --- 2.20: reclaim reads fresh state, so running it after absorb sees absorb -----

  def test_reclaim_pass_runs_after_absorb
    init_repo
    write_savepoint(line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z")))
    ctx = build_context(worktree: @repo)

    abort_result = RunnerSweep.abort_if_merging(ctx)
    assert abort_result[:ok]

    # Simulate "absorb" landing between the abort check and the reclaim pass:
    # a later dispatch already wrote a `done` line for n1 out from under us.
    write_savepoint(
      File.read(File.join(@dir, "savepoint.md")) +
      line("n1", "done", { gates: "integrity+suite", commit: "abc123" })
    )

    result = RunnerSweep.reclaim(ctx, now: Time.iso8601("2030-01-01T00:00:00Z"))

    assert_empty result[:reclaimed], "reclaim must see the post-absorb done line, not a snapshot taken before it"
    assert_equal "done", NodeLedger.status_for(File.join(@dir, "savepoint.md"), "n1")
  end
end
