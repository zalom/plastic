# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "tmpdir"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli/commands/status"

class CliStatusTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("plastic-cli-status")
    @fixture = CliFixture.new(@dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def status(*argv, directory: "/nowhere")
    Plastic::CLI::Commands::Status.call(argv, directory: directory, **@fixture.streams)
  end

  def test_one_row_per_store_with_the_active_count
    @fixture.global_store(active: [["41", "Security first"]])
      .project("plastic", active: [["363", "The command line"], ["367", "The skill cut"]])
    status

    assert_equal "global   1 active  41", @fixture.printed.lines[0].chomp
    assert_equal "plastic  2 active  363, 367", @fixture.printed.lines[1].chomp
  end

  def test_a_store_with_no_active_work_still_has_a_row
    @fixture.global_store(active: []).project("plastic", active: [])
    status

    assert_includes @fixture.printed, "global   0 active"
    assert_includes @fixture.printed, "plastic  0 active"
  end

  def test_a_store_whose_index_is_missing_is_listed_with_nothing_active
    @fixture.global_store(active: []).project("plastic", active: [["363", "The command line"]])
    @fixture.drop_index("plastic")
    status

    assert_includes @fixture.printed, "plastic  0 active"
  end

  def test_the_working_directory_chooses_the_store_to_continue
    @fixture.global_store(active: [["41", "Security first"], ["52", "The registry"]])
      .project("plastic", active: [["363", "The command line"]])
    status(directory: File.join(@fixture.home, "code", "plastic", "scripts"))

    assert_includes @fixture.printed, "next: plastic continue --project plastic"
    assert_includes @fixture.printed, "because: the working directory is inside plastic"
  end

  def test_the_busiest_store_wins_when_the_directory_says_nothing
    @fixture.global_store(active: [["41", "Security first"]])
      .project("plastic", active: [["363", "The command line"], ["367", "The skill cut"]])
    status

    assert_includes @fixture.printed, "next: plastic continue --project plastic"
    assert_includes @fixture.printed, "because: plastic holds the most active work, 2 intents"
  end

  def test_the_global_store_needs_no_project_flag
    @fixture.global_store(active: [["41", "Security first"]]).project("plastic", active: [])
    status

    assert_includes @fixture.printed, "next: plastic continue\n"
  end

  def test_a_tie_is_broken_the_same_way_on_every_run
    @fixture.project("alpha", active: [["1", "One"]]).project("beta", active: [["2", "Two"]])
    status

    assert_includes @fixture.printed, "next: plastic continue --project alpha"
  end

  def test_no_active_work_anywhere_says_so
    @fixture.global_store(active: [])
    status

    assert_includes @fixture.printed, "because: no store has active work"
  end

  def test_no_active_work_anywhere_still_exits_zero
    @fixture.global_store(active: [])

    assert_equal 0, status
  end

  def test_json_carries_one_key_per_store
    @fixture.global_store(active: [["41", "Security first"]]).project("plastic", active: [])
    status("--json")

    assert_equal({"global" => "1 active  41", "plastic" => "0 active"},
      JSON.parse(@fixture.printed).fetch("result"))
  end

  def test_the_working_directory_defaults_to_the_current_one
    @fixture.global_store(active: [])

    assert_equal 0, Plastic::CLI::Commands::Status.call([], **@fixture.streams)
  end
end
