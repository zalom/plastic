# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/document_get"
require_relative "../../../scripts/lib/plastic/commands/document_batch"

class DocumentGetTest < Plastic::TestCase
  def test_prints_a_historical_qualified_document_as_structured_json
    Plastic::Graph::EvidenceWriter.new(knowledge, origin).write("1", "plan.md", "first")
    reference = retrieval.reference("1", "plan.md").fetch(:uri)
    Plastic::Graph::EvidenceWriter.new(knowledge, origin).write("1", "plan.md", "second")

    result = plastic("document", "get", reference, "--json", table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    assert_includes result.out, "first"
    assert_includes result.out, "revision"
  end

  def test_batch_routes_each_qualified_reference_to_its_selected_store_in_order
    first = write_document("global", "1", "global.md", "global")
    second = write_document("other", "2", "other.md", "other")

    result = plastic("document", "batch", second, first, second, "--json", table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    assert_equal 2, result.out.scan('"store"').count { |entry| entry }
    assert_operator result.out.index("other"), :<, result.out.index("global")
  end

  private

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def write_document(store, intent_id, path, body)
    graphs = Plastic::Graph.open(home: @plastic_home, store:)
    Plastic::Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), origin).write(intent_id, path, body)
    graphs.retrieval.reference(intent_id, path).fetch(:uri)
  end
end
