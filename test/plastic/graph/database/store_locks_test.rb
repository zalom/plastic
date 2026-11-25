# frozen_string_literal: true

require_relative "../../../test_helper"

class StoreLocksTest < Plastic::TestCase
  Database = Plastic::Graph::Database

  def root = File.join(@home, "locks", "store")

  def store = (@store ||= Database.open_store(root, Plastic::Graph::Origin.new(@plastic_home)))

  def second
    @second ||= Database::Connection.open(store.path, attach: store.files).tap { |connection| connection.busy_timeout = 0 }
  end

  def first = Database::ConnectionPool.for(store.path, attach: store.files)

  def setup
    super
    store.rows("SELECT 1")
  end

  def teardown
    @second&.close
    super
  end

  def test_a_write_holds_every_file_so_a_second_writer_is_refused_until_it_commits
    first.execute("BEGIN IMMEDIATE")
    first.execute("DELETE FROM nodes")

    assert_raises(SQLite3::BusyException) { second.execute("BEGIN IMMEDIATE") }

    first.execute("COMMIT")
    second.execute("BEGIN IMMEDIATE")
    second.execute("DELETE FROM nodes")
    second.execute("COMMIT")
  end

  def test_a_rebuild_runs_deferred_and_leaves_work_and_knowledge_writable_from_a_second_connection
    store.rebuilding do |_batch, connection|
      connection.execute("DELETE FROM document_passages")
      second.execute("BEGIN DEFERRED")
      second.execute("DELETE FROM nodes")
      second.execute("DELETE FROM intents")
      second.execute("COMMIT")
    end
  end

  def test_a_rebuild_writes_only_retrieval_tables_and_counts_them
    store.rebuilding { |batch| batch.write(:document_passages, "DELETE FROM document_passages") }

    assert_equal [], store.phrases
  end
end
