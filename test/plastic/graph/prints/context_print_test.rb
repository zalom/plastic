# frozen_string_literal: true

require_relative "../../../test_helper"

class PrintsContextPrintTest < Plastic::TestCase
  def put(table, data)
    row = { intent_id: "1", data:, updated_at: "2026-10-05T10:00:00+02:00" }
    store_graphs.databases[:knowledge].transaction { |batch| batch.put(table, row) }
  end

  def printed_context
    intent = retrieval.intent("1")
    Plastic::Graph::Prints::ContextPrint.call(intent, Plastic::Graph::Prints::Contents.read(retrieval, "1"))
  end

  def setup
    super
    store_graphs.work.write_intent(title: "One")
  end

  def test_an_intent_with_no_discovery_and_no_context_prints_nothing
    assert_empty printed_context
  end

  def test_a_discovery_and_a_context_print_into_one_file
    put(:retrieval_discoveries, JSON.generate("found" => 1))
    put(:retrieval_contexts, JSON.generate("kept" => 2))

    data = JSON.parse(sole(printed_context).text)

    assert_equal [{ "found" => 1 }, { "kept" => 2 }], data.values_at("discovery", "context")
  end

  def test_a_row_that_is_not_json_prints_as_null
    put(:retrieval_discoveries, "not json")

    assert_nil JSON.parse(sole(printed_context).text)["discovery"]
  end
end
