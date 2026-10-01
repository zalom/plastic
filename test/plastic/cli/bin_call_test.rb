# frozen_string_literal: true

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

  def test_bin_call_help_lists_the_shipped_commands
    out = plastic_bin("help", table: Plastic::CLI::TABLE).out

    assert_includes out, "intent new"
    refute_includes out, "kernel"
  end
end
