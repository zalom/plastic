# frozen_string_literal: true

require "digest"
require "json"
require_relative "../../test_helper"

class SchemaTest < Plastic::TestCase
  Schema = Plastic::Graph::Schema

  def table(name) = Schema.table_named(name)

  def test_the_file_of_a_table_is_the_file_that_holds_it
    assert_equal ["work_graph.db", "knowledge_graph.db", "retrieval_graph.db"], %i[nodes intents document_passages].map { |name| Schema.file_of(name) }
  end

  def test_the_file_of_an_unknown_table_raises_unknown_table
    error = assert_raises(Schema::UnknownTable) { Schema.file_of("intnets") }

    assert_equal "no database file holds the table intnets", error.message
  end

  def test_the_schema_names_each_database_file
    assert_equal %w[plastic.db work_graph.db knowledge_graph.db retrieval_graph.db], %i[local work knowledge retrieval].map { |key| Schema.file(key) }
  end

  def test_the_schema_joins_the_ddl_of_the_tables_of_plastic_db
    assert_equal %i[command_runs sessions settings printed chat_messages store_migrations].map { |name| table(name).ddl }.join("\n"), Schema.fetch(:local)
  end

  def test_the_schema_lists_the_tables_of_knowledge_graph_db_in_order
    assert_equal %i[intents clusters completions approvals verdicts archives archive_entries documents legacy_intents_data document_heads retrieval_contexts retrieval_discoveries rulings links printed sqlar],
      Schema.databases.fetch(:knowledge).last
  end

  def test_a_store_has_a_work_and_a_knowledge_database_and_one_derived_file
    assert_equal [%i[work knowledge], %i[retrieval]], [Schema.store, Schema.derived]
  end

  def test_the_retrieval_database_holds_the_passages_and_the_search_entries
    assert_equal %i[document_passages document_fts], Schema.databases.fetch(:retrieval).last
  end

  def test_the_retrieval_schema_has_the_passages_and_fts_index_and_knowledge_keeps_the_canonical_tables
    schema = Schema.fetch(:retrieval)

    assert_includes schema, 'CREATE TABLE IF NOT EXISTS "document_passages"'
    assert_includes schema, 'CREATE VIRTUAL TABLE IF NOT EXISTS "document_fts" USING fts5'
    refute_match(/document_passages|document_fts|retrieval_schema/, Schema.fetch(:knowledge))
  end

  def test_the_knowledge_heads_are_unique_by_intent_path_and_origin
    assert_includes Schema.table_named(:document_heads).ddl, 'UNIQUE("intent_id", "path", "origin_id")'
  end

  def test_the_knowledge_schema_has_the_pinned_ddl_and_sqlite_catalog
    assert_equal "dd9d52cd09e4c229c4410c2af7d28c2ca6162e2c3d9a15294f16b1388191efda", Digest::SHA256.hexdigest(Schema.fetch(:knowledge))
    assert_equal "4ee2c0a20b4c58a2050e73e21bc1d96c0f10c5a7b1bcc84696c4b9f4b3239c94", Digest::SHA256.hexdigest(JSON.generate(schema_catalog))
  end

  def test_a_tally_names_one_and_many
    assert_equal ["1 command run", "2 work log lines", "1 x"],
      [Schema.tally(:command_runs, 1), Schema.tally("work_log", 2), Schema.tally(:x, 1)]
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
