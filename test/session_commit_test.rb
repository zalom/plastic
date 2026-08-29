# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/session_ledger"

# Intent 300: `scripts/session-commit`, driven as a real subprocess. Every
# spawn is hermetic: a Dir.mktmpdir PLASTIC_HOME (and store), an explicit
# --session, and CLAUDE_CODE_SESSION_ID cleared in the child environment
# (test/hermeticity_guard_test.rb's PLASTIC_TMP/Dir.mktmpdir isolation rule
# applies the same way here as it does to append-ledger).
class SessionCommitTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/session-commit", __dir__)
  RUNNER = Worktree::ShellRunner.new
  SESSION = "b7137962"
  DAY = "20260829"

  def setup
    @home = Dir.mktmpdir("session-commit-home")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def git(dir, *args)
    RUNNER.run("-C", dir, *args)
  end

  def build_repo
    dir = Dir.mktmpdir("session-commit-repo")
    git(dir, "init", "-q", "-b", "main")
    git(dir, "config", "user.email", "test@example.com")
    git(dir, "config", "user.name", "Test")
    File.write(File.join(dir, "README.md"), "hello\n")
    git(dir, "add", "-A")
    git(dir, "commit", "-q", "-m", "initial")
    dir
  end

  def run_session_commit(*args, env: {})
    base = {
      "CLAUDE_CODE_SESSION_ID" => nil,
      "PLASTIC_HOME" => @home,
    }
    full_args = [RbConfig.ruby, SCRIPT, "--store", @store, "--plastic-home", @home,
                 "--day", DAY, "--session", SESSION, *args]
    out = IO.popen(base.merge(env), full_args, err: [:child, :out], &:read)
    [out.strip, $?.exitstatus]
  end

  def savepoint_lines
    path = SessionLedger.savepoint_path(@store, DAY)
    File.exist?(path) ? File.read(path).each_line.to_a : []
  end

  # --- cli: missing --cwd or --summary ---------------------------------------

  def test_missing_cwd_exits_2_and_writes_nothing
    out, status = run_session_commit("--summary", "a summary")
    assert_equal 2, status, out
    assert_empty savepoint_lines
  end

  def test_missing_summary_exits_2_and_writes_nothing
    out, status = run_session_commit("--cwd", @home)
    assert_equal 2, status, out
    assert_empty savepoint_lines
  end

  # --- ledger: every outcome writes exactly one line -------------------------

  def test_no_repo_writes_exactly_one_note_line
    Dir.mktmpdir("not-a-repo") do |dir|
      out, status = run_session_commit("--cwd", dir, "--summary", "irrelevant")
      assert_equal 0, status, out
      assert_equal "no repo", out
      lines = savepoint_lines
      assert_equal 1, lines.length
      assert_match(/\bNote\b.*no repo/, lines.first)
    end
  end

  def test_a_landed_commit_writes_exactly_one_item_line
    repo = build_repo
    File.write(File.join(repo, "work.txt"), "changed\n")

    out, status = run_session_commit("--cwd", repo, "--summary", "Change the resume page")
    assert_equal 0, status, out

    lines = savepoint_lines
    assert_equal 1, lines.length
    assert_match(/\bItem\b/, lines.first)
    assert_includes lines.first, "Change the resume page"

    assert_equal "session/#{DAY}", git(repo, "rev-parse", "--abbrev-ref", "HEAD").stdout.to_s.strip
  ensure
    FileUtils.rm_rf(repo)
  end

  def test_a_clean_tree_writes_exactly_one_note_line
    repo = build_repo

    out, status = run_session_commit("--cwd", repo, "--summary", "nothing changed")
    assert_equal 0, status, out
    assert_equal "nothing to commit", out

    lines = savepoint_lines
    assert_equal 1, lines.length
    assert_match(/\bNote\b/, lines.first)
  ensure
    FileUtils.rm_rf(repo)
  end
end
