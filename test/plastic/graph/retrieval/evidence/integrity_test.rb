# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/evidence/writer"

class RetrievalEvidenceIntegrityTest < Plastic::TestCase
  Integrity = Plastic::Graph::Retrieval::Evidence::Integrity

  def setup
    super
    @calls = 0
    Plastic::Graph::Retrieval::Evidence::Writer.new(store_database, origin, clock: FixedClock::CLOCK).write("1", "plan.md", "Integrity evidence\n")
    reindex
  end

  def integrity = Integrity.new(store_database, origin, before_rebuild: -> { @calls += 1 })

  def drop(table) = store_database.transaction { |batch| batch.add("DELETE FROM #{table}") }

  def test_whole_evidence_reports_nothing_to_repair
    assert_equal({ repairable: false }, integrity.report)
  end

  def test_a_lost_search_row_reports_repairable
    drop("document_fts")

    assert integrity.report.fetch(:repairable)
  end

  def test_repair_rebuilds_the_lost_rows_after_its_hook
    drop("document_fts")
    integrity.repair

    assert_equal [false, 1], [integrity.report.fetch(:repairable), @calls]
  end

  def test_repair_builds_the_passages_of_an_edited_body_from_the_current_text
    store_database.transaction { |batch| batch.add("UPDATE documents SET body = :body", body: "Edited evidence\n") }
    integrity.repair

    assert_equal [false, ["Edited evidence\n"]], [integrity.report.fetch(:repairable), store_database.rows("SELECT body FROM document_passages").map { |row| row.fetch("body") }]
  end
end
