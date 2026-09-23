# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require "tmpdir"
require "yaml"
require "json"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli"

class CliProjectRoadmapCommandsTest < Minitest::Test
  WHICH_REPORT = JSON.generate(
    "state" => "dispatchable", "roadmap" => "cli", "frontier_wave" => "Batch 1",
    "dispatchable_queue" => [{"id" => "376", "status" => "queued", "wave" => "Batch 1"}],
    "in_flight" => [{"id" => "363", "status" => "delivering", "wave" => "Batch 1"}],
    "blocked" => [], "tie" => false, "tie_candidates" => []
  )

  def setup
    @dir = Dir.mktmpdir("plastic-cli-project-roadmap")
    @fixture = CliFixture.new(@dir).global_store(active: [["372", "Skills to commands"]])
    @calls = []
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Runs one command class directly, with a runner double that never spawns a
  # real script - the same seam test/cli/intent_commands_test.rb uses.
  def command(verb, *argv, status: 0, directory: "/nowhere")
    file, const, = Plastic::CLI::TABLE.fetch(verb)
    require File.expand_path("../../scripts/lib/cli/#{file}", __dir__)
    runner = lambda do |path, arguments, capture: false|
      @calls << [path, arguments]
      next status unless capture

      [@captured || WHICH_REPORT, status]
    end
    Plastic::CLI::Commands.const_get(const).call(argv, directory: directory, runner: runner, **@fixture.streams)
  end

  # Runs the real dispatcher, for the cases that turn on matching, not on the
  # runner seam.
  def run_cli(*argv)
    Plastic::CLI.call(argv, directory: "/nowhere", **@fixture.streams)
  end

  def script(name)
    File.expand_path("../../scripts/#{name}", __dir__)
  end

  def projects_yml
    File.join(@fixture.plastic_home, "projects.yml")
  end

  def project_path
    dir = File.join(@dir, "code", "acme")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "AGENTS.md"), "# acme\n")
    dir
  end

  # --- plastic project, alone or with an unknown word -------------------------

  def test_bare_project_lists_the_subcommands
    assert_equal 0, run_cli("project")

    assert_includes @fixture.printed, "project list"
    assert_includes @fixture.printed, "project new"
  end

  def test_an_unknown_project_subcommand_exits_two
    assert_equal 2, run_cli("project", "bogus")
  end

  def test_an_unknown_project_subcommand_lists_the_subcommands
    run_cli("project", "bogus")

    Plastic::CLI::TABLE.keys.select { |name| name.start_with?("project ") }.each do |name|
      assert_includes @fixture.warned, name
    end
  end

  # --- plastic roadmap, alone or with an unknown word --------------------------

  def test_bare_roadmap_lists_the_subcommands
    assert_equal 0, run_cli("roadmap")

    assert_includes @fixture.printed, "roadmap show"
    assert_includes @fixture.printed, "roadmap next"
  end

  def test_an_unknown_roadmap_subcommand_exits_two
    assert_equal 2, run_cli("roadmap", "bogus")
  end

  def test_an_unknown_roadmap_subcommand_lists_the_subcommands
    run_cli("roadmap", "bogus")

    Plastic::CLI::TABLE.keys.select { |name| name.start_with?("roadmap ") }.each do |name|
      assert_includes @fixture.warned, name
    end
  end

  # --- project list -------------------------------------------------------------

  def test_list_prints_one_row_per_store
    @fixture.project("acme", active: [])
    require_relative "../../scripts/lib/cli/commands/project_list"
    Plastic::CLI::Commands::ProjectList.call([], directory: "/nowhere", **@fixture.streams)

    assert_includes @fixture.printed, "global"
    assert_includes @fixture.printed, "acme"
  end

  def test_list_names_status_in_its_next_step
    require_relative "../../scripts/lib/cli/commands/project_list"
    Plastic::CLI::Commands::ProjectList.call([], directory: "/nowhere", **@fixture.streams)

    assert_includes @fixture.printed, "next: plastic status"
  end

  # --- project new ---------------------------------------------------------------

  def test_new_registers_the_project_in_projects_yml
    path = project_path
    command("project new", "acme", "--path", path)

    data = YAML.safe_load_file(projects_yml)

    assert_equal File.expand_path(path), data["projects"]["acme"]["path"]
    assert_equal "active", data["projects"]["acme"]["status"]
  end

  def test_new_keeps_the_projects_already_registered
    File.write(projects_yml, YAML.dump("projects" => {"older" => {"path" => "/elsewhere"}}))
    command("project new", "acme", "--path", project_path)

    assert_equal %w[acme older], YAML.safe_load_file(projects_yml)["projects"].keys.sort
  end

  def test_new_passes_through_parent
    path = project_path
    command("project new", "acme", "--path", path, "--parent", "372")

    data = YAML.safe_load_file(projects_yml)

    assert_equal "372", data["projects"]["acme"]["parent"]
  end

  def test_new_runs_provision_then_validate
    path = project_path
    command("project new", "acme", "--path", path)

    assert_equal [script("provision-project-store"), script("validate-project")], @calls.map(&:first)
    assert_equal "acme", @calls[0].last.first
    assert_equal "acme", @calls[1].last.first
  end

  def test_new_names_links_in_its_next_step
    command("project new", "acme", "--path", project_path)

    assert_includes @fixture.printed, "next: plastic project links"
  end

  def test_new_without_a_slug_exits_two
    assert_equal 2, command("project new", "--path", project_path)
  end

  def test_new_without_a_path_exits_two
    assert_equal 2, command("project new", "acme")
  end

  def test_new_with_a_path_that_does_not_exist_is_a_failure
    assert_equal 1, command("project new", "acme", "--path", File.join(@dir, "missing"))
  end

  def test_new_with_no_agents_file_never_registers
    bare = File.join(@dir, "bare")
    FileUtils.mkdir_p(bare)

    assert_equal 1, command("project new", "acme", "--path", bare)
    refute_path_exists projects_yml
  end

  def test_new_with_a_path_that_does_not_exist_never_registers
    command("project new", "acme", "--path", File.join(@dir, "missing"))

    refute_path_exists projects_yml
  end

  def test_new_with_an_already_registered_slug_is_a_failure
    @fixture.register("acme", "path" => project_path)

    assert_equal 1, command("project new", "acme", "--path", project_path)
  end

  def test_new_rejects_a_slug_outside_lowercase_letters_digits_and_hyphens
    ["Bad Slug", "Acme", "acme_co", "-acme", "a/b"].each do |bad|
      assert_equal 2, command("project new", bad, "--path", project_path), bad
    end
    refute_path_exists projects_yml
  end

  def test_new_names_the_slug_rule
    command("project new", "Bad Slug", "--path", project_path)

    assert_includes @fixture.warned, "lowercase letters, digits and hyphens"
  end

  def test_new_refuses_the_reserved_global_slug
    assert_equal 2, command("project new", "global", "--path", project_path)
  end

  def test_new_accepts_digits_and_inner_hyphens
    assert_equal 0, command("project new", "acme-2", "--path", project_path)
  end

  def test_new_refuses_a_path_registered_under_another_slug
    @fixture.register("acme", "path" => File.expand_path(project_path))

    assert_equal 1, command("project new", "other", "--path", "#{project_path}/")
    assert_includes @fixture.warned, "already registered as acme"
    assert_equal %w[acme], YAML.safe_load_file(projects_yml)["projects"].keys
  end

  def test_new_ignores_rows_without_a_path
    @fixture.register("odd", "not a mapping")

    assert_equal 0, command("project new", "acme", "--path", project_path)
  end

  def test_new_with_a_failing_provision_exits_one
    assert_equal 1, command("project new", "acme", "--path", project_path, status: 5)
  end

  # --- project links --------------------------------------------------------------

  def test_links_runs_project_links
    command("project links")

    assert_equal [script("project-links")], @calls.map(&:first)
    assert_equal [["--plastic-home", @fixture.plastic_home]], @calls.map(&:last)
  end

  def test_links_passes_through_dry_run
    command("project links", "--dry-run")

    assert_equal [["--plastic-home", @fixture.plastic_home, "--dry-run"]], @calls.map(&:last)
    assert_includes @fixture.printed, "next: none"
  end

  def test_links_names_status_in_its_next_step
    command("project links")

    assert_includes @fixture.printed, "next: plastic status"
  end

  def test_a_failing_links_exits_one
    assert_equal 1, command("project links", status: 6)
  end

  # --- roadmap show ----------------------------------------------------------------

  def test_show_runs_report_screen_state
    @fixture.roadmap("global", "372", "# roadmap\n")
    command("roadmap show", "372")

    assert_equal [script("report-screen")], @calls.map(&:first)
    assert_equal [["roadmap", File.join(@fixture.plastic_home, "roadmaps", "372.md"), "state"]], @calls.map(&:last)
  end

  def test_show_names_log_in_its_next_step
    command("roadmap show", "372")

    assert_includes @fixture.printed, 'next: plastic roadmap log 372 EVENT "TEXT"'
  end

  def test_show_names_a_cycle_and_a_graph_id_no_batch_lists
    @fixture.roadmap("global", "cyclic", "# Roadmap: cyclic\n\n## Graph\n- 1 needs 2\n- 2 needs 1\n- 9 needs 1\n\n" \
      "## Batches\n### Batch 1\n- [ ] 1 a - queued\n- [ ] 2 b - queued\n")
    command("roadmap show", "cyclic")

    assert_match(/^warning\s+cyclic graph: 1 > 2 > 1\nwarning\s+graph names 9, no batch entry$/, @fixture.printed)
    assert_includes @fixture.printed, "next: plastic roadmap check cyclic"
  end

  def test_next_on_a_tie_says_any_candidate_may_be_picked
    @captured = JSON.generate("state" => "tie", "roadmap" => nil, "tie" => false,
      "tie_candidates" => [{"roadmap" => "good"}])
    command("roadmap next")

    assert_includes @fixture.printed, "because: the roadmaps tie; the first is shown, and any of them may be picked"
  end

  def test_show_without_a_slug_exits_two
    assert_equal 2, command("roadmap show")
  end

  def test_a_failing_show_exits_one
    assert_equal 1, command("roadmap show", "372", status: 7)
  end

  # --- roadmap next -----------------------------------------------------------------

  def test_next_runs_roadmap_next_which
    command("roadmap next")

    assert_equal [script("roadmap-next")], @calls.map(&:first)
    assert_equal [["--roadmaps-dir", File.join(@fixture.plastic_home, "roadmaps"), "--which"]], @calls.map(&:last)
  end

  def test_next_names_the_winning_slug_in_its_next_step
    command("roadmap next")

    assert_includes @fixture.printed, "next: plastic roadmap show cli"
  end

  def test_next_falls_back_to_the_placeholder_when_no_roadmap_won
    @captured = JSON.generate("state" => "none", "roadmap" => nil)
    command("roadmap next")

    assert_includes @fixture.printed, "next: plastic roadmap show SLUG"
  end

  def test_next_prints_a_screen_not_the_document
    command("roadmap next")

    refute_includes @fixture.printed, "dispatchable_queue"
  end

  def test_next_screen_carries_the_state_and_the_winner
    command("roadmap next")

    assert_includes @fixture.printed, "state       dispatchable"
    assert_includes @fixture.printed, "roadmap     cli"
    assert_includes @fixture.printed, "wave        Batch 1"
  end

  def test_next_screen_lists_the_queue_and_what_is_in_flight
    command("roadmap next")

    assert_includes @fixture.printed, "376  queued  Batch 1"
    assert_includes @fixture.printed, "363  delivering  Batch 1"
  end

  def test_next_says_none_when_the_queue_is_empty
    @captured = JSON.generate("state" => "waiting", "roadmap" => "cli", "dispatchable_queue" => [])
    command("roadmap next")

    assert_includes @fixture.printed, "next     none"
  end

  # Acceptance N8: roadmap-next --which reports a tie with "tie" false and
  # each candidate as an object; the screen names them all the same.
  def test_next_names_the_tie_candidates_from_the_scripts_own_report
    @captured = JSON.generate("state" => "tie", "roadmap" => nil, "tie" => false,
      "tie_candidates" => [{"roadmap" => "good", "last_event" => "1970-01-01T00:00:00Z"},
        {"roadmap" => "nograph", "last_event" => "1970-01-01T00:00:00Z"}])
    command("roadmap next")

    assert_match(/^tie\s+good, nograph$/, @fixture.printed)
    assert_includes @fixture.printed, "next: plastic roadmap show good"
  end

  def test_next_names_the_tie_candidates_when_two_roadmaps_tie
    @captured = JSON.generate("state" => "tie", "roadmap" => nil, "tie" => true,
      "tie_candidates" => %w[cli rlm])
    command("roadmap next")

    assert_includes @fixture.printed, "cli, rlm"
  end

  def test_next_under_json_prints_the_rows_as_data
    command("roadmap next", "--json")

    assert_includes @fixture.printed, '"roadmap": "cli"'
  end

  def test_a_failing_next_exits_one
    assert_equal 1, command("roadmap next", status: 8)
  end

  def test_a_failing_next_names_the_exit_code
    command("roadmap next", status: 8)

    assert_includes @fixture.warned, "roadmap-next exited 8"
  end

  def test_next_with_an_unreadable_report_exits_one
    @captured = "not a report"

    assert_equal 1, command("roadmap next")
  end

  def test_next_with_an_unreadable_report_says_so
    @captured = "not a report"
    command("roadmap next")

    assert_includes @fixture.warned, "roadmap-next did not print a report"
  end

  # --- roadmap log -------------------------------------------------------------------

  def test_log_runs_roadmap_savepoint_append
    command("roadmap log", "372", "Commit", "shipped the thin slice")

    assert_equal [script("roadmap-savepoint")], @calls.map(&:first)
    assert_equal [["append", "--roadmap", File.join(@fixture.plastic_home, "roadmaps", "372.md"),
      "--event", "Commit", "--detail", "shipped the thin slice"]], @calls.map(&:last)
  end

  def test_log_with_a_failing_script_exits_one
    assert_equal 1, command("roadmap log", "372", "Commit", "shipped the thin slice", status: 7)
  end

  def test_log_names_show_in_its_next_step
    command("roadmap log", "372", "Commit", "shipped the thin slice")

    assert_includes @fixture.printed, "next: plastic roadmap show 372"
  end

  def test_log_without_a_slug_exits_two
    assert_equal 2, command("roadmap log")
  end

  def test_log_without_an_event_exits_two
    assert_equal 2, command("roadmap log", "372")
  end

  def test_log_without_text_exits_two
    assert_equal 2, command("roadmap log", "372", "Commit")
  end

  # --- roadmap check -----------------------------------------------------------------

  def graphed_roadmap(name = "372")
    @fixture.roadmap("global", name, "# roadmap\n\n## Graph\n- 372 needs nothing\n")
  end

  def test_check_runs_roadmap_graph_check
    graphed_roadmap
    command("roadmap check", "372")

    assert_equal [script("roadmap-graph")], @calls.map(&:first)
    assert_equal [["check", File.join(@fixture.plastic_home, "roadmaps", "372.md")]], @calls.map(&:last)
  end

  def test_check_names_show_in_its_next_step
    graphed_roadmap
    command("roadmap check", "372")

    assert_includes @fixture.printed, "next: plastic roadmap show 372"
  end

  def test_check_without_a_slug_exits_two
    assert_equal 2, command("roadmap check")
  end

  def test_a_failing_check_exits_one
    graphed_roadmap

    assert_equal 1, command("roadmap check", "372", status: 4)
  end

  def test_check_on_a_roadmap_that_does_not_exist_exits_one
    assert_equal 1, command("roadmap check", "nosuch")
  end

  def test_check_on_a_roadmap_that_does_not_exist_says_so
    command("roadmap check", "nosuch")

    assert_includes @fixture.warned, "no roadmap nosuch in roadmaps"
  end

  def test_check_on_a_roadmap_with_no_graph_names_migrate
    @fixture.roadmap("global", "372", "# roadmap\n\n## Batches\n")
    command("roadmap check", "372")

    assert_includes @fixture.warned, "plastic roadmap migrate 372 writes one from its batches"
  end

  def test_check_on_a_roadmap_with_no_graph_never_runs_the_script
    @fixture.roadmap("global", "372", "# roadmap\n\n## Batches\n")
    command("roadmap check", "372")

    assert_empty @calls
  end

  # --- roadmap migrate --------------------------------------------------------------

  def test_migrate_runs_roadmap_graph_migrate
    graphed_roadmap
    command("roadmap migrate", "372")

    assert_equal [script("roadmap-graph")], @calls.map(&:first)
    assert_equal [["migrate", File.join(@fixture.plastic_home, "roadmaps", "372.md")]], @calls.map(&:last)
  end

  def test_migrate_passes_dry_run_through
    graphed_roadmap
    command("roadmap migrate", "372", "--dry-run")

    assert_includes @calls.first.last, "--dry-run"
  end

  def test_migrate_names_check_in_its_next_step
    graphed_roadmap
    command("roadmap migrate", "372")

    assert_includes @fixture.printed, "next: plastic roadmap check 372"
  end

  def test_migrate_without_a_slug_exits_two
    assert_equal 2, command("roadmap migrate")
  end

  def test_migrate_on_a_roadmap_that_does_not_exist_exits_one
    assert_equal 1, command("roadmap migrate", "nosuch")
  end

  def test_a_failing_migrate_exits_one
    graphed_roadmap

    assert_equal 1, command("roadmap migrate", "372", status: 5)
  end
end
