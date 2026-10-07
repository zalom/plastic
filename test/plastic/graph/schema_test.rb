# frozen_string_literal: true

require "digest"
require "json"
require_relative "../../test_helper"

class SchemaTest < Plastic::TestCase
  Schema = Plastic::Graph::Schema

  def table(name) = Schema.table_named(name)

  def test_the_schema_names_each_database_file
    assert_equal %w[local.db work_graph.db knowledge_graph.db references.db], %i[local work knowledge references].map { |key| Schema.file(key) }
  end

  def test_the_schema_joins_each_database_tables_ddl
    assert_equal [table(:routine_runs).ddl, table(:sessions).ddl, table(:locks).ddl, table(:backups).ddl].join("\n"), Schema.fetch(:local)
    assert_equal %i[documents legacy_intents_data document_revisions document_heads document_passages document_fts retrieval_schema retrieval_backfills retrieval_contexts retrieval_discoveries rulings links printed changes],
      Schema.databases.fetch(:knowledge).last
  end

  def test_the_knowledge_schema_has_the_retrieval_tables_and_fts_index
    schema = Schema.fetch(:knowledge)

    %w[document_revisions document_heads document_passages retrieval_schema].each do |table_name|
      assert_includes schema, %(CREATE TABLE IF NOT EXISTS "#{table_name}")
    end
    assert_includes schema, 'CREATE VIRTUAL TABLE IF NOT EXISTS "document_fts" USING fts5'
    assert_includes Schema.table_named(:document_heads).ddl, 'UNIQUE("intent_id", "path", "origin_id")'
  end

  def test_the_knowledge_schema_has_the_pinned_ddl_and_sqlite_catalog
    assert_equal "05ceced76cebfb0a415ea455267902a66c75fecadde1941898d62cfa88e7aae9", Digest::SHA256.hexdigest(Schema.fetch(:knowledge))
    assert_equal "9480cf34c99dfffaf3c8f575e1cb7838e17dc9d7b2f760c9c6b9a9341c2861d4", Digest::SHA256.hexdigest(JSON.generate(schema_catalog))
  end

  def test_a_tally_names_one_and_many
    assert_equal ["1 routine run", "2 savepoint lines", "1 x"],
      [Schema.tally(:routine_runs, 1), Schema.tally("savepoints", 2), Schema.tally(:x, 1)]
    assert_equal ["1 legacy file", "6 legacy files"], [Schema.tally(:legacy_intents_data, 1), Schema.tally(:legacy_intents_data, 6)]
  end

  def test_a_phrase_joins_one_two_and_three_tallies
    assert_equal ["1 intent", "1 intent and 2 clusters", "1 intent, 2 clusters, and 1 node"],
      [{ intents: 1 }, { intents: 1, clusters: 2 }, { intents: 1, clusters: 2, nodes: 1 }].map { |counts| Schema.phrase(counts) }
  end

  private

  def schema_catalog
    database = Plastic::Graph::Database.new(File.join(@home, "schema-contract.db"), Schema.fetch(:knowledge))
    database.rows("SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name")
  end
end
