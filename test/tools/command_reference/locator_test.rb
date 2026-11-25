# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceLocatorTest < Minitest::Test
  Lines = Struct.new(:rows) do
    def lines(_file) = rows
  end

  def locator(rows) = CommandReference::Locator.new(Lines.new(rows))

  def test_the_word_above_the_line_is_found
    assert_equal 2, locator(["gate :a", "gate :b", "  ->(c) { 1 }"]).above("f.rb", 3, "gate")
  end

  def test_a_blank_line_between_stops_the_search
    assert_nil locator(["gate :a", "", "  ->(c) { 1 }"]).above("f.rb", 3, "gate")
  end

  def test_a_window_with_no_word_and_no_stop_finds_nothing
    assert_nil locator(["x"] * 12).above("f.rb", 12, "gate")
  end
end
