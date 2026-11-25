# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/graph/knowledge/repair/rebuild/brief"

# A worker brief of an old actions/ folder names the step it served, and may hold a result.
class RebuildBriefTest < Minitest::Test
  Brief = Plastic::Graph::Knowledge::Repair::Rebuild::Brief

  def test_the_step_number_comes_from_the_file_name
    assert_equal ["1", "10", "2a", nil, nil], ["ACTION_1.md", "ACTION_10_release_beta.md", "ACTION-2a.md", "01-restoration.md", "reports.md"].map { |name| Brief.new(name, "# x\n").number }
  end

  def test_the_heading_is_the_first_title_line
    assert_equal "Engine: rendering", Brief.new("ACTION_2.md", "\n# Engine: rendering\n\ntext\n").heading
  end

  def test_a_brief_without_a_heading_is_named_for_its_file
    assert_equal "reports", Brief.new("reports.md", "text only\n").heading
  end

  def test_a_result_section_gives_its_text
    assert_equal "Shipped and green.", Brief.new("ACTION_1.md", "# t\n\n## Result\nShipped and green.\n\n## Notes\nx\n").result
  end

  def test_a_brief_with_no_result_section_has_no_result
    assert_nil Brief.new("ACTION_1.md", "# t\n\n## Goal\nx\n").result
  end

  def test_an_evidence_table_is_evidence
    table = "# t\n\n| Requirement | Evidence | Result |\n| --- | --- | --- |\n| a | b | c |\n"

    assert_equal [true, false], [Brief.new("01-x.md", table).evidence?, Brief.new("ACTION_1.md", "# t\n").evidence?]
  end

  def test_an_empty_result_section_has_no_result
    assert_nil Brief.new("ACTION_1.md", "# t\n\n## Result\n\n## Notes\nx\n").result
  end
end
