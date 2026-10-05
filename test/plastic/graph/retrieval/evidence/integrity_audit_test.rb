# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/retrieval/evidence/writer"

class RetrievalEvidenceIntegrityAuditTest < Plastic::TestCase
  def setup
    super
    Plastic::Graph::Retrieval::Evidence::Writer.new(knowledge, origin).write("1", "plan.md", "Audited evidence\n")
  end

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def report
    snapshot = Plastic::Graph::Retrieval::Evidence::IntegritySnapshot.new(knowledge, origin).capture
    Plastic::Graph::Retrieval::Evidence::IntegrityAudit.report(snapshot)
  end

  def change(sql) = knowledge.transaction { |batch| batch.add(sql) }

  def test_matching_rows_report_no_drift
    assert_equal({ repairable: false, missing: [] }, report)
  end

  def test_a_head_with_the_wrong_hash_drifts
    change("UPDATE document_heads SET sha256 = 'wrong'")

    assert report.fetch(:repairable)
  end

  def test_a_lost_passage_drifts
    change("DELETE FROM document_passages")

    assert report.fetch(:repairable)
  end

  def test_an_extra_search_row_drifts
    change("INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES ('x', '1', 'plan.md', 's', 9, '#{origin}')")

    assert report.fetch(:repairable)
  end

  def test_a_document_whose_body_has_no_revision_is_missing
    change("UPDATE documents SET body = 'edited'")

    assert_equal ["1:plan.md has no immutable revision"], report.fetch(:missing)
  end
end
