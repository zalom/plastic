# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "rbconfig"
require_relative "../scripts/lib/session_ledger"

# `scripts/session-commit` (intent 390): Plastic runs no version control
# command, so this script only records the item (the day ledger plus one
# "Item" savepoint line) and prints the commit instruction. Every spawn is
# hermetic: a Dir.mktmpdir PLASTIC_HOME, an explicit --session, and
# CLAUDE_CODE_SESSION_ID cleared in the child environment. No test here
# creates a git repository or shells out to git.
class SessionCommitRecordTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/session-commit", __dir__)
  SESSION = "b7137962"
  DAY = "20260829"

  def setup
    @plastic_home = Dir.mktmpdir("session-commit-home")
    @global_store = File.join(@plastic_home, "store")
    FileUtils.mkdir_p(@global_store)
  end

  def teardown
    FileUtils.rm_rf(@plastic_home)
  end

  def run_session_commit(*args, store: @global_store)
    env = {"CLAUDE_CODE_SESSION_ID" => nil}
    full_args = [RbConfig.ruby, SCRIPT, "--store", store, "--plastic-home", @plastic_home,
      "--day", DAY, "--session", SESSION, *args]
    out = IO.popen(env, full_args, err: [:child, :out], &:read)
    [out.strip, $?.exitstatus]
  end

  def savepoint_lines(store)
    path = SessionLedger.savepoint_path(store, DAY)
    File.exist?(path) ? File.read(path).each_line.to_a : []
  end

  def register_project(slug:, path:, agents_file: true)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "AGENTS.md"), "# Conventions\n") if agents_file
    File.write(File.join(@plastic_home, "projects.yml"),
      {"projects" => {slug => {"path" => path}}}.to_yaml)
  end

  def assert_one_item_line(store, summary)
    lines = savepoint_lines(store)

    assert_equal 1, lines.length
    assert_match(/\bItem\b/, lines.first)
    assert_includes lines.first, summary
  end

  # --- usage errors ------------------------------------------------------

  def test_missing_cwd_exits_2_and_writes_nothing
    out, status = run_session_commit("--summary", "a summary")

    assert_equal 2, status, out
    assert_empty savepoint_lines(@global_store)
  end

  def test_missing_summary_exits_2_and_writes_nothing
    out, status = run_session_commit("--cwd", @plastic_home)

    assert_equal 2, status, out
    assert_empty savepoint_lines(@global_store)
  end

  # --- the Item line -------------------------------------------------------

  def test_records_exactly_one_item_line_in_the_named_store
    project_store = File.join(@plastic_home, "projects", "demo", "store")
    FileUtils.mkdir_p(project_store)
    repo = File.join(@plastic_home, "repo")
    register_project(slug: "demo", path: repo)

    out, status = run_session_commit("--cwd", repo, "--summary", "Change the resume page",
      store: project_store)

    assert_equal 0, status, out
    assert_one_item_line(project_store, "Change the resume page")
  end

  def test_ref_is_recorded_in_the_item_line
    repo = File.join(@plastic_home, "repo")
    register_project(slug: "demo", path: repo)

    out, status = run_session_commit("--cwd", repo, "--summary", "Change the resume page",
      "--ref", "abc123")

    assert_equal 0, status, out

    lines = savepoint_lines(@global_store)

    assert_equal 1, lines.length
    assert_includes lines.first, "Change the resume page (ref abc123)"
  end

  def test_no_ref_leaves_the_summary_unchanged
    out, status = run_session_commit("--cwd", @plastic_home, "--summary", "no reference here")

    assert_equal 0, status, out
    lines = savepoint_lines(@global_store)

    assert_includes lines.first, "no reference here"
    refute_includes lines.first, "(ref"
  end

  # --- the printed instruction ---------------------------------------------

  def test_instruction_inside_a_registered_project_names_the_path_and_agents_md
    repo = File.join(@plastic_home, "repo")
    register_project(slug: "demo", path: repo)

    out, status = run_session_commit("--cwd", repo, "--summary", "landed a fix")

    assert_equal 0, status, out
    assert_includes out, repo
    assert_includes out, "AGENTS.md"
  end

  def test_instruction_outside_a_registered_project_names_no_repository
    out, status = run_session_commit("--cwd", @plastic_home, "--summary", "no project here")

    assert_equal 0, status, out
    refute_includes out, "AGENTS.md"
    assert_includes out, "completion-and-done"
  end

  def test_instruction_outside_a_registered_project_still_records_to_the_given_store
    run_session_commit("--cwd", @plastic_home, "--summary", "no project here")

    assert_equal 1, savepoint_lines(@global_store).length, "the record still lands in the store it was given"
  end

  def test_instruction_points_at_completion_and_done_with_no_pull_request_template
    repo = File.join(@plastic_home, "repo")
    register_project(slug: "demo", path: repo)

    out, status = run_session_commit("--cwd", repo, "--summary", "landed a fix")

    assert_equal 0, status, out
    assert_includes out, "plastic help completion-and-done"
  end

  def test_instruction_names_a_detected_pull_request_template
    repo = File.join(@plastic_home, "repo")
    register_project(slug: "demo", path: repo)
    template_dir = File.join(repo, ".github", "PULL_REQUEST_TEMPLATE")
    FileUtils.mkdir_p(template_dir)
    File.write(File.join(template_dir, "feature.md"), "template\n")

    out, status = run_session_commit("--cwd", repo, "--summary", "landed a fix")

    assert_equal 0, status, out
    assert_includes out, "gh pr create --template feature.md"
  end
end
