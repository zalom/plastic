# frozen_string_literal: true

require_relative "../../test_helper"

class FileSystemTest < Plastic::TestCase
  def file_system = Plastic::Graph::FileSystem.new

  def path(name) = File.join(@home, name)

  def test_rename_moves_the_file
    File.write(path("a"), "x")
    file_system.rename(path("a"), path("b"))

    assert_equal [false, "x"], [File.exist?(path("a")), File.read(path("b"))]
  end

  def test_rename_of_a_missing_file_raises
    assert_raises(Errno::ENOENT) { file_system.rename(path("missing"), path("b")) }
  end

  def test_remove_entry_removes_a_whole_folder
    FileUtils.mkdir_p(path("tree/inner"))
    file_system.remove_entry(path("tree"))

    refute_path_exists path("tree")
  end

  def test_copy_tree_copies_every_file_below_the_folder
    FileUtils.mkdir_p(path("tree/inner"))
    File.write(path("tree/inner/f"), "x")
    file_system.copy_tree(path("tree"), path("copy"))

    assert_equal "x", File.read(path("copy/inner/f"))
  end
end
