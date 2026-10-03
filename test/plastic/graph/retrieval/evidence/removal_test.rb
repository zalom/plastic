# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/retrieval/evidence/writer"

class RetrievalEvidenceRemovalTest < Plastic::TestCase
  def test_removal_clears_current_rows_and_keeps_immutable_revisions
    writer.write("1", "plan.md", "first evidence")
    writer.write("1", "plan.md", "second evidence")
    writer.remove("1", "plan.md")

    assert_empty current_rows
    assert_equal ["first evidence", "second evidence"], immutable_rows
  end

  private

  def writer = Plastic::Graph::Retrieval::Evidence::Writer.new(knowledge, origin)
  def knowledge = store_graphs.databases.fetch(:knowledge)

  def current_rows = %w[document_heads document_fts].flat_map { |table| knowledge.rows("SELECT * FROM #{table} WHERE path = 'plan.md'") }

  def immutable_rows
    knowledge.rows("SELECT body FROM document_revisions WHERE path = 'plan.md' UNION SELECT p.body FROM document_passages p JOIN document_revisions r ON r.sha256 = p.sha256 WHERE r.path = 'plan.md'")
      .map { |row| row.fetch("body") }.sort
  end
end
