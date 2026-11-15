# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/removal_folders"

class RemovalFoldersTest < Plastic::TestCase
  Folders = Plastic::Installations::RemovalFolders
  Record = Struct.new(:folders)

  def test_a_folder_the_removal_will_empty_is_planned_and_a_folder_with_a_foreign_file_is_not
    root = File.join(@home, "agent")
    mine = File.join(root, "mine")
    other = File.join(root, "other")
    [mine, other].each { |folder| FileUtils.mkdir_p(folder) }
    File.write(File.join(mine, "a"), "x")
    File.write(File.join(other, "b"), "x")

    assert_equal [mine], folders([mine, other], root).planned([File.join(mine, "a")])
  end

  def test_a_removed_folder_is_gone_and_a_non_empty_folder_stays
    root = File.join(@home, "agent")
    empty = File.join(root, "empty")
    full = File.join(root, "full")
    [empty, full].each { |folder| FileUtils.mkdir_p(folder) }
    File.write(File.join(full, "b"), "x")

    assert_equal [[empty], [false, true]], [folders([empty, full], root).removed([]), [File.directory?(empty), File.directory?(full)]]
  end

  private

  def folders(listed, root)
    Folders.new(Record.new(listed), Plastic::Installations::Roots.new([root]))
  end
end
