# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceWordsTest < Minitest::Test
  def test_no_words_wrap_to_one_empty_line
    assert_equal [""], CommandReference::Words.wrap(nil, 10)
  end

  def test_words_wrap_at_the_width
    assert_equal ["aa bb", "cc"], CommandReference::Words.wrap("aa bb cc", 5)
  end

  def test_a_pipe_in_a_cell_is_escaped
    assert_equal "a\\|b", CommandReference::Words.cell("a|b")
  end
end
