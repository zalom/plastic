# frozen_string_literal: true

require "sqlite3"
require "tmpdir"
require_relative "../../../test_helper"

class GraphBackupSourceCheckTest < Plastic::TestCase
  SourceCheck = Plastic::Graph::Backup::SourceCheck

  def setup
    super
    @root = Dir.mktmpdir("source_check", @home)
  end

  def database(name, version)
    path = File.join(@root, name)
    SQLite3::Database.new(path) { |db| db.execute("PRAGMA user_version = #{version}") }
    path
  end

  def test_the_version_of_a_full_check_is_the_stamp_of_the_knowledge_file
    paths = [database("work_graph.db", 1), database("knowledge_graph.db", 7)]

    assert_equal 7, SourceCheck.new(paths).version
  end

  def test_a_partial_check_of_a_store_without_a_knowledge_file_takes_the_lowest_stamp
    paths = [database("work_graph.db", 3), database("references.db", 2)]

    assert_equal 2, SourceCheck.new(paths).version
  end

  def test_a_partial_check_reads_the_knowledge_file_that_is_not_in_the_list
    knowledge = database("knowledge_graph.db", 7)
    paths = [database("work_graph.db", 3)]

    assert_equal [7, true], [SourceCheck.new(paths).version, File.file?(knowledge)]
  end
end
