# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/knowledge/sync_selection"

class KnowledgeSyncSelectionTest < Plastic::TestCase
  SyncSelection = Plastic::Graph::Knowledge::SyncSelection

  def reports_of = Plastic::Graph::Knowledge::Reports

  REPORTS = %w[resources/output/reports/review.md resources/output/reports/page.HTML resources/output/reports/plot.png].freeze

  def selection(types: %w[md html], references: false, asked: [], reports: reports_of.none) = SyncSelection.new(types:, references:, asked:, reports:)

  def recorded(*pairs, mandatory: []) = reports_of.new(mandatory:, recorded: -> { pairs })

  def test_reads_a_recorded_markdown_or_html_report_of_its_intent
    selected = selection(reports: recorded(*REPORTS.map { |rel| ["1", rel] }))

    assert_equal [true, true, false], REPORTS.map { |rel| selected.read?(rel, intent_id: "1") }
  end

  def test_a_report_that_is_neither_recorded_nor_mandatory_is_not_read
    refute selection.read?("resources/output/reports/review.md", intent_id: "1")
  end

  def test_a_recorded_report_is_read_only_in_its_own_intent
    selected = selection(reports: recorded(["1", "resources/output/reports/review.md"]))

    assert_equal [true, false], %w[1 2].map { |id| selected.read?("resources/output/reports/review.md", intent_id: id) }
  end

  def test_a_mandatory_report_is_read_in_every_intent
    selected = selection(reports: recorded(mandatory: %w[review.md]))

    assert_equal [true, true, false], [["1", "review.md"], ["2", "review.md"], ["1", "other.md"]].map { |id, name| selected.read?("resources/output/reports/#{name}", intent_id: id) }
  end

  def test_the_report_rule_leaves_output_files_alone
    assert selection.read?("resources/output/files/page.html", intent_id: "1")
  end

  def test_a_store_path_selects_by_the_intent_of_its_folder
    selected = selection(reports: recorded(["7", "resources/output/reports/review.md"]))

    assert_equal [true, false], %w[store/7--seven store/8--eight].map { |dir| selected.selects?("#{dir}/resources/output/reports/review.md") }
  end

  def test_reads_output_files_by_included_type
    selected = selection(types: %w[md html pdf])

    assert_equal [true, true, false], %w[resources/output/files/paper.pdf resources/output/files/page.html resources/output/files/shot.png].map { |rel| selected.read?(rel) }
  end

  def test_never_reads_resources_tmp
    refute selection(references: true).read?("resources/tmp/scratch.md")
  end

  def test_reads_references_only_with_the_setting_on
    assert_equal [false, true], [selection, selection(references: true)].map { |selected| selected.read?("resources/references/paper.pdf") }
  end

  def test_skips_a_type_not_included
    refute selection(types: %w[md]).read?("resources/output/reports/page.html")
  end

  def test_intent_root_notes_are_read_as_before
    selected = selection(types: [])

    assert_equal [true] * 6, %w[spec.md outcome.md graph.json context.json work.log actions/1.json].map { |rel| selected.read?(rel) }
  end

  def test_a_markdown_file_at_the_top_of_the_folder_is_not_a_note
    assert_equal [false, false], %w[notes.md findings.md].map { |rel| selection(types: %w[md]).read?(rel) }
  end

  def test_a_file_in_no_resources_folder_is_not_read
    assert_equal [false, false], %w[reviews/one.md notes/shot.png].map { |rel| selection.read?(rel) }
  end

  def test_a_store_file_outside_the_intent_folders_is_always_selected
    assert selection(types: []).selects?("roadmaps/one.md")
  end

  def test_a_type_is_new_when_it_is_neither_included_nor_asked
    selected = selection(asked: %w[pdf])

    assert_equal %w[docx], selected.new_types(%w[resources/output/files/a.pdf resources/output/reports/b.md resources/output/files/c.DOCX resources/tmp/d.zip resources/references/e.epub])
  end
end
