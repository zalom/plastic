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
    assert_equal "plastic nothing here is not in this build yet; it lands with its stage\n", call.err
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
end
