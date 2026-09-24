# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/lib/codex_adapter"

# CodexAdapter (intent 340b, G7c, n6; intent 391): the `codex exec` argv per
# kind and the sandbox and --add-dir it carries, printed and never run.
# Matrix rows 6.1-6.10 in nodes/n6.md.
class CodexAdapterTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("codex-adapter")
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && Dir.exist?(@tmp)
  end

  # --- fixtures ---------------------------------------------------------------

  # A worktree directory whose `.git` FILE points at `gitdir` - the exact
  # shape a real git worktree carries. CodexAdapter never shells out to git
  # to resolve this, so no real repository is needed to test it.
  def make_worktree(gitdir)
    dir = File.join(@tmp, "worktree-#{rand(1_000_000)}")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, ".git"), "gitdir: #{gitdir}\n")
    dir
  end

  # --- 6.1/6.2: verify and research get the read-only sandbox -----------------

  def test_verify_sandbox_is_read_only
    assert_equal "read-only", CodexAdapter.sandbox_mode("verify")
  end

  def test_research_sandbox_is_read_only
    assert_equal "read-only", CodexAdapter.sandbox_mode("research")
  end

  # --- 6.3: work gets workspace-write ------------------------------------------

  def test_work_sandbox_is_workspace_write
    assert_equal "workspace-write", CodexAdapter.sandbox_mode("work")
  end

  # --- 6.4: verify and research get no --add-dir at all ------------------------

  def test_read_only_kinds_get_no_add_dir
    worktree = make_worktree("/repo/.git/worktrees/n1")
    assert_equal [], CodexAdapter.add_dir_args(kind: "verify", worktree: worktree)
    assert_equal [], CodexAdapter.add_dir_args(kind: "research", worktree: worktree)
  end

  # --- 6.5: work gets exactly one --add-dir, the repository's own .git --------

  def test_work_adds_only_the_repository_git_dir
    worktree = make_worktree("/repo/.git/worktrees/n1")
    assert_equal ["--add-dir", "/repo/.git"], CodexAdapter.add_dir_args(kind: "work", worktree: worktree)
  end

  # --- 6.6: the .git path is derived from the worktree's own gitdir pointer ---

  def test_git_dir_resolved_from_the_worktree_pointer
    # A repo root that "count path segments up" would get wrong: nothing
    # about this worktree's own location hints at where the real repo is.
    worktree = File.join(@tmp, "deeply", "nested", "place", "n1-worktree")
    FileUtils.mkdir_p(worktree)
    File.write(File.join(worktree, ".git"), "gitdir: /elsewhere/entirely/myrepo/.git/worktrees/n1-worktree\n")

    assert_equal "/elsewhere/entirely/myrepo/.git", CodexAdapter.git_dir_for_worktree(worktree)
  end

  def test_git_dir_is_nil_for_a_plain_directory
    plain = File.join(@tmp, "not-a-worktree")
    FileUtils.mkdir_p(plain)
    assert_nil CodexAdapter.git_dir_for_worktree(plain)
  end

  # --- 6.7: nothing in the argv widens beyond the node worktree and .git ------

  def test_no_argv_widens_beyond_the_node_worktree_and_git
    worktree = make_worktree("/repo/.git/worktrees/n1")
    argv = CodexAdapter.build_argv(kind: "work", worktree: worktree)

    assert_equal(
      ["codex", "exec", "-C", worktree, "--sandbox", "workspace-write", "--add-dir", "/repo/.git",
       "-"],
      argv
    )
    refute_includes argv.join(" "), ".plastic"
    refute_includes argv.join(" "), "intent"
  end

  # --- 6.8: -C is the node worktree --------------------------------------------

  def test_runs_in_the_node_worktree
    worktree = make_worktree("/repo/.git/worktrees/n1")
    argv = CodexAdapter.build_argv(kind: "verify", worktree: worktree)

    idx = argv.index("-C")
    refute_nil idx
    assert_equal worktree, argv[idx + 1]
  end

  def test_build_argv_passes_model
    argv = CodexAdapter.build_argv(kind: "verify", worktree: @tmp, model: "gpt-5.6-sol", effort: "medium")

    assert_equal "gpt-5.6-sol", argv[argv.index("--model") + 1]
  end

  def test_build_argv_passes_reasoning_effort
    argv = CodexAdapter.build_argv(kind: "verify", worktree: @tmp, model: "gpt-5.6-sol", effort: "medium")

    assert_includes argv, 'model_reasoning_effort="medium"'
  end

  # --- 6.9: the node input rides on stdin, never as an argument --------------------

  def test_input_goes_on_stdin
    line = CodexAdapter.command_line(kind: "verify", worktree: @tmp, input: "/store/n1 input.md")

    assert line.end_with?(' - < /store/n1\ input.md'), line
  end

  def test_command_line_escapes_every_argument
    line = CodexAdapter.command_line(kind: "verify", worktree: "/a b", input: "/in.md", effort: "medium")

    assert_equal 'codex exec -C /a\ b --sandbox read-only --config model_reasoning_effort\=\"medium\" - < /in.md', line
  end

  def test_no_worktree_leaves_out_the_directory_switch
    refute_includes CodexAdapter.build_argv(kind: "research", worktree: nil), "-C"
  end

  # --- 6.10: an unknown kind gets the work sandbox -----------------------------

  def test_unknown_kind_uses_work_sandbox
    worktree = make_worktree("/repo/.git/worktrees/n1")
    assert_equal "workspace-write", CodexAdapter.sandbox_mode("mystery")
    assert_equal ["--add-dir", "/repo/.git"], CodexAdapter.add_dir_args(kind: "mystery", worktree: worktree)
  end
end
