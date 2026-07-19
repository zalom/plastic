# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

require_relative "../scripts/lib/maintenance_git"

class MaintenanceGitTest < Minitest::Test
  def setup
    @repo = Dir.mktmpdir("plastic-maintenance-git")
    Open3.capture3("git", "-C", @repo, "init", "-q", "-b", "main")
    File.write(File.join(@repo, "seed.md"), "seed\n")
    Open3.capture3("git", "-C", @repo, "add", "seed.md")
    Open3.capture3("git", "-C", @repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "seed")
  end

  def teardown
    FileUtils.remove_entry(@repo) if @repo && Dir.exist?(@repo)
  end

  def branches
    out, = Open3.capture3("git", "-C", @repo, "branch", "--list")
    out.lines.map { |l| l.sub("*", "").strip }
  end

  def test_runs_block_and_merges_scoped_change_back_to_main
    result = MaintenanceGit.run_scoped(repo_dir: @repo, branch_name: "maintenance/t1",
                                       commit_message: "chore: t1") do
      File.write(File.join(@repo, "new.md"), "new\n")
    end

    assert_equal ["new.md"], result[:changed]
    assert result[:committed]
    assert result[:merged]

    out, = Open3.capture3("git", "-C", @repo, "rev-parse", "--abbrev-ref", "HEAD")
    assert_equal "main", out.strip
    assert File.exist?(File.join(@repo, "new.md"))
    refute_includes branches, "maintenance/t1", "the maintenance branch must be deleted after merge"

    status_out, = Open3.capture3("git", "-C", @repo, "status", "--porcelain")
    assert_empty status_out.strip
  end

  # FALSIFIABLE (208): with no global or system git identity available, the scoped merge-back
  # must still succeed because run_scoped passes committer identity on the merge itself. This
  # fails on the pre-fix lib (git aborts the no-ff merge with an unknown-committer error) on
  # any machine, including one whose OS account gives git a name it could otherwise guess.
  # user.useConfigOnly=true (injected via GIT_CONFIG_COUNT/KEY/VALUE, git's own env-config
  # mechanism) disables that OS-account guess, so this isolation is real even on a machine
  # with a normal user account and no git identity configured anywhere.
  ISOLATED_IDENTITY_KEYS = %w[
    GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
    GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  ].freeze

  def test_merges_back_when_no_host_git_identity_is_configured
    saved = ENV.slice(*ISOLATED_IDENTITY_KEYS)
    ENV["GIT_CONFIG_GLOBAL"] = File::NULL
    ENV["GIT_CONFIG_SYSTEM"] = File::NULL
    ENV["GIT_CONFIG_COUNT"] = "1"
    ENV["GIT_CONFIG_KEY_0"] = "user.useConfigOnly"
    ENV["GIT_CONFIG_VALUE_0"] = "true"
    %w[GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL].each { |k| ENV.delete(k) }

    result = MaintenanceGit.run_scoped(repo_dir: @repo, branch_name: "maintenance/noid",
                                       commit_message: "chore: noid") do
      File.write(File.join(@repo, "noid.md"), "noid\n")
    end

    assert result[:merged], "the no-ff merge-back must succeed without any host git identity"
    out, = Open3.capture3("git", "-C", @repo, "rev-parse", "--abbrev-ref", "HEAD")
    assert_equal "main", out.strip
    assert File.exist?(File.join(@repo, "noid.md"))
    refute_includes branches, "maintenance/noid", "the maintenance branch must be deleted after merge"
    status_out, = Open3.capture3("git", "-C", @repo, "status", "--porcelain")
    assert_empty status_out.strip
  ensure
    ISOLATED_IDENTITY_KEYS.each do |k|
      saved.key?(k) ? ENV[k] = saved[k] : ENV.delete(k)
    end
  end

  def test_refuses_to_start_when_working_tree_is_dirty
    File.write(File.join(@repo, "unrelated.md"), "dirty\n")

    assert_raises(MaintenanceGit::DirtyWorkingTree) do
      MaintenanceGit.run_scoped(repo_dir: @repo, branch_name: "maintenance/t2",
                                 commit_message: "chore: t2") { flunk "block must never run" }
    end

    refute_includes branches, "maintenance/t2", "no branch should be created on refusal"
  end

  # FALSIFIABLE (208): a no-op block must not fabricate a commit or leave a branch behind.
  def test_noop_block_makes_no_commit_and_deletes_branch
    before_log, = Open3.capture3("git", "-C", @repo, "log", "--oneline")

    result = MaintenanceGit.run_scoped(repo_dir: @repo, branch_name: "maintenance/t3",
                                       commit_message: "chore: t3") { } # no-op

    refute result[:committed]
    refute result[:merged]
    assert_empty result[:changed]
    after_log, = Open3.capture3("git", "-C", @repo, "log", "--oneline")
    assert_equal before_log, after_log, "a no-op run must add zero commits"
    refute_includes branches, "maintenance/t3"
  end

  # FALSIFIABLE (208): an error mid-block must restore a clean main with no orphaned branch
  # and no partial file left over, proving the clean-tree precondition made recovery safe.
  def test_error_in_block_restores_clean_main_and_deletes_branch
    assert_raises(RuntimeError) do
      MaintenanceGit.run_scoped(repo_dir: @repo, branch_name: "maintenance/t4",
                                 commit_message: "chore: t4") do
        File.write(File.join(@repo, "partial.md"), "oops\n")
        raise "boom"
      end
    end

    out, = Open3.capture3("git", "-C", @repo, "rev-parse", "--abbrev-ref", "HEAD")
    assert_equal "main", out.strip
    status_out, = Open3.capture3("git", "-C", @repo, "status", "--porcelain")
    assert_empty status_out.strip, "the working tree must be clean after a failed maintenance attempt"
    refute File.exist?(File.join(@repo, "partial.md"))
    refute_includes branches, "maintenance/t4"
  end

  def test_not_a_git_repo_raises_before_touching_anything
    plain_dir = Dir.mktmpdir("plastic-not-a-repo")
    begin
      assert_raises(MaintenanceGit::NotAGitRepo) do
        MaintenanceGit.run_scoped(repo_dir: plain_dir, branch_name: "x", commit_message: "x") { }
      end
    ensure
      FileUtils.remove_entry(plain_dir)
    end
  end
end
