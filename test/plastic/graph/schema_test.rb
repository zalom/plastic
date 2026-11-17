# frozen_string_literal: true

require "digest"
require "json"
require_relative "../../test_helper"

class SchemaTest < Plastic::TestCase
  Schema = Plastic::Graph::Schema

  def table(name) = Schema.table_named(name)

  def test_the_schema_names_each_database_file
    assert_equal %w[plastic.db work_graph.db knowledge_graph.db references.db], %i[local work knowledge references].map { |key| Schema.file(key) }
  end

  def test_the_schema_joins_each_database_tables_ddl
    assert_equal [table(:command_runs).ddl, table(:sessions).ddl, table(:settings).ddl, table(:printed).ddl].join("\n"), Schema.fetch(:local)
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
    assert_equal "bc834c3d8f79f244ea514d752db7bc1a1bdedd7b362e43f2401912963d20b290", Digest::SHA256.hexdigest(Schema.fetch(:knowledge))
    assert_equal "829606114a518e27b8afa8a6eddf7ad503602c90f7be8f7473bb829be64669b8", Digest::SHA256.hexdigest(JSON.generate(schema_catalog))
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

  def test_a_head_inserted_after_its_passages_puts_them_in_the_search_index
    add_passage("aaa", "first words")
    add_head("aaa")

    assert_equal ["first words"], found("first")
  end

  def test_a_head_inserted_before_its_passages_gets_no_search_rows
    add_head("aaa")
    add_passage("aaa", "first words")

    assert_empty found("first")
  end

  def test_a_head_changed_to_a_new_body_loses_the_old_words_and_gains_the_new
    add_passage("aaa", "first words")
    add_passage("bbb", "second words")
    add_head("aaa")
    knowledge.transaction { |batch| batch.add("UPDATE document_heads SET sha256 = 'bbb' WHERE intent_id = '1'") }

    assert_equal [[], ["second words"]], [found("first"), found("second")]
  end

  def test_a_head_changed_with_the_same_body_keeps_one_search_row_for_each_passage
    add_passage("aaa", "first words")
    add_head("aaa")
    knowledge.transaction { |batch| batch.add("UPDATE document_heads SET updated_at = 'later' WHERE intent_id = '1'") }

    assert_equal ["first words"], found("first")
  end

  def test_a_head_deleted_leaves_no_search_row_for_it
    add_passage("aaa", "first words")
    add_head("aaa")
    knowledge.transaction { |batch| batch.add("DELETE FROM document_heads WHERE intent_id = '1'") }

    assert_empty found("first")
  end

  def test_a_database_made_before_the_triggers_gains_the_three_triggers_when_it_opens
    path = File.join(@home, "before-triggers.db")
    SQLite3::Database.new(path).tap { |old| old.execute_batch(Schema.databases.fetch(:knowledge).last.map { |name| Schema.ddl(name) }.join("\n")) }.close
    database = Plastic::Graph::Database.new(path, Schema.fetch(:knowledge))

    assert_equal 3, database.rows("SELECT name FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'document_heads'").size
  end

  def test_a_schema_file_keeps_its_triggers_apart_from_its_tables
    file = Plastic::Graph::SchemaFile.define(version: 1) do
      create_table(:things, key: []) { |table| table.serial :seq }
      create_trigger :things_after_insert, on: :things, sql: "AFTER INSERT ON things BEGIN SELECT 1; END"
    end

    assert_equal %i[things_after_insert], file.triggers.keys
    assert_equal :things, file.triggers.fetch(:things_after_insert).on
  end

  private

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def add_passage(sha, body)
    knowledge.transaction do |batch|
      batch.add("INSERT INTO document_passages (sha256, intent_id, path, position, body, line_start, line_end, origin_id) VALUES (:sha, '1', 'plan.md', 0, :body, 1, 1, :origin)", sha:, body:, origin:)
    end
  end

  def add_head(sha)
    knowledge.transaction do |batch|
      batch.add("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES ('1', 'plan.md', :sha, 't', :origin)", sha:, origin:)
    end
  end

  def found(word) = knowledge.rows("SELECT body FROM document_fts WHERE document_fts MATCH :word", word:).map { |row| row.fetch("body") }

  def schema_catalog
    database = Plastic::Graph::Database.new(File.join(@home, "schema-contract.db"), Schema.fetch(:knowledge))
    database.rows("SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name")
  end
end
