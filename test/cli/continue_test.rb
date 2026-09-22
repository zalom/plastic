# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "tmpdir"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli/commands/continue"

class CliContinueTest < Minitest::Test
  ROADMAP = <<~TEXT
    # Roadmap: cli and rlm

    ## Batches

    ### Batch 1 the command line foundation

    - [ ] 363 the command line — queued
    - [ ] 367 the skill cut — queued
  TEXT

  def setup
    @dir = Dir.mktmpdir("plastic-cli-continue")
    @fixture = CliFixture.new(@dir)
      .global_store(active: [])
      .project("plastic", active: [["363", "The command line"], ["367", "The skill cut"]])
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def continue(*argv, directory: "/nowhere")
    Plastic::CLI::Commands::Continue.call(argv, directory: directory, **@fixture.streams)
  end

  def test_the_project_block_names_the_project_and_its_root
    continue("--project", "plastic")

    assert_equal "project  plastic", @fixture.printed.lines[0].chomp
    assert_equal "root     #{File.join(@fixture.plastic_home, "projects", "plastic")}",
      @fixture.printed.lines[1].chomp
  end

  def test_the_active_row_lists_every_active_intent_with_its_title
    continue("--project", "plastic")

    assert_includes @fixture.printed, "active   363  The command line"
    assert_includes @fixture.printed, "         367  The skill cut"
  end

  def test_the_roadmap_row_names_the_roadmap_and_its_frontier
    @fixture.roadmap("plastic", "cli-and-rlm", ROADMAP)
    continue("--project", "plastic")

    assert_includes @fixture.printed, "roadmap  cli-and-rlm  frontier Batch 1 the command line foundation"
  end

  def test_a_project_with_no_roadmap_says_none
    continue("--project", "plastic")

    assert_includes @fixture.printed, "roadmap  none"
  end

  def test_a_project_with_no_roadmap_still_exits_zero
    assert_equal 0, continue("--project", "plastic")
  end

  def test_the_next_step_points_at_the_frontier_intent_plan
    @fixture.roadmap("plastic", "cli-and-rlm", ROADMAP)
    continue("--project", "plastic")

    assert_includes @fixture.printed,
      "next: plastic intent show 363 --project plastic"
    assert_includes @fixture.printed, "because: 363 is first on the frontier of cli-and-rlm"
  end

  def test_with_no_roadmap_the_next_step_points_at_the_first_active_intent
    continue("--project", "plastic")

    assert_includes @fixture.printed,
      "next: plastic intent show 363 --project plastic"
    assert_includes @fixture.printed, "because: 363 is the first active intent in plastic"
  end

  def test_with_no_active_work_and_no_roadmap_the_next_step_is_new_work
    continue

    assert_includes @fixture.printed, "because: global has no active work and no roadmap"
  end

  def test_the_working_directory_picks_the_project_without_a_flag
    continue(directory: File.join(@fixture.home, "code", "plastic"))

    assert_includes @fixture.printed, "project  plastic"
  end

  def test_an_unknown_project_exits_with_the_usage_code
    assert_equal 2, continue("--project", "nope")
  end

  def test_an_unknown_project_lists_the_known_ones
    continue("--project", "nope")

    assert_includes @fixture.warned, "global, plastic"
  end

  def test_json_and_text_carry_the_same_project_and_reason
    @fixture.roadmap("plastic", "cli-and-rlm", ROADMAP)
    continue("--project", "plastic", "--json")
    payload = JSON.parse(@fixture.printed)

    assert_equal "plastic", payload.dig("result", "project")
    assert_equal ["363  The command line", "367  The skill cut"], payload.dig("result", "active")
    assert_equal "363 is first on the frontier of cli-and-rlm", payload.fetch("because")
  end

  def test_a_roadmap_with_no_grouping_heading_fails_rather_than_guessing
    @fixture.roadmap("plastic", "cli-and-rlm", "# Roadmap: cli and rlm\n\n- [ ] 363 the command line\n")

    assert_equal Plastic::CLI::Command::FAILED, continue("--project", "plastic")
    assert_match(/grouping heading/, @fixture.warned)
  end

  def test_an_intent_listed_with_no_directory_sends_the_reader_to_status
    FileUtils.rm_rf(@fixture.intent_dir("plastic", "363"))

    continue("--project", "plastic")

    assert_includes @fixture.printed, "next: plastic status"
  end
end
