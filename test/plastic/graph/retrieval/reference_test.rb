# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalReferenceTest < Plastic::TestCase
  def setup
    super
    @intent = open_intent
  end

  def references(store = "global") = Plastic::Graph::Retrieval::Reference.new(store_graphs.databases, store:, origin: Plastic::Graph::Origin.new(@plastic_home))

  def revision = store_graphs.databases[:knowledge].row("SELECT sha256 FROM document_heads").fetch("sha256")

  def uri = references.reference("1", @intent.file).fetch(:uri)

  def test_a_reference_names_the_current_revision
    assert_equal "plastic://global/1/#{@intent.file}?revision=#{revision}", uri
  end

  def test_a_reference_to_no_document_is_refused
    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { references.reference("1", "none.md") }
  end

  def test_a_fetch_returns_the_reference_with_the_body
    assert_equal [uri, true], references.fetch(uri).values_at(:uri, :body).then { |found, body| [found, body.include?("Alpha")] }
  end

  def test_a_fetch_from_another_store_is_refused
    error = assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { references("other").fetch(uri) }

    assert_equal "source global is not other", error.message
  end

  def test_a_passage_fetch_adds_the_position_and_lines
    assert_equal [1, 1], references.fetch_passage(uri, 1).values_at(:position, :line_start)
  end

  def test_a_search_row_becomes_a_qualified_reference
    row = { "intent_id" => "1", "path" => @intent.file, "sha256" => revision }

    assert_equal uri, references.search_reference(row).fetch(:uri)
  end
end
