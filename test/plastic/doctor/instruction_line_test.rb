# frozen_string_literal: true

require_relative "whole_home"
require_relative "../../../scripts/lib/plastic/doctor"

class DoctorInstructionLineTest < Plastic::TestCase
  include WholeHome

  def path = File.join(@home, "AGENTS.md")

  def problem = Plastic::Doctor::InstructionLine.new(path, /PLASTIC\.md/).problem

  def test_a_file_with_the_line_has_no_problem
    write(path, "Read ~/.plastic/PLASTIC.md first.\n")

    assert_nil problem
  end

  def test_a_file_without_the_line_is_named
    write(path, "# Project\n")

    assert_equal "#{path} has no Plastic line", problem
  end

  def test_a_missing_file_is_named
    assert_equal "#{path} is missing", problem
  end
end
