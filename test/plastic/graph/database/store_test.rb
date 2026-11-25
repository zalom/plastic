# frozen_string_literal: true

require_relative "../../../test_helper"

class DatabaseStoreTest < Plastic::TestCase
  Database = Plastic::Graph::Database
  ROWS = 20
  BLOB = 50_000
  FILL = "INSERT INTO sqlar (name, mode, mtime, sz, data, origin_id) VALUES (:name, 420, 0, 0, zeroblob(#{BLOB}), 'o')".freeze
  PASSAGE = "INSERT INTO document_passages (sha256, intent_id, path, position, body, line_start, line_end, origin_id) " \
            "VALUES ('s', '1', :path, 0, zeroblob(#{BLOB}), 1, 1, 'o')".freeze

  def root = File.join(@home, "vacuum", "store")

  def store = (@store ||= Database.open_store(root, Plastic::Graph::Origin.new(@plastic_home)))

  def file(name) = File.join(root, "#{name}_graph.db")

  def free_pages(name) = SQLite3::Database.open(file(name)) { |database| database.get_first_value("PRAGMA freelist_count") }

  def fill_knowledge = store.transaction { |batch| ROWS.times { |index| batch.write(:sqlar, FILL, name: "f#{index}") } }

  def fill_retrieval = store.rebuilding { |batch| ROWS.times { |index| batch.write(:document_passages, PASSAGE, path: "p#{index}") } }

  def test_a_write_that_deletes_rows_leaves_no_free_page_and_a_smaller_file
    fill_knowledge
    before = File.size(file("knowledge"))
    store.transaction { |batch| batch.write(:sqlar, "DELETE FROM sqlar") }

    assert_equal [0, true], [free_pages("knowledge"), File.size(file("knowledge")) < before]
  end

  def test_a_rebuild_gives_back_the_free_pages_of_retrieval_and_leaves_those_of_knowledge
    fill_knowledge
    fill_retrieval
    SQLite3::Database.open(file("knowledge")) { |database| database.execute("DELETE FROM sqlar") }
    store.rebuilding { |batch| batch.write(:document_passages, "DELETE FROM document_passages") }

    assert_equal [0, true], [free_pages("retrieval"), free_pages("knowledge").positive?]
  end

  def test_a_rebuild_that_writes_nothing_leaves_the_free_pages_of_retrieval
    fill_retrieval
    SQLite3::Database.open(file("retrieval")) { |database| database.execute("DELETE FROM document_passages") }
    store.rebuilding { |_batch| nil }

    assert_predicate free_pages("retrieval"), :positive?
  end
end
