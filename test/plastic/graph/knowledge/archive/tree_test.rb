# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/archive/writer"

class KnowledgeArchiveTreeTest < Plastic::TestCase
  Tree = Plastic::Graph::Knowledge::Archive::Tree

  def root = File.join(@home, "tree")

  def test_a_tree_lists_the_root_then_each_entry_in_name_order_with_its_bytes
    FileUtils.mkdir_p(File.join(root, "b"))
    File.write(File.join(root, "a.md"), "A")
    File.write(File.join(root, "b", "c.md"), "C")

    assert_equal [["", "directory", nil], ["a.md", "file", "A"], ["b", "directory", nil], ["b/c.md", "file", "C"]],
      Tree.read(root).map { |entry| entry.values_at(:path, :kind, :data) }
  end

  def test_a_link_is_kept_as_its_target_and_never_followed
    FileUtils.mkdir_p(root)
    File.symlink("/elsewhere", File.join(root, "link"))

    assert_equal ["link", "link", "/elsewhere"], Tree.read(root).last.values_at(:path, :kind, :data)
  end

  def test_a_missing_root_reads_empty
    assert_empty Tree.read(root)
  end

  def test_a_root_that_is_a_link_is_refused
    FileUtils.mkdir_p(File.join(@home, "real"))
    File.symlink(File.join(@home, "real"), root)

    assert_equal "archive root must be a directory, not a link", assert_raises(Tree::Error) { Tree.read(root) }.message
  end

  def test_a_special_file_is_refused
    FileUtils.mkdir_p(root)
    File.mkfifo(File.join(root, "pipe"))

    assert_match(/\Acannot archive special file /, assert_raises(Tree::Error) { Tree.read(root) }.message)
  end
end
