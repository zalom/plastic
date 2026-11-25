# frozen_string_literal: true

require_relative "../../../command_reference_helper"

class CommandReferenceGlyphsTest < Minitest::Test
  def test_a_narrow_label_measures_less_than_a_wide_one_of_the_same_length
    assert_operator CommandReference::Figures::Glyphs.width("illi"), :<, CommandReference::Figures::Glyphs.width("mwmw")
  end

  def test_a_longer_label_measures_more_than_a_shorter_one_with_the_same_letters
    assert_operator CommandReference::Figures::Glyphs.width("Ends"), :<, CommandReference::Figures::Glyphs.width("Ends and more")
  end
end
