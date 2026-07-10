# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"
require_relative "../scripts/lib/worktree"
require_relative "../scripts/lib/lock"

# Hermetic tests for the Worktree module (intent 73c1). No real git runs: a
# FakeRunner records calls and returns scripted results. projects.yml is built
# inside a tmp HOME so resolution is deterministic.
class WorktreeTest < Minitest::Test
  # A fake ShellRunner. Records every `run(*args)` and returns a scripted
  # Result. By default every git call "succeeds"; tests can override per-arg.
  class FakeRunner
    attr_reader :calls

    def initialize(&block)
      @calls = []
      @responder = block
    end

    def run(*args)
      @calls << args.map(&:to_s)
      r = @responder ? @responder.call(args.map(&:to_s)) : nil
      r || Worktree::ShellRunner::Result.new(0, "true\n", "")
    end
  end

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
    assert_equal File.join(@plastic_home, ".worktrees", "73c1--worktree-x"), p["store"]
    assert_equal "plastic-store/73c1--worktree-x", p["store_branch"]
  end

  def test_paths_resolves_repo_from_projects_yml_when_nil
    p = Worktree.paths(slug: "demo", intent_id: "9", intent_slug: "s", home: @home)
    assert_equal File.join(@repo, ".claude", "worktrees", "9--s"), p["code"]
  end

  def test_paths_code_nil_when_repo_unresolvable
    p = Worktree.paths(slug: "nope", intent_id: "9", intent_slug: "s", home: @home)
    assert_nil p["code"]
    assert_nil p["code_branch"]
    # store path is always present (consistency worktree)
    assert_equal File.join(@plastic_home, ".worktrees", "9--s"), p["store"]
    assert_equal "plastic-store/9--s", p["store_branch"]
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

  # --- provision -------------------------------------------------------------

  def bridge_data(id: "73c1", slug: "worktree-x")
    {
      "intent" => {
        "id" => id,
        "dir" => "#{id}--#{slug}",
        "store" => @store,
        "name" => slug,
      },
    }
  end

  def test_provision_creates_both_worktrees_with_git_C
    runner = FakeRunner.new do |args|
      # rev-parse probe must report a git repo
      if args[1] == @repo && args[2] == "rev-parse"
        next Worktree::ShellRunner::Result.new(0, "true\n", "")
      end
      Worktree::ShellRunner::Result.new(0, "", "")
    end
    data = Worktree.provision(bridge_data, home: @home, runner: runner)

    wt = data["worktree"]
    assert_equal true, wt["provisioned"]
    assert_equal File.join(@repo, ".claude", "worktrees", "73c1--worktree-x"), wt["code"]
    assert_equal "plastic/73c1--worktree-x", wt["code_branch"]
    assert_equal File.join(@plastic_home, ".worktrees", "73c1--worktree-x"), wt["store"]
    assert_equal "plastic-store/73c1--worktree-x", wt["store_branch"]

    # Every git op used -C with the resolved path, never cwd (decision D6).
    add_calls = runner.calls.select { |c| c.include?("add") }
    assert add_calls.all? { |c| c[0] == "-C" }, "all worktree adds must use -C"
    code_add = add_calls.find { |c| c[1] == @repo }
    store_add = add_calls.find { |c| c[1] == @plastic_home }
    refute_nil code_add
    refute_nil store_add
    assert_includes code_add, "plastic/73c1--worktree-x"
    assert_includes store_add, "plastic-store/73c1--worktree-x"
  end

  def test_provision_fail_open_when_repo_not_git
    # rev-parse reports NOT a git repo for the code repo.
    runner = FakeRunner.new do |args|
      if args[2] == "rev-parse"
        next Worktree::ShellRunner::Result.new(128, "", "not a git repository")
      end
      Worktree::ShellRunner::Result.new(0, "", "")
    end
    out = capture_stderr do
      data = Worktree.provision(bridge_data, home: @home, runner: runner)
      wt = data["worktree"]
      assert_equal false, wt["provisioned"]
      assert_nil wt["code"]
      assert_nil wt["code_branch"]
    end
    refute_empty out
    # No code worktree add was attempted against the non-git repo.
    code_add = runner.calls.find { |c| c.include?("add") && c[1] == @repo }
    assert_nil code_add
  end

  def test_provision_fail_open_when_repo_unresolvable
    data = bridge_data
    data["intent"]["store"] = File.join(@plastic_home, "projects", "ghost", "store")
    out = capture_stderr do
      result = Worktree.provision(data, home: @home, runner: FakeRunner.new)
      assert_equal false, result["worktree"]["provisioned"]
      assert_nil result["worktree"]["code"]
    end
    refute_empty out
  end

  def test_provision_idempotent_reuses_existing_worktree
    code = File.join(@repo, ".claude", "worktrees", "73c1--worktree-x")
    FileUtils.mkdir_p(code)
    runner = FakeRunner.new do |args|
      if args[2] == "rev-parse"
        next Worktree::ShellRunner::Result.new(0, "true\n", "")
      end
      Worktree::ShellRunner::Result.new(0, "", "")
    end
    data = Worktree.provision(bridge_data, home: @home, runner: runner)
    assert_equal true, data["worktree"]["provisioned"]
    assert_equal code, data["worktree"]["code"]
    # No `worktree add` against the repo because the dir already exists (reuse).
    code_add = runner.calls.find { |c| c.include?("add") && c[1] == @repo }
    assert_nil code_add
  end

  def test_provision_global_store_only_intent_has_no_code
    data = bridge_data
    data["intent"]["store"] = File.join(@plastic_home, "store") # global store
    out = capture_stderr do
      result = Worktree.provision(data, home: @home, runner: FakeRunner.new)
      assert_equal false, result["worktree"]["provisioned"]
      assert_nil result["worktree"]["code"]
    end
    refute_empty out
  end

  def test_provision_gitignores_lock_files_in_the_store_repo
    runner = FakeRunner.new do |args|
      if args[2] == "rev-parse"
        next Worktree::ShellRunner::Result.new(0, "true\n", "")
      end
      Worktree::ShellRunner::Result.new(0, "", "")
    end
    Worktree.provision(bridge_data, home: @home, runner: runner)
    gitignore = File.read(File.join(@plastic_home, ".gitignore"))
    assert_includes gitignore.lines.map(&:strip), "*.lock",
                    "delivery.lock files must never be committed to the store repo"
  end

  # --- release ---------------------------------------------------------------

  def test_release_removes_both_and_prunes_then_clears_block
    runner = FakeRunner.new
    data = bridge_data
    data["worktree"] = {
      "code" => File.join(@repo, ".claude", "worktrees", "73c1--worktree-x"),
      "code_branch" => "plastic/73c1--worktree-x",
      "store" => File.join(@plastic_home, ".worktrees", "73c1--worktree-x"),
      "store_branch" => "plastic-store/73c1--worktree-x",
      "provisioned" => true,
    }
    result = Worktree.release(data, home: @home, runner: runner)
    assert_nil result["worktree"], "worktree block must be cleared"

    removes = runner.calls.select { |c| c.include?("remove") }
    prunes = runner.calls.select { |c| c.include?("prune") }
    assert_equal 2, removes.length
    assert removes.all? { |c| c[0] == "-C" }
    refute_empty prunes
  end

  def test_release_noop_when_nothing_provisioned
    runner = FakeRunner.new
    data = bridge_data # no "worktree" key
    result = Worktree.release(data, home: @home, runner: runner)
    assert_empty runner.calls
    assert_nil result["worktree"]
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
