# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/context_persistence"

class ContextPersistenceTest < Plastic::TestCase
  DOCUMENT = { "intent_id" => "1", "evidence" => [] }.freeze

  def persist = Plastic::Workflows::ContextPersistence.new(call_context(intent_id: "1")).persist(DOCUMENT)

  def test_the_context_is_written_as_a_row
    persist
    row = store_graphs.databases[:knowledge].row("SELECT data FROM retrieval_contexts WHERE intent_id = '1'")

    assert_equal DOCUMENT, JSON.parse(row.fetch("data"))
  end

  def test_the_context_is_written_as_a_file_of_the_store
    persist

    assert_equal DOCUMENT, JSON.parse(File.read(store_path("context/1.json")))
  end

  def test_the_document_comes_back_unchanged
    assert_equal DOCUMENT, persist
  end
end
