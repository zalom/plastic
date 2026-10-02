# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/evidence_writer"

class EvidenceRemovalTest < Plastic::TestCase
  def test_removal_clears_current_rows_and_keeps_immutable_revisions
    writer.write("1", "plan.md", "first evidence")
    writer.write("1", "plan.md", "second evidence")
    writer.remove("1", "plan.md")

    assert_empty current_rows
    assert_equal ["first evidence", "second evidence"], immutable_rows
  end

  private

  def writer = Plastic::Graph::EvidenceWriter.new(knowledge, origin)
  def knowledge = store_graphs.databases.fetch(:knowledge)
  def current_rows = %w[document_heads document_fts].flat_map { |table| knowledge.rows("SELECT * FROM #{table}") }
  def immutable_rows = %w[document_revisions document_passages].flat_map { |table| knowledge.rows("SELECT body FROM #{table}") }.map { |row| row.fetch("body") }.uniq.sort
end
