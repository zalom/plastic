# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require_relative "../scripts/lib/session_git"
require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/installer_core"
require_relative "../scripts/lib/project_validator"

# Intent 300: the branch model and flow settings behind `session-commit`.
# Real-repo cases build their own repository under Dir.mktmpdir with a local
# user name and email, and use the real Worktree::ShellRunner (git IS the
# thing under test here: branches, staging, pushing, stashing, hooks). Pure
# logic (subject truncation, branch templating, ticket resolution) is tested
# without touching git at all.
class SessionGitTest < Minitest::Test
  RUNNER = Worktree::ShellRunner.new

  def git(dir, *args)
    RUNNER.run("-C", dir, *args)
  end

  def build_repo
    dir = Dir.mktmpdir("session-git-repo")
    git(dir, "init", "-q", "-b", "main")
    git(dir, "config", "user.email", "test@example.com")
    git(dir, "config", "user.name", "Test")
    File.write(File.join(dir, "README.md"), "hello\n")
    git(dir, "add", "-A")
    git(dir, "commit", "-q", "-m", "initial")
    dir
  end

  def write_dirty_file(dir, name = "work.txt", content = "changed\n")
    File.write(File.join(dir, name), content)
  end

  def current_branch(dir)
    git(dir, "rev-parse", "--abbrev-ref", "HEAD").stdout.to_s.strip
  end

  def head_sha(dir)
    git(dir, "rev-parse", "HEAD").stdout.to_s.strip
  end

  def setup
    @home = Dir.mktmpdir("session-git-home")
    @plastic_home = File.join(@home, ".plastic")
    FileUtils.mkdir_p(@plastic_home)
    @day = "20260829"
    @session = "b7137962"
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def register_project(slug, repo_path)
    File.write(File.join(@plastic_home, "projects.yml"),
               YAML.dump({ "projects" => { slug => { "path" => repo_path } } }))
  end

  def write_flow(slug, flow_hash)
    project_dir = File.join(@plastic_home, "projects", slug)
    FileUtils.mkdir_p(project_dir)
    File.write(File.join(project_dir, "project.yml"), YAML.dump({ "flow" => flow_hash }))
  end

  def store
    File.join(@plastic_home, "store")
  end

  def commit!(cwd, summary, **kwargs)
    SessionGit.commit!(cwd: cwd, summary: summary, day: @day, session: @session,
                        plastic_home: @plastic_home, store: store, **kwargs)
  end

  # --- resolve: cwd outside any repo ---------------------------------------

  def test_resolve_repo_outside_any_repo_is_nil
    Dir.mktmpdir("not-a-repo") do |dir|
      assert_nil SessionGit.resolve_repo(dir, runner: RUNNER)
    end
  end

  def test_commit_outside_any_repo_reports_no_repo_and_is_a_note
    Dir.mktmpdir("not-a-repo") do |dir|
      result = commit!(dir, "irrelevant summary")
      assert_equal "no repo", result.message
      assert_equal "Note", result.event
    end
  end

  # --- resolve: cwd nested in a repo subdir --------------------------------

  def test_resolve_repo_from_nested_subdir_finds_the_root
    repo = build_repo
    nested = File.join(repo, "a", "b")
    FileUtils.mkdir_p(nested)

    assert_equal repo, SessionGit.resolve_repo(nested, runner: RUNNER)
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- flow: project with a flow: block reads all five knobs ---------------

  def test_load_flow_reads_all_five_knobs_from_the_project_flow_block
    repo = build_repo
    register_project("demo", repo)
    write_flow("demo", {
      "mode" => "pull_request",
      "base" => "trunk",
      "branch_template" => "quick/{{ticket}}",
      "ticket_source" => "intent_id",
      "workspace" => "worktree",
    })

    flow, notes = SessionGit.load_flow(cwd: repo, repo: repo, plastic_home: @plastic_home, runner: RUNNER)

    assert_equal "pull_request", flow["mode"]
    assert_equal "trunk", flow["base"]
    assert_equal "quick/{{ticket}}", flow["branch_template"]
    assert_equal "intent_id", flow["ticket_source"]
    assert_equal "worktree", flow["workspace"]
    assert_empty notes
  ensure
    FileUtils.rm_rf(repo)
  end

  def test_load_flow_unknown_mode_falls_back_to_direct_with_a_note
    repo = build_repo
    register_project("demo", repo)
    write_flow("demo", { "mode" => "carrier-pigeon" })

    flow, notes = SessionGit.load_flow(cwd: repo, repo: repo, plastic_home: @plastic_home, runner: RUNNER)

    assert_equal "direct", flow["mode"]
    refute_empty notes
    assert notes.any? { |n| n.include?("carrier-pigeon") }
  ensure
    FileUtils.rm_rf(repo)
  end

  def test_load_flow_unknown_workspace_falls_back_to_checkout_with_a_note
    repo = build_repo
    register_project("demo", repo)
    write_flow("demo", { "workspace" => "moon-base" })

    flow, notes = SessionGit.load_flow(cwd: repo, repo: repo, plastic_home: @plastic_home, runner: RUNNER)

    assert_equal "checkout", flow["workspace"]
    refute_empty notes
    assert notes.any? { |n| n.include?("moon-base") }
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- flow: no project match -> defaults, base falls through the chain ----

  def test_load_flow_no_project_match_uses_defaults_and_detects_base
    repo = build_repo # no register_project call at all: an unregistered repo

    flow, notes = SessionGit.load_flow(cwd: repo, repo: repo, plastic_home: @plastic_home, runner: RUNNER)

    assert_equal "direct", flow["mode"]
    assert_equal "main", flow["base"] # no origin/HEAD, no `main` ref race: this repo's only branch
    assert_equal "session/{{day}}", flow["branch_template"]
    assert_equal "intent_id", flow["ticket_source"]
    assert_equal "checkout", flow["workspace"]
    assert_empty notes
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- direct: on base, dirty tree ------------------------------------------

  def test_direct_on_base_dirty_tree_commits_to_session_branch_and_fast_forwards_base
    repo = build_repo
    write_dirty_file(repo)

    result = commit!(repo, "Change how titles appear")

    assert_equal "Item", result.event
    assert_equal "session/#{@day}", current_branch(repo)
    assert_equal head_sha(repo), git(repo, "rev-parse", "main").stdout.to_s.strip
    assert_match(/\AChange how titles appear \(\h{4,}\)\z/, result.message)
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- direct: on session branch already ------------------------------------

  def test_direct_on_session_branch_already_is_reused_not_recreated
    repo = build_repo
    git(repo, "branch", "session/#{@day}", "main")
    git(repo, "checkout", "-q", "session/#{@day}")
    File.write(File.join(repo, "extra.txt"), "extra\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "an earlier item already on the session branch")
    earlier_sha = head_sha(repo)

    write_dirty_file(repo)
    result = commit!(repo, "Second item")

    assert_equal "Item", result.event
    assert_equal "session/#{@day}", current_branch(repo)
    log = git(repo, "log", "--format=%H", "session/#{@day}").stdout.to_s.split("\n")
    assert_includes log, earlier_sha, "the branch must be reused, not recreated from main's tip"
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- direct: clean tree -----------------------------------------------------

  def test_direct_clean_tree_is_nothing_to_commit
    repo = build_repo

    result = commit!(repo, "nothing changed")

    assert_equal "nothing to commit", result.message
    assert_equal "Note", result.event
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- direct: on a plastic/<id>--<slug> branch (agent lock) ------------------

  def test_direct_on_plastic_prefixed_branch_touches_nothing
    repo = build_repo
    git(repo, "checkout", "-q", "-b", "plastic/123--x")
    write_dirty_file(repo)

    result = commit!(repo, "should not land")

    assert_equal "Note", result.event
    assert_includes result.message, "left branch plastic/123--x untouched: agent lock"
    assert_equal "plastic/123--x", current_branch(repo)
    assert_match(/^\?\? work\.txt/, git(repo, "status", "--porcelain").stdout.to_s)
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- direct: on a branch checked out in .claude/worktrees/ -------------------

  def test_direct_on_branch_checked_out_in_dot_claude_worktrees_touches_nothing
    repo = build_repo
    git(repo, "branch", "someones-feature", "main")
    wt = File.join(repo, ".claude", "worktrees", "someones-feature")
    git(repo, "worktree", "add", wt, "someones-feature")
    write_dirty_file(wt)

    result = SessionGit.commit!(cwd: wt, summary: "should not land", day: @day, session: @session,
                                 plastic_home: @plastic_home, store: store, runner: RUNNER)

    assert_equal "Note", result.event
    assert_includes result.message, "agent lock"
    assert_match(/^\?\? work\.txt/, git(wt, "status", "--porcelain").stdout.to_s)
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- direct: on feature/x, dirty --------------------------------------------

  def test_direct_on_feature_branch_dirty_commits_there_and_notes_the_deviation
    repo = build_repo
    git(repo, "checkout", "-q", "-b", "feature/x")
    write_dirty_file(repo)

    result = commit!(repo, "A quick fix")

    assert_equal "Note", result.event
    assert_includes result.message, "on feature/x, not the session branch"
    assert_equal "feature/x", current_branch(repo)
    assert_equal "", git(repo, "status", "--porcelain").stdout.to_s.strip
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- direct: detached HEAD ----------------------------------------------------

  def test_direct_detached_head_commits_nothing
    repo = build_repo
    sha = head_sha(repo)
    git(repo, "checkout", "-q", sha)
    write_dirty_file(repo)

    result = commit!(repo, "detached work")

    assert_equal "Note", result.event
    assert_includes result.message, "detached HEAD"
    assert_match(/^\?\? work\.txt/, git(repo, "status", "--porcelain").stdout.to_s)
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- direct: base moved ahead independently (non fast forward) ---------------

  def test_direct_base_moved_ahead_independently_refuses_the_push
    repo = build_repo
    git(repo, "branch", "session/#{@day}", "main")

    # Someone else advances main directly, so the session branch's push
    # target no longer fast-forwards from the session branch's own tip.
    git(repo, "checkout", "-q", "main")
    File.write(File.join(repo, "other.txt"), "someone else's work\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "advance main independently")

    git(repo, "checkout", "-q", "session/#{@day}")
    write_dirty_file(repo)

    result = commit!(repo, "an item on the stale session branch")

    assert_equal "Note", result.event
    assert_includes result.message, "not a fast-forward"
    assert_equal "session/#{@day}", current_branch(repo)
    # the commit itself landed on the session branch even though the push was refused
    assert_equal "", git(repo, "status", "--porcelain").stdout.to_s.strip
    refute_equal git(repo, "rev-parse", "main").stdout.to_s.strip,
                 git(repo, "rev-parse", "session/#{@day}").stdout.to_s.strip
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- direct: workspace: worktree ----------------------------------------------

  def test_direct_workspace_worktree_cuts_the_session_branch_into_a_worktree
    repo = build_repo
    register_project("demo", repo)
    write_flow("demo", { "workspace" => "worktree" })
    write_dirty_file(repo)

    result = commit!(repo, "worktree-routed item")

    assert_equal "Item", result.event
    wt_path = File.join(repo, ".claude", "worktrees", "session-#{@day}")
    assert Dir.exist?(wt_path), "expected the session worktree at #{wt_path}"
    assert_equal "session/#{@day}", current_branch(wt_path)
    assert_equal head_sha(wt_path), git(repo, "rev-parse", "main").stdout.to_s.strip
    # the original checkout stays on main, untouched by a branch switch
    assert_equal "main", current_branch(repo)
    assert_equal "", git(repo, "status", "--porcelain").stdout.to_s.strip
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- pr: mode: pull_request, gh stubbed ---------------------------------------

  class FakeGhRunner
    Result = Struct.new(:status, :stdout, :stderr) do
      def success?
        status.zero?
      end
    end

    def initialize(available:, pr_result: nil)
      @available = available
      @pr_result = pr_result || Result.new(0, "https://github.com/example/repo/pull/1\n", "")
      @calls = []
    end

    attr_reader :calls

    def available?
      @available
    end

    def run(*args)
      @calls << args
      @pr_result
    end
  end

  def test_pr_mode_with_gh_available_cuts_the_templated_branch_and_records_the_pr_url
    repo = build_repo
    register_project("demo", repo)
    write_flow("demo", { "mode" => "pull_request", "branch_template" => "pr/{{day}}-{{slug}}" })
    write_dirty_file(repo)
    gh = FakeGhRunner.new(available: true)

    result = commit!(repo, "Fix the login bug", gh_runner: gh)

    assert_equal "Item", result.event
    assert_equal "pr https://github.com/example/repo/pull/1", result.message
    assert_equal "main", current_branch(repo), "must return to the previous branch"
    expected_branch = "pr/#{@day}-fix-the-login-bug"
    assert git(repo, "rev-parse", "--verify", "--quiet", expected_branch).success?
    refute_empty gh.calls
    assert_equal ["pr", "create", "--base", "main", "--head", expected_branch, "--fill"], gh.calls.first
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- pr: gh missing --------------------------------------------------------------

  def test_pr_mode_with_gh_missing_still_lands_the_commit_and_notes_gh_missing
    repo = build_repo
    register_project("demo", repo)
    write_flow("demo", { "mode" => "pull_request" })
    write_dirty_file(repo)
    gh = FakeGhRunner.new(available: false)

    result = commit!(repo, "Fix without gh", gh_runner: gh)

    assert_equal "Note", result.event
    assert_equal "gh missing", result.message
    assert_equal "main", current_branch(repo)
    assert_empty gh.calls
    branch = "session/#{@day}" # branch_template default; day-only, no ticket/slug in default template
    assert git(repo, "rev-parse", "--verify", "--quiet", branch).success?
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- template rendering -----------------------------------------------------------

  def test_render_branch_substitutes_day_ticket_and_slug
    rendered = SessionGit.render_branch("pr/{{day}}/{{ticket}}/{{slug}}", day: "20260829", ticket: "300", slug: "fix-login")
    assert_equal "pr/20260829/300/fix-login", rendered
  end

  def test_resolve_ticket_uses_the_pointer_when_it_names_an_intent
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(store, @session))
    File.write(SessionLedger.pointer_path(store, @session), "300\n")

    ticket = SessionGit.resolve_ticket(day: @day, store: store, session: @session, ticket_source: "intent_id")
    assert_equal "300", ticket
  end

  def test_resolve_ticket_falls_back_to_the_day_id_when_the_pointer_names_the_day
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(store, @session))
    File.write(SessionLedger.pointer_path(store, @session), "#{@day}\n")

    ticket = SessionGit.resolve_ticket(day: @day, store: store, session: @session, ticket_source: "intent_id")
    assert_equal @day, ticket
  end

  def test_resolve_ticket_falls_back_to_the_day_id_when_no_pointer_exists
    ticket = SessionGit.resolve_ticket(day: @day, store: store, session: @session, ticket_source: "intent_id")
    assert_equal @day, ticket
  end

  def test_resolve_ticket_ignores_the_pointer_when_ticket_source_is_not_intent_id
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(store, @session))
    File.write(SessionLedger.pointer_path(store, @session), "300\n")

    ticket = SessionGit.resolve_ticket(day: @day, store: store, session: @session, ticket_source: "day")
    assert_equal @day, ticket
  end

  # --- commit: summary truncation ----------------------------------------------------

  def test_subject_for_truncates_a_long_summary_to_72_chars
    long = "x" * 100
    subject = SessionGit.subject_for(long)
    assert_equal 72, subject.length
    assert_equal "x" * 72, subject
  end

  def test_subject_for_a_multiline_summary_keeps_only_the_first_line
    subject = SessionGit.subject_for("First line of the summary\nSecond line never appears")
    assert_equal "First line of the summary", subject
  end

  # --- commit: repository commit-msg hook rejects ------------------------------------

  def test_commit_msg_hook_rejection_is_a_note_not_an_exit_failure
    repo = build_repo
    hooks_dir = File.join(repo, ".git", "hooks")
    FileUtils.mkdir_p(hooks_dir)
    hook_path = File.join(hooks_dir, "commit-msg")
    File.write(hook_path, <<~SH)
      #!/bin/sh
      echo "no thanks" 1>&2
      exit 1
    SH
    FileUtils.chmod(0o755, hook_path)
    write_dirty_file(repo)

    result = commit!(repo, "should be rejected by the hook")

    assert_equal "Note", result.event
    assert_includes result.message, "no thanks"
    assert_match(/^\?\? work\.txt/, git(repo, "status", "--porcelain").stdout.to_s)
  ensure
    FileUtils.rm_rf(repo)
  end

  # --- library: no ENV read in session_git.rb ----------------------------------------

  def test_library_source_has_no_env_token
    source = File.read(File.expand_path("../scripts/lib/session_git.rb", __dir__))
    refute_match(/\bENV\b/, source)
  end

  # --- installer: manifest -------------------------------------------------------------

  def test_installer_manifest_includes_session_commit_and_session_git_lib
    installer = InstallerCore.new(package_root: File.expand_path("..", __dir__))
    assert_includes installer.core_files.keys, "scripts/session-commit"
    assert_includes installer.core_files.keys, "scripts/lib/session_git.rb"
  end

  # --- validator: flow: block --------------------------------------------------------

  def test_project_validator_accepts_a_project_yml_with_a_flow_block
    Dir.mktmpdir do |home|
      Dir.mktmpdir do |project_root|
        File.write(File.join(home, "projects.yml"),
                   YAML.dump({ "projects" => { "demo" => { "path" => project_root } } }))
        project_dir = File.join(home, "projects", "demo")
        FileUtils.mkdir_p(File.join(project_dir, "store"))
        File.write(File.join(project_dir, "project.yml"),
                   YAML.dump({ "governing_docs" => ["AGENTS.md"],
                               "flow" => { "mode" => "direct", "workspace" => "checkout" } }))
        File.write(File.join(project_dir, "INDEX.md"), "# Index\n")
        File.write(File.join(project_root, "AGENTS.md"), "# Project\n")

        result = ProjectValidator.validate("demo", plastic_home: home)
        assert result[:ok], result.inspect
        assert_empty result[:errors]
      end
    end
  end

  def test_project_validator_reports_a_bad_flow_mode_value
    Dir.mktmpdir do |home|
      Dir.mktmpdir do |project_root|
        File.write(File.join(home, "projects.yml"),
                   YAML.dump({ "projects" => { "demo" => { "path" => project_root } } }))
        project_dir = File.join(home, "projects", "demo")
        FileUtils.mkdir_p(File.join(project_dir, "store"))
        File.write(File.join(project_dir, "project.yml"),
                   YAML.dump({ "governing_docs" => ["AGENTS.md"],
                               "flow" => { "mode" => "carrier-pigeon" } }))
        File.write(File.join(project_dir, "INDEX.md"), "# Index\n")
        File.write(File.join(project_root, "AGENTS.md"), "# Project\n")

        result = ProjectValidator.validate("demo", plastic_home: home)
        # a bad flow value is reported but never blocks spawn completeness: SessionGit
        # degrades it to a default plus a Note at commit time instead.
        assert result[:ok], result.inspect
        assert result[:errors].any? { |e| e.include?("flow.mode") && e.include?("carrier-pigeon") }
      end
    end
  end
end
