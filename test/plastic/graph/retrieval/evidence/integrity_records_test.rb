# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/evidence/writer"

class RetrievalEvidenceIntegrityRecordsTest < Plastic::TestCase
  Evidence = Plastic::Graph::Retrieval::Evidence
  DIGEST = Digest::SHA256.hexdigest("Body\n")

  def document = Evidence::IntegrityDocument.from_row({ "intent_id" => "1", "path" => "plan.md", "body" => "Body\n", "updated_at" => STAMP })

  def test_a_document_digests_its_body
    assert_equal DIGEST, document.digest
  end

  def test_a_document_gives_one_passage_row_per_passage_under_its_digest
    assert_equal [{ sha256: DIGEST, intent_id: "1", path: "plan.md", origin_id: "o", body: "Body\n", position: 1, line_start: 1, line_end: 1 }],
      document.passage_rows("o")
  end

  def test_a_document_head_row_points_at_its_digest
    assert_equal({ intent_id: "1", path: "plan.md", sha256: DIGEST, updated_at: STAMP, origin_id: "o" }, document.head_row("o"))
  end

  def test_a_document_gives_one_search_row_per_passage
    assert_equal [["Body\n", 1]], document.fts_rows("o").map { |row| row.values_at(:body, :position) }
  end
end
