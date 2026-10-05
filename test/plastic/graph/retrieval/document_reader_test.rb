# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalDocumentReaderTest < Plastic::TestCase
  Missing = Plastic::Graph::RetrievalGraph::MissingReference

  def setup
    super
    @intent = open_intent
    @path = @intent.file
  end

  def reader = Plastic::Graph::Retrieval::DocumentReader.new(store_graphs.databases[:knowledge], origin)

  def fields(**more) = { intent_id: "1", path: @path, **more }

  def rewrite = Plastic::Graph::Retrieval::Evidence::Writer.new(store_graphs.databases[:knowledge], origin).write("1", @path, "changed")

  def test_the_current_revision_is_the_hash_of_the_current_body
    assert_equal reader.fetch(fields).fetch("sha256"), reader.current_revision("1", @path)
  end

  def test_a_document_with_no_head_has_no_current_revision
    assert_equal "no current document 1:none.md", assert_raises(Missing) { reader.current_revision("1", "none.md") }.message
  end

  def test_a_fetch_with_no_revision_reads_the_current_body
    rewrite

    assert_equal "changed", reader.fetch(fields).fetch("body")
  end

  def test_a_fetch_with_a_revision_reads_that_body
    old = reader.current_revision("1", @path)
    rewrite

    refute_equal "changed", reader.fetch(fields(revision: old)).fetch("body")
  end

  def test_a_fetch_of_an_unknown_revision_is_refused
    assert_equal "no document 1:#{@path}", assert_raises(Missing) { reader.fetch(fields(revision: "0" * 64)) }.message
  end

  def test_a_passage_reads_its_body_and_lines
    passage = reader.passage(fields(revision: reader.current_revision("1", @path)), 1)

    assert_equal [1, true], [passage.fetch(:line_start), passage.fetch(:body).include?("Alpha")]
  end

  def test_a_passage_past_the_last_is_refused
    assert_equal "no passage 99", assert_raises(Missing) { reader.passage(fields(revision: reader.current_revision("1", @path)), 99) }.message
  end
end
