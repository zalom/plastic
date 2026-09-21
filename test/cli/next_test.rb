# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "tmpdir"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli/commands/next"

class CliNextTest < Minitest::Test
  ROADMAP = <<~TEXT
    # Roadmap: cli and rlm

    ## Batches

    ### Batch 1 the command line foundation

    - [ ] 363 the command line — queued
    - [ ] 367 the skill cut — queued

    ### Batch 2 the databases

    - [ ] 368 the retrieval graph — queued
  TEXT

  def setup
    @dir = Dir.mktmpdir("plastic-cli-next")
    @fixture = CliFixture.new(@dir)
      .global_store(active: [])
      .project("plastic", active: [["363", "The command line"], ["367", "The skill cut"]])
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def next_command(*argv)
    Plastic::CLI::Commands::Next.call(argv + ["--project", "plastic"], directory: "/nowhere",
                                                                      **@fixture.streams)
  end

  def test_a_dispatchable_frontier_names_the_first_entry
    @fixture.roadmap("plastic", "cli-and-rlm", ROADMAP)
    next_command

    assert_equal "next work  363  in Batch 1 the command line foundation",
      @fixture.printed.lines.first.chomp
  end

  def test_a_dispatchable_frontier_points_at_the_intent_plan
    @fixture.roadmap("plastic", "cli-and-rlm", ROADMAP)
    next_command

    assert_includes @fixture.printed,
      "next: read #{File.join(@fixture.intent_dir("plastic", "363"), "plan.md")}"
  end

  def test_a_dispatchable_frontier_says_why_that_entry
    @fixture.roadmap("plastic", "cli-and-rlm", ROADMAP)
    next_command

    assert_includes @fixture.printed, "because: 363 is first on the frontier of cli-and-rlm"
  end

  def test_a_plain_run_prints_one_result_line
    @fixture.roadmap("plastic", "cli-and-rlm", ROADMAP)
    next_command
    rows = @fixture.printed.lines.take_while { |line| line.strip != "" }

    assert_equal 1, rows.length
  end

  def why_output
    @fixture.roadmap("plastic", "cli-and-rlm", ROADMAP)
    next_command("--why")
    @fixture.printed
  end

  def test_the_why_flag_names_the_roadmap_and_its_frontier
    printed = why_output

    assert_includes printed, "roadmap       cli-and-rlm"
    assert_includes printed, "frontier      Batch 1 the command line foundation"
  end

  def test_the_why_flag_lists_what_is_dispatchable_in_flight_and_blocked
    printed = why_output

    assert_includes printed, "dispatchable  363, 367"
    assert_includes printed, "in flight     none"
    assert_includes printed, "blocked       none"
  end

  def test_an_entry_already_delivering_is_named_as_in_flight
    body = ROADMAP.sub("- [ ] 363 the command line — queued",
      "- [ ] 363 the command line — delivering")
    @fixture.roadmap("plastic", "cli-and-rlm", body)
    next_command

    assert_includes @fixture.printed, "next work  367  in Batch 1 the command line foundation"
  end

  def test_a_project_with_no_roadmap_directory_says_there_is_none
    next_command

    assert_includes @fixture.printed, "next work  none"
    assert_includes @fixture.printed, "because: plastic has no roadmap"
  end

  def test_a_project_with_no_roadmap_directory_still_exits_zero
    assert_equal 0, next_command
  end

  def test_an_exhausted_roadmap_says_every_entry_is_delivered
    body = ROADMAP.gsub("— queued", "— delivered")
    @fixture.project("plastic", active: [],
      completed: [["363", "The command line"], ["367", "The skill cut"]])
    @fixture.roadmap("plastic", "cli-and-rlm", body)
    next_command

    assert_includes @fixture.printed, "next work  none"
    assert_includes @fixture.printed, "because: every entry on cli-and-rlm is delivered"
  end

  def test_a_roadmap_with_no_grouping_heading_fails_loudly
    @fixture.roadmap("plastic", "broken", "# Roadmap\n\nno grouping heading here\n")

    assert_equal 1, next_command
    assert_includes @fixture.warned, "grouping heading"
  end

  def test_json_carries_the_next_work_and_the_reason
    @fixture.roadmap("plastic", "cli-and-rlm", ROADMAP)
    next_command("--json")
    payload = JSON.parse(@fixture.printed)

    assert_equal "363  in Batch 1 the command line foundation", payload.dig("result", "next work")
    assert_equal "363 is first on the frontier of cli-and-rlm", payload.fetch("because")
  end

  def test_an_id_with_no_intent_directory_falls_back_to_naming_the_id
    body = ROADMAP.sub("363 the command line", "999 a missing intent")
    @fixture.roadmap("plastic", "cli-and-rlm", body)
    next_command

    assert_includes @fixture.printed, "next: plastic status"
    assert_includes @fixture.printed, "because: 999 is first on the frontier of cli-and-rlm"
  end
end
