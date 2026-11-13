# frozen_string_literal: true

require "tmpdir"
require "sqlite3"
require_relative "../../../../../test_helper"

class KnowledgeSyncPreviewMirrorTest < Plastic::TestCase
  Mirror = Plastic::Graph::Knowledge::Sync::Preview::Mirror

  def setup
    super
    @root = Dir.mktmpdir("plastic-mirror-test")
    @source = File.join(@root, "source")
    @target = File.join(@root, "twin")
  end

  def teardown
    FileUtils.rm_rf(@root)
    super
  end

  def test_a_folder_that_is_not_there_gives_an_empty_twin
    Mirror.new(@source, @target).call

    assert_empty Dir.children(@target)
  end

  def test_a_file_is_hard_linked_into_the_twin
    FileUtils.mkdir_p(File.join(@source, "store"))
    File.write(File.join(@source, "store/note.md"), "note")

    Mirror.new(@source, @target).call

    assert File.identical?(File.join(@source, "store/note.md"), File.join(@target, "store/note.md"))
  end

  def test_a_file_that_cannot_be_linked_is_copied
    FileUtils.mkdir_p([@source, @target])
    File.write(File.join(@source, "note.md"), "from the source")
    File.write(File.join(@target, "note.md"), "already there")

    Mirror.new(@source, @target).call

    assert_equal "from the source", File.read(File.join(@target, "note.md"))
    refute File.identical?(File.join(@source, "note.md"), File.join(@target, "note.md"))
  end

  def test_a_database_is_vacuumed_into_the_twin_and_its_sidecars_are_left_out
    FileUtils.mkdir_p(@source)
    database = SQLite3::Database.new(File.join(@source, "work_graph.db"))
    database.execute("CREATE TABLE notes(body TEXT)")
    database.execute("INSERT INTO notes VALUES ('kept')")
    database.close
    File.write(File.join(@source, "work_graph.db-shm"), "sidecar")

    Mirror.new(@source, @target).call

    assert_equal ["work_graph.db"], Dir.children(@target)
    assert_equal [["kept"]], SQLite3::Database.new(File.join(@target, "work_graph.db"), readonly: true).execute("SELECT body FROM notes")
  end
end
