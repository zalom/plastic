# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/retrieval/context/freshness"

class RetrievalContextFreshnessTest < Plastic::TestCase
  Source = Struct.new(:graph) do
    def retrieval(_reference) = graph
  end

  def setup
    super
    @intent = open_intent
    @reference = retrieval.reference("1", @intent.file).fetch(:uri)
  end

  def states(*references) = Plastic::Graph::Retrieval::Context::Freshness.new(source: Source.new(retrieval)).call({ "evidence" => references })

  def test_each_saved_reference_gets_its_state
    assert_equal({ "evidence" => [{ "uri" => @reference, "state" => "fresh", "archived" => false }] }, states(@reference))
  end

  def test_a_reference_to_no_document_is_missing
    assert_equal [{ "uri" => "plastic://global/1/none.md", "state" => "missing" }], states("plastic://global/1/none.md").fetch("evidence")
  end

  def test_a_revision_whose_document_was_removed_is_stale
    Plastic::Graph::Retrieval::Evidence::Writer.new(store_graphs.databases[:knowledge], origin).remove("1", @intent.file)

    assert_equal [{ "uri" => @reference, "state" => "stale" }], states(@reference).fetch("evidence")
  end
end
