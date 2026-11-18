# frozen_string_literal: true

require "sqlite3"
require "tmpdir"
require_relative "../../../test_helper"

class GraphBackupSourceCheckTest < Plastic::TestCase
  include SchemaVersions

  SourceCheck = Plastic::Graph::Backup::SourceCheck

  def setup
    super
    @root = Dir.mktmpdir("source_check", @home)
  end

  def database(name, version)
    path = File.join(@root, name)
    record_versions(path, [version.to_s])
    path
  end

  def test_the_version_of_a_full_check_is_the_newest_version_the_knowledge_file_records
    paths = [database("work_graph.db", 20_260_101_000_001), database("knowledge_graph.db", 20_260_101_000_007)]

    assert_equal 20_260_101_000_007, SourceCheck.new(paths).version
  end

  def test_a_partial_check_of_a_store_without_a_knowledge_file_takes_the_lowest_version
    paths = [database("work_graph.db", 20_260_101_000_003), database("references.db", 20_260_101_000_002)]

    assert_equal 20_260_101_000_002, SourceCheck.new(paths).version
  end

  def test_a_partial_check_reads_the_knowledge_file_that_is_not_in_the_list
    knowledge = database("knowledge_graph.db", 20_260_101_000_007)
    paths = [database("work_graph.db", 20_260_101_000_003)]

    assert_equal [20_260_101_000_007, true], [SourceCheck.new(paths).version, File.file?(knowledge)]
  end

  def test_a_beta_2_knowledge_file_with_no_table_reads_version_zero
    path = File.join(@root, "knowledge_graph.db")
    SQLite3::Database.new(path) { |db| db.execute("CREATE TABLE documents (id INTEGER)") }

    assert_equal 0, SourceCheck.new([path]).version
  end
end
