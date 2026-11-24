# frozen_string_literal: true

require_relative "../../../../test_helper"
require "plastic/graph/knowledge/intent/noter"

class IntentNoterTest < Minitest::Test
  def problem(label, text) = Plastic::Graph::Knowledge::Intent::Noter.problem(label, text)

  def test_a_one_line_note_has_no_problem
    assert_nil problem("Report", "a line")
  end

  def test_a_note_with_a_line_break_names_the_problem
    assert_equal "the note is one line; it holds a line break", problem("Report", "a\nb")
  end

  def test_a_verification_line_in_its_form_has_no_problem
    assert_nil problem("Committed", "plastic/1 at abc1234")
  end

  def test_a_verification_line_with_a_placeholder_names_its_form
    assert_equal "the Committed line takes the form 'Committed: <branch> at <commit>'", problem("Committed", "<branch> at <commit>")
  end

  def test_a_verification_line_without_a_form_takes_any_text
    assert_nil problem("Pull request", "none, a direct commit")
  end
end
