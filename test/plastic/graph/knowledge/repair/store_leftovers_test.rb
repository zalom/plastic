# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/repair/store_leftovers"

class RepairStoreLeftoversTest < Plastic::TestCase
  Leftovers = Plastic::Graph::Knowledge::Repair::StoreLeftovers

  KEPT = %w[store/1--a/intent.md store/index.json store/.gitkeep store/.obsidian/app.json store/.DS_Store].freeze

  def setup
    super
    @folder = Plastic::Graph::Knowledge::StoreFolder.new(File.join(@home, "folder"))
    KEPT.each { |rel| @folder.write(rel, "{}\n") }
    %w[store/.sessions/20260912/a.json store/.tmp/heartbeat store/.enola/hooks.json].each { |rel| @folder.write(rel, "x\n") }
    @folder.write("store/work_graph.db", "")
  end

  def leftovers = Leftovers.new(@folder)

  def test_the_retired_folders_and_the_empty_database_are_removed
    assert_equal %w[store/.enola/ store/.sessions/ store/.tmp/ store/work_graph.db], leftovers.removals
  end

  def test_the_repair_removes_them_and_keeps_what_the_layout_allows
    lines = leftovers.call

    assert_equal ["removed store/.enola/", "removed store/.sessions/", "removed store/.tmp/", "removed store/work_graph.db"], lines
    assert_equal KEPT.sort, snapshot(@folder.root).keys.sort
  end

  def test_a_database_that_holds_data_is_named_and_left
    @folder.write("store/work_graph.db", "SQLite format 3\u0000")

    assert_equal [false, ["left store/work_graph.db: it holds data, and the layout does not allow it here"]], [leftovers.removals.include?("store/work_graph.db"), leftovers.left]
  end

  def test_an_entry_the_layout_does_not_name_is_named_and_left
    @folder.write("store/stray.txt", "x\n")

    assert_equal ["left store/stray.txt: the layout does not name it"], leftovers.left
  end

  def test_the_preview_names_each_removal_and_writes_nothing
    before = snapshot(@folder.root)

    assert_equal ["preview: remove store/.enola/", "preview: remove store/.sessions/", "preview: remove store/.tmp/", "preview: remove store/work_graph.db"],
      leftovers.preview
    assert_equal before, snapshot(@folder.root)
  end

  def test_a_store_folder_in_the_layout_has_nothing_to_remove
    clean = Plastic::Graph::Knowledge::StoreFolder.new(File.join(@home, "clean"))
    clean.write("store/index.json", "{}\n")

    assert_equal [[], []], [Leftovers.new(clean).removals, Leftovers.new(clean).left]
  end
end
