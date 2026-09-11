# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

require_relative "../scripts/lib/node_worktree"
require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/worktree"

# NodeWorktree (intent 340, G7, n3): a work node's own git worktree, cut from
# the intent branch tip, merged back into the intent branch, and swept once
# its node is terminal. Matrix rows 3.1-3.19 in actions/ACTION_2.md n3 (3.19
# lives in install_sync_test.rb).
#
# Every row here builds a real throwaway git repository under Dir.mktmpdir -
# the only honest way to test a merge conflict - with the intent worktree
# checked out on the intent branch, exactly like a real Plastic delivery.
class NodeWorktreeTest < Minitest::Test
  INTENT_ID = "340"
  INTENT_SLUG = "wt-fixture"

  def setup
    @repo = Dir.mktmpdir("nwt-repo")
    git("init", "-q", "-b", "alpha")
    git("config", "user.email", "nwt@example.com")
    git("config", "user.name", "NWT Test")
    # Disable background gc/maintenance: it can race a tmpdir teardown that
    # removes the repo out from under it (`.git/objects/maintenance.lock`
    # vanishing mid-remove), which is a test-harness flake, not a real bug.
    git("config", "gc.auto", "0")
    File.write(File.join(@repo, "README.md"), "hi\n")
    git("add", "README.md")
    git("commit", "-q", "-m", "init")

    @intent_worktree = File.join(@repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}")
    @intent_branch = "plastic/#{INTENT_ID}--#{INTENT_SLUG}"
    FileUtils.mkdir_p(File.dirname(@intent_worktree))
    git("worktree", "add", @intent_worktree, "-b", @intent_branch)

    @dir = Dir.mktmpdir("nwt-intent")
  end

  def teardown
    FileUtils.remove_entry(@repo) if @repo && Dir.exist?(@repo)
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  # --- fixture helpers -----------------------------------------------------------

  def git(*args, dir: @repo)
    out, err, status = Open3.capture3("git", "-C", dir, *args.map(&:to_s))
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  def build_context(intent_dir: @dir, worktree: @intent_worktree, worktree_branch: @intent_branch,
                     intent_id: INTENT_ID, intent_slug: INTENT_SLUG)
    RunnerCore::Context.new(
      intent_dir: intent_dir, intent_id: intent_id, intent_slug: intent_slug,
      store: nil, plastic_home: nil, session: nil,
      worktree: worktree, worktree_branch: worktree_branch,
      graph: { ok: true, edges: {}, nodes: {} }, errors: []
    )
  end

  def node_branch(node, intent_id: INTENT_ID, intent_slug: INTENT_SLUG)
    "plastic/#{intent_id}--#{intent_slug}--#{node}"
  end

  def node_dir(node, intent_id: INTENT_ID, intent_slug: INTENT_SLUG)
    File.join(@repo, ".claude", "worktrees", "#{intent_id}--#{intent_slug}--#{node}")
  end

  # Provisions n1 for real (via NodeWorktree.provision), then commits `content`
  # to `filename` on its branch. Leaves HEAD of @intent_worktree on the intent
  # branch (checks the node worktree out, commits, does not touch the intent
  # worktree's own checkout).
  def commit_on_node(node, filename:, content:, context: build_context)
    result = NodeWorktree.provision(context, node: node, kind: "work")
    File.write(File.join(result[:path], filename), content)
    git("add", filename, dir: result[:path])
    git("commit", "-q", "-m", "#{node} work", dir: result[:path])
    result
  end

  def write_savepoint(content)
    File.write(File.join(@dir, "savepoint.md"), content)
  end

  # subject/state plus fields, either as a Hash or as kwargs (both fixture
  # styles are used below).
  def line(subject, state, fields = nil, ts: "2026-01-01T00:00:00Z", **kwfields)
    fields = (fields || {}).merge(kwfields)
    rendered = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
    rendered = " #{rendered}" unless rendered.empty?
    "#{ts}  #{subject}  #{state}#{rendered}\n"
  end

  # --- 3.1: path and branch derivation --------------------------------------------

  def test_path_and_branch_include_intent_and_node
    ctx = build_context
    p = NodeWorktree.paths(ctx, node: "n1")

    assert_equal File.join(@repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}--n1"), p["path"]
    assert_equal "plastic/#{INTENT_ID}--#{INTENT_SLUG}--n1", p["branch"]

    other = NodeWorktree.paths(build_context(intent_id: "9", intent_slug: "other-fixture"), node: "n1")
    refute_equal p["path"], other["path"]
    refute_equal p["branch"], other["branch"]
  end

  # --- 3.2: cut from the intent branch tip, not the repo's checkout ---------------

  def test_branch_is_cut_from_intent_branch_tip
    # Advance the intent branch past `alpha` so a wrong cut point is provable.
    File.write(File.join(@intent_worktree, "intent-only.txt"), "x\n")
    git("add", "intent-only.txt", dir: @intent_worktree)
    git("commit", "-q", "-m", "intent work", dir: @intent_worktree)
    intent_tip = git("rev-parse", @intent_branch).strip

    # Leave the repo's own checkout on `alpha`, which does NOT carry that commit.
    result = NodeWorktree.provision(build_context, node: "n1", kind: "work")

    assert result[:provisioned]
    node_base = git("merge-base", @intent_branch, result[:branch]).strip
    assert_equal intent_tip, node_base, "the node branch must fork from the intent branch's own tip"
  end

  # --- 3.3: idempotent reuse -------------------------------------------------------

  def test_provision_is_idempotent
    ctx = build_context
    first = NodeWorktree.provision(ctx, node: "n1", kind: "work")
    second = NodeWorktree.provision(ctx, node: "n1", kind: "work")

    assert first[:provisioned]
    assert second[:provisioned]
    assert_equal first[:path], second[:path]
  end

  # --- 3.4/3.5: verify and research nodes get no worktree -------------------------

  def test_verify_node_gets_no_worktree
    result = NodeWorktree.provision(build_context, node: "v1", kind: "verify")
    refute result[:provisioned]
    assert_nil result[:path]
    refute Dir.exist?(node_dir("v1"))
  end

  def test_research_node_gets_no_worktree
    result = NodeWorktree.provision(build_context, node: "r1", kind: "research")
    refute result[:provisioned]
    assert_nil result[:path]
    refute Dir.exist?(node_dir("r1"))
  end

  # --- 3.6: fail open on an unresolvable or non-git repo ---------------------------

  def test_non_git_repo_fails_open
    not_git = Dir.mktmpdir("nwt-notgit")
    ctx = build_context(worktree: File.join(not_git, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}"))

    result = NodeWorktree.provision(ctx, node: "n1", kind: "work")

    assert result[:ok]
    refute result[:provisioned]
    assert_nil result[:path]
  ensure
    FileUtils.remove_entry(not_git) if not_git && Dir.exist?(not_git)
  end

  # --- 3.7/3.7a: merge targets the intent branch in the intent worktree -----------

  def test_merge_targets_intent_branch_in_intent_worktree
    ctx = build_context
    commit_on_node("n1", filename: "n1.txt", content: "work\n", context: ctx)

    result = NodeWorktree.merge(ctx, node: "n1")

    assert result[:ok], result[:error]
    refute_nil result[:commit]
    assert File.exist?(File.join(@intent_worktree, "n1.txt")), "the merge must land in the INTENT worktree"
    refute File.exist?(File.join(@repo, "n1.txt")), "the merge must never land in the repo's own main checkout"
  end

  def test_merge_refuses_wrong_checked_out_branch
    ctx = build_context
    commit_on_node("n1", filename: "n1.txt", content: "work\n", context: ctx)
    git("checkout", "-q", "-b", "decoy-branch", dir: @intent_worktree)

    result = NodeWorktree.merge(ctx, node: "n1")

    refute result[:ok]
    assert_match(/decoy-branch/, result[:error])
    refute File.exist?(File.join(@intent_worktree, "n1.txt"))
  end

  # --- 3.8/3.9/3.10/3.11: release policy by terminal state -------------------------

  def test_done_removes_worktree_after_merge
    ctx = build_context
    result = commit_on_node("n1", filename: "n1.txt", content: "work\n", context: ctx)
    NodeWorktree.merge(ctx, node: "n1")

    release = NodeWorktree.release(ctx, node: "n1", state: "done")

    assert release[:removed]
    refute Dir.exist?(result[:path])
  end

  def test_failed_verification_keeps_worktree
    ctx = build_context
    result = commit_on_node("n1", filename: "n1.txt", content: "work\n", context: ctx)

    release = NodeWorktree.release(ctx, node: "n1", state: "failed_verification")

    refute release[:removed]
    assert Dir.exist?(result[:path])
  end

  def test_needs_decision_keeps_worktree
    ctx = build_context
    result = commit_on_node("n1", filename: "n1.txt", content: "work\n", context: ctx)

    release = NodeWorktree.release(ctx, node: "n1", state: "needs_decision")

    refute release[:removed]
    assert Dir.exist?(result[:path])
  end

  def test_terminal_states_remove_worktree
    ctx = build_context
    %w[superseded abandoned].each do |state|
      node = "n#{state.length}"
      result = commit_on_node(node, filename: "#{node}.txt", content: "work\n", context: ctx)
      release = NodeWorktree.release(ctx, node: node, state: state)
      assert release[:removed], "state #{state} must remove the worktree"
      refute Dir.exist?(result[:path])
    end
  end

  # --- 3.12/3.12a: conflict handling -----------------------------------------------

  # Provisions n1 from the CURRENT intent branch tip (before shared.txt exists
  # anywhere), then commits DIVERGENT shared.txt content on the node branch
  # and on the intent worktree - a genuine add/add conflict, the only honest
  # way to prove the abort-and-report path fires.
  def provision_and_diverge_on_shared_file
    ctx = build_context
    NodeWorktree.provision(ctx, node: "n1", kind: "work")
    node_path = NodeWorktree.paths(ctx, node: "n1")["path"]
    File.write(File.join(node_path, "shared.txt"), "node version\n")
    git("add", "shared.txt", dir: node_path)
    git("commit", "-q", "-m", "node edits shared.txt", dir: node_path)

    File.write(File.join(@intent_worktree, "shared.txt"), "intent version\n")
    git("add", "shared.txt", dir: @intent_worktree)
    git("commit", "-q", "-m", "intent edits shared.txt", dir: @intent_worktree)

    ctx
  end

  def test_conflict_aborts_merge_and_names_paths
    ctx = provision_and_diverge_on_shared_file

    result = NodeWorktree.merge(ctx, node: "n1")

    refute result[:ok]
    assert_equal ["shared.txt"], result[:conflicted]
    status = git("status", "--porcelain", dir: @intent_worktree)
    assert_empty status.strip, "the abort must leave the intent worktree clean"
  end

  def test_conflict_result_carries_paths
    ctx = provision_and_diverge_on_shared_file

    result = NodeWorktree.merge(ctx, node: "n1")

    assert_kind_of Array, result[:conflicted]
    refute_empty result[:conflicted]
  end

  # --- 3.13/3.14: changed_paths -----------------------------------------------------

  def test_changed_paths_lists_node_branch_diff
    ctx = build_context
    commit_on_node("n1", filename: "n1.txt", content: "work\n", context: ctx)

    paths = NodeWorktree.changed_paths(ctx, node: "n1")

    assert_equal ["n1.txt"], paths
  end

  # --- 9.8: an unmeasurable diff is nil, never [] (B3) -------------------------

  def test_changed_paths_returns_nil_when_it_cannot_measure
    ctx = build_context
    # n1 has never been provisioned: its branch does not exist, so the git
    # diff itself fails - that must read as "cannot measure" (nil), never
    # silently as "nothing changed" ([]), the exact fail-open B3 named.
    paths = NodeWorktree.changed_paths(ctx, node: "n1", kind: "work")

    assert_nil paths
  end

  # --- 9.9: a verify/research node's diff is measured against the intent worktree -

  def test_verify_node_diff_is_measured_against_the_intent_worktree
    ctx = build_context
    # A verify node gets no worktree or branch of its own (matrix 3.4), so
    # the only place it could actually leave a diff is the shared intent
    # worktree - committing directly there is the reviewer's own
    # reproduction of "a reviewer edits the code it is reviewing".
    File.write(File.join(@intent_worktree, "verify-edit.txt"), "edited by v1\n")
    git("add", "verify-edit.txt", dir: @intent_worktree)
    git("commit", "-q", "-m", "v1 edits the code it is reviewing", dir: @intent_worktree)

    paths = NodeWorktree.changed_paths(ctx, node: "v1", kind: "verify")

    assert_equal ["verify-edit.txt"], paths
  end

  def test_empty_diff_is_empty_not_error
    ctx = build_context
    NodeWorktree.provision(ctx, node: "n1", kind: "work") # no commits on the node branch

    paths = NodeWorktree.changed_paths(ctx, node: "n1")

    assert_equal [], paths
  end

  # --- 3.15/3.16/3.17/3.18: the reaper -----------------------------------------------

  def test_reaper_removes_terminal_node_worktree
    ctx = build_context
    result = commit_on_node("n1", filename: "n1.txt", content: "work\n", context: ctx)
    NodeWorktree.merge(ctx, node: "n1")
    write_savepoint(line("n1", "running", holder: "auto-1", expires: "2026-01-01T00:00:00Z",
                              packet: "abc", model: "sonnet") +
                     line("n1", "done", gates: "integrity+suite", commit: "abc123", ts: "2026-01-01T01:00:00Z"))

    outcome = NodeWorktree.reap(ctx)

    assert_equal ["n1"], outcome[:removed].map { |r| r[:node] }
    refute Dir.exist?(result[:path])
  end

  def test_reaper_keeps_unmerged_node_branch
    ctx = build_context
    result = commit_on_node("n1", filename: "n1.txt", content: "work\n", context: ctx)
    # Never merged: n1's branch carries a commit the intent branch does not have.
    write_savepoint(line("n1", "running", holder: "auto-1", expires: "2026-01-01T00:00:00Z",
                              packet: "abc", model: "sonnet") +
                     line("n1", "done", gates: "integrity+suite", commit: "abc123", ts: "2026-01-01T01:00:00Z"))

    outcome = NodeWorktree.reap(ctx)

    assert_empty outcome[:removed]
    assert_equal ["n1"], outcome[:spared].map { |s| s[:node] }
    assert Dir.exist?(result[:path])
  end

  def test_reaper_spares_non_terminal_node
    ctx = build_context
    result = commit_on_node("n1", filename: "n1.txt", content: "work\n", context: ctx)
    NodeWorktree.merge(ctx, node: "n1")
    write_savepoint(line("n1", "running", holder: "auto-1", expires: "2026-01-01T00:00:00Z",
                              packet: "abc", model: "sonnet"))

    outcome = NodeWorktree.reap(ctx)

    assert_empty outcome[:removed]
    assert_equal ["n1"], outcome[:spared].map { |s| s[:node] }
    assert Dir.exist?(result[:path])
  end

  def test_reaper_ignores_non_node_worktrees
    ctx = build_context
    # Another intent's node worktree, sitting in the very same directory.
    other_dir = File.join(@repo, ".claude", "worktrees", "999--other--n1")
    git("worktree", "add", other_dir, "-b", "plastic/999--other--n1")

    outcome = NodeWorktree.reap(ctx)

    assert Dir.exist?(other_dir)
    assert Dir.exist?(@intent_worktree)
    assert_empty outcome[:removed].select { |r| r[:dir] == other_dir }
  end
end
