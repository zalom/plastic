# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/evidence/writer"

class RetrievalEvidenceWriterTest < Plastic::TestCase
  def test_a_second_write_replaces_the_text_and_its_derived_rows
    write_evidence("first evidence")
    write_evidence("second evidence")

    reindex

    assert_equal ["second evidence"], rows("documents d JOIN document_heads h USING (intent_id, path)", "d.body")
    assert_equal ["second evidence"], rows("document_passages", "body")
    assert_equal ["second evidence"], rows("document_fts", "body")
  end

  def test_removing_one_of_two_identical_bodies_keeps_the_other
    writer = Plastic::Graph::Retrieval::Evidence::Writer.new(store_database, origin, clock: FixedClock::CLOCK)
    writer.write("1", "first.md", "shared evidence")
    writer.write("2", "second.md", "shared evidence")
    writer.remove("1", "first.md")

    assert_equal [["2", "second.md", "shared evidence"]],
      store_database.rows("SELECT intent_id, path, body FROM documents JOIN document_heads USING (intent_id, path) ORDER BY intent_id").map(&:values)
  end

  def test_a_removed_and_added_document_has_exactly_its_new_search_rows
    writer = Plastic::Graph::Retrieval::Evidence::Writer.new(store_database, origin, clock: FixedClock::CLOCK)
    writer.write("1", "plan.md", "first evidence")
    writer.remove("1", "plan.md")
    writer.write("1", "plan.md", "again evidence")
    reindex

    assert_equal ["again evidence"], rows("document_fts", "body")
  end

  def test_a_document_written_again_with_the_same_body_keeps_one_search_row_for_each_passage
    write_evidence("same evidence")
    write_evidence("same evidence")
    reindex

    assert_equal ["same evidence"], rows("document_fts", "body")
  end

  def test_a_document_written_is_found_by_search_and_an_old_body_is_not
    write_evidence("first evidence")
    write_evidence("second evidence")
    reindex
    found = ->(word) { store_database.rows("SELECT body FROM document_fts WHERE document_fts MATCH :word", word:).size }

    assert_equal [0, 1], [found.call("first"), found.call("second")]
  end

  def test_a_document_removed_leaves_no_search_row
    write_evidence("first evidence")
    Plastic::Graph::Retrieval::Evidence::Writer.new(store_database, origin, clock: FixedClock::CLOCK).remove("1", "plan.md")
    reindex

    assert_empty rows("document_fts", "body")
  end

  private

  def write_evidence(body) = Plastic::Graph::Retrieval::Evidence::Writer.new(store_database, origin, clock: FixedClock::CLOCK).write("1", "plan.md", body)

  def rows(table, column) = store_database.rows("SELECT #{column} AS value FROM #{table}").map { |row| row.fetch("value") }

  def count(table) = store_database.row("SELECT count(*) AS n FROM #{table}").fetch("n")
end
