# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/context_persistence"

class ContextPersistenceTest < Plastic::TestCase
  DOCUMENT = { "intent_id" => "1", "evidence" => [] }.freeze

  def setup
    super
    open_intent
  end

  def persist = Plastic::Workflows::ContextPersistence.new(call_context(intent_id: "1")).persist(DOCUMENT)

  def test_the_context_is_written_as_a_row
    persist
    row = store_graphs.databases[:knowledge].row("SELECT data FROM retrieval_contexts WHERE intent_id = '1'")

    assert_equal DOCUMENT, JSON.parse(row.fetch("data"))
  end

  def test_the_context_is_printed_into_the_intent_folder
    persist
    printed = JSON.parse(File.read(store_path("store/1--alpha/context.json")))

    assert_equal DOCUMENT, printed.fetch("context")
    assert_equal "1", printed.fetch("intent")
  end

  def test_nothing_is_written_at_the_store_root
    persist

    refute File.exist?(store_path("context/1.json"))
  end

  def test_the_document_comes_back_unchanged
    assert_equal DOCUMENT, persist
  end
end
