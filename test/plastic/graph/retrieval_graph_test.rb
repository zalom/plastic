# frozen_string_literal: true

require_relative "../../test_helper"
require "digest"
require_relative "../../../lib/plastic/graph/retrieval/evidence/writer"
require "timeout"

class RetrievalGraphTest < Plastic::TestCase
  def put(key, table, row) = store_graphs.databases[key].transaction { |batch| batch.put(table, row) }

  def saved_passages = derived.rows("SELECT position, body FROM document_passages ORDER BY position")

  def index_text(intent, name, body)
    path = "#{intent.dir}/#{name}"
    write(path, body)
    apply_read(Plastic::Graph::Knowledge::Reader.new(folder, { intent.intent_id => intent }, origin, retrieval:).read(path))
  end

  def test_the_origin_id_is_the_installation_id
    assert_equal [origin, "global"], [retrieval.origin_id, retrieval.store]
  end

  def test_intents_read_in_luhmann_order
    work = store_graphs.work
    %w[One Two].each { |title| work.write_intent(title:) }
    work.write_intent(title: "Child", parent_id: "1")

    assert_equal %w[1 1a 2], retrieval.intents.map(&:intent_id)
    assert_equal ["Child", nil], [retrieval.intent("1a").title, retrieval.intent("9")]
  end

  def test_rows_of_another_origin_stay_out
    put(:knowledge, :intents, { intent_id: "1", origin_id: "beef", slug: "a", title: "A", status: "open" })

    assert_empty retrieval.intents
  end

  def test_a_read_with_an_intent_id_reads_that_intent_alone
    %w[One Two].each { |title| store_graphs.work.write_intent(title:) }
    read = retrieval

    assert_equal [%w[1 2], ["2"], ["intent.md"]], [read.work_log.map(&:intent_id), read.work_log("2").map(&:intent_id),
      read.documents("2").map(&:path)]
  end

  def test_clusters_nodes_and_edges_read_back
    put(:knowledge, :clusters, { name: "Core", intent_id: "1" })
    put(:work, :nodes, { intent_id: "1", id: "n1", kind: "build" })
    put(:work, :edges, { intent_id: "1", from: "n1", to: "n2", kind: "needs" })

    assert_equal [["Core"], ["n1"], ["n2"]], [retrieval.clusters.map(&:name), retrieval.nodes.map(&:id), retrieval.edges("1").map(&:to)]
  end

  def test_a_kept_file_reads_without_its_bytes_and_its_bytes_read_by_name
    row = { name: "store/1--a/x.bin", mode: 0o100644, mtime: 0, sz: 2, data: SQLite3::Blob.new("\x00\xFF".b),
            intent_id: "1", sha256: "h" }
    put(:references, :sqlar, row)

    assert_equal [["store/1--a/x.bin", "h"]], retrieval.kept_files("1").map { |file| [file.name, file.sha256] }
    assert_equal "\x00\xFF".b, retrieval.kept_file_data("store/1--a/x.bin")
  end

  def test_printed_maps_each_path_to_its_hash_across_the_databases
    put(:work, :printed, { path: "store/index.json", sha256: "a", at: "t" })
    put(:knowledge, :printed, { path: "store/1--a/spec.md", sha256: "b", at: "t" })

    assert_equal({ "store/index.json" => "a", "store/1--a/spec.md" => "b" }, retrieval.printed)
  end

  def test_searches_indexed_passages_without_matching_an_intent_title
    intent = open_intent("Unrelated")
    read_research(intent)

    retrieval.repair

    assert_equal [[intent.intent_id, "research.txt", "The retrieval evidence stays searchable.\n", 1]],
      retrieval.search("retrieval evidence").map { |row| row.values_at("intent_id", "path", "body", "position") }
  end

  def test_an_intents_initial_document_is_searchable
    intent = open_intent("Retrieval planning")
    retrieval.repair

    assert_equal [[intent.intent_id, intent.file]], retrieval.search("retrieval planning").map { |row| row.values_at("intent_id", "path") }
  end

  def test_splits_long_unicode_text_into_bounded_passages
    intent = open_intent("Passages")
    index_text(intent, "long.txt", "ž" * 1700)
    retrieval.repair

    assert_equal [[1, 1600], [2, 300]], saved_passages.last(2).map { |row| [row.fetch("position"), row.fetch("body").length] }
  end

  def test_repairs_a_missing_fts_row_from_immutable_evidence
    intent = open_intent("Repair")
    index_text(intent, "repair.txt", "Repairable evidence\n")
    retrieval.repair
    derived.transaction { |batch| batch.add("DELETE FROM document_fts") }

    retrieval.repair

    assert_equal ["repair.txt"], retrieval.search("repairable").map { |row| row.fetch("path") }
  end
end

class RetrievalReadTest < Plastic::TestCase
  def test_fetches_current_and_historical_qualified_references_without_ambiguous_paths
    reference = historical_reference

    assert_historical_reference(reference)
  end

  def test_rejects_unknown_and_stale_qualified_references
    reference = removed_reference

    assert_removed_reference(reference)
  end

  def test_fetches_a_batch_in_request_order_with_duplicates
    writer.write("1", "a.md", "a")
    writer.write("2", "b.md", "b")
    a = retrieval.reference("1", "a.md")
    b = retrieval.reference("2", "b.md")

    assert_equal %w[b a b], retrieval.fetch_batch([b, a, b]).map { |row| row.fetch(:body) }
  end

  def test_reads_an_open_intent_by_its_id
    open_intent("Indexed")

    assert_equal "1", retrieval.intent("1").intent_id
  end

  def test_fetches_one_bounded_passage_from_a_qualified_revision
    writer.write("1", "long.md", "a" * 1700)
    reindex
    passage = retrieval.fetch_passage(retrieval.reference("1", "long.md"), 2)

    assert_equal [2, 1, 1], passage.values_at(:position, :line_start, :line_end)
    assert_equal 300, passage.fetch(:body).length
  end

  def test_rejects_a_qualified_hash_reference_from_another_store
    writer.write("1", "plan.md", "current")
    foreign = retrieval.reference("1", "plan.md").merge(store: "other")

    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { retrieval.fetch_reference(foreign) }
  end

  def test_rejects_malformed_or_invalid_utf8_qualified_addresses
    address = Plastic::Graph::Retrieval::Address.new("global")

    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { address.fields_for("not a reference") }
    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { address.fields_for("plastic://global/1/%FF") }
  end

  def test_refuses_to_build_a_reference_for_a_document_without_a_current_head
    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { retrieval.reference("1", "missing.md") }
  end

  private

  def writer = Plastic::Graph::Retrieval::Evidence::Writer.new(knowledge, origin)
  def knowledge = store_graphs.databases.fetch(:knowledge)

  def historical_reference
    writer.write("1", historical_path, "first body")
    reference = retrieval.reference("1", historical_path)
    writer.write("1", historical_path, "second body")
    reference
  end

  def assert_historical_reference(reference)
    assert_equal expected_reference, reference.fetch(:uri)
    assert_equal "first body", retrieval.fetch_reference(reference.fetch(:uri)).fetch(:body)
    assert_equal "second body", retrieval.fetch_reference(retrieval.reference("1", historical_path)).fetch(:body)
  end

  def historical_path = "dir/a:b @ 100% ž.md"

  def expected_reference = "plastic://global/1/dir%2Fa%3Ab%20%40%20100%25%20%C5%BE.md?revision=920de5214f0d1366297d417e04180cfe6939c853d544ddfeea9e9c030ced9c41"

  def removed_reference
    writer.write("1", "plan.md", "current")
    reference = retrieval.reference("1", "plan.md")
    writer.remove("1", "plan.md")
    reference
  end

  def assert_removed_reference(reference)
    assert_equal "current", retrieval.fetch_reference(reference).fetch(:body)
    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { retrieval.fetch_reference("plastic://global/1/missing.md") }
    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { retrieval.fetch_reference(reference.merge(revision: "missing")) }
  end
end

class RetrievalRepairIntegrityTest < Plastic::TestCase
  def test_repair_rebuilds_wrong_values_and_orphans_without_losing_revisions
    writer.write("1", "repair.md", "repair evidence")
    revision = knowledge.row("SELECT sha256, body FROM document_revisions")
    reindex
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

    error = assert_raises(Plastic::Graph::Retrieval::Evidence::Integrity::EvidenceLost) { repair }

    assert_includes error.message, "1:missing.md has no immutable revision"
    assert_equal "canonical evidence", knowledge.row("SELECT body FROM documents WHERE path = 'missing.md'").fetch("body")
  end

  def test_repair_rebuilds_derived_rows_without_writing_canonical_documents_or_change_log
    writer.write("1", "repair.md", "repair evidence")
    reindex
    before = canonical_state
    derived.transaction { |batch| batch.add("DELETE FROM document_fts") }

    repair

    assert_equal before, canonical_state
  end

  def test_repair_scales_past_sqlite_expression_depth
    1001.times { |index| writer.write(index.to_s, "#{index}.md", "evidence #{index}") }
    reindex
    derived.transaction { |batch| batch.add("DELETE FROM document_fts") }

    repair

    assert_equal 1001, derived.row("SELECT count(*) AS n FROM document_fts").fetch("n")
  end

  def test_repair_keeps_distinct_passages_for_identical_bodies_with_different_extraction
    writer.write("1", "first.txt", "<p>shared</p><p>evidence</p>")
    writer.write("2", "second.html", "<p>shared</p><p>evidence</p>")
    reindex
    derived.transaction { |batch| batch.add("DELETE FROM document_fts") }

    repair

    assert_equal [["1", "first.txt"], ["2", "second.html"]],
      derived.rows("SELECT intent_id, path FROM document_passages ORDER BY intent_id").map(&:values)
  end

  private

  def assert_repaired(revision)
    assert_equal revision, knowledge.row("SELECT sha256, body FROM document_revisions")
    assert_equal ["repair evidence"], retrieval.search("repair").map { |row| row.fetch("body") }
    assert_equal [[1, 1]], derived.rows("SELECT line_start, line_end FROM document_passages").map(&:values)
  end

  def writer = Plastic::Graph::Retrieval::Evidence::Writer.new(knowledge, origin)
  def knowledge = store_graphs.databases.fetch(:knowledge)
  def repair = retrieval.repair

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
    reindex
    derived.transaction { |batch| batch.add("DELETE FROM document_fts") }
    Plastic::Graph::Retrieval::Evidence::Integrity.new(knowledge, derived, origin, before_rebuild: concurrent_writer).repair
  end

  def canonical_state
    { documents: knowledge.rows("SELECT intent_id, path, body, updated_at FROM documents ORDER BY intent_id, path"),
      changes: knowledge.rows("SELECT * FROM changes ORDER BY seq") }
  end

  def corrupt_derived_rows
    knowledge.transaction { |batch| batch.add("UPDATE document_heads SET sha256 = 'wrong'") }
    derived.transaction do |batch|
      batch.add("UPDATE document_passages SET body = 'wrong', line_start = 9, line_end = 9")
      batch.add("UPDATE document_fts SET body = 'wrong', sha256 = 'wrong'")
      batch.add("INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES ('orphan', '9', 'orphan.md', 'orphan', 1, :origin)", origin:)
    end
  end
end

class RetrievalRepairSnapshotTest < Plastic::TestCase
  def test_repair_holds_an_immediate_snapshot_against_a_second_connection
    process, acquired = repair_with_blocked_writer

    assert_equal "acquired", Timeout.timeout(1) { acquired.read }
    Process.wait(process)
    process = nil
  ensure
    Process.wait(process) if process
    close_pipes
  end

  private

  def read_research(intent)
    path = "#{intent.dir}/research.txt"
    write(path, "The retrieval evidence stays searchable.\n")
    apply_read(Plastic::Graph::Knowledge::Reader.new(folder, { intent.intent_id => intent }, origin, retrieval:).read(path))
  end

  def repair_with_blocked_writer
    isolated_writer.write("1", "repair.md", "repair evidence")
    Plastic::Graph::Retrieval::Index.new(isolated, isolated_derived, origin).rebuild
    isolated_derived.transaction { |batch| batch.add("DELETE FROM document_fts") }
    @pipes = IO.pipe + IO.pipe
    blocked_repairer.repair
    [@writer, acquired]
  end

  def blocked_repairer = Plastic::Graph::Retrieval::Evidence::Integrity.new(isolated, isolated_derived, origin, before_rebuild: method(:block_writer))

  def block_writer
    @writer = fork { concurrent_update }
    attempted_writer.close
    acquired_writer.close

    assert_equal "attempted", Timeout.timeout(1) { attempted.read(9) }
    assert_nil IO.select([acquired], nil, nil, 0.1)
  end

  def concurrent_update
    attempted.close
    acquired.close
    attempted_writer.write("attempted")
    with_isolated_connection { |connection| begin_and_update(connection) }
  ensure
    close_pipes
    exit!
  end

  def with_isolated_connection
    connection = Plastic::Graph::Database::Connection.open(isolated.path)
    yield connection
  ensure
    connection&.close
  end

  def update_isolated_document(connection)
    connection.execute("UPDATE documents SET updated_at = 'after' WHERE origin_id = ?", [origin])
    connection.commit
  end

  def begin_and_update(connection)
    connection.execute("BEGIN IMMEDIATE")
    acquired_writer.write("acquired")
    update_isolated_document(connection)
  end

  def close_pipes
    @pipes.to_a.each { |pipe| pipe.close unless pipe.closed? }
  end

  def attempted = @pipes.fetch(0)
  def attempted_writer = @pipes.fetch(1)
  def acquired = @pipes.fetch(2)
  def acquired_writer = @pipes.fetch(3)
  def isolated = (@isolated ||= Plastic::Graph::Database.new(File.join(@home, "isolated", "knowledge_graph.db"), Plastic::Graph::Schema.fetch(:knowledge), origin: Plastic::Graph::Origin.new(@plastic_home)))
  def isolated_derived = (@isolated_derived ||= Plastic::Graph::Database.new(File.join(@home, "isolated", "retrieval_graph.db"), Plastic::Graph::Schema.fetch(:retrieval), origin: Plastic::Graph::Origin.new(@plastic_home)))
  def isolated_writer = Plastic::Graph::Retrieval::Evidence::Writer.new(isolated, origin)
end

class RetrievalRepairTest < Plastic::TestCase
  DERIVED_TABLES = %w[document_heads document_passages document_fts].freeze

  def test_repairs_each_corrupted_derived_table_from_current_documents
    DERIVED_TABLES.each do |table|
      index_current_document
      ((table == "document_heads") ? knowledge : derived).transaction { |batch| batch.add("DELETE FROM #{table}") }

      audit = retrieval.repair

      assert_repaired
      assert_equal({ repairable: false, missing: [] }, audit)
    end
  end

  private

  def index_current_document
    Plastic::Graph::Retrieval::Evidence::Writer.new(knowledge, origin).write("1", "repair.md", "repair evidence")
    reindex
  end

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def assert_repaired
    assert_equal ["repair evidence"], retrieval.search("repair").map { |row| row.fetch("body") }
    assert_equal [1], DERIVED_TABLES.map { |table| ((table == "document_heads") ? knowledge : derived).row("SELECT count(*) AS n FROM #{table}").fetch("n") }.uniq
  end
end

module RetrievalRoadmapFixtures
  def roadmap_fields(title)
    Plastic::Graph::Knowledge::Roadmap::Fields.new(title:, goal: "Deliver #{title}", done: ["Verify #{title}"])
  end

  def seed_roadmap
    work.write_batch("delivery", 2, fields: roadmap_fields("Later"))
    work.write_batch("delivery", 1, fields: roadmap_fields("First"))
    work.add_item("delivery", "a", 1, fields: roadmap_fields("Evidence"), needs: [])
    work.add_item("delivery", "b", 2, fields: roadmap_fields("Review"), needs: ["a"])
    work.add_log("delivery", "First entry")
    work.add_log("delivery", "Second entry")
  end

  def work = store_graphs.work
end

class RetrievalRoadmapRecordsTest < Plastic::TestCase
  include RetrievalRoadmapFixtures

  def test_reads_a_missing_roadmap_without_inventing_records
    assert_nil retrieval.roadmap("absent")
    assert_equal [[], [], [], []], [retrieval.batches("absent"), retrieval.roadmap_items("absent"),
      retrieval.roadmap_edges("absent"), retrieval.roadmap_log("absent")]
  end

  def test_reads_the_roadmap_and_batches_in_position_order
    seed_roadmap

    assert_equal "delivery", retrieval.roadmap("delivery").slug
    assert_equal [1, 2], retrieval.batches("delivery").map(&:position)
  end

  def test_preserves_item_order_dependencies_and_log_order
    seed_roadmap

    assert_equal %w[a b], retrieval.roadmap_items("delivery").map(&:item)
    assert_equal [["a", "b"]], retrieval.roadmap_edges("delivery").map { |edge| [edge.from, edge.to] }
    assert_equal ["First entry", "Second entry"], retrieval.roadmap_log("delivery").map(&:text)
  end

  def test_starting_a_roadmap_item_indexes_its_spec_as_immutable_evidence
    seed_roadmap
    intent_id, problem, kind = work.open_roadmap_item("delivery", "a")
    document = retrieval.fetch_reference(retrieval.reference(intent_id, "spec.md"))

    assert_equal ["1", nil, nil], [intent_id, problem, kind]
    assert_includes document.fetch(:body), "Verify Evidence"
    assert_equal Digest::SHA256.hexdigest(document.fetch(:body)), document.fetch(:revision)
  end
end
