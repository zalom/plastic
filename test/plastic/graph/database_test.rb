# frozen_string_literal: true

require_relative "../support/kernel"

class DatabaseTest < Minitest::Test
  include KernelFixtures::DatabaseHome

  Program = Plastic::Graph::Database::Program

  # The sqlite3 program on a database in a temporary folder.
  def program_call(script, file: "work_graph.db")
    Dir.mktmpdir("plastic-program") { |dir| Program.new.call(File.join(dir, file), script) }
  end

  def test_the_program_needs_sqlite3_on_the_search_path
    error = assert_raises(Database::Error) { Program.new("").check }

    assert_equal "sqlite3 is not on PATH; install it, then call again", error.message
  end

  def test_the_program_passes_its_check_when_sqlite3_is_found
    assert_nil Program.new.check
  end

  def test_the_program_returns_each_result_set_in_order
    assert_equal [[{ "a" => 1 }], [{ "b" => "x" }, { "b" => "y" }]],
      program_call("SELECT 1 AS a; CREATE TABLE t(b); INSERT INTO t VALUES ('x'), ('y'); SELECT b FROM t ORDER BY b;")
  end

  def test_a_script_with_no_rows_returns_no_sets
    assert_empty program_call("CREATE TABLE t(a);")
  end

  def test_an_sql_error_names_the_file
    error = assert_raises(Database::Error) { program_call("SELECT nope;") }

    assert_match(/\Awork_graph\.db: .*no such column: nope/, error.message)
  end

  def test_a_folder_that_cannot_be_made_names_the_file
    Dir.mktmpdir("plastic-program") do |dir|
      File.write(File.join(dir, "taken"), "")
      error = assert_raises(Database::Error) { Program.new.call(File.join(dir, "taken", "home.db"), "SELECT 1;") }

      assert_match(/\Ahome\.db: /, error.message)
    end
  end

  def test_opening_checks_the_engine_first
    assert_raises(Database::Error) { Database.open_home("/nowhere", engine: Program.new("")) }
    assert_raises(Database::Error) { Database.open_store("/nowhere", nil, engine: Program.new("")) }
  end

  def test_open_home_opens_the_home_database
    databases = Database.open_home("/home")

    assert_equal [:home], databases.keys
    assert_equal ["/home/home.db", "home.db"], [databases[:home].path, databases[:home].file]
  end

  def test_the_schema_is_made_on_the_first_read
    assert_empty @database.rows("SELECT name FROM notes")
  end

  def test_rows_and_row_read_with_values
    insert("a")
    insert("b")

    assert_equal [{ "name" => "a" }, { "name" => "b" }], @database.rows("SELECT name FROM routine_runs ORDER BY id")
    assert_equal({ "name" => "b" }, @database.row("SELECT name FROM routine_runs WHERE name = :name", name: "b"))
    assert_nil @database.row("SELECT name FROM routine_runs WHERE name = 'c'")
  end

  def test_an_empty_transaction_runs_nothing
    database = Database.new(File.join(@dir, "x.db"), "")

    assert_equal [[], false], [database.transaction { |_batch| nil }, File.exist?(File.join(@dir, "x.db"))]
  end

  def test_returning_rows_come_back_in_order
    returned = @database.transaction do |batch|
      batch.write(:routine_runs, "INSERT INTO routine_runs(name) VALUES (:name) RETURNING name", name: "a")
      batch.write(:routine_runs, "INSERT INTO routine_runs(name) VALUES (:name) RETURNING name", name: "b")
    end

    assert_equal [[{ "name" => "a" }], [{ "name" => "b" }]], returned
    assert_equal({ "routine_runs" => 2 }, @database.written)
  end

  def test_a_conflict_clause_skips_the_duplicate
    insert("a")
    @database.transaction { |batch| batch.insert(:routine_runs, { name: "a" }, conflict: "NOTHING") }

    assert_equal 1, @database.row("SELECT count(*) AS n FROM routine_runs")["n"]
  end

  def test_the_record_names_the_columns_in_order
    @database.transaction { |batch| batch.insert(:stored, { store: "plastic", name: "x" }) }

    assert_equal({ "store" => "plastic", "name" => "x" }, @database.row("SELECT * FROM stored"))
  end

  def test_bytes_go_in_as_a_blob
    @database.transaction { |batch| batch.insert(:routine_runs, { name: "b", data: SQL::Bytes.new("hi") }) }

    assert_equal "hi", @database.row("SELECT CAST(data AS TEXT) AS t FROM routine_runs")["t"]
  end

  def test_the_program_fails_its_check_on_a_folder_with_no_sqlite3
    Dir.mktmpdir("plastic-path") { |dir| assert_raises(Database::Error) { Program.new(dir).check } }
  end

  def test_the_program_makes_the_folder_of_a_new_database
    Dir.mktmpdir("plastic-program") do |dir|
      Program.new.call(File.join(dir, "new", "home.db"), "CREATE TABLE t(a);")

      assert_path_exists File.join(dir, "new", "home.db")
    end
  end

  def test_puts_and_applies_return_the_batch_so_writes_chain
    batch = Plastic::Graph::Database::Batch.new

    assert_same batch, batch.put(:clusters, { name: "C", intent_id: "1" }).apply([])
  end
end
