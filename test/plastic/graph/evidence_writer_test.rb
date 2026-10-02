# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/evidence_writer"

class EvidenceWriterTest < Plastic::TestCase
  PassageFailure = Class.new(StandardError)

  def test_keeps_revisions_immutable_and_updates_only_current_derived_rows
    write_evidence("first evidence")
    write_evidence("second evidence")

    assert_immutable_rows
    assert_equal ["second evidence"], rows("document_heads h JOIN document_revisions r ON r.sha256 = h.sha256", "r.body")
    assert_equal ["second evidence"], rows("document_fts", "body")
  end

  def test_passage_failure_leaves_no_partial_revision_head_or_fts_rows
    writer = Plastic::Graph::EvidenceWriter.new(knowledge, origin, after_passages: -> { raise PassageFailure })

    assert_raises(PassageFailure) { writer.write("1", "plan.md", "failed evidence") }
    assert_equal [0], %w[document_revisions document_heads document_passages document_fts].map { |table| count(table) }.uniq
  end

  def test_keeps_separate_revision_membership_for_identical_bodies_at_distinct_identities
    writer = Plastic::Graph::EvidenceWriter.new(knowledge, origin)
    writer.write("1", "first.md", "shared evidence")
    writer.write("2", "second.md", "shared evidence")
    writer.remove("1", "first.md")

    assert_equal [["1", "first.md", "shared evidence"], ["2", "second.md", "shared evidence"]],
      knowledge.rows("SELECT intent_id, path, body FROM document_revisions ORDER BY intent_id").map(&:values)
  end

  private

  def write_evidence(body) = Plastic::Graph::EvidenceWriter.new(knowledge, origin).write("1", "plan.md", body)

  def assert_immutable_rows
    assert_equal ["first evidence", "second evidence"], rows("document_revisions", "body").sort
    assert_equal ["first evidence", "second evidence"], rows("document_passages", "body").sort
  end

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def rows(table, column) = knowledge.rows("SELECT #{column} AS value FROM #{table}").map { |row| row.fetch("value") }

  def count(table) = knowledge.row("SELECT count(*) AS n FROM #{table}").fetch("n")
end
