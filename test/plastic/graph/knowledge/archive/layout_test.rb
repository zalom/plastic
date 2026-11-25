# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/archive/snapshot"

class KnowledgeArchiveLayoutTest < Plastic::TestCase
  def setup
    super
    @intent = open_intent("Paths", status: "future")
    graphs = store_graphs
    @database = graphs.databases.fetch(:store)
    @snapshot = Plastic::Graph::Knowledge::Archive::Snapshot.new(@database, @intent.intent_id, origin)
    @root = folder.path(@intent.dir)
    @entries = Plastic::Graph::Knowledge::Archive::Tree.read(@root)
    FileUtils.remove_entry(@root)
  end

  def save(entries)
    @database.transaction { |batch| @snapshot.capture(batch, entries) }
  end

  def extra(path, kind, data)
    { path:, kind:, data:, mode: 0o755, mtime: "0/1" }
  end

  def test_restoration_refuses_a_snapshot_with_no_directory_root
    save(@entries.reject { |entry| entry[:path].empty? })

    error = assert_raises(Plastic::Graph::Knowledge::Archive::Tree::Error) { @snapshot.restore(@root) }

    assert_equal "archive snapshot has no directory root", error.message
  end

  def test_restoration_refuses_an_intent_with_no_snapshot
    error = assert_raises(Plastic::Graph::Knowledge::Archive::Tree::Error) { @snapshot.restore(@root) }

    assert_equal "intent #{@intent.intent_id} has no archive snapshot", error.message
  end

  class Racing < Plastic::Graph::FileSystem
    def present?(_path) = true
  end

  def test_a_root_that_appears_during_restoration_is_preserved_and_nothing_is_published
    save(@entries)
    racing = Plastic::Graph::Knowledge::Archive::Snapshot.new(@database, @intent.intent_id, origin, files: Racing.new)
    error = assert_raises(Plastic::Graph::Knowledge::Archive::Tree::Error) { racing.restore(@root) }

    assert_equal ["#{@root} appeared during restoration; preserved", false], [error.message, File.exist?(@root)]
  end

  def test_restoration_refuses_parent_traversal_before_writing
    save([*@entries, extra("../escaped", "file", "outside")])

    assert_raises(Plastic::Graph::Knowledge::Archive::Tree::Error) { @snapshot.restore(@root) }
    refute_path_exists File.join(File.dirname(@root), "escaped")
    refute_path_exists @root
  end

  def test_restoration_never_writes_through_a_snapshot_symlink
    outside = File.join(@plastic_home, "outside")
    FileUtils.mkdir_p(outside)
    save([*@entries, extra("escape", "link", outside), extra("escape/owned", "file", "outside")])

    assert_raises(Plastic::Graph::Knowledge::Archive::Tree::Error) { @snapshot.restore(@root) }
    refute_path_exists File.join(outside, "owned")
    refute_path_exists @root
  end

  def test_restoration_refuses_a_noncanonical_path
    save([*@entries, extra("./alias", "file", "alias")])

    assert_raises(Plastic::Graph::Knowledge::Archive::Tree::Error) { @snapshot.restore(@root) }
    refute_path_exists @root
  end

  def test_restoration_refuses_an_unknown_entry_kind
    save([*@entries, extra("odd", "socket", "")])

    assert_raises(Plastic::Graph::Knowledge::Archive::Tree::Error) { @snapshot.restore(@root) }
    refute_path_exists @root
  end
end
