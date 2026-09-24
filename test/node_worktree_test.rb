# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/lib/node_worktree"
require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/node_ledger"

# NodeWorktree (intent 340, G7, n3; git removed by intent 390 part B): a work
# node's own worktree path, cut from the intent branch tip, merged back into
# the intent branch, and swept once its node is terminal. Matrix rows
# 3.1-3.19 in actions/ACTION_2.md n3 (3.19 lives in install_sync_test.rb).
#
# Owner ruling 2026-09-24: Plastic runs no version control command, so this
# module creates, merges and removes nothing itself anymore - every test here
# asserts on the printed instruction text and on plain files/directories,
# never on a real git repository. `changed_paths` and its conflict-handling
# tests (former rows 3.12/3.12a/3.13/3.14/9.8/9.9) are gone with the method:
# NodeReturn's closed schema carries no file list to measure a diff against
# once git is out of the picture (see node_worktree.rb's own comment). The
# reaper's former "keeps unmerged node branch" row (3.16) is gone the same
# way: with no git call left to count commits ahead, Plastic can no longer
# tell a merged branch from an unmerged one, so a terminal node's worktree is
# always named for removal now - a real capability lost, recorded here as a
# finding, not patched over with a fabricated signal.
class NodeWorktreeTest < Minitest::Test
  INTENT_ID = "340"
  INTENT_SLUG = "wt-fixture"

  def setup
    @repo = Dir.mktmpdir("nwt-repo")
    @intent_worktree = File.join(@repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}")
    @intent_branch = "plastic/#{INTENT_ID}--#{INTENT_SLUG}"
    FileUtils.mkdir_p(@intent_worktree)

    @dir = Dir.mktmpdir("nwt-intent")
  end

  def teardown
    FileUtils.remove_entry(@repo) if @repo && Dir.exist?(@repo)
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  # --- fixture helpers -----------------------------------------------------------

  def build_context(intent_dir: @dir, worktree: @intent_worktree, worktree_branch: @intent_branch,
                     intent_id: INTENT_ID, intent_slug: INTENT_SLUG)
    RunnerCore::Context.new(
      intent_dir: intent_dir, intent_id: intent_id, intent_slug: intent_slug,
      store: nil, plastic_home: nil, session: nil,
      worktree: worktree, worktree_branch: worktree_branch,
      graph: { ok: true, edges: {}, nodes: {} }, errors: []
    )
  end

  def node_dir(node, intent_id: INTENT_ID, intent_slug: INTENT_SLUG)
    File.join(@repo, ".claude", "worktrees", "#{intent_id}--#{intent_slug}--#{node}")
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

    assert_equal node_dir("n1"), p["path"]
    assert_equal "plastic/#{INTENT_ID}--#{INTENT_SLUG}--n1", p["branch"]

    other = NodeWorktree.paths(build_context(intent_id: "9", intent_slug: "other-fixture"), node: "n1")
    refute_equal p["path"], other["path"]
    refute_equal p["branch"], other["branch"]
  end

  # --- 3.2: the instruction cuts from the intent branch, never a literal alpha ----

  def test_provision_instruction_cuts_from_intent_branch
    result = NodeWorktree.provision(build_context, node: "n1", kind: "work")

    refute result[:provisioned]
    assert_equal "git -C #{@repo} worktree add #{node_dir('n1')} -b #{result[:branch]} #{@intent_branch}",
                 result[:instruction]
    refute Dir.exist?(node_dir("n1")), "provision must create nothing itself"
  end

  # --- 3.3: idempotent reuse -------------------------------------------------------

  def test_provision_reports_provisioned_when_directory_already_exists
    FileUtils.mkdir_p(node_dir("n1"))

    result = NodeWorktree.provision(build_context, node: "n1", kind: "work")

    assert result[:provisioned]
    assert_nil result[:instruction]
    assert_equal node_dir("n1"), result[:path]
  end

  # --- 3.4/3.5: verify and research nodes get no worktree -------------------------

  def test_verify_node_gets_no_worktree
    result = NodeWorktree.provision(build_context, node: "v1", kind: "verify")
    refute result[:provisioned]
    assert_nil result[:path]
    assert_nil result[:instruction]
  end

  def test_research_node_gets_no_worktree
    result = NodeWorktree.provision(build_context, node: "r1", kind: "research")
    refute result[:provisioned]
    assert_nil result[:path]
  end

  # --- 3.6: fail open on an unresolvable repo ---------------------------------------

  def test_no_intent_worktree_fails_open
    ctx = build_context(worktree: nil)

    result = NodeWorktree.provision(ctx, node: "n1", kind: "work")

    assert result[:ok]
    refute result[:provisioned]
    assert_nil result[:path]
    assert_nil result[:instruction]
  end

  # --- 3.7: merge names the instruction against the intent branch/worktree --------

  def test_merge_names_intent_worktree_and_node_branch
    ctx = build_context

    result = NodeWorktree.merge(ctx, node: "n1")

    assert result[:ok], result[:error]
    assert_equal "git -C #{@intent_worktree} merge --no-ff --no-edit plastic/#{INTENT_ID}--#{INTENT_SLUG}--n1",
                 result[:instruction]
  end

  def test_merge_refuses_with_no_intent_worktree
    ctx = build_context(worktree: nil)

    result = NodeWorktree.merge(ctx, node: "n1")

    refute result[:ok]
    assert_nil result[:instruction]
    refute_nil result[:error]
  end

  # --- 3.8/3.9/3.10/3.11: release policy by terminal state -------------------------

  def test_done_names_removal_instruction_when_directory_exists
    FileUtils.mkdir_p(node_dir("n1"))

    release = NodeWorktree.release(build_context, node: "n1", state: "done")

    refute release[:removed], "Plastic removes nothing itself"
    assert_equal "git -C #{@repo} worktree remove #{node_dir('n1')}", release[:instruction]
    assert Dir.exist?(node_dir("n1")), "release must remove nothing itself"
  end

  def test_failed_verification_names_no_instruction
    FileUtils.mkdir_p(node_dir("n1"))

    release = NodeWorktree.release(build_context, node: "n1", state: "failed_verification")

    refute release[:removed]
    assert_nil release[:instruction]
  end

  def test_needs_decision_names_no_instruction
    FileUtils.mkdir_p(node_dir("n1"))

    release = NodeWorktree.release(build_context, node: "n1", state: "needs_decision")

    refute release[:removed]
    assert_nil release[:instruction]
  end

  def test_terminal_states_name_removal_instruction
    %w[superseded abandoned].each do |state|
      node = "n#{state.length}"
      FileUtils.mkdir_p(node_dir(node))

      release = NodeWorktree.release(build_context, node: node, state: state)

      assert_equal "git -C #{@repo} worktree remove #{node_dir(node)}", release[:instruction],
                   "state #{state} must name a removal instruction"
    end
  end

  def test_release_names_no_instruction_when_directory_absent
    release = NodeWorktree.release(build_context, node: "n1", state: "done")

    refute release[:removed]
    assert_nil release[:instruction]
  end

  # --- 3.15/3.17/3.18: the reaper -----------------------------------------------

  def test_reaper_names_removal_instruction_for_terminal_node
    FileUtils.mkdir_p(node_dir("n1"))
    write_savepoint(line("n1", "running", holder: "auto-1", expires: "2026-01-01T00:00:00Z",
                              input: "abc", model: "sonnet") +
                     line("n1", "done", gates: "integrity+suite", commit: "abc123", ts: "2026-01-01T01:00:00Z"))

    outcome = NodeWorktree.reap(build_context)

    assert_empty outcome[:removed], "Plastic removes nothing itself"
    assert_equal ["n1"], outcome[:instructions].map { |i| i[:node] }
    assert_equal "git -C #{@repo} worktree remove #{node_dir('n1')}", outcome[:instructions].first[:instruction]
    assert Dir.exist?(node_dir("n1"))
  end

  def test_reaper_spares_non_terminal_node
    FileUtils.mkdir_p(node_dir("n1"))
    write_savepoint(line("n1", "running", holder: "auto-1", expires: "2026-01-01T00:00:00Z",
                              input: "abc", model: "sonnet"))

    outcome = NodeWorktree.reap(build_context)

    assert_empty outcome[:instructions]
    assert_equal ["n1"], outcome[:spared].map { |s| s[:node] }
    assert Dir.exist?(node_dir("n1"))
  end

  def test_reaper_ignores_non_node_worktrees
    # Another intent's node worktree, sitting in the very same directory.
    other_dir = File.join(@repo, ".claude", "worktrees", "999--other--n1")
    FileUtils.mkdir_p(other_dir)

    outcome = NodeWorktree.reap(build_context)

    assert Dir.exist?(other_dir)
    assert Dir.exist?(@intent_worktree)
    assert_empty outcome[:instructions].select { |i| i[:dir] == other_dir }
  end
end
