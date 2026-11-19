# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/migration/store_compaction"

class StoreCompactionTest < Plastic::TestCase
  FILES = %w[knowledge_graph.db work_graph.db retrieval_graph.db].freeze

  def vacuum_mode(file) = SQLite3::Database.open(file) { |database| database.get_first_value("PRAGMA auto_vacuum") }

  def test_a_compaction_moves_each_file_of_a_store_made_without_vacuum_to_incremental_vacuum
    home = File.join(Dir.mktmpdir, ".plastic")
    Plastic::Graph.create(home:, store: "alpha")
    root = File.join(home, "stores", "alpha")
    Plastic::Graph::Database::ConnectionPool.release(root)
    files = FILES.map { |name| File.join(root, name) }
    files.each { |file| SQLite3::Database.open(file) { |database| database.execute_batch("PRAGMA auto_vacuum = NONE; VACUUM") } }
    Plastic::Graph::StoreCompaction.call(home, "alpha")
    Plastic::Graph::Database::ConnectionPool.release(root)

    assert_equal [2, 2, 2], files.map { |file| vacuum_mode(file) }
  end

  def test_a_compaction_leaves_the_knowledge_file_with_no_free_pages_and_its_rows_kept
    home = File.join(Dir.mktmpdir, ".plastic")
    Plastic::Graph.create(home:, store: "alpha")
    path = File.join(home, "stores", "alpha", "knowledge_graph.db")
    SQLite3::Database.open(path) { |db| db.execute_batch("CREATE TABLE ballast (data BLOB); INSERT INTO ballast VALUES (zeroblob(200000)); DELETE FROM ballast") }
    Plastic::Graph::StoreCompaction.call(home, "alpha")

    assert_equal [0, Plastic::Graph::MIGRATIONS.versions(:store).size], SQLite3::Database.open(path) { |db| [db.get_first_value("PRAGMA freelist_count"), db.get_first_value("SELECT count(*) FROM schema_migrations")] }
  end
end
