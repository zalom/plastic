# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/context_readback"
require_relative "../../../scripts/lib/plastic/workflows/context_persistence"

class ContextReadbackTest < Plastic::TestCase
  def setup
    super
    @reference = retrieval.reference("1", open_intent.file).fetch(:uri)
    @context = call_context(intent_id: "1")
    Plastic::Workflows::ContextPersistence.new(@context).persist({ "evidence" => [@reference] })
  end

  def readback = Plastic::Workflows::ContextReadback.new(@context).call

  def test_the_saved_context_comes_back_with_its_evidence
    assert_equal [@reference], readback.fetch("evidence")
  end

  def test_current_evidence_reads_fresh
    assert_equal "fresh", sole(readback.dig("freshness", "evidence")).fetch("state")
  end

  def test_evidence_whose_document_was_removed_reads_stale
    Plastic::Graph::Retrieval::Evidence::Writer.new(store_graphs.databases[:knowledge], origin).remove("1", retrieval.intent("1").file)

    assert_equal "stale", sole(readback.dig("freshness", "evidence")).fetch("state")
  end
end
