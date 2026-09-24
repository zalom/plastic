# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"

require_relative "../scripts/lib/runner_sweep"
require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/node_input"
require_relative "../scripts/lib/worktree"

# RunnerSweep (intent 340, G7, n2): the reclaim and the extension. Matrix
# rows 2.1-2.21 in actions/ACTION_2.md n2 (2.21 lives in install_sync_test.rb).
#
# Owner ruling 2026-09-24 (intent 390 part B): Plastic runs no version
# control command. #abort_if_merging (a `git rev-parse MERGE_HEAD` check) is
# gone with every test that once proved it - Plastic never runs a merge of
# its own to leave half-finished. Freshness (extend vs. reclaim) no longer
# comes from a node branch's own commit time; every test below drives it
# through a plain file's mtime under the node's own worktree directory
# instead, with no git repository anywhere in this file.
class RunnerSweepTest < Minitest::Test
  INTENT_ID = "340"
  INTENT_SLUG = "sweep-fixture"

  def setup
    @home = Dir.mktmpdir("sweep-home")
    @dir = Dir.mktmpdir("sweep-intent", @home)
    @repo = Dir.mktmpdir("sweep-repo")
    @intent_worktree = File.join(@repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}")
    FileUtils.mkdir_p(@intent_worktree)
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

  # --- node worktree freshness fixture (mtime replaces a git commit time) ------

  def node_worktree_dir(node)
    File.join(@repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}--#{node}")
  end

  # Writes one file under the node's own worktree directory with the given
  # mtime forced onto it - the file-system stand-in for "a new commit landed
  # on the node's branch at this time".
  def touch_node_worktree_file(node, mtime:, filename: "work.txt")
    dir = node_worktree_dir(node)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, filename)
    File.write(path, "work\n")
    File.utime(mtime, mtime, path)
  end

  # --- 2.1/2.3/2.2/2.16/2.17: the merge-abort check is gone --------------------
  #
  # Owner ruling 2026-09-24: #abort_if_merging (a `git rev-parse MERGE_HEAD`
  # check) and its recovery-command printing are gone outright - Plastic
  # never runs a merge of its own to leave half-finished, so there is nothing
  # left for a later step to trip on. #run's own order narrows to "heartbeat,
  # then reclaim", proven below.

  def test_run_heartbeats_when_session_present
    write_savepoint("")
    calls = []
    heartbeat = lambda { |*args, **kwargs| calls << [args, kwargs]; true }
    ctx = build_context(worktree: @intent_worktree, session: "auto-xyz")

    result = RunnerSweep.run(ctx, heartbeat: heartbeat)

    assert result[:ok]
    assert_equal 1, calls.length
  end

  def test_run_skips_heartbeat_when_no_session
    write_savepoint("")
    calls = []
    heartbeat = lambda { |*args, **kwargs| calls << [args, kwargs]; true }
    ctx = build_context(worktree: @intent_worktree, session: nil)

    result = RunnerSweep.run(ctx, heartbeat: heartbeat)

    assert result[:ok]
    assert_empty calls
  end

  # --- 2.4/2.5: expired vs. unexpired -----------------------------------------------

  def test_expired_node_with_no_commits_is_reclaimed
    write_savepoint(line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z", holder: "auto-1")))
    ctx = build_context(worktree: @intent_worktree)

    result = RunnerSweep.reclaim(ctx, now: Time.iso8601("2030-01-01T00:00:00Z"))

    assert_equal 1, result[:reclaimed].length
    assert_equal "n1", result[:reclaimed].first[:node]
    assert_equal "auto-1", result[:reclaimed].first[:holder]
    assert_equal "planned", NodeLedger.status_for(File.join(@dir, "savepoint.md"), "n1")
  end

  def test_unexpired_node_is_not_reclaimed
    future = (Time.now + 3600).utc.iso8601
    write_savepoint(line("n1", "running", running_fields(expires: future)))
    ctx = build_context(worktree: @intent_worktree)

    result = RunnerSweep.reclaim(ctx, now: Time.now)

    assert_empty result[:reclaimed]
    assert_empty result[:extended]
    assert_equal "running", NodeLedger.status_for(File.join(@dir, "savepoint.md"), "n1")
  end

  # --- 2.6/2.7/2.8: extension mechanics ---------------------------------------------

  def test_expired_node_with_new_files_is_extended
    mtime = Time.iso8601("2026-01-01T00:30:00Z")
    touch_node_worktree_file("n1", mtime: mtime)
    expires = (mtime - 60).utc.iso8601
    write_savepoint(line("n1", "running", running_fields(expires: expires)))
    ctx = build_context(worktree: @intent_worktree)

    result = RunnerSweep.reclaim(ctx, now: mtime + 3600)

    assert_empty result[:reclaimed]
    assert_equal 1, result[:extended].length
    assert_equal "n1", result[:extended].first[:node]
    assert_equal "running", NodeLedger.status_for(File.join(@dir, "savepoint.md"), "n1")
    assert File.exist?(extensions_path("n1", 1))
  end

  def test_third_expiry_reclaims_despite_new_files
    mtime = Time.iso8601("2026-01-01T00:30:00Z")
    touch_node_worktree_file("n1", mtime: mtime)
    expires = (mtime - 60).utc.iso8601
    write_savepoint(line("n1", "running", running_fields(expires: expires)))
    ctx = build_context(worktree: @intent_worktree)

    now = mtime + 3600
    RunnerSweep.reclaim(ctx, now: now)
    RunnerSweep.reclaim(ctx, now: now)
    result = RunnerSweep.reclaim(ctx, now: now)

    assert_equal 1, result[:reclaimed].length
    assert_equal "n1", result[:reclaimed].first[:node]
    assert_equal 2, File.read(extensions_path("n1", 1)).each_line.count
  end

  def test_extension_count_resets_per_attempt
    mtime = Time.iso8601("2026-01-01T00:30:00Z")
    touch_node_worktree_file("n1", mtime: mtime)
    expires_1 = (mtime - 3600).utc.iso8601
    FileUtils.mkdir_p(File.join(@dir, "attempts"))
    File.write(extensions_path("n1", 1),
               "2026-01-01T00:00:00Z  mtime=2025-12-31T23:00:00Z\n2026-01-01T00:01:00Z  mtime=2025-12-31T23:05:00Z\n")

    expires_2 = (mtime - 60).utc.iso8601
    write_savepoint(
      line("n1", "running", running_fields(expires: expires_1), ts: "2026-01-01T00:00:00Z") +
      line("n1", "reclaimed", { holder: "auto-1", expired: expires_1 }, ts: "2026-01-01T01:00:00Z") +
      line("n1", "running", running_fields(expires: expires_2), ts: "2026-01-01T02:00:00Z")
    )
    ctx = build_context(worktree: @intent_worktree)

    result = RunnerSweep.reclaim(ctx, now: mtime + 3600)

    assert_empty result[:reclaimed]
    assert_equal 1, result[:extended].length
    assert File.exist?(extensions_path("n1", 2))
    refute_equal File.read(extensions_path("n1", 1)), File.read(extensions_path("n1", 2))
  end

  def test_extension_line_records_mtime_and_time
    mtime = Time.iso8601("2026-01-01T00:30:00Z")
    touch_node_worktree_file("n1", mtime: mtime)
    expires = (mtime - 60).utc.iso8601
    write_savepoint(line("n1", "running", running_fields(expires: expires)))
    ctx = build_context(worktree: @intent_worktree)

    now = mtime + 3600
    RunnerSweep.reclaim(ctx, now: now)

    written = File.read(extensions_path("n1", 1)).strip
    assert_match(/mtime=#{Regexp.escape(mtime.utc.iso8601)}/, written)
    assert_match(/#{Regexp.escape(now.utc.iso8601)}/, written)
  end

  # --- 338a n3, 3.6: extensions are written and counted under attempts/ ---------

  def test_extensions_file_lives_under_attempts
    mtime = Time.iso8601("2026-01-01T00:30:00Z")
    touch_node_worktree_file("n1", mtime: mtime)
    expires = (mtime - 60).utc.iso8601
    write_savepoint(line("n1", "running", running_fields(expires: expires)))
    ctx = build_context(worktree: @intent_worktree)

    now = mtime + 3600
    result = RunnerSweep.reclaim(ctx, now: now)

    expected = File.join(@dir, "attempts", "n1--a1.extensions")
    assert_equal 1, result[:extended].length
    assert File.exist?(expected), "extension file must live under attempts/, not the retired directory"
    assert_equal 1, File.read(expected).each_line.count
  end

  # --- 2.10/2.11: the reclaim line's required fields and node-input integration --

  def test_reclaim_line_carries_required_fields
    write_savepoint(line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z", holder: "auto-9")))
    ctx = build_context(worktree: @intent_worktree)

    RunnerSweep.reclaim(ctx, now: Time.iso8601("2030-01-01T00:00:00Z"))

    entries = NodeLedger.entries(File.join(@dir, "savepoint.md"))
    reclaimed_entry = entries.find { |e| e[:subject] == "n1" && e[:state] == "reclaimed" }
    refute_nil reclaimed_entry
    refute reclaimed_entry[:torn], "the reclaimed line must satisfy NodeLedger's own required fields"
    assert_equal "auto-9", reclaimed_entry[:fields]["holder"]
    assert_equal "2000-01-01T00:00:00Z", reclaimed_entry[:fields]["expired"]
  end

  # --- 2.12: a done node is never reclaimed -----------------------------------------

  def test_done_node_is_never_reclaimed
    write_savepoint(
      line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z"), ts: "2026-01-01T00:00:00Z") +
      line("n1", "done", { gates: "integrity+suite", commit: "abc123" }, ts: "2026-01-01T01:00:00Z")
    )
    ctx = build_context(worktree: @intent_worktree)

    result = RunnerSweep.reclaim(ctx, now: Time.iso8601("2030-01-01T00:00:00Z"))

    assert_empty result[:reclaimed]
    assert_equal "done", NodeLedger.status_for(File.join(@dir, "savepoint.md"), "n1")
  end

  # --- 2.13: a missing node worktree never raises ------------------------------------

  def test_missing_node_worktree_does_not_raise
    # no touch_node_worktree_file call: neither node's worktree directory
    # exists on disk at all.
    write_savepoint(
      line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z"), ts: "2026-01-01T00:00:00Z") +
      line("n2", "running", running_fields(expires: "2000-01-01T00:00:00Z"), ts: "2026-01-01T00:00:00Z")
    )
    ctx = build_context(worktree: @intent_worktree)

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
    torn = "2026-01-01T00:00:00Z  n1  running holder=auto-1\n" # missing expires/input/model
    healthy = line("n2", "running", running_fields(expires: "2000-01-01T00:00:00Z"))
    write_savepoint(torn + healthy)
    ctx = build_context(worktree: @intent_worktree)

    result = RunnerSweep.reclaim(ctx, now: Time.iso8601("2030-01-01T00:00:00Z"))

    reclaimed_ids = result[:reclaimed].map { |r| r[:node] }
    refute_includes reclaimed_ids, "n1"
    assert_includes reclaimed_ids, "n2"
    assert_equal "planned", NodeLedger.status_for(File.join(@dir, "savepoint.md"), "n1")
  end

  # --- 2.15: the report lists every reclaim and extension ---------------------------

  def test_report_lists_reclaims_and_extensions
    mtime = Time.iso8601("2026-01-01T00:30:00Z")
    touch_node_worktree_file("n1", mtime: mtime)
    write_savepoint(
      line("n1", "running", running_fields(expires: (mtime - 60).utc.iso8601), ts: "2026-01-01T00:00:00Z") +
      line("n2", "running", running_fields(expires: "2000-01-01T00:00:00Z"), ts: "2026-01-01T00:00:01Z")
    )
    ctx = build_context(worktree: @intent_worktree)

    result = RunnerSweep.run(ctx, now: mtime + 3600)

    assert result[:ok]
    assert_equal ["n2"], result[:reclaimed].map { |r| r[:node] }
    assert_equal ["n1"], result[:extended].map { |r| r[:node] }
  end

  # --- 2.18: the extension attempt number comes from the ledger, not the caller ---

  def test_extension_attempt_number_comes_from_ledger
    mtime = Time.iso8601("2026-01-01T00:30:00Z")
    touch_node_worktree_file("n1", mtime: mtime)
    write_savepoint(
      line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z"), ts: "2026-01-01T00:00:00Z") +
      line("n1", "reclaimed", { holder: "auto-1", expired: "2000-01-01T00:00:00Z" }, ts: "2026-01-01T01:00:00Z") +
      line("n1", "running", running_fields(expires: (mtime - 60).utc.iso8601), ts: "2026-01-01T02:00:00Z")
    )
    ctx = build_context(worktree: @intent_worktree)

    RunnerSweep.reclaim(ctx, now: mtime + 3600)

    refute File.exist?(extensions_path("n1", 1))
    assert File.exist?(extensions_path("n1", 2))
  end

  # --- 2.19: a returned node is spared from this step's reclaim pass ---------------

  def test_returned_node_is_not_reclaimed
    write_savepoint(line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z")))
    ctx = build_context(worktree: @intent_worktree)

    result = RunnerSweep.reclaim(ctx, skip: ["n1"], now: Time.iso8601("2030-01-01T00:00:00Z"))

    assert_empty result[:reclaimed]
    assert_equal "running", NodeLedger.status_for(File.join(@dir, "savepoint.md"), "n1")
  end

  # --- 2.20: reclaim reads fresh state, so running it after absorb sees absorb -----

  def test_reclaim_pass_runs_after_absorb
    write_savepoint(line("n1", "running", running_fields(expires: "2000-01-01T00:00:00Z")))
    ctx = build_context(worktree: @intent_worktree)

    # Simulate "absorb" landing before the reclaim pass: a later dispatch
    # already wrote a `done` line for n1 out from under us.
    write_savepoint(
      File.read(File.join(@dir, "savepoint.md")) +
      line("n1", "done", { gates: "integrity+suite", commit: "abc123" })
    )

    result = RunnerSweep.reclaim(ctx, now: Time.iso8601("2030-01-01T00:00:00Z"))

    assert_empty result[:reclaimed], "reclaim must see the post-absorb done line, not a snapshot taken before it"
    assert_equal "done", NodeLedger.status_for(File.join(@dir, "savepoint.md"), "n1")
  end
end
