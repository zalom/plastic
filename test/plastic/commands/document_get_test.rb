# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/document_get"

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

  private

  def knowledge = store_graphs.databases.fetch(:knowledge)
end
