# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/retrieval/evidence/writer"

class RetrievalEvidenceDocumentTest < Plastic::TestCase
  def document(body = "First line\nSecond line\n") = Plastic::Graph::Retrieval::Evidence::Document.new("1", "plan.md", body, now: STAMP)

  def test_the_revision_is_the_hash_of_the_body
    assert_equal Digest::SHA256.hexdigest("First line\nSecond line\n"), document.revision
  end

  def test_the_passages_carry_the_body_and_its_lines
    assert_equal [[1, "First line\nSecond line\n", 1, 2]], document.passages.map { |passage| passage.values_at(:position, :body, :line_start, :line_end) }
  end

  def test_the_document_row_carries_the_body_and_time
    assert_equal({ intent_id: "1", path: "plan.md", body: "x", updated_at: STAMP }, document("x").document_row)
  end

  def test_the_revision_row_carries_the_origin
    assert_equal [Digest::SHA256.hexdigest("x"), "o"], document("x").revision_row("o").values_at(:sha256, :origin_id)
  end

  def test_the_head_row_points_at_the_revision
    assert_equal({ intent_id: "1", path: "plan.md", sha256: Digest::SHA256.hexdigest("x"), updated_at: STAMP }, document("x").head_row)
  end
end
