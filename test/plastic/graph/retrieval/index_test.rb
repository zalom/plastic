# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/retrieval/index"

# The search rows of several intents are built again in one pass, and the rows of every other intent stay.
class RetrievalIndexTest < Plastic::TestCase
  fixtures :empty

  def store = store_database

  def put_document(intent_id, body)
    store.transaction { |batch| batch.put(:documents, { intent_id:, path: "notes.md", body:, updated_at: STAMP }) }
  end

  def fts_intents = store.rows("SELECT DISTINCT intent_id FROM document_fts ORDER BY intent_id").map { |row| row.fetch("intent_id") }

  def index = Plastic::Graph::Retrieval::Index.new(store, origin)

  def test_the_named_intents_get_their_search_rows_and_the_others_keep_theirs
    put_document("3", "# Three\n\nThe third intent.\n")
    index.rebuild_intents(%w[3])
    %w[1 2].each { |intent_id| put_document(intent_id, "# Notes #{intent_id}\n\nThe zanzibar route.\n") }
    store.transaction { |batch| batch.add("DELETE FROM documents WHERE intent_id = '3'") }
    index.rebuild_intents(%w[1 2])

    assert_equal %w[1 2 3], fts_intents
  end

  def test_no_intent_builds_nothing_and_clears_nothing
    put_document("3", "# Three\n\nThe third intent.\n")
    index.rebuild_intents(%w[3])
    index.rebuild_intents([])

    assert_equal %w[3], fts_intents
  end
end
