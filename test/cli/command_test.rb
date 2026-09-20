# encoding: UTF-8
# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require_relative "../../scripts/lib/cli/command"

class CliCommandTest < Minitest::Test
  class Probe < Plastic::CLI::Command
    USAGE_LINE = "plastic probe [--loud] [--json]"

    attr_reader :seen

    def options(parser)
      parser.on("--loud") { @options[:loud] = true }
      parser.on("--raise KIND") { |kind| @options[:raise] = kind }
    end

    def call
      @seen = @argv.dup
      raise Plastic::CLI::Command::Refusal, "the owner arms the lock" if @options[:raise] == "refusal"
      raise Plastic::CLI::Command::Failure, "install.rb exited 7" if @options[:raise] == "failure"

      @output.row("loud", @options[:loud] ? "yes" : "no")
      @output.next_step("plastic help", because: "the probe is done")
    end
  end

  class Silent < Plastic::CLI::Command
    USAGE_LINE = "plastic silent"
  end

  def setup
    @out = StringIO.new
    @err = StringIO.new
  end

  def test_a_subclass_that_defines_no_work_says_so_by_name
    error = assert_raises(NoMethodError) do
      Silent.new([], out: @out, err: @err, env: {}, home: "/nowhere").run
    end

    assert_equal "#{Silent} must define call", error.message
  end

  def probe(*argv)
    Probe.new(argv, out: @out, err: @err, env: {}, home: "/nowhere")
  end

  def test_the_success_code_is_zero
    assert_equal 0, Plastic::CLI::Command::OK
  end

  def test_the_failure_code_is_one
    assert_equal 1, Plastic::CLI::Command::FAILED
  end

  def test_the_usage_code_is_two
    assert_equal 2, Plastic::CLI::Command::USAGE
  end

  def test_the_refusal_code_is_three
    assert_equal 3, Plastic::CLI::Command::REFUSED
  end

  def test_a_plain_run_exits_zero
    assert_equal 0, probe.run
  end

  def test_a_plain_run_prints_its_result
    probe.run

    assert_equal "loud  no\n\nnext: plastic help\nbecause: the probe is done\n", @out.string
  end

  def test_an_option_the_command_declares_is_parsed
    probe("--loud").run

    assert_includes @out.string, "loud  yes"
  end

  def test_the_json_flag_is_parsed_by_the_base_class
    probe("--json").run

    assert_includes @out.string, %("next": "plastic help")
  end

  def test_positional_arguments_survive_option_parsing
    command = probe("--loud", "363")
    command.run

    assert_equal ["363"], command.seen
  end

  def test_an_unknown_option_exits_with_the_usage_code
    assert_equal 2, probe("--nope").run
  end

  def test_an_unknown_option_prints_the_usage_line
    probe("--nope").run

    assert_includes @err.string, "plastic probe [--loud] [--json]"
  end

  def test_an_unknown_option_prints_nothing_on_the_result_stream
    probe("--nope").run

    assert_empty @out.string
  end

  def test_a_refusal_exits_three
    assert_equal 3, probe("--raise", "refusal").run
  end

  def test_a_refusal_says_the_step_belongs_to_the_owner
    probe("--raise", "refusal").run

    assert_includes @err.string, "the owner arms the lock"
    assert_includes @err.string, "Stop and ask"
  end

  def test_a_failure_exits_one
    assert_equal 1, probe("--raise", "failure").run
  end

  def test_a_failure_names_what_went_wrong
    probe("--raise", "failure").run

    assert_includes @err.string, "install.rb exited 7"
  end

  def test_the_help_flag_prints_the_usage_line_and_exits_zero
    assert_equal 0, probe("--help").run
    assert_includes @out.string, "plastic probe [--loud] [--json]"
  end
end
