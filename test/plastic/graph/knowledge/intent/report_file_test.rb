# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/intent/report_file"

class ReportFileTest < Minitest::Test
  Intent = Struct.new(:intent_id, :dir)

  def report = Plastic::Graph::Knowledge::Intent::ReportFile.new(Intent.new("1", "store/1--x"), "resources/output/reports/a.html")

  def test_the_line_names_the_setting_in_parentheses
    assert_equal ["- #{report.path}", "- #{report.path} (mandatory)"], [report.line(""), report.line("mandatory")]
  end

  def test_an_outcome_that_lists_the_line_already_gives_nil
    assert_nil report.outcome("# Outcome\n\n## Reports\n\n- #{report.path}\n", "", "## Reports")
  end

  def test_the_line_of_the_other_form_is_replaced
    body = "# Outcome\n\n## Reports\n\n- #{report.path}\n"

    assert_equal "# Outcome\n\n## Reports\n\n- #{report.path} (mandatory)\n", report.outcome(body, "mandatory", "## Reports")
  end

  def test_a_line_with_other_words_stays
    body = "# Outcome\n\n## Reports\n\n- #{report.path}, asked: \"x\"\n"

    assert_equal "#{body}- #{report.path}\n", report.outcome(body, "", "## Reports")
  end
end
