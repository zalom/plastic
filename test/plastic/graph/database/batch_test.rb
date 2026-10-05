# frozen_string_literal: true

require_relative "../../../test_helper"

class DatabaseBatchTest < Plastic::TestCase
  Batch = Plastic::Graph::Database::Batch

  def work = store_graphs.databases[:work]

  def cluster(name) = { name:, intent_id: "1" }

  def names = work.rows("SELECT name FROM clusters").map { |row| row["name"] }

  def changes = work.rows("SELECT \"table\", operation FROM changes ORDER BY rowid").map(&:values)

  def test_a_new_batch_is_empty_until_a_statement_is_added
    batch = Batch.new

    assert_equal [true, false], [batch.empty?, batch.add("SELECT 1").empty?]
  end

  def test_a_put_in_a_store_database_stamps_the_origin_and_logs_the_change
    work.transaction { |batch| batch.put(:clusters, cluster("C")) }

    assert_equal [store_graphs.retrieval.origin_id], work.rows("SELECT origin_id FROM clusters").map { |row| row["origin_id"] }
    assert_equal [%w[clusters put]], changes
  end

  def test_a_put_with_insert_refuses_a_row_already_there
    work.transaction { |batch| batch.put(:clusters, cluster("C")) }

    assert_raises(Plastic::Graph::Database::Error) { work.transaction { |batch| batch.put(:clusters, cluster("C"), statement: :insert) } }
    assert_equal 1, work.rows("SELECT * FROM clusters").size
  end

  def test_a_remove_deletes_the_matching_rows_and_logs_the_removal
    work.transaction { |batch| batch.put_all(:clusters, [cluster("A"), cluster("B")]) }
    work.transaction { |batch| batch.remove_all(:clusters, [cluster("A")]) }

    assert_equal ["B"], names
    assert_equal %w[put put remove], changes.map(&:last)
  end

  def test_insert_rows_writes_each_row_under_its_table_in_order
    work.transaction { |batch| batch.insert_rows(clusters: cluster("A"), nodes: { intent_id: "1", id: "n1", state: "open" }) }

    assert_equal [%w[clusters put], %w[nodes put]], changes
  end

  def test_a_counted_write_reports_its_rows_only_when_it_changed_some
    batch = Batch.new.write(:clusters, "DELETE FROM clusters")

    assert_match(/WHERE changes\(\) > 0;\z/, batch.statements.last)
  end

  def test_the_home_database_keeps_no_change_log
    batch = Batch.new.put(:locks, { store: "s", intent_id: "1", session_id: "x", mode: "auto", taken_at: STAMP, renewed_at: STAMP })

    assert_empty(batch.statements.grep(/INSERT INTO changes/))
  end

  def test_apply_adds_the_statements_of_each_read_in_order
    batch = Batch.new.apply([->(b) { b.add("SELECT 1") }, ->(b) { b.add("SELECT 2") }])

    assert_equal ["SELECT 1;", "SELECT 2;"], batch.statements
  end
end
