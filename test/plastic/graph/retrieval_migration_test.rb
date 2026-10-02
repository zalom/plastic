# frozen_string_literal: true

require_relative "../../test_helper"

class RetrievalMigrationTest < Plastic::TestCase
  def test_first_read_migrates_legacy_documents_and_references_once_per_origin
    seed_legacy_evidence

    assert_equal ["legacy.md:legacy document", "reference.txt:legacy reference"], search_paths_and_bodies
    first = migration_state

    assert_equal ["legacy.md:legacy document", "reference.txt:legacy reference"], search_paths_and_bodies
    assert_equal first, migration_state
  end

  private

  def seed_legacy_evidence
    put(:knowledge, :documents, { intent_id: "1", path: "legacy.md", body: "legacy document", updated_at: "then" })
    put(:references, :sqlar, { name: "store/1--legacy/reference.txt", mode: 0o100644, mtime: 0, sz: 16,
                                data: Plastic::Graph::SQL::Bytes.new("legacy reference"), intent_id: "1", sha256: "legacy" })
  end

  def put(database, table, row)
    store_graphs.databases.fetch(database).transaction { |batch| batch.put(table, row) }
  end

  def search_paths_and_bodies
    retrieval.search("legacy").map { |row| row.values_at("path", "body").join(":") }.sort
  end

  def migration_state
    knowledge = store_graphs.databases.fetch(:knowledge)
    { marker: knowledge.rows("SELECT * FROM retrieval_backfills ORDER BY name, origin_id"),
      documents: knowledge.rows("SELECT intent_id, path, sha256 FROM document_heads ORDER BY intent_id, path"),
      passages: knowledge.rows("SELECT sha256, position FROM document_passages ORDER BY sha256, position"),
      fts: knowledge.rows("SELECT intent_id, path, sha256, position FROM document_fts ORDER BY intent_id, path, position") }
  end
end
