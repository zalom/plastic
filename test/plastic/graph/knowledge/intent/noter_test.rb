# frozen_string_literal: true

require_relative "../../../../test_helper"
require "plastic/graph/knowledge/intent/noter"

class IntentNoterTest < Minitest::Test
  def test_a_one_line_note_has_no_problem
    assert_nil Plastic::Graph::Knowledge::Intent::Noter.problem("a line")
  end

  def test_a_note_with_a_line_break_names_the_problem
    assert_equal "the note is one line; it holds a line break", Plastic::Graph::Knowledge::Intent::Noter.problem("a\nb")
  end
end
