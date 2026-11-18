# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/installations/home_ignore"

class InstallationsHomeIgnoreTest < Plastic::TestCase
  def ignore = Plastic::Installations::HomeIgnore.new(@plastic_home)

  def file = File.join(@plastic_home, ".gitignore")

  def setup
    super
    FileUtils.mkdir_p(@plastic_home)
  end

  def test_a_missing_file_is_made_with_the_database_line
    result = ignore.apply

    assert_equal [["*.db", "*.db-*"], "*.db *.db-* added"], [File.readlines(file, chomp: true), result]
  end

  def test_a_file_whose_last_line_has_no_newline_keeps_that_line_whole
    File.write(file, "backups/")
    ignore.apply

    assert_equal ["backups/", "*.db", "*.db-*"], File.readlines(file, chomp: true)
  end

  def test_a_file_that_lists_the_line_is_left_as_it_is
    File.write(file, "*.db\n*.db-*\nbackups/\n")
    result = ignore.apply

    assert_equal ["*.db\n*.db-*\nbackups/\n", "*.db *.db-* listed"], [File.read(file), result]
  end

  def test_a_file_that_lists_only_the_database_line_gets_the_side_file_line
    File.write(file, "*.db\n")
    ignore.apply

    assert_equal ["*.db", "*.db-*"], File.readlines(file, chomp: true)
  end

  def test_home_ignore_lists_the_journal_and_exists_before_the_first_prompt_is_written
    ignore.apply

    assert_includes File.readlines(file, chomp: true), "*.db-*"
    assert File.fnmatch?("*.db-*", "plastic.db-journal")
  end
end
