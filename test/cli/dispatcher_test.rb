# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require "tmpdir"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli"

class CliDispatcherTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("plastic-cli-dispatcher")
    @fixture = CliFixture.new(@dir).global_store(active: [])
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def run_cli(*argv)
    Plastic::CLI.call(argv, **@fixture.streams)
  end

  def test_no_arguments_print_the_command_list
    assert_equal 0, run_cli

    assert_includes @fixture.printed, "plastic <command>"
  end

  def test_a_known_command_runs
    assert_equal 0, run_cli("help")

    assert_includes @fixture.printed, "status"
  end

  def test_an_unknown_command_exits_with_the_usage_code
    assert_equal 2, run_cli("stauts")
  end

  def test_an_unknown_command_names_the_closest_command
    run_cli("stauts")

    assert_includes @fixture.warned, "status"
  end

  def test_an_unknown_command_with_no_close_name_still_points_at_help
    run_cli("zzzzzz")

    assert_includes @fixture.warned, "plastic help"
  end

  def test_a_scrambled_command_name_names_that_command_and_no_other
    run_cli("necotinu")

    assert_includes @fixture.warned, "Closest: continue\n"
  end

  def test_a_commands_help_flag_prints_its_usage_line
    assert_equal 0, run_cli("status", "--help")

    assert_includes @fixture.printed, "plastic status [--json]"
  end

  def test_a_commands_short_help_flag_prints_its_usage_line
    assert_equal 0, run_cli("status", "-h")

    assert_includes @fixture.printed, "plastic status [--json]"
  end

  def test_a_commands_help_flag_answers_in_json_when_asked
    assert_equal 0, run_cli("status", "--help", "--json")

    assert_includes @fixture.printed, %("usage": "plastic status [--json]")
  end

  def test_an_unknown_command_prints_nothing_on_the_result_stream
    run_cli("stauts")

    assert_empty @fixture.printed
  end

  def test_the_version_flag_runs_the_version_command
    assert_equal 0, run_cli("--version")

    assert_includes @fixture.printed, "version"
  end

  def test_the_short_version_flag_runs_the_version_command
    assert_equal 0, run_cli("-v")

    assert_includes @fixture.printed, "version"
  end

  def test_the_help_flag_runs_the_help_command
    assert_equal 0, run_cli("--help")

    assert_includes @fixture.printed, "plastic <command>"
  end

  def test_the_short_help_flag_runs_the_help_command
    assert_equal 0, run_cli("-h")

    assert_includes @fixture.printed, "plastic <command>"
  end

  def test_a_two_word_command_beats_its_one_word_prefix
    table = {"help" => ["commands/help", "Help", "one word"],
             "help tutorial" => ["commands/help", "Help", "two words"]}
    cli = Plastic::CLI.new(%w[help tutorial], table: table, **@fixture.streams)

    assert_equal ["help tutorial", []], cli.match(%w[help tutorial])
    assert_equal 0, cli.call
  end

  def test_a_one_word_command_keeps_its_remaining_arguments
    cli = Plastic::CLI.new(%w[help status], **@fixture.streams)

    assert_equal ["help", ["status"]], cli.match(%w[help status])
  end

  def test_an_unmatched_argument_list_answers_nil
    cli = Plastic::CLI.new(%w[nope], **@fixture.streams)

    assert_nil cli.match(%w[nope])
  end
end
