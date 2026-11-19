# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/evidence/writer"

class RetrievalEvidenceRemovalTest < Plastic::TestCase
  def test_removal_clears_the_document_and_its_current_rows
    writer.write("1", "plan.md", "first evidence")
    writer.write("1", "plan.md", "second evidence")
    writer.remove("1", "plan.md")
    reindex

    assert_empty current_rows
    assert_empty documents
  end

  private

  def writer = Plastic::Graph::Retrieval::Evidence::Writer.new(store_database, origin, clock: FixedClock::CLOCK)
  def current_rows = store_database.rows("SELECT * FROM document_heads WHERE path = 'plan.md'") + store_database.rows("SELECT * FROM document_fts WHERE path = 'plan.md'")
  def documents = store_database.rows("SELECT body FROM documents WHERE path = 'plan.md'")
end
