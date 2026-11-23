# frozen_string_literal: true

require_relative "../../test_helper"
require "digest"
require_relative "../../../lib/plastic/graph/evidence/writer"
require "timeout"

class RetrievalGraphTest < Plastic::TestCase
  def put(table, row) = store_database.transaction { |batch| batch.put(table, row) }

  def saved_passages = store_database.rows("SELECT position, body FROM document_passages ORDER BY position")

  def index_text(intent, name, body)
    path = "#{intent.dir}/#{name}"
    write(path, body)
    apply_read(Plastic::Graph::Knowledge::Reader.new(folder, { intent.intent_id => intent }, origin, retrieval:).read(path, FixedClock::STAMP))
  end

  def test_the_origin_id_is_the_installation_id
    assert_equal [origin, "global"], [retrieval.origin_id, retrieval.store]
  end

  def test_a_reference_into_an_archived_intent_is_archived
    intent = open_intent
    put(:archives, { intent_id: "1", at: STAMP })

    assert retrieval.archived_reference?(retrieval.reference("1", intent.file).fetch(:uri))
  end

  def test_a_reference_into_a_live_intent_is_not_archived
    intent = open_intent

    refute retrieval.archived_reference?(retrieval.reference("1", intent.file).fetch(:uri))
  end

  def test_a_reference_to_no_document_is_refused
    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { retrieval.archived_reference?("plastic://global/1/none.md") }
  end

  def test_the_record_reads_are_not_mixins_of_the_graph
    names = Plastic::Graph::RetrievalGraph.ancestors.map { |ancestor| ancestor.name.to_s.split("::").last }

    assert_empty names & %w[RoadmapReads StoreReads ArchiveReads StructureReads]
  end

  def test_the_record_reads_are_objects_the_graph_hands_out
    readers = [retrieval.stored, retrieval.archives, retrieval.structure]

    assert_equal %w[StoreRead ArchiveReader StructureReader], readers.map { |reader| reader.class.name.split("::").last }
  end

  def test_intents_read_in_luhmann_order
    work = store_graphs.work
    %w[One Two].each { |title| work.write_intent(title:) }
    work.write_intent(title: "Child", parent_id: "1")

    assert_equal %w[1 1a 2], retrieval.intents.map(&:intent_id)
    assert_equal ["Child", nil], [retrieval.intent("1a").title, retrieval.intent("9")]
  end

  def test_rows_of_another_origin_stay_out
    put(:intents, { intent_id: "1", origin_id: "beef", slug: "a", title: "A", status: "open" })

    assert_empty retrieval.intents
  end

  def test_a_read_with_an_intent_id_reads_that_intent_alone
    %w[One Two].each { |title| store_graphs.work.write_intent(title:) }
    read = retrieval

    assert_equal [%w[1 2], ["2"], ["intent.md"]], [read.structure.work_log.map(&:intent_id), read.structure.work_log("2").map(&:intent_id),
      read.documents("2").map(&:path)]
  end

  def test_clusters_nodes_and_edges_read_back
    put(:clusters, { name: "Core", intent_id: "1" })
    put(:nodes, { intent_id: "1", id: "n1", kind: "build" })
    put(:edges, { intent_id: "1", from: "n1", to: "n2", kind: "needs" })

    assert_equal [["Core"], ["n1"], ["n2"]], [retrieval.clusters.map(&:name), structure.nodes.map(&:id), structure.edges("1").map(&:to)]
  end

  def test_a_kept_file_reads_without_its_bytes_and_its_bytes_read_by_name
    row = { name: "store/1--a/x.bin", mode: 0o100644, mtime: 0, sz: 2, data: SQLite3::Blob.new("\x00\xFF".b),
            intent_id: "1", sha256: "h" }
    put(:sqlar, row)

    assert_equal [["store/1--a/x.bin", "h"]], retrieval.archives.kept_files("1").map { |file| [file.name, file.sha256] }
    assert_equal "\x00\xFF".b, retrieval.stored.kept_file_data("store/1--a/x.bin")
  end

  def test_printed_maps_each_path_to_its_hash
    put(:printed, { path: "store/index.json", sha256: "a", at: "t" })
    put(:printed, { path: "store/1--a/spec.md", sha256: "b", at: "t" })

    assert_equal({ "store/index.json" => "a", "store/1--a/spec.md" => "b" }, retrieval.stored.printed)
  end

  def test_searches_indexed_passages_without_matching_an_intent_title
    intent = open_intent("Unrelated")
    index_text(intent, "research.txt", "The retrieval evidence stays searchable.\n")

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
    store_database.transaction { |batch| batch.add("DELETE FROM document_fts") }

    retrieval.repair

    assert_equal ["repair.txt"], retrieval.search("repairable").map { |row| row.fetch("path") }
  end
end

class RetrievalReadTest < Plastic::TestCase
  def test_fetches_the_current_qualified_reference_and_refuses_a_replaced_one
    reference = historical_reference

    assert_historical_reference(reference)
  end

  def test_rejects_unknown_and_removed_qualified_references
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

  def writer = Plastic::Graph::Retrieval::Evidence::Writer.new(store_database, origin, clock: FixedClock::CLOCK)

  def historical_reference
    writer.write("1", historical_path, "first body")
    reference = retrieval.reference("1", historical_path)
    writer.write("1", historical_path, "second body")
    reference
  end

  def assert_historical_reference(reference)
    assert_equal expected_reference, reference.fetch(:uri)
    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { retrieval.fetch_reference(reference.fetch(:uri)) }
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
    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { retrieval.fetch_reference(reference) }
    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { retrieval.fetch_reference("plastic://global/1/missing.md") }
    assert_raises(Plastic::Graph::RetrievalGraph::MissingReference) { retrieval.fetch_reference(reference.merge(revision: "missing")) }
  end
end

class RetrievalRepairIntegrityTest < Plastic::TestCase
  def test_repair_rebuilds_wrong_values_and_orphans_without_changing_documents
    writer.write("1", "repair.md", "repair evidence")
    document = store_database.row("SELECT body, updated_at FROM documents")
    reindex
    corrupt_derived_rows

    repair

    assert_repaired(document)
  end

  def test_repair_uses_a_current_snapshot_when_a_writer_commits_before_rebuild
    repair_after_concurrent_write

    assert_equal ["new evidence"], retrieval.search("new").map { |row| row.fetch("body") }
    assert_empty retrieval.search("old")
  end

  def test_repair_indexes_a_document_that_has_no_head_without_changing_it
    store_database.transaction do |batch|
      batch.add("INSERT INTO documents (intent_id, path, body, updated_at, origin_id) VALUES ('1', 'headless.md', 'canonical evidence', 'then', :origin)", origin:)
    end

    repair

    assert_equal ["headless.md"], retrieval.search("canonical").map { |row| row.fetch("path") }
    assert_equal "canonical evidence", store_database.row("SELECT body FROM documents WHERE path = 'headless.md'").fetch("body")
  end

  def test_repair_rebuilds_derived_rows_without_writing_canonical_documents
    writer.write("1", "repair.md", "repair evidence")
    reindex
    before = canonical_state
    store_database.transaction { |batch| batch.add("DELETE FROM document_fts") }

    repair

    assert_equal before, canonical_state
  end

  def test_repair_scales_past_sqlite_expression_depth
    1001.times { |index| writer.write(index.to_s, "#{index}.md", "evidence #{index}") }
    reindex
    store_database.transaction { |batch| batch.add("DELETE FROM document_fts") }

    repair

    assert_equal 1001, store_database.row("SELECT count(*) AS n FROM document_fts").fetch("n")
  end

  def test_repair_keeps_distinct_passages_for_identical_bodies_with_different_extraction
    writer.write("1", "first.txt", "<p>shared</p><p>evidence</p>")
    writer.write("2", "second.html", "<p>shared</p><p>evidence</p>")
    reindex
    store_database.transaction { |batch| batch.add("DELETE FROM document_fts") }

    repair

    assert_equal [["1", "first.txt"], ["2", "second.html"]],
      store_database.rows("SELECT intent_id, path FROM document_passages ORDER BY intent_id").map(&:values)
  end

  private

  def assert_repaired(document)
    assert_equal document, store_database.row("SELECT body, updated_at FROM documents")
    assert_equal ["repair evidence"], retrieval.search("repair").map { |row| row.fetch("body") }
    assert_equal [[1, 1]], store_database.rows("SELECT line_start, line_end FROM document_passages").map(&:values)
  end

  def writer = Plastic::Graph::Retrieval::Evidence::Writer.new(store_database, origin, clock: FixedClock::CLOCK)
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
    store_database.transaction { |batch| batch.add("DELETE FROM document_fts") }
    Plastic::Graph::Retrieval::Evidence::Integrity.new(store_database, origin, before_rebuild: concurrent_writer).repair
  end

  def canonical_state = store_database.rows("SELECT intent_id, path, body, updated_at FROM documents ORDER BY intent_id, path")

  def corrupt_derived_rows
    store_database.transaction { |batch| batch.add("UPDATE document_heads SET sha256 = 'wrong'") }
    store_database.transaction do |batch|
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

  def repair_with_blocked_writer
    isolated_writer.write("1", "repair.md", "repair evidence")
    Plastic::Graph::Retrieval::Index.new(isolated, origin).rebuild
    isolated.transaction { |batch| batch.add("DELETE FROM document_fts") }
    @pipes = IO.pipe + IO.pipe
    blocked_repairer.repair
    [@writer, acquired]
  end

  def blocked_repairer = Plastic::Graph::Retrieval::Evidence::Integrity.new(isolated, origin, before_rebuild: method(:block_writer))

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
    connection.execute("BEGIN DEFERRED")
    update_isolated_document(connection)
    acquired_writer.write("acquired")
  end

  def close_pipes
    @pipes.to_a.each { |pipe| pipe.close unless pipe.closed? }
  end

  def attempted = @pipes.fetch(0)
  def attempted_writer = @pipes.fetch(1)
  def acquired = @pipes.fetch(2)
  def acquired_writer = @pipes.fetch(3)
  def isolated = (@isolated ||= Plastic::Graph::Database.open_store(File.join(@home, "isolated"), Plastic::Graph::Origin.new(@plastic_home)))
  def isolated_writer = Plastic::Graph::Retrieval::Evidence::Writer.new(isolated, origin, clock: FixedClock::CLOCK)
end

class RetrievalRepairTest < Plastic::TestCase
  DERIVED_TABLES = %w[document_heads document_passages document_fts].freeze

  def test_repairs_each_corrupted_derived_table_from_current_documents
    DERIVED_TABLES.each do |table|
      index_current_document
      store_database.transaction { |batch| batch.add("DELETE FROM #{table}") }

      audit = retrieval.repair

      assert_repaired
      assert_equal({ repairable: false }, audit)
    end
  end

  private

  def index_current_document
    Plastic::Graph::Retrieval::Evidence::Writer.new(store_database, origin, clock: FixedClock::CLOCK).write("1", "repair.md", "repair evidence")
    reindex
  end

  def assert_repaired
    assert_equal ["repair evidence"], retrieval.search("repair").map { |row| row.fetch("body") }
    assert_equal [1], DERIVED_TABLES.map { |table| store_database.row("SELECT count(*) AS n FROM #{table}").fetch("n") }.uniq
  end
end
