# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "stringio"
require_relative "../../scripts/lib/cli"
require_relative "../../scripts/lib/cli/commands/help"

class CliHelpTest < Minitest::Test
  def setup
    @out = StringIO.new
    @err = StringIO.new
  end

  def help(*argv)
    Plastic::CLI::Commands::Help.call(argv, out: @out, err: @err, env: {}, home: "/nowhere")
  end

  def test_the_command_list_exits_zero
    assert_equal 0, help
  end

  def test_the_command_list_opens_with_the_usage_line
    help

    assert_equal "usage".ljust(Plastic::CLI::TABLE.keys.map(&:length).max + 2) + "plastic <command> [options]",
      @out.string.lines.first.chomp
  end

  def test_the_command_list_names_every_command_in_the_table
    help

    Plastic::CLI::TABLE.each_key { |name| assert_includes @out.string, name }
  end

  def test_the_command_list_carries_each_summary
    help

    assert_includes @out.string, Plastic::CLI::TABLE.fetch("status")[2]
  end

  def test_the_command_list_is_sorted_by_name
    help
    names = @out.string.lines.drop(1).filter_map { |line| line[/\A(\S+)\s\s/, 1] }
    commands = names - ["topics"]

    assert_equal commands.sort, commands
    assert_equal "topics", names.last, "the topic list sits under the commands, not sorted among them"
  end

  def test_the_command_list_ends_with_a_next_step
    help

    assert_includes @out.string, "next: plastic status"
  end

  def test_one_command_prints_its_usage_line_and_summary
    help("status")

    assert_includes @out.string, Plastic::CLI::Commands::Status::USAGE_LINE
    assert_includes @out.string, Plastic::CLI::TABLE.fetch("status")[2]
  end

  def test_one_command_never_suggests_running_that_command
    help("uninstall")

    assert_includes @out.string, "next: none"
  end

  def test_several_words_are_joined_into_one_grouped_command_name
    help("intent", "new")

    assert_includes @out.string, Plastic::CLI::Commands::IntentNew::USAGE_LINE
  end

  def test_an_unknown_command_exits_with_the_usage_code
    assert_equal 2, help("nope")
  end

  def test_an_unknown_command_names_itself_on_the_error_stream
    help("nope")

    assert_includes @err.string, "nope"
  end

  def test_an_unknown_command_prints_nothing_on_the_result_stream
    help("nope")

    assert_empty @out.string
  end

  def test_json_carries_one_key_per_command
    help("--json")
    result = JSON.parse(@out.string).fetch("result")

    assert_equal Plastic::CLI::TABLE.keys.sort, (result.keys - %w[usage topics]).sort
  end
end
