# frozen_string_literal: true

require_relative "../../test_helper"

class RetrievalMigrationTest < Plastic::TestCase
  MigrationInterrupted = Class.new(StandardError)

  def teardown
    Plastic::Graph::Database::ConnectionPool.disconnect
    super
  end

  def test_first_read_migrates_legacy_documents_and_references_once_per_origin
    seed_legacy_evidence

    assert_equal ["legacy.md:legacy document", "reference.txt:legacy reference"], search_paths_and_bodies
    first = migration_state

    assert_equal ["legacy.md:legacy document", "reference.txt:legacy reference"], search_paths_and_bodies
    assert_equal first, migration_state
  end

  def test_reopens_and_completes_an_old_schema_after_each_evidence_commit
    (1..2).each do |boundary|
      create_old_schema

      assert_raises(MigrationInterrupted) { interrupted_backfill(boundary) }
      reopen.retrieval.search("legacy")

      assert_migration_complete
    end
  end

  def test_source_read_requires_maintenance_without_writing_an_old_database
    create_old_schema
    before = database_bytes

    assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) { retrieval.search("legacy", migrate: false) }
    assert_equal before, database_bytes
  end

  def test_backfill_markers_stay_isolated_between_origins
    seed_legacy_evidence
    other_origin = "another-installation"
    put(:knowledge, :documents, { intent_id: "2", path: "other.md", body: "other legacy", updated_at: "then", origin_id: other_origin })

    retrieval.backfill!
    Plastic::Graph::ReferenceBackfill.new(store_graphs.databases, other_origin).call

    assert_equal [["retrieval", origin], ["retrieval", other_origin]],
      knowledge.rows("SELECT name, origin_id FROM retrieval_backfills ORDER BY origin_id").map { |row| row.values_at("name", "origin_id") }
    assert_equal ["legacy.md", "other.md", "reference.txt"],
      knowledge.rows("SELECT path FROM document_heads ORDER BY path").map { |row| row.fetch("path") }
  end

  private

  def seed_legacy_evidence
    put(:knowledge, :documents, { intent_id: "1", path: "legacy.md", body: "legacy document", updated_at: "then" })
    put(:references, :sqlar, { name: "store/1--legacy/reference.txt", mode: 0o100644, mtime: 0, sz: 16,
                                data: Plastic::Graph::SQL::Bytes.new("legacy reference"), intent_id: "1", sha256: "legacy" })
  end

  def create_old_schema
    Plastic::Graph::Database::ConnectionPool.disconnect
    %w[knowledge_graph.db references.db].each { |file| FileUtils.rm_f(store_path(file)) }
    create_legacy_knowledge
    create_legacy_references
  end

  def create_legacy_knowledge
    SQLite3::Database.new(store_path("knowledge_graph.db")).tap do |database|
      database.execute_batch("CREATE TABLE documents(intent_id TEXT, path TEXT, body TEXT, updated_at TEXT, origin_id TEXT, UNIQUE(intent_id, path, origin_id));")
      database.execute("INSERT INTO documents VALUES (?, ?, ?, ?, ?)", ["1", "legacy.md", "legacy document", "then", origin])
      database.close
    end
  end

  def create_legacy_references
    SQLite3::Database.new(store_path("references.db")).tap do |database|
      database.execute_batch("CREATE TABLE sqlar(name TEXT PRIMARY KEY, mode INT, mtime INT, sz INT, data BLOB, intent_id TEXT, sha256 TEXT, origin_id TEXT);")
      database.execute("INSERT INTO sqlar VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        ["store/1--legacy/reference.txt", 0o100644, 0, 16, "legacy reference", "1", "legacy", origin])
      database.close
    end
  end

  def interrupted_backfill(boundary)
    writes = 0
    callback = lambda do
      writes += 1
      raise MigrationInterrupted if writes == boundary
    end
    Plastic::Graph::ReferenceBackfill.new(store_graphs.databases, origin, after_write: callback).call
  end

  def reopen
    Plastic::Graph::Database::ConnectionPool.disconnect
    Plastic::Graph.open(home: @plastic_home, store: "global")
  end

  def database_bytes
    %w[knowledge_graph.db references.db].to_h { |file| [file, File.binread(store_path(file))] }
  end

  def put(database, table, row)
    store_graphs.databases.fetch(database).transaction { |batch| batch.put(table, row) }
  end

  def search_paths_and_bodies
    retrieval.search("legacy").map { |row| row.values_at("path", "body").join(":") }.sort
  end

  def migration_state
    knowledge = store_graphs.databases.fetch(:knowledge)
    { schema: knowledge.rows("SELECT name, version, completed_at FROM retrieval_schema"),
      marker: knowledge.rows("SELECT name, origin_id FROM retrieval_backfills ORDER BY name, origin_id") }.merge(derived_state(knowledge))
  end

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def derived_state(knowledge)
    { revisions: knowledge.rows("SELECT intent_id, path, body FROM document_revisions ORDER BY path"),
      documents: knowledge.rows("SELECT intent_id, path, sha256 FROM document_heads ORDER BY intent_id, path"),
      passages: knowledge.rows("SELECT sha256, position, body FROM document_passages ORDER BY body"),
      fts: knowledge.rows("SELECT intent_id, path, sha256, position, body FROM document_fts ORDER BY path") }
  end

  def assert_migration_complete
    state = migration_state

    assert_evidence_counts(state)
    assert_marker(state)
    assert_equal ["legacy.md", "reference.txt"], state.fetch(:fts).map { |row| row.fetch("path") }
  end

  def assert_evidence_counts(state) = assert_equal([2], state.values_at(:revisions, :documents, :passages, :fts).map(&:size).uniq)

  def assert_marker(state)
    assert_equal "complete", state.fetch(:schema).fetch(0).fetch("completed_at")
    assert_equal [["retrieval", origin]], state.fetch(:marker).map { |row| row.values_at("name", "origin_id") }
  end
end
