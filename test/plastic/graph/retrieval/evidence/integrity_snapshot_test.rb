# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/retrieval/evidence/writer"

class RetrievalEvidenceIntegritySnapshotTest < Plastic::TestCase
  # A digester that counts the bodies it digests.
  class CountingDigester
    attr_reader :calls

    def initialize = @calls = 0

    def hexdigest(body)
      @calls += 1
      "digest-#{body}"
    end
  end

  def test_computes_each_document_digest_once_when_capturing_the_snapshot
    Plastic::Graph::Retrieval::Evidence::Writer.new(knowledge, origin).write("1", "evidence.md", "immutable evidence")
    digester = CountingDigester.new
    document = snapshot(digester).capture.fetch(:documents).fetch(0)
    document.head_row(origin)
    document.fts_rows(origin)

    assert_equal 1, digester.calls
  end

  def test_the_head_and_search_rows_carry_the_digest_of_the_body
    Plastic::Graph::Retrieval::Evidence::Writer.new(knowledge, origin).write("1", "evidence.md", "immutable evidence")
    document = snapshot(CountingDigester.new).capture.fetch(:documents).fetch(0)

    assert_equal ["digest-immutable evidence"], digests(document)
  end

  private

  def digests(document) = [document.head_row(origin), *document.fts_rows(origin)].map { |row| row[:sha256] }.uniq

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def snapshot(digester) = Plastic::Graph::Retrieval::Evidence::IntegritySnapshot.new(knowledge, origin, digester:)
end
