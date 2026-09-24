# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"
require_relative "../scripts/lib/worktree"
require_relative "../scripts/lib/lock"

# Hermetic tests for the Worktree module (intent 73c1). Plastic runs no
# version control command (intent 390): these tests cover only the pure path
# helpers and the lock-freshness check. projects.yml is built inside a tmp
# HOME so resolution is deterministic.
class WorktreeTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("wt-home")
    @plastic_home = File.join(@home, ".plastic")
    FileUtils.mkdir_p(@plastic_home)
    @repo = File.join(@home, "apps", "demo")
    FileUtils.mkdir_p(@repo)
    write_projects(
      "demo" => @repo,
    )
    @store = File.join(@plastic_home, "projects", "demo", "store")
    FileUtils.mkdir_p(@store)
    @tmp = Dir.mktmpdir("wt-tmp")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  def write_projects(map)
    body = { "projects" => map.transform_values { |p| { "path" => p } } }
    File.write(File.join(@plastic_home, "projects.yml"), body.to_yaml)
  end

  # --- paths -----------------------------------------------------------------

  def test_paths_id_first_naming
    p = Worktree.paths(slug: "demo", intent_id: "73c1", intent_slug: "worktree-x",
                       home: @home, repo_path: @repo)
    assert_equal File.join(@repo, ".claude", "worktrees", "73c1--worktree-x"), p["code"]
    assert_equal "plastic/73c1--worktree-x", p["code_branch"]
  end

  def test_paths_resolves_repo_from_projects_yml_when_nil
    p = Worktree.paths(slug: "demo", intent_id: "9", intent_slug: "s", home: @home)
    assert_equal File.join(@repo, ".claude", "worktrees", "9--s"), p["code"]
  end

  def test_paths_code_nil_when_repo_unresolvable
    p = Worktree.paths(slug: "nope", intent_id: "9", intent_slug: "s", home: @home)
    assert_nil p["code"]
    assert_nil p["code_branch"]
  end

  # --- repo_for --------------------------------------------------------------

  def test_repo_for_returns_abs_path
    assert_equal File.expand_path(@repo), Worktree.repo_for("demo", home: @home)
  end

  def test_repo_for_unknown_slug_is_nil
    assert_nil Worktree.repo_for("ghost", home: @home)
  end

  def test_repo_for_blank_slug_is_nil
    assert_nil Worktree.repo_for(nil, home: @home)
    assert_nil Worktree.repo_for("", home: @home)
  end

  # --- lock_held_by_other? (intent 108: the delivery.lock file decides) -------

  def intent_dir_with_lock(store, id, slug, session:, mtime: nil)
    dir = File.join(store, "#{id}--#{slug}")
    FileUtils.mkdir_p(dir)
    Lock.acquire(dir, session: session)
    FileUtils.touch(Lock.path(dir), mtime: mtime) if mtime
    dir
  end

  def test_lock_held_by_other_true_for_fresh_foreign_lock
    intent_dir_with_lock(@store, "73c1", "worktree-x", session: "other")
    assert Worktree.lock_held_by_other?(
      intent_id: "73c1", store: @store, current_session: "me", home: @home
    )
  end

  def test_lock_not_held_by_self
    intent_dir_with_lock(@store, "73c1", "worktree-x", session: "me")
    refute Worktree.lock_held_by_other?(
      intent_id: "73c1", store: @store, current_session: "me", home: @home
    )
  end

  def test_lock_not_held_by_other_for_a_delegate
    dir = intent_dir_with_lock(@store, "73c1", "worktree-x", session: "other")
    Lock.add_delegate(dir, delegate: "me", session: "other")
    refute Worktree.lock_held_by_other?(
      intent_id: "73c1", store: @store, current_session: "me", home: @home
    ), "a delegate of the owner does not count as 'other' (D4)"
  end

  def test_lock_not_held_when_stale
    intent_dir_with_lock(@store, "73c1", "worktree-x", session: "other",
                         mtime: Time.now - 4000)
    refute Worktree.lock_held_by_other?(
      intent_id: "73c1", store: @store, current_session: "me", home: @home
    ), "a stale lock does not hold (explicit takeover reclaims it)"
  end

  def test_lock_not_held_for_different_intent
    intent_dir_with_lock(@store, "99", "other-thing", session: "other")
    refute Worktree.lock_held_by_other?(
      intent_id: "73c1", store: @store, current_session: "me", home: @home
    )
  end

  def test_lock_scoped_by_store_when_provided
    other_store = File.join(@plastic_home, "projects", "elsewhere", "store")
    intent_dir_with_lock(other_store, "73c1", "worktree-x", session: "other")
    refute Worktree.lock_held_by_other?(
      intent_id: "73c1", store: @store, current_session: "me", home: @home
    )
  end

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end
end
