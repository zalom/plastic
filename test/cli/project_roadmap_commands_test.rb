# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require "tmpdir"
require "yaml"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli"

class CliProjectRoadmapCommandsTest < Minitest::Test
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
    runner = lambda do |path, arguments|
      @calls << [path, arguments]
      status
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

  def test_next_names_show_in_its_next_step
    command("roadmap next")

    assert_includes @fixture.printed, "next: plastic roadmap show SLUG"
  end

  def test_a_failing_next_exits_one
    assert_equal 1, command("roadmap next", status: 8)
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

  def test_check_runs_roadmap_graph_check
    command("roadmap check", "372")

    assert_equal [script("roadmap-graph")], @calls.map(&:first)
    assert_equal [["check", File.join(@fixture.plastic_home, "roadmaps", "372.md")]], @calls.map(&:last)
  end

  def test_check_names_show_in_its_next_step
    command("roadmap check", "372")

    assert_includes @fixture.printed, "next: plastic roadmap show 372"
  end

  def test_check_without_a_slug_exits_two
    assert_equal 2, command("roadmap check")
  end

  def test_a_failing_check_exits_one
    assert_equal 1, command("roadmap check", "372", status: 4)
  end
end
