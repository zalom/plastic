# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/graph/knowledge/repair/rebuild/empty_folders"

# An old actions folder with nothing in it goes; one that holds a file stays.
class RebuildEmptyFoldersTest < Plastic::TestCase
  def setup
    super
    @folder = Plastic::Graph::Knowledge::StoreFolder.new(File.join(@home, "folder"))
    @folder.write("store/1--a/intent.md", "# A\n")
    @folder.write("store/2--b/actions/a.md", "# a\n")
    FileUtils.mkdir_p(@folder.path("store/1--a/actions"))
  end

  def test_an_empty_actions_folder_is_removed_and_one_with_a_file_stays
    Plastic::Graph::Knowledge::Repair::Rebuild::EmptyFolders.new(@folder).sweep(%w[store/1--a store/2--b])

    assert_equal [false, true], [File.exist?(@folder.path("store/1--a/actions")), File.exist?(@folder.path("store/2--b/actions/a.md"))]
  end
end
