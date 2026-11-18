# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/evidence/writer"

class RetrievalEvidenceIntegrityRebuilderTest < Plastic::TestCase
  def setup
    super
    Plastic::Graph::Retrieval::Evidence::Writer.new(store_database, origin, clock: FixedClock::CLOCK).write("1", "plan.md", "Rebuilt evidence\n")
    @expected = rows("document_heads")
  end

  def rows(table) = store_database.rows("SELECT * FROM #{table} ORDER BY 1, 2, 3")

  def rebuild
    snapshot = Plastic::Graph::Retrieval::Evidence::IntegritySnapshot.new(store_database, origin).capture
    store_database.transaction { |batch| Plastic::Graph::Retrieval::Evidence::IntegrityRebuilder.new(origin).rebuild(batch, snapshot) }
  end

  def test_a_rebuild_writes_back_the_same_heads
    store_database.transaction { |batch| batch.add("DELETE FROM document_heads") }
    rebuild

    assert_equal @expected, rows("document_heads")
  end

  def recorded_sql
    sqls = []
    recording = Object.new
    recording.define_singleton_method(:add) { |sql, **| sqls << sql }
    snapshot = Plastic::Graph::Retrieval::Evidence::IntegritySnapshot.new(store_database, origin).capture
    Plastic::Graph::Retrieval::Evidence::IntegrityRebuilder.new(origin).rebuild(recording, snapshot)
    sqls
  end

  def test_a_rebuild_touches_no_search_or_passage_table
    assert_empty recorded_sql.grep(/document_fts|document_passages/)
  end

  def test_a_rebuild_drops_a_derived_row_with_no_source
    store_database.transaction { |batch| batch.add("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES ('9', 'x.md', 's', 't', :origin)", origin:) }
    rebuild

    assert_equal ["1"], rows("document_heads").map { |row| row.fetch("intent_id") }
  end

  def test_a_rebuild_leaves_the_rows_of_another_origin
    store_database.transaction { |batch| batch.add("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES ('9', 'x.md', 's', 't', 'beef')") }
    rebuild

    assert_equal %w[1 9], rows("document_heads").map { |row| row.fetch("intent_id") }
  end
end
