# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/doctor"

class DoctorHomeIgnoreTest < Plastic::TestCase
  def ignore = Plastic::Doctor::HomeIgnore.new(@plastic_home)

  def file = File.join(@plastic_home, ".gitignore")

  def setup
    super
    FileUtils.mkdir_p(@plastic_home)
  end

  def test_a_missing_file_is_made_with_the_database_line
    result = ignore.check

    assert_equal [["*.db"], "ok, *.db added"], [File.readlines(file, chomp: true), result.value]
  end

  def test_a_file_whose_last_line_has_no_newline_keeps_that_line_whole
    File.write(file, "backups/")
    ignore.check

    assert_equal ["backups/", "*.db"], File.readlines(file, chomp: true)
  end

  def test_a_file_that_lists_the_line_is_left_as_it_is
    File.write(file, "*.db\nbackups/\n")
    result = ignore.check

    assert_equal ["*.db\nbackups/\n", "ok, *.db listed"], [File.read(file), result.value]
  end
end
