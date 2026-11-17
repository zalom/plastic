# frozen_string_literal: true

require_relative "../../../test_helper"

class DatabaseBatchTest < Plastic::TestCase
  Batch = Plastic::Graph::Database::Batch

  def cluster(name) = { name:, intent_id: "1" }

  def names = knowledge.rows("SELECT name FROM clusters").map { |row| row["name"] }

  def changes = knowledge.rows("SELECT \"table\", operation FROM changes ORDER BY rowid").map(&:values)

  def test_a_new_batch_is_empty_until_a_statement_is_added
    batch = Batch.new

    assert_equal [true, false], [batch.empty?, batch.add("SELECT 1").empty?]
  end

  def test_a_put_in_a_store_database_stamps_the_origin_and_logs_the_change
    knowledge.transaction { |batch| batch.put(:clusters, cluster("C")) }

    assert_equal [store_graphs.retrieval.origin_id], knowledge.rows("SELECT origin_id FROM clusters").map { |row| row["origin_id"] }
    assert_equal [%w[clusters put]], changes
  end

  def test_a_put_with_insert_refuses_a_row_already_there
    knowledge.transaction { |batch| batch.put(:clusters, cluster("C")) }

    assert_raises(Plastic::Graph::Database::Error) { knowledge.transaction { |batch| batch.put(:clusters, cluster("C"), statement: :insert) } }
    assert_equal 1, knowledge.rows("SELECT * FROM clusters").size
  end

  def test_a_remove_deletes_the_matching_rows_and_logs_the_removal
    knowledge.transaction { |batch| batch.put_all(:clusters, [cluster("A"), cluster("B")]) }
    knowledge.transaction { |batch| batch.remove_all(:clusters, [cluster("A")]) }

    assert_equal ["B"], names
    assert_equal %w[put put remove], changes.map(&:last)
  end

  def test_insert_rows_writes_each_row_under_its_table_in_order
    knowledge.transaction { |batch| batch.insert_rows(clusters: cluster("A"), approvals: { intent_id: "1" }) }

    assert_equal [%w[clusters put], %w[approvals put]], changes
  end

  def test_a_counted_write_names_its_table_and_a_plain_add_names_none
    batch = Batch.new.write(:clusters, "DELETE FROM clusters").add("SELECT 1")

    assert_equal ["clusters", nil], batch.statements.map(&:table)
  end

  def test_add_keeps_the_text_and_the_values_apart
    batch = Batch.new.add("SELECT :a", a: "see :id")

    assert_equal ["SELECT :a", { a: "see :id" }], [batch.statements.first.sql, batch.statements.first.values]
  end

  def test_the_local_database_keeps_no_change_log
    batch = Batch.new.put(:sessions, { session_id: "x", harness: "claude-code" })

    assert_empty(batch.statements.map(&:sql).grep(/INSERT INTO changes/))
  end

  def test_apply_adds_the_statements_of_each_read_in_order
    batch = Batch.new.apply([->(b) { b.add("SELECT 1") }, ->(b) { b.add("SELECT 2") }])

    assert_equal ["SELECT 1", "SELECT 2"], batch.statements.map(&:sql)
  end
end

class ChangeLogTest < Plastic::TestCase
  def work = @work ||= store_graphs.databases[:knowledge]

  def changes(database = work) = database.rows("SELECT * FROM changes ORDER BY seq")

  def test_every_put_appends_one_change_with_its_key_and_no_row
    knowledge.transaction { |batch| batch.put(:clusters, { name: "Core", intent_id: "1" }) }
    change = sole(changes)

    assert_equal ["clusters", "put", origin, nil], change.values_at("table", "operation", "origin_id", "row")
    assert_equal({ "name" => "Core", "intent_id" => "1", "origin_id" => origin }, JSON.parse(change["key"]))
    assert_match(/[+-]\d\d:\d\d\z/, change["at"])
  end

  def test_a_failed_write_leaves_no_change_row
    assert_raises(Plastic::Graph::Database::Error) do
      knowledge.transaction do |batch|
        batch.put(:clusters, { name: "Core", intent_id: "1" })
        batch.add("INSERT INTO nowhere VALUES (1)")
      end
    end

    assert_empty changes
    assert_empty knowledge.rows("SELECT * FROM clusters")
  end

  def test_a_removal_is_logged_with_no_row
    knowledge.transaction { |batch| batch.put(:clusters, { name: "Core", intent_id: "1" }) }
    knowledge.transaction { |batch| batch.remove(:clusters, name: "Core") }
    change = changes.last

    assert_equal "remove", change["operation"]
    assert_nil change["row"]
    assert_equal({ "name" => "Core", "intent_id" => "1", "origin_id" => origin }, JSON.parse(change["key"]))
  end

  def test_a_kept_file_logs_its_name_and_not_its_bytes
    references = store_graphs.databases[:knowledge]
    row = { name: "store/1--a/resources/x.bin", mode: 0o100644, mtime: 0, sz: 2, data: SQLite3::Blob.new("ab"),
            intent_id: "1", sha256: "x" }
    references.transaction { |batch| batch.put(:sqlar, row) }
    change = sole(changes(references))

    assert_equal [{ "name" => "store/1--a/resources/x.bin" }, nil], [JSON.parse(change["key"]), change["row"]]
  end

  def test_the_local_database_keeps_no_change_log
    local = store_graphs.databases[:local]
    local.transaction { |batch| batch.put(:command_runs, { store: "global", tool: "x", subject: "" }) }

    assert_empty local.rows("SELECT name FROM sqlite_master WHERE name = 'changes'")
  end
end
