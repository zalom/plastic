# frozen_string_literal: true

require_relative "../../test_helper"

class DatabaseTest < Plastic::TestCase
  Database = Plastic::Graph::Database
  SQL = Plastic::Graph::SQL

  def scratch(file) = Database.new(File.join(@home, "scratch", file), "")

  def test_rows_returns_the_first_result_set
    assert_equal [{ "a" => 1 }], scratch("x.db").rows("SELECT 1 AS a; SELECT 2 AS b;")
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

    assert_match(/\Ahome\.db: /, error.message)
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

  def machine = File.join(@home, "machine")

  def home_db_from_before
    Database.new(File.join(machine, "home.db"), Plastic::Graph::Schema.fetch(:local)).transaction do |batch|
      batch.insert(:routine_runs, { store: "s", tool: "t", subject: "a" })
    end
    Database::ConnectionPool.release(machine)
  end

  def first_use = Database.open_local(machine).fetch(:local).tap { |local| local.rows("SELECT 1") }

  def test_open_local_opens_the_local_database
    databases = Database.open_local("/home")

    assert_equal [:local], databases.keys
    assert_equal ["/home/local.db", "local.db"], [databases[:local].path, databases[:local].file]
  end

  def test_a_home_db_left_from_before_becomes_local_db_on_first_use
    home_db_from_before

    assert_equal ["a"], first_use.rows("SELECT subject FROM routine_runs").map { |row| row.fetch("subject") }
    assert_equal [false, true], [File.exist?(File.join(machine, "home.db")), File.exist?(File.join(machine, "local.db"))]
  end

  def test_only_the_call_that_renamed_the_file_says_so
    home_db_from_before

    assert_equal [["home.db renamed to local.db"], []], [first_use.phrases, first_use.phrases]
  end

  def test_opening_renames_nothing_before_the_first_use
    home_db_from_before
    Database.open_local(machine)

    assert_equal [true, false], [File.exist?(File.join(machine, "home.db")), File.exist?(File.join(machine, "local.db"))]
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
      batch.write(:routine_runs, "INSERT INTO routine_runs(name) VALUES (:name) RETURNING name", name: "a")
      batch.write(:routine_runs, "INSERT INTO routine_runs(name) VALUES (:name) RETURNING name", name: "b")
    end

    assert_equal [[{ "name" => "a" }], [{ "name" => "b" }]], returned
    assert_equal({ "routine_runs" => 2 }, database.written)
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

  def test_bytes_go_in_as_a_blob
    database.transaction { |batch| batch.insert(:routine_runs, { name: "b", data: SQL::Bytes.new("hi") }) }

    assert_equal "hi", database.row("SELECT CAST(data AS TEXT) AS t FROM routine_runs")["t"]
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
