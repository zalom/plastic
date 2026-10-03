# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/evidence_writer"

class RetrievalReadTest < Plastic::TestCase
  def test_fetches_current_and_historical_qualified_references_without_ambiguous_paths
    reference = historical_reference

    assert_historical_reference(reference)
  end

  def test_rejects_unknown_and_stale_qualified_references
    reference = removed_reference

    assert_removed_reference(reference)
  end

  def test_fetches_a_batch_in_request_order_with_duplicates
    writer.write("1", "a.md", "a")
    writer.write("2", "b.md", "b")
    a = retrieval.reference("1", "a.md")
    b = retrieval.reference("2", "b.md")

    assert_equal %w[b a b], retrieval.fetch_batch([b, a, b]).map { |row| row.fetch(:body) }
  end

  def test_exact_intent_and_document_reads_use_their_qualified_indexes
    open_intent("Indexed")
    writer.write("1", "plan.md", "indexed")

    assert_equal "1", retrieval.intent("1").intent_id
    plans = retrieval.exact_lookup_plans("1", "plan.md").flatten.join(" ")

    assert_includes plans, "SEARCH"
    refute_includes plans, "SCAN"
  end

  def test_fetches_one_bounded_passage_from_a_qualified_revision
    writer.write("1", "long.md", "a" * 1700)
    reference = retrieval.reference("1", "long.md")

    passage = retrieval.fetch_passage(reference, 2)

    assert_equal [2, 300, 1, 1], passage.values_at(:position, :body, :line_start, :line_end).then { |position, body, first, last| [position, body.length, first, last] }
  end

  def test_rejects_a_qualified_hash_reference_from_another_store
    writer.write("1", "plan.md", "current")
    foreign = retrieval.reference("1", "plan.md").merge(store: "other")

    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { retrieval.fetch_reference(foreign) }
  end

  private

  def writer = Plastic::Graph::EvidenceWriter.new(knowledge, origin)
  def knowledge = store_graphs.databases.fetch(:knowledge)

  def historical_reference
    writer.write("1", historical_path, "first body")
    reference = retrieval.reference("1", historical_path)
    writer.write("1", historical_path, "second body")
    reference
  end

  def assert_historical_reference(reference)
    assert_equal expected_reference, reference.fetch(:uri)
    assert_equal "first body", retrieval.fetch_reference(reference.fetch(:uri)).fetch(:body)
    assert_equal "second body", retrieval.fetch_reference(retrieval.reference("1", historical_path)).fetch(:body)
  end

  def historical_path = "dir/a:b @ 100% ž.md"

  def expected_reference = "plastic://global/1/dir%2Fa%3Ab%20%40%20100%25%20%C5%BE.md?revision=920de5214f0d1366297d417e04180cfe6939c853d544ddfeea9e9c030ced9c41"

  def removed_reference
    writer.write("1", "plan.md", "current")
    reference = retrieval.reference("1", "plan.md")
    writer.remove("1", "plan.md")
    reference
  end

  def assert_removed_reference(reference)
    assert_equal "current", retrieval.fetch_reference(reference).fetch(:body)
    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { retrieval.fetch_reference("plastic://global/1/missing.md") }
    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { retrieval.fetch_reference(reference.merge(revision: "missing")) }
  end
end
