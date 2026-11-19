# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/knowledge/sync_selection"

class KnowledgeSyncSelectionTest < Plastic::TestCase
  SyncSelection = Plastic::Graph::Knowledge::SyncSelection

  def selection(types: %w[md html], references: false, asked: []) = SyncSelection.new(types:, references:, asked:)

  def test_reads_markdown_and_html_in_output_reports_by_default
    selected = selection

    assert_equal [true, true, false], %w[resources/output/reports/review.md resources/output/reports/page.HTML resources/output/reports/plot.png].map { |rel| selected.read?(rel) }
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
