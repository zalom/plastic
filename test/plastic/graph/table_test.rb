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

  def test_which_tables_carry_an_origin_and_a_count
    flags = %i[clusters printed command_runs].map { |name| [table(name).origin?, table(name).counted?] }

    assert_equal [[true, true], [true, false], [false, true]], flags
  end
end
