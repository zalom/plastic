# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/evidence_writer"
require "timeout"

class RetrievalRepairIntegrityTest < Plastic::TestCase
  def test_repair_rebuilds_wrong_values_and_orphans_without_losing_revisions
    writer.write("1", "repair.md", "repair evidence")
    revision = knowledge.row("SELECT sha256, body FROM document_revisions")
    corrupt_derived_rows

    repair

    assert_repaired(revision)
  end

  def test_repair_uses_a_current_snapshot_when_a_writer_commits_before_rebuild
    repair_after_concurrent_write

    assert_equal ["new evidence"], retrieval.search("new").map { |row| row.fetch("body") }
    assert_empty retrieval.search("old")
  end

  def test_repair_reports_missing_immutable_evidence_without_changing_canonical_documents
    knowledge.transaction do |batch|
      batch.add("INSERT INTO documents (intent_id, path, body, updated_at, origin_id) VALUES ('1', 'missing.md', 'canonical evidence', 'then', :origin)", origin:)
    end

    error = assert_raises(Plastic::Graph::EvidenceIntegrity::EvidenceLost) { repair }

    assert_includes error.message, "1:missing.md has no immutable revision"
    assert_equal "canonical evidence", knowledge.row("SELECT body FROM documents WHERE path = 'missing.md'").fetch("body")
  end

  def test_repair_rebuilds_derived_rows_without_writing_canonical_documents_or_change_log
    writer.write("1", "repair.md", "repair evidence")
    before = canonical_state
    knowledge.transaction { |batch| batch.add("DELETE FROM document_fts") }

    repair

    assert_equal before, canonical_state
  end

  def test_repair_scales_past_sqlite_expression_depth
    1001.times { |index| writer.write(index.to_s, "#{index}.md", "evidence #{index}") }
    knowledge.transaction { |batch| batch.add("DELETE FROM document_fts") }

    repair

    assert_equal 1001, knowledge.row("SELECT count(*) AS n FROM document_fts").fetch("n")
  end

  def test_repair_keeps_distinct_passages_for_identical_bodies_with_different_extraction
    writer.write("1", "first.txt", "<p>shared</p><p>evidence</p>")
    writer.write("2", "second.html", "<p>shared</p><p>evidence</p>")
    knowledge.transaction { |batch| batch.add("DELETE FROM document_fts") }

    repair

    assert_equal [["1", "first.txt"], ["2", "second.html"]],
      knowledge.rows("SELECT intent_id, path FROM document_passages ORDER BY intent_id").map(&:values)
  end

  def test_repair_holds_an_immediate_snapshot_against_a_second_connection
    isolated_writer.write("1", "repair.md", "repair evidence")
    isolated.transaction { |batch| batch.add("DELETE FROM document_fts") }
    attempted, attempted_writer = IO.pipe
    acquired, acquired_writer = IO.pipe
    writer = nil

    repairer = Plastic::Graph::EvidenceIntegrity.new(isolated, origin, before_rebuild: lambda {
      writer = fork { concurrent_update(attempted, attempted_writer, acquired, acquired_writer) }
      attempted_writer.close
      acquired_writer.close
      wait_for_blocked_writer(attempted, acquired)
    })
    repairer.repair!

    assert_equal "acquired", Timeout.timeout(1) { acquired.read }
    Process.wait(writer)
    writer = nil
  ensure
    Process.wait(writer) if writer
    [attempted, attempted_writer, acquired, acquired_writer].compact.each { |pipe| pipe.close unless pipe.closed? }
  end

  private

  def assert_repaired(revision)
    assert_equal revision, knowledge.row("SELECT sha256, body FROM document_revisions")
    assert_equal ["repair evidence"], retrieval.search("repair").map { |row| row.fetch("body") }
    assert_equal [[1, 1]], knowledge.rows("SELECT line_start, line_end FROM document_passages").map(&:values)
  end

  def writer = Plastic::Graph::EvidenceWriter.new(knowledge, origin)
  def knowledge = store_graphs.databases.fetch(:knowledge)
  def repair = retrieval.repair!
  def isolated = (@isolated ||= Plastic::Graph::Database.new(File.join(@home, "isolated", "knowledge_graph.db"), Plastic::Graph::Schema.fetch(:knowledge), origin: Plastic::Graph::Origin.new(@plastic_home)))
  def isolated_writer = Plastic::Graph::EvidenceWriter.new(isolated, origin)

  def concurrent_writer
    called = false
    -> do
      next if called

      called = true
      writer.write("1", "repair.md", "new evidence")
    end
  end

  def repair_after_concurrent_write
    writer.write("1", "repair.md", "old evidence")
    knowledge.transaction { |batch| batch.add("DELETE FROM document_fts") }
    Plastic::Graph::EvidenceIntegrity.new(knowledge, origin, before_rebuild: concurrent_writer).repair!
  end

  def canonical_state
    { documents: knowledge.rows("SELECT intent_id, path, body, updated_at FROM documents ORDER BY intent_id, path"),
      changes: knowledge.rows("SELECT * FROM changes ORDER BY seq") }
  end

  def concurrent_update(attempted, attempted_writer, acquired, acquired_writer)
    attempted.close
    acquired.close
    connection = Plastic::Graph::Database::Connection.open(isolated.path)
    attempted_writer.write("attempted")
    connection.execute("BEGIN IMMEDIATE")
    acquired_writer.write("acquired")
    connection.execute("UPDATE documents SET updated_at = 'after' WHERE origin_id = ?", [origin])
    connection.commit
  ensure
    connection&.close
    attempted_writer.close unless attempted_writer.closed?
    acquired_writer.close unless acquired_writer.closed?
    exit!
  end

  def wait_for_blocked_writer(attempted, acquired)
    assert_equal "attempted", Timeout.timeout(1) { attempted.read(9) }
    assert_nil IO.select([acquired], nil, nil, 0.1)
  end

  def corrupt_derived_rows
    knowledge.transaction do |batch|
      batch.add("UPDATE document_passages SET body = 'wrong', line_start = 9, line_end = 9")
      batch.add("UPDATE document_heads SET sha256 = 'wrong'")
      batch.add("UPDATE document_fts SET body = 'wrong', sha256 = 'wrong'")
      batch.add("INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES ('orphan', '9', 'orphan.md', 'orphan', 1, :origin)", origin:)
    end
  end
end
