# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalDocumentReaderTest < Plastic::TestCase
  Missing = Plastic::Graph::RetrievalGraph::MissingReference

  def setup
    super
    @intent = open_intent
    @path = @intent.file
  end

  def reader = Plastic::Graph::Retrieval::DocumentReader.new(store_database, origin)

  def fields(**more) = { intent_id: "1", path: @path, **more }

  def rewrite = Plastic::Graph::Retrieval::Evidence::Writer.new(store_graphs.databases.fetch(:store), origin, clock: FixedClock::CLOCK).write("1", @path, "changed")

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

  def test_a_fetch_with_the_current_revision_reads_the_current_body
    rewrite

    assert_equal "changed", reader.fetch(fields(revision: reader.current_revision("1", @path))).fetch("body")
  end

  def test_a_fetch_of_a_replaced_revision_is_refused
    old = reader.current_revision("1", @path)
    rewrite

    assert_equal "no document 1:", assert_raises(Missing) { reader.fetch(fields(revision: old)) }.message
  end

  def test_a_fetch_of_an_unknown_revision_is_refused
    assert_equal "no document 1:#{@path}", assert_raises(Missing) { reader.fetch(fields(revision: "0" * 64)) }.message
  end

  def test_a_passage_reads_its_body_and_lines
    reindex
    passage = reader.passage(fields(revision: reader.current_revision("1", @path)), 1)

    assert_equal [1, true], [passage.fetch(:line_start), passage.fetch(:body).include?("Alpha")]
  end

  def test_a_passage_past_the_last_is_refused
    reindex

    assert_equal "no passage 99", assert_raises(Missing) { reader.passage(fields(revision: reader.current_revision("1", @path)), 99) }.message
  end

  def test_a_passage_read_with_the_retrieval_file_gone_asks_for_the_repair
    reindex
    fields = fields(revision: reader.current_revision("1", @path))
    lose_retrieval_file

    assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) { reader.passage(fields, 1) }
  end
end
