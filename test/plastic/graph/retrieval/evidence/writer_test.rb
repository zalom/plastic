# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/retrieval/evidence/writer"

class RetrievalEvidenceWriterTest < Plastic::TestCase
  def test_keeps_revisions_immutable_and_updates_only_current_derived_rows
    write_evidence("first evidence")
    write_evidence("second evidence")

    reindex

    assert_immutable_rows
    assert_equal ["second evidence"], rows("document_heads h JOIN document_revisions r ON r.sha256 = h.sha256", "r.body")
    assert_equal ["second evidence"], rows("document_fts", "body")
  end

  def test_keeps_separate_revision_membership_for_identical_bodies_at_distinct_identities
    writer = Plastic::Graph::Retrieval::Evidence::Writer.new(store_database, origin, clock: FixedClock::CLOCK)
    writer.write("1", "first.md", "shared evidence")
    writer.write("2", "second.md", "shared evidence")
    writer.remove("1", "first.md")

    assert_equal [["1", "first.md", "shared evidence"], ["2", "second.md", "shared evidence"]],
      store_database.rows("SELECT intent_id, path, body FROM document_revisions ORDER BY intent_id").map(&:values)
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

  def assert_immutable_rows
    assert_equal ["first evidence", "second evidence"], rows("document_revisions", "body").sort
    assert_equal ["first evidence", "second evidence"], rows("document_passages", "body").sort
  end

  def rows(table, column) = store_database.rows("SELECT #{column} AS value FROM #{table}").map { |row| row.fetch("value") }

  def count(table) = store_database.row("SELECT count(*) AS n FROM #{table}").fetch("n")
end
