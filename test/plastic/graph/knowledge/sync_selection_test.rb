# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/knowledge/sync_selection"

class KnowledgeSyncSelectionTest < Plastic::TestCase
  SyncSelection = Plastic::Graph::Knowledge::SyncSelection

  PATHS = %w[spec.md resources/report.md graph.json context.json actions/1.json resources/shot.PNG resources/demo.mp4
    resources/page.html .hidden references/notes.md references/paper.pdf].freeze

  def read_by(selection) = PATHS.select { |rel| selection.read?(rel) }

  def test_each_path_has_the_kind_its_folder_and_extension_name
    kinds = PATHS.map { |rel| SyncSelection.kind_of(rel) }

    assert_equal %w[notes notes notes notes notes media media documents documents references references], kinds
  end

  def test_with_no_kind_turned_on_only_the_notes_and_the_graph_are_read
    assert_equal %w[spec.md resources/report.md graph.json context.json actions/1.json], read_by(SyncSelection.none)
  end

  def test_every_kind_on_reads_every_path
    assert_equal PATHS, read_by(SyncSelection.all)
  end
end
