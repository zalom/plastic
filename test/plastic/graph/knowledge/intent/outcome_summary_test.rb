# frozen_string_literal: true

require_relative "../../../../test_helper"
require "plastic/graph/knowledge/intent/outcome_summary"

class OutcomeSummaryTest < Minitest::Test
  SUMMARY = Plastic::Graph::Knowledge::Intent::OutcomeSummary

  def replace(body, text) = SUMMARY.for(body).replace(text)

  def test_an_outcome_without_a_title_gets_the_starter_and_keeps_its_sections
    assert_equal "# Outcome\n\nNew.\n\n## Notes\n\n- Report: r\n", replace("Old.\n\n## Notes\n\n- Report: r\n", "New.\n")
  end

  def test_the_title_of_the_outcome_stays
    assert_equal "# Outcome of the release\n\nNew.\n", replace("# Outcome of the release\n\nOld.\n", "New.")
  end

  def test_blank_lines_around_the_summary_are_dropped_and_its_indentation_kept
    assert_equal "# Outcome\n\n    code\n\nWords.\n", replace(nil, "\n\n    code\n\nWords.\n\n\n")
  end

  def test_a_summary_with_a_heading_of_any_level_names_it
    assert_match "the summary holds the heading '### Checks'", SUMMARY.problem("Words.\n  ### Checks\n")
  end

  def test_a_hash_without_a_space_is_not_a_heading
    assert_nil SUMMARY.problem("#hashtag and words\n")
  end

  def test_an_empty_summary_names_the_problem
    assert_equal "the summary is empty; write what the work delivered or why it stopped", SUMMARY.problem(" \n")
  end
end
