# frozen_string_literal: true

require "json"
require_relative "../../test_helper"

# bin/plastic's own entry: runs a shipped command, lists the shipped table,
# and names a command with no stage yet.
class BinCallTest < Plastic::TestCase
  def test_bin_call_runs_a_command_the_table_has
    call = plastic_bin("kernel", "who")

    assert_equal 0, call.code
    assert_includes call.out, "session"
    assert_equal "", call.err
  end

  def test_bin_call_names_a_command_with_no_stage_yet
    call = plastic_bin("nothing", "here")

    assert_equal 2, call.code
    assert_equal "plastic nothing here is not a command; run plastic help for the list\n", call.err
    assert_equal "", call.out
  end

  def test_bin_call_with_no_words_lists_only_the_shipped_table
    call = plastic_bin(table: Plastic::CLI::TABLE)

    assert_equal 0, call.code
    assert_equal Plastic::CLI::TABLE.size, call.out.lines.size
    assert_equal "", call.err
  end

  def test_bin_call_help_json_prints_the_shipped_commands_as_one_document
    call = plastic_bin("help", "--json", table: Plastic::CLI::TABLE)
    document = JSON.parse(call.out)

    assert_equal [0, ""], [call.code, call.err]
    assert_equal Plastic::CLI::TABLE.keys, document.fetch("result").keys
    assert_nil document.fetch("next")
  end

  def test_bin_call_help_lists_the_shipped_commands
    call = plastic_bin("help", table: Plastic::CLI::TABLE)

    assert_equal [0, ""], [call.code, call.err]
    assert_includes call.out, "intent new"
    refute_includes call.out, "kernel"
  end

  def test_bin_call_help_accepts_help_flags_and_reports_unknown_commands
    flagged = plastic_bin("help", "--help", table: Plastic::CLI::TABLE)
    unknown = plastic_bin("help", "not-a-command", table: Plastic::CLI::TABLE)

    assert_equal [0, Plastic::CLI::TABLE.size], [flagged.code, flagged.out.lines.size]
    assert_equal [2, "plastic: no command \"not-a-command\"; plastic help lists them\n"], [unknown.code, unknown.err]
  end

  def test_bin_call_help_for_a_command_returns_its_exact_json_usage_without_a_home
    home, environment = absent_home_environment(env: {})

    code = Plastic::CLI.bin_call(%w[help sync down --json], environment:, table: Plastic::CLI::TABLE)
    document = JSON.parse(environment.out.string)

    assert_equal 0, code
    assert_equal "plastic sync down [--overwrite [PATH]] [--merge] [--dry-run]", document.dig("result", "output")&.first
    refute_path_exists home
  end

  def test_bin_call_command_help_returns_its_exact_json_usage_before_scope_resolution
    home, environment = absent_home_environment

    code = Plastic::CLI.bin_call(%w[sync down --help --json --project missing], environment:, table: Plastic::CLI::TABLE)
    document = JSON.parse(environment.out.string)

    assert_equal 0, code
    assert_equal "plastic sync down [--overwrite [PATH]] [--merge] [--dry-run]", document.dig("result", "output")&.first
    assert_equal ["", false], [environment.err.string, File.exist?(home)]
  end

  def test_bin_call_command_help_keeps_text_help_usable
    call = plastic_bin("sync", "down", "--help", table: Plastic::CLI::TABLE)

    assert_equal 0, call.code
    assert_equal "plastic sync down [--overwrite [PATH]] [--merge] [--dry-run]", call.out.lines.first&.chomp
  end

  def test_bin_call_help_for_a_command_keeps_text_help_usable
    call = plastic_bin("help", "sync", "down", table: Plastic::CLI::TABLE)

    assert_equal 0, call.code
    assert_equal "plastic sync down [--overwrite [PATH]] [--merge] [--dry-run]", call.out.lines.first&.chomp
  end

  def test_help_with_a_topic_name_prints_that_chapter
    call = plastic_bin("help", "tools", table: Plastic::CLI::TABLE)

    assert_equal [0, ""], [call.code, call.err]
    assert_equal File.read(File.expand_path("../../../docs/help/tools.md", __dir__)), call.out
  end

  def test_a_command_wins_over_a_topic_of_the_same_name
    topics = Dir.mktmpdir
    File.write(File.join(topics, "status.md"), "A chapter named status\n")
    _home, environment = absent_home_environment
    code = Plastic::CLI.bin_call(%w[help status], environment:, table: Plastic::CLI::TABLE, topics:)

    assert_equal 0, code
    assert_includes environment.out.string, "plastic status"
    refute_includes environment.out.string, "A chapter named status"
  end

  private

  def absent_home_environment(env: nil)
    home = File.join(Dir.mktmpdir, "absent-home")
    environment = Plastic::CLI::Command::Environment.new(env: env || { "PLASTIC_HOME" => home }, input: StringIO.new,
      out: StringIO.new, err: StringIO.new, home:, directory: home)
    [home, environment]
  end
end
