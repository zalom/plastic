# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/retrieval/evidence/writer"

class RetrievalEvidenceWriterTest < Plastic::TestCase
  PassageFailure = Class.new(StandardError)

  Statements = Struct.new(:sqls) do
    def put(_table, _row) = nil

    def add(sql, **) = sqls << sql
  end

  def test_keeps_revisions_immutable_and_updates_only_current_derived_rows
    write_evidence("first evidence")
    write_evidence("second evidence")

    assert_immutable_rows
    assert_equal ["second evidence"], rows("document_heads h JOIN document_revisions r ON r.sha256 = h.sha256", "r.body")
    assert_equal ["second evidence"], rows("document_fts", "body")
  end

  def test_passage_failure_leaves_no_partial_revision_head_or_fts_rows
    writer = Plastic::Graph::Retrieval::Evidence::Writer.new(knowledge, origin, after_passages: -> { raise PassageFailure })

    assert_raises(PassageFailure) { writer.write("1", "plan.md", "failed evidence") }
    assert_equal [0], %w[document_revisions document_heads document_passages document_fts].map { |table| count(table) }.uniq
  end

  def test_keeps_separate_revision_membership_for_identical_bodies_at_distinct_identities
    writer = Plastic::Graph::Retrieval::Evidence::Writer.new(knowledge, origin)
    writer.write("1", "first.md", "shared evidence")
    writer.write("2", "second.md", "shared evidence")
    writer.remove("1", "first.md")

    assert_equal [["1", "first.md", "shared evidence"], ["2", "second.md", "shared evidence"]],
      knowledge.rows("SELECT intent_id, path, body FROM document_revisions ORDER BY intent_id").map(&:values)
  end

  def test_a_known_heads_set_skips_the_search_row_delete_for_a_new_document_only
    heads = Set[["1", "old.md"]]
    writer = Plastic::Graph::Retrieval::Evidence::Writer.new(nil, origin, heads:)
    batch = Statements.new([])
    writer.apply(batch, "1", "new.md", "New\n")
    writer.apply(batch, "1", "old.md", "Old\n")
    writer.apply(batch, "1", "new.md", "Newer\n")

    assert_equal 2, batch.sqls.count { |sql| sql.start_with?("DELETE FROM document_fts") }
  end

  def test_a_changed_body_read_again_replaces_its_search_rows_with_heads_known
    write_evidence("first evidence")
    writer = Plastic::Graph::Retrieval::Evidence::Writer.new(nil, origin, heads: Set[["1", "plan.md"]])
    knowledge.transaction { |batch| writer.apply(batch, "1", "plan.md", "second evidence") }

    assert_equal ["second evidence"], rows("document_fts", "body")
  end

  def test_a_removed_and_added_document_has_exactly_its_new_search_rows
    writer = Plastic::Graph::Retrieval::Evidence::Writer.new(knowledge, origin)
    writer.write("1", "plan.md", "first evidence")
    writer.remove("1", "plan.md")
    again = Plastic::Graph::Retrieval::Evidence::Writer.new(nil, origin, heads: Set.new)
    knowledge.transaction { |batch| again.apply(batch, "1", "plan.md", "again evidence") }

    assert_equal ["again evidence"], rows("document_fts", "body")
  end

  private

  def write_evidence(body) = Plastic::Graph::Retrieval::Evidence::Writer.new(knowledge, origin).write("1", "plan.md", body)

  def assert_immutable_rows
    assert_equal ["first evidence", "second evidence"], rows("document_revisions", "body").sort
    assert_equal ["first evidence", "second evidence"], rows("document_passages", "body").sort
  end

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def rows(table, column) = knowledge.rows("SELECT #{column} AS value FROM #{table}").map { |row| row.fetch("value") }

  def count(table) = knowledge.row("SELECT count(*) AS n FROM #{table}").fetch("n")
end
