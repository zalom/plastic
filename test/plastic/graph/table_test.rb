# frozen_string_literal: true

require_relative "../../test_helper"

class TableTest < Plastic::TestCase
  Schema = Plastic::Graph::Schema
  CLUSTER = { name: "C", intent_id: "1", origin_id: "o" }.freeze
  CLUSTER_SQL = %(INSERT INTO "clusters" ("name", "intent_id", "origin_id") VALUES (:v_name, :v_intent_id, :v_origin_id))
  CLUSTER_VALUES = { v_name: "C", v_intent_id: "1", v_origin_id: "o" }.freeze

  def bound(sql, values) = Plastic::Graph::SQL::Bound.new(sql, values)

  def table(name) = Schema.table_named(name)

  def test_the_ddl_lists_the_columns_and_the_unique_key
    assert_equal 'CREATE TABLE IF NOT EXISTS "clusters"("name" TEXT NOT NULL, "intent_id" TEXT NOT NULL, ' \
                 '"origin_id" TEXT NOT NULL, UNIQUE("name", "intent_id", "origin_id"));', table(:clusters).ddl
  end

  def test_a_table_with_no_key_has_no_unique_clause
    refute_includes table(:changes).ddl, "UNIQUE"
  end

  def test_an_upsert_updates_the_columns_outside_the_key
    expected = bound(%(INSERT INTO "printed" ("path", "sha256") VALUES (:v_path, :v_sha256) ON CONFLICT("path") DO UPDATE SET "sha256" = excluded."sha256"),
      { v_path: "p", v_sha256: "h" })

    assert_equal expected, table(:printed).upsert({ path: "p", sha256: "h" })
  end

  def test_an_upsert_of_a_row_that_is_all_key_does_nothing
    expected = bound(%(#{CLUSTER_SQL} ON CONFLICT("name", "intent_id", "origin_id") DO NOTHING), CLUSTER_VALUES)

    assert_equal expected, table(:clusters).upsert(CLUSTER)
  end

  def test_an_insert_takes_the_row_as_it_stands
    assert_equal bound(CLUSTER_SQL, CLUSTER_VALUES), table(:clusters).insert(CLUSTER)
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

    assert_equal [[true, true, true], [true, false, false], [false, true, true]], flags
  end

  def test_a_change_row_logs_a_put_with_the_row_and_a_remove_without
    put, remove = %w[put remove].map { |operation| table(:printed).change(operation, { path: "p" }, "o") }

    assert_equal %(INSERT INTO changes("table", "key", operation, "row", at, origin_id) SELECT :c_table, json_object('path', "path"), :c_operation, NULL, :c_at, :c_origin FROM "printed" WHERE "path" IS :m_path), remove.sql
    assert_equal({ c_table: "printed", c_operation: "remove", c_origin: "o", m_path: "p" }, remove.values.except(:c_at))
    assert_match(/\A\d{4}-\d\d-\d\dT[\d:]+[+-]\d\d:\d\d\z/, remove.values.fetch(:c_at))
    assert_includes put.sql, %(:c_operation, json_object('path', "path", 'sha256', "sha256", 'at', "at", 'origin_id', "origin_id"), )
    assert_equal "put", put.values.fetch(:c_operation)
  end
end
