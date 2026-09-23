# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require "tmpdir"
require "json"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli"

class CliAutoSessionCommandsTest < Minitest::Test
  LOCK_REPORT = JSON.generate(
    "intent_dir" => "/store/372--skills-to-commands", "session" => "s1",
    "lock" => nil, "lock_fresh" => false, "lock_corrupt" => false,
    "worktree" => {"code" => nil, "code_branch" => nil, "provisioned" => false},
    "delivering" => false, "claims" => []
  )

  REPO = File.expand_path("../..", __dir__)

  def setup
    @dir = Dir.mktmpdir("plastic-cli-auto-session")
    @fixture = CliFixture.new(@dir).global_store(active: [["372", "Skills to commands"]])
    @calls = []
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Same seam test/cli/project_roadmap_commands_test.rb uses: a runner double
  # that never spawns a real script.
  def command(verb, *argv, status: 0, directory: "/nowhere")
    file, const, = Plastic::CLI::TABLE.fetch(verb)
    require File.expand_path("../../scripts/lib/cli/#{file}", __dir__)
    runner = lambda do |path, arguments, capture: false|
      @calls << [path, arguments]
      next status unless capture

      [@captured || LOCK_REPORT, status]
    end
    Plastic::CLI::Commands.const_get(const).call(argv, directory: directory, runner: runner, **@fixture.streams)
  end

  def run_cli(*argv)
    Plastic::CLI.call(argv, directory: "/nowhere", **@fixture.streams)
  end

  def script(name)
    File.expand_path("../../scripts/#{name}", __dir__)
  end

  def intent_dir
    @fixture.intent_dir("global", "372")
  end

  # --- plastic auto, alone or with an unknown word -----------------------------

  def test_bare_auto_exits_zero
    assert_equal 0, run_cli("auto")
  end

  def test_bare_auto_lists_the_take_and_brief_subcommands
    run_cli("auto")

    assert_includes @fixture.printed, "auto take"
    assert_includes @fixture.printed, "auto brief"
  end

  def test_bare_auto_lists_the_report_and_lock_subcommands
    run_cli("auto")

    assert_includes @fixture.printed, "auto report"
    assert_includes @fixture.printed, "auto lock"
  end

  def test_an_unknown_auto_subcommand_exits_two
    assert_equal 2, run_cli("auto", "bogus")
  end

  def test_an_unknown_auto_subcommand_lists_the_subcommands
    run_cli("auto", "bogus")

    Plastic::CLI::TABLE.keys.select { |name| name.start_with?("auto ") }.each do |name|
      assert_includes @fixture.warned, name
    end
  end

  # --- plastic session, alone or with an unknown word --------------------------

  def test_bare_session_exits_zero
    assert_equal 0, run_cli("session")
  end

  def test_bare_session_lists_the_subcommands
    run_cli("session")

    assert_includes @fixture.printed, "session commit"
    assert_includes @fixture.printed, "session handoff"
    assert_includes @fixture.printed, "session summary"
  end

  def test_an_unknown_session_subcommand_exits_two
    assert_equal 2, run_cli("session", "bogus")
  end

  # --- auto take ------------------------------------------------------------------

  def test_take_runs_plastic_lock_arm
    command("auto take", "372")

    assert_equal [script("plastic-lock")], @calls.map(&:first)
    assert_equal [["arm", "--intent-dir", intent_dir, "--mode", "auto"]], @calls.map(&:last)
  end

  def test_take_names_brief_in_its_next_step
    command("auto take", "372")

    assert_includes @fixture.printed, "next: plastic auto brief 372"
  end

  def test_take_forwards_the_explicit_inline_override
    command("auto take", "372", "--allow-inline")

    assert_equal ["arm", "--intent-dir", intent_dir, "--mode", "auto", "--allow-inline"], @calls.last.last
  end

  def test_take_with_an_unknown_id_exits_one
    assert_equal 1, command("auto take", "999")
  end

  def test_a_failing_take_exits_one
    assert_equal 1, command("auto take", "372", status: 5)
  end

  # --- auto brief ------------------------------------------------------------------

  def test_brief_runs_spawn_preamble
    command("auto brief", "372")

    assert_equal [script("spawn-preamble")], @calls.map(&:first)
    assert_equal [[intent_dir]], @calls.map(&:last)
  end

  def test_brief_passes_through_role
    command("auto brief", "372", "--role", "executor")

    assert_equal [[intent_dir, "--role", "executor"]], @calls.map(&:last)
  end

  def test_brief_with_role_advisor_prints_the_three_shapes
    command("auto brief", "372", "--role", "advisor")

    assert_includes @fixture.printed, "verdict plus the biggest risk"
    assert_includes @fixture.printed, "stepped plan plus a risk map"
    assert_includes @fixture.printed, "kill criteria"
  end

  def test_brief_without_role_advisor_never_prints_the_three_shapes
    command("auto brief", "372", "--role", "executor")

    refute_includes @fixture.printed, "kill criteria"
  end

  def test_brief_with_no_role_never_prints_the_three_shapes
    command("auto brief", "372")

    refute_includes @fixture.printed, "kill criteria"
  end

  def test_brief_names_report_in_its_next_step
    command("auto brief", "372")

    assert_includes @fixture.printed, "next: plastic auto report 372"
  end

  def test_a_failing_brief_exits_one
    assert_equal 1, command("auto brief", "372", status: 5)
  end

  # --- auto report -----------------------------------------------------------------

  def test_report_runs_agent_report
    command("auto report", "372")

    assert_equal [script("agent-report")], @calls.map(&:first)
    assert_equal [[intent_dir]], @calls.map(&:last)
  end

  def test_report_passes_through_role
    command("auto report", "372", "--role", "enforcer")

    assert_equal [[intent_dir, "--role", "enforcer"]], @calls.map(&:last)
  end

  def test_report_always_prints_the_review_rules
    command("auto report", "372")

    assert_includes @fixture.printed, "Review by risk"
    assert_includes @fixture.printed, "deviations"
  end

  def test_report_names_lock_release_in_its_next_step
    command("auto report", "372")

    assert_includes @fixture.printed, "next: plastic auto lock release 372"
  end

  def test_a_failing_report_exits_one
    assert_equal 1, command("auto report", "372", status: 5)
  end

  # --- auto lock ---------------------------------------------------------------------

  def test_lock_status_runs_plastic_lock_status
    command("auto lock", "status", "372")

    assert_equal [script("plastic-lock")], @calls.map(&:first)
    assert_equal [["status", "--intent-dir", intent_dir]], @calls.map(&:last)
  end

  def test_lock_fix_runs_plastic_lock_fix
    command("auto lock", "fix", "372")

    assert_equal [["fix", "--intent-dir", intent_dir]], @calls.map(&:last)
  end

  def test_lock_release_runs_plastic_lock_release
    command("auto lock", "release", "372")

    assert_equal [["release", "--intent-dir", intent_dir]], @calls.map(&:last)
  end

  def test_lock_names_the_next_verb_by_current_verb
    command("auto lock", "status", "372")

    assert_includes @fixture.printed, "next: none"
  end

  def test_lock_with_an_unknown_verb_exits_two
    assert_equal 2, command("auto lock", "bogus", "372")
  end

  def test_lock_with_an_unknown_id_exits_one
    assert_equal 1, command("auto lock", "status", "999")
  end

  def test_lock_status_prints_a_screen_not_the_document
    command("auto lock", "status", "372")

    refute_includes @fixture.printed, "lock_corrupt"
  end

  def test_lock_status_screen_names_the_intent_and_an_open_lock
    command("auto lock", "status", "372")

    assert_includes @fixture.printed, "372--skills-to-commands"
    assert_includes @fixture.printed, "lock        none"
  end

  def test_lock_status_names_the_session_that_holds_a_fresh_lock
    @captured = JSON.generate("intent_dir" => "/store/372", "lock" => {"session" => "abc"},
      "lock_fresh" => true, "delivering" => true)
    command("auto lock", "status", "372")

    assert_includes @fixture.printed, "held by abc"
  end

  def test_lock_status_accepts_a_lock_that_is_not_a_hash
    @captured = JSON.generate("intent_dir" => "/store/372", "lock" => "abc", "lock_fresh" => true)
    command("auto lock", "status", "372")

    assert_includes @fixture.printed, "held by abc"
  end

  def test_lock_status_uses_the_current_owner_session_field
    @captured = JSON.generate("intent_dir" => "/store/372", "lock" => {"owner_session" => "current-owner", "session" => "legacy"},
      "lock_fresh" => true)
    command("auto lock", "status", "372")

    assert_includes @fixture.printed, "held by current-owner"
  end

  def test_lock_status_marks_a_stale_lock_stale
    @captured = JSON.generate("intent_dir" => "/store/372", "lock" => {"session" => "abc"},
      "lock_fresh" => false)
    command("auto lock", "status", "372")

    assert_includes @fixture.printed, "held by abc, stale"
  end

  def test_lock_status_names_fix_for_a_corrupt_lock
    @captured = JSON.generate("intent_dir" => "/store/372", "lock" => {}, "lock_corrupt" => true)
    command("auto lock", "status", "372")

    assert_includes @fixture.printed, "plastic auto lock fix 372 rewrites it"
  end

  def test_lock_status_does_not_hide_a_corrupt_unreadable_lock
    @captured = JSON.generate("intent_dir" => "/store/372", "lock" => nil, "lock_corrupt" => true)
    command("auto lock", "status", "372")

    assert_includes @fixture.printed, "corrupt, plastic auto lock fix 372"
  end

  def test_lock_status_shows_a_provisioned_worktree
    @captured = JSON.generate("intent_dir" => "/store/372", "lock" => nil,
      "worktree" => {"code" => "/wt/372", "code_branch" => "wt-372", "provisioned" => true})
    command("auto lock", "status", "372")

    assert_includes @fixture.printed, "/wt/372  on  wt-372"
  end

  def test_lock_status_lists_the_claims
    @captured = JSON.generate("intent_dir" => "/store/372", "lock" => nil, "claims" => ["a.rb"])
    command("auto lock", "status", "372")

    assert_includes @fixture.printed, "a.rb"
  end

  def test_a_failing_lock_status_exits_one
    assert_equal 1, command("auto lock", "status", "372", status: 5)
  end

  def test_a_failing_lock_status_names_the_exit_code
    command("auto lock", "status", "372", status: 5)

    assert_includes @fixture.warned, "plastic-lock exited 5"
  end

  def test_lock_status_with_an_unreadable_report_exits_one
    @captured = "not a report"

    assert_equal 1, command("auto lock", "status", "372")
  end

  def test_lock_status_with_an_unreadable_report_says_so
    @captured = "not a report"
    command("auto lock", "status", "372")

    assert_includes @fixture.warned, "plastic-lock did not print a report"
  end

  def test_a_failing_lock_release_exits_one
    assert_equal 1, command("auto lock", "release", "372", status: 5)
  end

  # --- session commit --------------------------------------------------------------

  def test_commit_runs_session_commit
    command("session commit", "shipped the thin slice", directory: "/code/plastic")

    assert_equal [script("session-commit")], @calls.map(&:first)
    assert_equal [["--cwd", "/code/plastic", "--summary", "shipped the thin slice"]], @calls.map(&:last)
  end

  def test_commit_without_a_summary_exits_two
    assert_equal 2, command("session commit")
  end

  def test_commit_names_handoff_in_its_next_step
    command("session commit", "shipped the thin slice")

    assert_includes @fixture.printed, "next: plastic session handoff"
  end

  def test_a_failing_commit_exits_one
    assert_equal 1, command("session commit", "shipped the thin slice", status: 5)
  end

  # --- session handoff ---------------------------------------------------------------

  def test_handoff_runs_write_handoff
    command("session handoff")

    assert_equal [script("write-handoff")], @calls.map(&:first)
    assert_equal [["--trigger", "tick"]], @calls.map(&:last)
  end

  def test_handoff_names_summary_in_its_next_step
    command("session handoff")

    assert_includes @fixture.printed, "next: plastic session summary"
  end

  def test_a_failing_handoff_exits_one
    assert_equal 1, command("session handoff", status: 5)
  end

  # --- session summary ---------------------------------------------------------------

  def test_summary_runs_day_summary
    command("session summary")

    assert_equal [script("day-summary")], @calls.map(&:first)
    assert_equal [[]], @calls.map(&:last)
  end

  def test_summary_names_status_in_its_next_step
    command("session summary")

    assert_includes @fixture.printed, "next: plastic status"
  end

  def test_a_failing_summary_exits_one
    assert_equal 1, command("session summary", status: 5)
  end

  # --- the four skills are gone, their reachable content moved to docs/help ---------

  def test_the_four_retired_skill_directories_are_gone
    %w[auto direct agent-advisor releasing].each do |name|
      refute_path_exists File.join(REPO, "skills", name), "skills/#{name} should have been deleted"
    end
  end
end
