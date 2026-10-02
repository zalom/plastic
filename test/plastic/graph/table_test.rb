# frozen_string_literal: true

require_relative "../../test_helper"

class TableTest < Plastic::TestCase
  Schema = Plastic::Graph::Schema
  CLUSTER = { name: "C", intent_id: "1", origin_id: "o" }.freeze
  CLUSTER_SQL = %(INSERT INTO "clusters" ("name", "intent_id", "origin_id") VALUES ('C', '1', 'o'))

  def table(name) = Schema.table_named(name)

  def test_the_ddl_lists_the_columns_and_the_unique_key
    assert_equal 'CREATE TABLE IF NOT EXISTS "clusters"("name" TEXT NOT NULL, "intent_id" TEXT NOT NULL, ' \
                 '"origin_id" TEXT NOT NULL, UNIQUE("name", "intent_id", "origin_id"));', table(:clusters).ddl
  end

  def test_a_table_with_no_key_has_no_unique_clause
    refute_includes table(:changes).ddl, "UNIQUE"
  end

  def test_an_upsert_updates_the_columns_outside_the_key
    assert_equal %(INSERT INTO "printed" ("path", "sha256") VALUES ('p', 'h') ON CONFLICT("path") DO UPDATE SET "sha256" = excluded."sha256"),
      table(:printed).upsert({ path: "p", sha256: "h" })
  end

  def test_an_upsert_of_a_row_that_is_all_key_does_nothing
    assert_equal %(#{CLUSTER_SQL} ON CONFLICT("name", "intent_id", "origin_id") DO NOTHING), table(:clusters).upsert(CLUSTER)
  end

  def test_an_insert_takes_the_row_as_it_stands
    assert_equal CLUSTER_SQL, table(:clusters).insert(CLUSTER)
  end

  def test_the_key_of_a_row_is_its_key_columns
    assert_equal({ name: "C", intent_id: "1", origin_id: nil }, table(:clusters).key_of({ name: "C", intent_id: "1", x: 2 }))
  end

  def test_a_json_row_reads_bytes_as_hex
    assert_includes table(:sqlar).json_row, %('data', hex("data"), 'intent_id', "intent_id")
    assert_equal %(json_object('path', "path")), table(:printed).json_key
  end

  def test_which_tables_carry_an_origin_a_log_and_a_count
    flags = %i[clusters printed routine_runs].map { |name| [table(name).origin?, table(name).logged?, table(name).counted?] }

    assert_equal [[true, true, true], [true, false, false], [false, true, false]], flags
  end

  def test_a_change_row_logs_a_put_with_the_row_and_a_remove_without
    put, remove = %w[put remove].map { |operation| table(:printed).change(operation, { path: "p" }, "o") }
    at = /'\d{4}-\d\d-\d\dT[\d:]+[+-]\d\d:\d\d'/

    assert_match(/\AINSERT INTO changes\("table", "key", operation, "row", at, origin_id\) SELECT 'printed', json_object\('path', "path"\), 'remove', NULL, #{at}, 'o' FROM "printed" WHERE "path" IS 'p'\z/o, remove)
    assert_includes put, %('put', json_object('path', "path", 'sha256', "sha256", 'at', "at", 'origin_id', "origin_id"), )
  end

  def test_the_schema_names_each_database_file
    assert_equal %w[home.db work_graph.db knowledge_graph.db references.db], %i[home work knowledge references].map { |key| Schema.file(key) }
  end

  def test_the_schema_joins_each_database_tables_ddl
    assert_equal [table(:routine_runs).ddl, table(:sessions).ddl, table(:locks).ddl, table(:backups).ddl].join("\n"), Schema.fetch(:home)
    assert_equal %i[documents document_revisions document_heads document_passages document_fts retrieval_schema retrieval_backfills retrieval_contexts retrieval_discoveries architecture_receipts rulings links printed changes],
      Schema::DATABASES.fetch(:knowledge).last
  end

  def test_a_tally_names_one_and_many
    assert_equal ["1 routine run", "2 savepoint lines", "1 x"],
      [Schema.tally(:routine_runs, 1), Schema.tally("savepoints", 2), Schema.tally(:x, 1)]
  end

  def test_a_phrase_joins_one_two_and_three_tallies
    assert_equal ["1 intent", "1 intent and 2 clusters", "1 intent, 2 clusters, and 1 node"],
      [{ intents: 1 }, { intents: 1, clusters: 2 }, { intents: 1, clusters: 2, nodes: 1 }].map { |counts| Schema.phrase(counts) }
  end
end
