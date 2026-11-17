# frozen_string_literal: true

require_relative "../../../test_helper"

class DatabaseBatchTest < Plastic::TestCase
  Batch = Plastic::Graph::Database::Batch

  def cluster(name) = { name:, intent_id: "1" }

  def names = store_database.rows("SELECT name FROM clusters").map { |row| row["name"] }

  def test_a_new_batch_is_empty_until_a_statement_is_added
    batch = Batch.new

    assert_equal [true, false], [batch.empty?, batch.add("SELECT 1").empty?]
  end

  def test_a_put_in_a_store_database_stamps_the_origin
    store_database.transaction { |batch| batch.put(:clusters, cluster("C")) }

    assert_equal [store_graphs.retrieval.origin_id], store_database.rows("SELECT origin_id FROM clusters").map { |row| row["origin_id"] }
  end

  def test_a_put_with_insert_refuses_a_row_already_there
    store_database.transaction { |batch| batch.put(:clusters, cluster("C")) }

    assert_raises(Plastic::Graph::Database::Error) { store_database.transaction { |batch| batch.put(:clusters, cluster("C"), statement: :insert) } }
    assert_equal 1, store_database.rows("SELECT * FROM clusters").size
  end

  def test_a_remove_deletes_the_matching_rows
    store_database.transaction { |batch| batch.put_all(:clusters, [cluster("A"), cluster("B")]) }
    store_database.transaction { |batch| batch.remove_all(:clusters, [cluster("A")]) }

    assert_equal ["B"], names
  end

  def test_insert_rows_writes_each_row_under_its_table
    store_database.transaction { |batch| batch.insert_rows(clusters: cluster("A"), approvals: { intent_id: "1" }) }

    assert_equal [1, 1], [store_database.rows("SELECT * FROM clusters").size, store_database.rows("SELECT * FROM approvals").size]
  end

  def test_a_counted_write_names_its_table_and_a_plain_add_names_none
    batch = Batch.new.write(:clusters, "DELETE FROM clusters").add("SELECT 1")

    assert_equal ["clusters", nil], batch.statements.map(&:table)
  end

  def test_add_keeps_the_text_and_the_values_apart
    batch = Batch.new.add("SELECT :a", a: "see :id")

    assert_equal ["SELECT :a", { a: "see :id" }], [batch.statements.first.sql, batch.statements.first.values]
  end

  def test_add_steps_adds_each_step_in_order_with_the_shared_values
    batch = Batch.new.add_steps([[nil, "SELECT :a"], [:clusters, "DELETE FROM clusters WHERE id = :a"]], a: 1)

    assert_equal [["SELECT :a", nil, { a: 1 }], ["DELETE FROM clusters WHERE id = :a", "clusters", { a: 1 }]], batch.statements.map { |entry| [entry.sql, entry.table, entry.values] }
  end

  FakeConnection = Struct.new(:changes) do
    def read(_sql, _values) = []
  end

  def test_run_executes_each_statement_and_tells_the_count_the_rows_it_changed
    counted = []
    Batch.new.write(:clusters, "DELETE FROM clusters").add("SELECT 1").run(FakeConnection.new(2)) { |table, rows| counted << [table, rows] }

    assert_equal [["clusters", 2]], counted
  end

  def test_apply_adds_the_statements_of_each_read_in_order
    batch = Batch.new.apply([->(b) { b.add("SELECT 1") }, ->(b) { b.add("SELECT 2") }])

    assert_equal ["SELECT 1", "SELECT 2"], batch.statements.map(&:sql)
  end
end
