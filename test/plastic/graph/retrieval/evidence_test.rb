# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalEvidenceTest < Plastic::TestCase
  def setup
    super
    @alpha = open_intent
    @beta = open_intent("Beta")
  end

  def evidence = Plastic::Graph::Retrieval::Evidence.new(store_graphs.databases, store: "global", origin: Plastic::Graph::Origin.new(@plastic_home))

  def uri(intent) = evidence.references.reference(intent.intent_id, intent.file).fetch(:uri)

  def test_the_documents_of_one_intent_read_alone
    assert_equal [@beta.file], evidence.documents("2").map(&:path)
  end

  def test_the_documents_of_every_intent_read_together
    assert_equal [@alpha.file, @beta.file], evidence.documents.map(&:path).sort
  end

  def test_a_document_fetches_by_intent_and_path
    assert_equal "1", evidence.fetch("1", @alpha.file).intent_id
  end

  def test_a_missing_document_fetches_nil
    assert_nil evidence.fetch("1", "none.md")
  end

  def test_a_batch_of_references_fetches_in_order
    assert_equal %w[beta alpha], evidence.fetch_batch([uri(@beta), uri(@alpha)]).map { |document| document.fetch(:body)[/Alpha|Beta/].downcase }
  end

  def test_a_passage_fetches_by_reference_and_position
    assert_equal 1, evidence.fetch_passage(uri(@alpha), 1).fetch(:position)
  end

  def test_a_search_of_current_evidence_needs_the_backfill_first
    store_graphs.databases[:knowledge].transaction { |batch| batch.add("DELETE FROM retrieval_backfills") }

    assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) { evidence.search_current("alpha") }
  end

  def test_a_search_backfills_then_finds_the_intent
    assert_equal ["1"], evidence.search("alpha").map { |row| row.fetch("intent_id") }
  end
end
