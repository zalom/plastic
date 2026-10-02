# frozen_string_literal: true

require "digest"
require_relative "../../test_helper"

class RetrievalMigrationIntegrityTest < Plastic::TestCase
  def test_completion_requires_the_current_schema_version_and_preserves_source_bytes
    before = completed_legacy_backfill
    resume_after_version_change

    assert_preserved_source_and_derived_rows(before)
  end

  private

  def origin_id = retrieval.origin_id
  def knowledge = store_graphs.databases.fetch(:knowledge)
  def references = store_graphs.databases.fetch(:references)
  def backfill = Plastic::Graph::ReferenceBackfill.new(store_graphs.databases, origin_id)
  def source_name = "store/1--legacy/reference.txt"
  def source_bytes = "legacy reference\n"

  def seed_legacy_rows
    knowledge.transaction do |batch|
      batch.add("INSERT INTO documents (intent_id, path, body, updated_at, origin_id) VALUES ('1', 'legacy.md', 'legacy document', 'then', :origin)", origin: origin_id)
    end
    references.transaction do |batch|
      batch.add("INSERT INTO sqlar (name, mode, mtime, sz, data, intent_id, sha256, origin_id) VALUES (:name, 33188, 0, :size, :data, '1', 'source', :origin)",
        name: source_name, size: source_bytes.bytesize, data: Plastic::Graph::SQL::Bytes.new(source_bytes), origin: origin_id)
    end
  end

  def completed_legacy_backfill
    seed_legacy_rows
    backfill.call
    derived_rows
  end

  def resume_after_version_change
    knowledge.transaction { |batch| batch.add("UPDATE retrieval_schema SET version = 0 WHERE name = 'retrieval'") }

    assert_equal 1, knowledge.rows("SELECT * FROM retrieval_backfills WHERE origin_id = :origin", origin: origin_id).size
    refute backfill.send(:complete?)
    backfill.call
  end

  def assert_preserved_source_and_derived_rows(before)
    assert_equal source_bytes, retrieval.kept_file_data(source_name)
    assert_equal expected_revisions, revision_rows
    assert_equal before, derived_rows
  end

  def expected_revisions
    [["1", "legacy.md", "legacy document", Digest::SHA256.hexdigest("legacy document")],
      ["1", "reference.txt", source_bytes, Digest::SHA256.hexdigest(source_bytes)]]
  end

  def revision_rows
    knowledge.rows("SELECT intent_id, path, body, sha256 FROM document_revisions ORDER BY path")
      .map { |row| row.values_at("intent_id", "path", "body", "sha256") }
  end

  def derived_rows
    %w[document_heads document_passages document_fts].to_h do |table|
      [table, knowledge.rows("SELECT * FROM #{table} ORDER BY 1, 2, 3")]
    end
  end
end
