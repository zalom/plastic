# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/active_delivery"
require_relative "../scripts/lib/lock"

# ActiveDelivery (intent 340b, G7c, n4, D10): which intent a session is
# delivering, walked across the global store and every configured project
# root. Matrix rows 4.23 to 4.27 (n4 action file). Hermetic: every fixture is
# a Dir.mktmpdir tree, and every call takes explicit paths.
class ActiveDeliveryTest < Minitest::Test
  SESSION = "auto-edc4b48edc"

  def setup
    @home = Dir.mktmpdir("active-delivery")
    @global_store = File.join(@home, "global-store")
    @project_root = File.join(@home, "projects")
    FileUtils.mkdir_p(@global_store)
    FileUtils.mkdir_p(@project_root)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def global_intent(name)
    dir = File.join(@global_store, name)
    FileUtils.mkdir_p(dir)
    dir
  end

  def project_intent(slug, name)
    dir = File.join(@project_root, slug, "store", name)
    FileUtils.mkdir_p(dir)
    dir
  end

  def resolve(session: SESSION)
    ActiveDelivery.resolve(global_store: @global_store, project_roots: [@project_root], session: session)
  end

  # --- 4.23 ------------------------------------------------------------------

  def test_walks_project_roots_and_global_store
    project_dir = project_intent("plastic", "340b--harness-adapters")
    Lock.acquire(project_dir, session: SESSION, run_mode: "auto")
    assert_equal project_dir, resolve

    FileUtils.rm_rf(@project_root)
    global_dir = global_intent("5--demo")
    Lock.acquire(global_dir, session: SESSION, run_mode: "auto")
    assert_equal global_dir, resolve
  end

  # --- 4.24 ------------------------------------------------------------------

  def test_returns_nothing_when_this_session_holds_none
    dir = project_intent("plastic", "340b--harness-adapters")
    Lock.acquire(dir, session: "some-other-session", run_mode: "auto")
    assert_nil resolve
  end

  def test_returns_nothing_when_no_lock_exists_at_all
    project_intent("plastic", "340b--harness-adapters")
    assert_nil resolve
  end

  # --- 4.25 ------------------------------------------------------------------

  def test_returns_nothing_on_more_than_one
    first = project_intent("plastic", "340b--harness-adapters")
    second = global_intent("5--demo")
    Lock.acquire(first, session: SESSION, run_mode: "auto")
    Lock.acquire(second, session: SESSION, run_mode: "auto")
    assert_nil resolve
  end

  # --- 4.26 ------------------------------------------------------------------

  def test_unparseable_lock_is_skipped
    torn = project_intent("plastic", "340b--harness-adapters")
    File.write(Lock.path(torn), "{not json")
    good = global_intent("5--demo")
    Lock.acquire(good, session: SESSION, run_mode: "auto")

    assert_equal good, resolve
  end

  # --- 4.27 ------------------------------------------------------------------

  def test_walk_reads_only_lock_files
    dir = project_intent("plastic", "340b--harness-adapters")
    Lock.acquire(dir, session: SESSION, run_mode: "auto")
    # A heavy graph.md that would raise if ActiveDelivery ever opened it.
    poison = File.join(dir, "graph.md")
    FileUtils.mkdir_p(poison) # a directory named graph.md: File.read would raise Errno::EISDIR

    result = resolve
    assert_equal dir, result
  end

  def test_candidate_intent_dirs_is_one_glob_per_root
    Lock.acquire(project_intent("plastic", "a"), session: SESSION, run_mode: "auto")
    Lock.acquire(project_intent("plastic", "b"), session: "other", run_mode: "auto")
    Lock.acquire(global_intent("c"), session: SESSION, run_mode: "auto")
    dirs = ActiveDelivery.candidate_intent_dirs(global_store: @global_store, project_roots: [@project_root])
    assert_equal 3, dirs.size
  end

  def test_blank_project_root_is_skipped_without_raising
    dir = global_intent("5--demo")
    Lock.acquire(dir, session: SESSION, run_mode: "auto")
    result = ActiveDelivery.resolve(global_store: @global_store, project_roots: ["", nil], session: SESSION)
    assert_equal dir, result
  end
end
