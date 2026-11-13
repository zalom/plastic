# frozen_string_literal: true

require_relative "../../test_helper"

class DatabaseTest < Plastic::TestCase
  Database = Plastic::Graph::Database
  SQL = Plastic::Graph::SQL

  def scratch(file) = Database.new(File.join(@home, "scratch", file), "")

  def test_rows_returns_the_rows_of_one_statement
    assert_equal [{ "a" => 1 }], scratch("x.db").rows("SELECT 1 AS a")
  end

  def test_a_read_with_no_rows_returns_none
    assert_empty scratch("x.db").rows("CREATE TABLE t(a)")
  end

  def test_a_failed_statement_commits_nothing_of_its_transaction
    error = assert_raises(Plastic::Graph::Database::Error) do
      database.transaction do |batch|
        batch.insert(:routine_runs, { name: "a" })
        batch.add("INSERT INTO nowhere VALUES (1)")
      end
    end

    assert_equal "work_graph.db: no such table: nowhere", error.message
    assert_equal [], database.rows("SELECT name FROM routine_runs")
  end

  def test_a_folder_that_cannot_be_made_names_the_file
    File.write(File.join(@home, "taken"), "")
    error = assert_raises(Database::Error) { Database.new(File.join(@home, "taken", "local.db"), "").rows("SELECT 1") }

    assert_match(/\Alocal\.db: /, error.message)
  end

  def test_a_failed_write_inside_an_open_transaction_undoes_only_itself
    insert("a")
    connection = Database::ConnectionPool.for(database.path)
    connection.execute("BEGIN")
    insert("b")
    assert_raises(Database::Error) { database.transaction { |batch| batch.add("INSERT INTO nowhere VALUES (1)") } }

    assert_equal %w[a b], database.rows("SELECT name FROM routine_runs ORDER BY id").map { |row| row["name"] }
    connection.rollback
  end

  def test_open_local_opens_the_local_database
    databases = Database.open_local("/home")

    assert_equal [:local], databases.keys
    assert_equal ["/home/local.db", "local.db"], [databases[:local].path, databases[:local].file]
  end

  def test_the_schema_is_made_on_the_first_read
    assert_empty database.rows("SELECT name FROM notes")
  end

  def test_rows_and_row_read_with_values
    insert("a")
    insert("b")

    assert_equal [{ "name" => "a" }, { "name" => "b" }], database.rows("SELECT name FROM routine_runs ORDER BY id")
    assert_equal({ "name" => "b" }, database.row("SELECT name FROM routine_runs WHERE name = :name", name: "b"))
    assert_nil database.row("SELECT name FROM routine_runs WHERE name = 'c'")
  end

  def test_an_empty_transaction_runs_nothing
    database = Database.new(File.join(@home, "x.db"), "")

    assert_equal [[], false], [database.transaction { |_batch| nil }, File.exist?(File.join(@home, "x.db"))]
  end

  def test_an_empty_immediate_transaction_runs_no_derived_write
    database = Database.new(File.join(@home, "immediate.db"), "")

    assert_nil database.immediate_transaction { |_batch, _connection| nil }
    assert_empty database.written
  end

  def test_returning_rows_come_back_in_order
    returned = database.transaction do |batch|
      batch.write(:tallies, "INSERT INTO tallies(name) VALUES (:name) RETURNING name", name: "a")
      batch.write(:tallies, "INSERT INTO tallies(name) VALUES (:name) RETURNING name", name: "b")
    end

    assert_equal [[{ "name" => "a" }], [{ "name" => "b" }]], returned
    assert_equal({ "tallies" => 2 }, database.written)
  end

  def test_a_conflict_clause_skips_the_duplicate
    insert("a")
    database.transaction { |batch| batch.insert(:routine_runs, { name: "a" }, conflict: "NOTHING") }

    assert_equal 1, database.row("SELECT count(*) AS n FROM routine_runs")["n"]
  end

  def test_the_record_names_the_columns_in_order
    database.transaction { |batch| batch.insert(:stored, { store: "plastic", name: "x" }) }

    assert_equal({ "store" => "plastic", "name" => "x" }, database.row("SELECT * FROM stored"))
  end

  def test_a_blob_of_every_byte_reads_back_equal
    bytes = (0..255).map(&:chr).join.b
    database.transaction { |batch| batch.insert(:routine_runs, { name: "b", data: SQLite3::Blob.new(bytes) }) }
    row = database.row("SELECT data, typeof(data) AS kind FROM routine_runs")

    assert_equal [bytes, "blob"], [row["data"].b, row["kind"]]
  end

  def test_a_binary_string_is_stored_as_text
    database.transaction { |batch| batch.insert(:routine_runs, { name: "t", data: "café".b }) }
    row = database.row("SELECT data, typeof(data) AS kind FROM routine_runs")

    assert_equal ["text", "café"], [row["kind"], row["data"].dup.force_encoding("UTF-8")]
  end

  def test_a_new_database_makes_its_folder
    scratch("local.db").rows("CREATE TABLE t(a)")

    assert_path_exists File.join(@home, "scratch", "local.db")
  end

  def test_puts_and_applies_return_the_batch_so_writes_chain
    batch = Plastic::Graph::Database::Batch.new

    assert_same batch, batch.put(:clusters, { name: "C", intent_id: "1" }).apply([])
  end
end

class DatabaseBindingTest < Plastic::TestCase
  Database = Plastic::Graph::Database
  SQL = Plastic::Graph::SQL

  def note(value) = database.transaction { |batch| batch.add("INSERT INTO notes(name) VALUES (:name)", name: value) }

  def stored = database.rows("SELECT name, typeof(name) AS kind FROM notes ORDER BY rowid").map(&:values)

  def test_awkward_text_round_trips
    values = ["it's \"quoted\"", "a\0b", "one\ntwo", "see :id and :intent_id", "日本語 текст"]
    values.each { |value| note(value) }

    assert_equal values, stored.map(&:first)
  end

  def test_each_kind_of_value_is_stored_as_the_literal_stored_it
    values = [true, false, { "a" => 1 }, [1, 2], :sym, nil, 3, 1.5]
    kinds = values.map { |value| database.row("SELECT :v AS v, typeof(:v) AS kind", v: value).values }

    assert_equal [[1, "integer"], [0, "integer"], ['{"a":1}', "text"], ["[1,2]", "text"], ["sym", "text"], [nil, "null"], [3, "integer"], [1.5, "real"]], kinds
  end

  def test_a_statement_with_an_extra_key_runs
    database.transaction { |batch| batch.add("INSERT INTO notes(name) VALUES (:name)", name: "a", other: "b") }

    assert_equal [["a", "text"]], stored
  end

  def test_a_statement_with_a_missing_key_raises_invalid_and_writes_nothing
    error = assert_raises(Plastic::Invalid) { database.transaction { |batch| batch.add("INSERT INTO notes(name) VALUES (:name)") } }

    assert_match(/work_graph\.db: .*:name/, error.message)
    assert_empty stored
  end

  class Unbindable
    def to_s = raise("no text")
  end

  def test_a_value_that_cannot_bind_raises_invalid_and_the_next_write_succeeds
    assert_raises(Plastic::Invalid) { note(Unbindable.new) }
    note("after")

    assert_equal [["after", "text"]], stored
  end

  def test_a_value_that_cannot_bind_inside_an_open_transaction_rolls_back_its_savepoint
    connection = Database::ConnectionPool.for(database.path)
    database.rows("SELECT 1")
    connection.execute("BEGIN")
    assert_raises(Plastic::Invalid) { note(Unbindable.new) }
    note("after")
    connection.rollback

    assert_empty stored
  end

  def test_a_second_connection_writes_after_a_batch_ends
    note("a")
    other = SQLite3::Database.new(database.path)
    other.execute("INSERT INTO notes(name) VALUES ('b')")
    other.close

    assert_equal %w[a b], stored.map(&:first)
  end

  def test_a_list_of_three_ids_finds_all_three_with_named_placeholders_only
    %w[a b c d].each { |value| note(value) }
    list = SQL.list(%w[a c d], "f")

    found = database.rows("SELECT name FROM notes WHERE name IN (#{list.sql}) ORDER BY name", **list.values)

    assert_equal %w[a c d], found.map { |row| row["name"] }
  end
end

class DatabaseWriteLogTest < Plastic::TestCase
  Database = Plastic::Graph::Database

  def test_an_upsert_twice_with_different_values_leaves_the_second
    work = store_graphs.databases.fetch(:work)
    %w[h1 h2].each { |sha| work.transaction { |batch| batch.put(:printed, { path: "p", sha256: sha, at: STAMP }) } }

    assert_equal [{ "sha256" => "h2" }], work.rows("SELECT sha256 FROM printed WHERE path = 'p'")
  end

  def test_the_change_row_of_a_put_holds_the_row_as_json_data
    work = store_graphs.databases.fetch(:work)
    work.transaction { |batch| batch.put(:clusters, { name: "C", intent_id: "1" }) }
    row = work.row("SELECT \"key\", \"row\" FROM changes WHERE \"table\" = 'clusters'")

    assert_equal ["C", "1"], JSON.parse(row["key"]).values_at("name", "intent_id")
    assert_equal ["C", "1"], JSON.parse(row["row"]).values_at("name", "intent_id")
  end

  def test_the_counts_ignore_writes_that_changed_no_row
    work = store_graphs.databases.fetch(:work)
    2.times { work.transaction { |batch| batch.put(:clusters, { name: "C", intent_id: "1" }) } }
    work.transaction { |batch| batch.remove(:clusters, name: "missing", intent_id: "1") }

    assert_equal({ "clusters" => 1 }, work.written)
  end

  def test_a_log_then_a_remove_counts_the_remove_only
    work = store_graphs.databases.fetch(:work)
    work.transaction { |batch| batch.put(:clusters, { name: "C", intent_id: "1" }) }
    work.transaction { |batch| batch.remove(:clusters, name: "C", intent_id: "1") }

    assert_equal({ "clusters" => 2 }, work.written)
  end

  def test_a_double_write_of_routine_runs_counts_the_larger
    database.transaction do |batch|
      batch.write(:routine_runs, "INSERT INTO routine_runs(name) VALUES (:name)", name: "a")
      batch.write(:routine_runs, "INSERT INTO routine_runs(name) VALUES (:name)", name: "b")
    end

    assert_equal({ "routine_runs" => 1 }, database.written)
  end

  def test_eight_thousand_statements_in_one_batch_take_under_a_tenth_of_a_second
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    database.transaction do |batch|
      8000.times { |n| batch.add("INSERT INTO notes(name) VALUES (:name)", name: "n#{n}") }
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator elapsed, :<, 0.1
    assert_equal 8000, database.row("SELECT count(*) AS n FROM notes")["n"]
  end
end
