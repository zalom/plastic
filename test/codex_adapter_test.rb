# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"

require_relative "../scripts/lib/codex_adapter"
require_relative "../scripts/lib/runner_policy"

# CodexAdapter (intent 340b, G7c, n6): the `codex exec` argv per kind, the
# sandbox and --add-dir it carries, the return read from
# --output-last-message with a stdout fallback, and the lease-derived
# timeout. Matrix rows 6.1-6.10, 6.18, 6.19, 6.23 in nodes/n6.md (the rest
# live in node_run_cli_test.rb - CLI-level refusals, the subprocess against
# a stub codex, and the end-to-end sandbox commit).
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

  def write_stub(name, content)
    path = File.join(@tmp, name)
    File.write(path, content)
    FileUtils.chmod(0o755, path)
    path
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
    argv = CodexAdapter.build_argv(kind: "work", worktree: worktree, output_last_message: "/tmp/out.msg")

    assert_equal(
      ["codex", "exec", "-C", worktree, "--sandbox", "workspace-write", "--add-dir", "/repo/.git",
       "--output-last-message", "/tmp/out.msg", "-"],
      argv
    )
    refute_includes argv.join(" "), ".plastic"
    refute_includes argv.join(" "), "intent"
  end

  # --- 6.8: -C is the node worktree --------------------------------------------

  def test_runs_in_the_node_worktree
    worktree = make_worktree("/repo/.git/worktrees/n1")
    argv = CodexAdapter.build_argv(kind: "verify", worktree: worktree, output_last_message: "/tmp/out.msg")

    idx = argv.index("-C")
    refute_nil idx
    assert_equal worktree, argv[idx + 1]
  end

  # --- 6.9: the packet rides on stdin, never as an argument --------------------

  def test_input_goes_on_stdin
    stub = write_stub("echo-stdin", <<~RUBY)
      #!/usr/bin/env ruby
      File.write(ARGV[0], $stdin.read)
    RUBY
    out_path = File.join(@tmp, "out.msg")
    huge_input = "INPUT-MARKER-#{'x' * 5000}"

    argv = [stub, out_path]
    result = CodexAdapter.execute(argv, stdin_data: huge_input, timeout_seconds: 5,
                                   output_last_message_path: out_path)

    refute_includes argv.join(" "), huge_input
    assert_equal huge_input, result[:message]
  end

  # --- 6.10: an unknown kind gets the work sandbox -----------------------------

  def test_unknown_kind_uses_work_sandbox
    worktree = make_worktree("/repo/.git/worktrees/n1")
    assert_equal "workspace-write", CodexAdapter.sandbox_mode("mystery")
    assert_equal ["--add-dir", "/repo/.git"], CodexAdapter.add_dir_args(kind: "mystery", worktree: worktree)
  end

  # --- 6.18: the return comes from --output-last-message, stdout ignored ------

  def test_return_read_from_output_last_message
    stub = write_stub("fixed-output", <<~RUBY)
      #!/usr/bin/env ruby
      $stdin.read
      puts "node: wrong"
      puts "status: failed_verification"
      puts "reason: this is stdout, must be ignored"
      File.write(ARGV[0], "node: n1\\nstatus: done\\ncommit: abc123def456\\n")
    RUBY
    out_path = File.join(@tmp, "out.msg")

    result = CodexAdapter.execute([stub, out_path], stdin_data: "input", timeout_seconds: 5,
                                   output_last_message_path: out_path)

    assert_equal "node: n1\nstatus: done\ncommit: abc123def456\n", result[:message]
  end

  # --- 6.19: stdout is the fallback, the last YAML document wins --------------

  def test_stdout_fallback_extracts_the_last_document
    stub = write_stub("stdout-only", <<~RUBY)
      #!/usr/bin/env ruby
      $stdin.read
      puts "not yaml at all, just prose"
      puts "---"
      puts "node: n1"
      puts "status: failed_verification"
      puts "reason: an earlier attempt, superseded"
      puts "---"
      puts "node: n1"
      puts "status: done"
      puts "commit: deadbeefcafe"
    RUBY
    missing_path = File.join(@tmp, "never-written.msg")

    result = CodexAdapter.execute([stub, missing_path], stdin_data: "input", timeout_seconds: 5,
                                   output_last_message_path: missing_path)

    parsed = YAML.safe_load(result[:message])
    assert_equal "done", parsed["status"]
    assert_equal "deadbeefcafe", parsed["commit"]
  end

  # --- 6.23: the timeout comes from the kind's own lease length ----------------

  def test_timeout_comes_from_the_kind_lease
    assert_equal RunnerPolicy.lease_minutes("work") * 60, CodexAdapter.timeout_seconds("work")
    assert_equal RunnerPolicy.lease_minutes("verify") * 60, CodexAdapter.timeout_seconds("verify")
    assert_equal RunnerPolicy.lease_minutes("research") * 60, CodexAdapter.timeout_seconds("research")
    refute_equal CodexAdapter.timeout_seconds("verify"), CodexAdapter.timeout_seconds("work")
  end
end
