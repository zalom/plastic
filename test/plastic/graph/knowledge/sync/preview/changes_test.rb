# frozen_string_literal: true

require "tmpdir"
require_relative "../../../../../test_helper"

class KnowledgeSyncPreviewChangesTest < Minitest::Test
  Changes = Plastic::Graph::Knowledge::Sync::Preview::Changes

  def setup
    @root = Dir.mktmpdir("plastic-changes-test")
    @source = File.join(@root, "source")
    @twin = File.join(@root, "twin")
    [@source, @twin].each { |dir| FileUtils.mkdir_p(File.join(dir, "store")) }
  end

  def teardown = FileUtils.rm_rf(@root)

  def put(dir, rel, text) = File.write(File.join(dir, rel), text)

  def test_a_file_only_in_the_twin_would_be_added_and_one_only_in_the_source_removed
    put(@twin, "store/new.md", "new")
    put(@source, "store/old.md", "old")

    assert_equal ["would remove store/old.md", "would add store/new.md"].sort, Changes.new(@source, @twin).call.sort
  end

  def test_a_file_with_other_bytes_would_be_changed_and_one_with_the_same_bytes_is_left_out
    put(@source, "store/a.md", "one")
    put(@twin, "store/a.md", "two")
    put(@source, "store/b.md", "same")
    put(@twin, "store/b.md", "same")

    assert_equal ["would change store/a.md"], Changes.new(@source, @twin).call
  end

  def test_a_folder_that_is_not_there_has_no_files_to_compare
    put(@twin, "store/new.md", "new")
    FileUtils.rm_rf(@source)

    assert_equal ["would add store/new.md"], Changes.new(@source, @twin).call
  end

  def test_a_hard_link_is_left_out_and_databases_are_never_listed
    put(@source, "store/a.md", "one")
    File.link(File.join(@source, "store/a.md"), File.join(@twin, "store/a.md"))
    put(@source, "work_graph.db", "x")
    put(@twin, "work_graph.db", "y")
    put(@twin, "work_graph.db-journal", "z")

    assert_empty Changes.new(@source, @twin).call
  end
end
