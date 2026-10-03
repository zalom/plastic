# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/evidence_writer"

class EvidenceIntegritySnapshotTest < Plastic::TestCase
  def test_computes_each_document_digest_once_when_capturing_the_snapshot
    Plastic::Graph::EvidenceWriter.new(knowledge, origin).write("1", "evidence.md", "immutable evidence")
    calls = count_digests do
      document = snapshot.capture.fetch(:documents).fetch(0)
      document.head_row(origin)
      document.fts_rows(origin)
    end

    assert_equal 1, calls
  end

  private

  def knowledge = store_graphs.databases.fetch(:knowledge)
  def snapshot = Plastic::Graph::EvidenceIntegritySnapshot.new(knowledge, origin)

  def count_digests
    calls = 0
    original = Digest::SHA256.method(:hexdigest)
    Digest::SHA256.define_singleton_method(:hexdigest) do |body|
      calls += 1
      "digest-#{body}"
    end
    yield
    calls
  ensure
    Digest::SHA256.define_singleton_method(:hexdigest, original) if original
  end
end
