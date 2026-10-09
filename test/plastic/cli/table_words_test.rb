# frozen_string_literal: true

require_relative "../../test_helper"

class TableWordsTest < Plastic::TestCase
  PRINTS_A_FILE = /\bprint\w*\b[^,;:]*\b(files?|folders?)\b/i

  def test_no_help_line_says_print_for_a_file_or_a_folder
    said = Plastic::CLI::TABLE.filter_map { |words, (_, help)| words if help.match?(PRINTS_A_FILE) }

    assert_empty said
  end

  def test_the_commands_that_write_files_say_write
    assert_equal "Write the rows that changed into files", Plastic::CLI::TABLE.fetch("sync down").last
    assert_equal "Open an intent: write its rows and its folder", Plastic::CLI::TABLE.fetch("intent new").last
  end
end
