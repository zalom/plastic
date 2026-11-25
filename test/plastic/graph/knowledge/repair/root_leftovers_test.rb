# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/repair/root_leftovers"

# A repair of every intent removes the root entries of a store folder that the layout marks remove, and no other.
class RepairRootLeftoversTest < Plastic::TestCase
  Leftovers = Plastic::Graph::Knowledge::Repair::RootLeftovers

  KEPT = %w[store/index.json originals/a.md project.yml AGENTS.md INDEX.md backups/b1/work_graph.db stray.txt].freeze

  def setup
    super
    @folder = Plastic::Graph::Knowledge::StoreFolder.new(File.join(@home, "folder"))
    KEPT.each { |rel| @folder.write(rel, "x\n") }
    %w[roadmaps/archived/r.md resources/links.rb config.yml].each { |rel| @folder.write(rel, "x\n") }
  end

  def leftovers = Leftovers.new(@folder)

  def test_the_entries_the_layout_marks_remove_are_the_removals
    assert_equal %w[roadmaps/ config.yml resources/].sort, leftovers.removals.sort
  end

  def test_the_preview_names_each_removal_and_changes_nothing
    before = snapshot(@folder.root)

    assert_equal leftovers.removals.map { |name| "preview: remove #{name}" }, leftovers.preview
    assert_equal before, snapshot(@folder.root)
  end

  def test_the_repair_removes_them_and_keeps_every_other_entry
    names = leftovers.removals
    lines = leftovers.call

    assert_equal names.map { |name| "removed #{name}" }, lines
    assert_equal KEPT.sort, snapshot(@folder.root).keys.sort
  end

  def test_a_store_without_them_has_nothing_to_remove
    leftovers.call

    assert_equal [[], []], [leftovers.call, leftovers.left]
  end
end
