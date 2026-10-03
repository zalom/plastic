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
  end

  def test_bin_call_names_a_command_with_no_stage_yet
    call = plastic_bin("nothing", "here")

    assert_equal 2, call.code
    assert_equal "plastic nothing here is not in this build yet; it lands with its stage\n", call.err
  end

  def test_bin_call_with_no_words_lists_only_the_shipped_table
    call = plastic_bin(table: Plastic::CLI::TABLE)

    assert_equal 0, call.code
    assert_equal Plastic::CLI::TABLE.size, call.out.lines.size
  end

  def test_bin_call_help_json_prints_the_shipped_commands_as_one_document
    call = plastic_bin("help", "--json", table: Plastic::CLI::TABLE)
    document = JSON.parse(call.out)

    assert_equal 0, call.code
    assert_equal Plastic::CLI::TABLE.keys, document.fetch("result").keys
    assert_nil document.fetch("next")
  end

  def test_bin_call_help_lists_the_shipped_commands
    out = plastic_bin("help", table: Plastic::CLI::TABLE).out

    assert_includes out, "intent new"
    refute_includes out, "kernel"
  end

  def test_bin_call_help_for_a_command_returns_its_exact_json_usage_without_a_home
    home, environment = absent_home_environment(env: {})

    code = Plastic::CLI.bin_call(%w[help sync down --json], environment:, table: Plastic::CLI::TABLE)
    document = JSON.parse(environment.out.string)

    assert_equal 0, code
    assert_equal ["plastic sync down [--overwrite [PATH]] [--merge]"], document.dig("result", "output")
    refute_path_exists home
  end

  def test_bin_call_command_help_returns_its_exact_json_usage_before_scope_resolution
    home, environment = absent_home_environment

    code = Plastic::CLI.bin_call(%w[sync down --help --json --project missing], environment:, table: Plastic::CLI::TABLE)
    document = JSON.parse(environment.out.string)

    assert_equal 0, code
    assert_equal ["plastic sync down [--overwrite [PATH]] [--merge]"], document.dig("result", "output")
    assert_equal ["", false], [environment.err.string, File.exist?(home)]
  end

  def test_bin_call_command_help_keeps_text_help_usable
    call = plastic_bin("sync", "down", "--help", table: Plastic::CLI::TABLE)

    assert_equal 0, call.code
    assert_equal "plastic sync down [--overwrite [PATH]] [--merge]\n", call.out
  end

  def test_bin_call_help_for_a_command_keeps_text_help_usable
    call = plastic_bin("help", "sync", "down", table: Plastic::CLI::TABLE)

    assert_equal 0, call.code
    assert_equal "plastic sync down [--overwrite [PATH]] [--merge]\n", call.out
  end

  private

  def absent_home_environment(env: nil)
    home = File.join(Dir.mktmpdir, "absent-home")
    environment = Plastic::CLI::Command::Environment.new(env: env || { "PLASTIC_HOME" => home }, input: StringIO.new,
      out: StringIO.new, err: StringIO.new, home:, directory: home)
    [home, environment]
  end
end
