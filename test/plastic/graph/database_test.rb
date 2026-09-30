# frozen_string_literal: true

require_relative "../support/kernel"

class DatabaseTest < Minitest::Test
  Database = Plastic::Graph::Database
  SCHEMA = <<~SQL
    CREATE TABLE IF NOT EXISTS routine_runs(id INTEGER PRIMARY KEY, name TEXT UNIQUE, data BLOB);
    CREATE TABLE IF NOT EXISTS tallies(name TEXT);
    CREATE TABLE IF NOT EXISTS notes(name TEXT);
    CREATE TABLE IF NOT EXISTS stored(store TEXT, name TEXT);
  SQL

  def setup
    @dir = Dir.mktmpdir("plastic-database")
    @database = Database.new(File.join(@dir, "work_graph.db"), SCHEMA)
  end

  def teardown = FileUtils.remove_entry(@dir)

  def insert(name, table: :routine_runs)
    @database.transaction { |batch| batch.insert(table, {name:}) }
  end

  def test_open_all_needs_sqlite3_on_the_path
    error = assert_raises(Database::Error) { Database.open_all(@dir, path: "") }

    assert_equal "sqlite3 is not on PATH; install it, then call again", error.message
  end

  def test_open_all_opens_the_work_graph_at_the_home
    databases = Database.open_all(@dir)

    assert_equal [:work], databases.keys
    assert_equal File.join(@dir, "work_graph.db"), databases[:work].path
  end

  def test_literals_quote_every_kind_of_value
    values = [nil, true, false, 3, 1.5, Database::Bytes.new("ab"), {"a" => 1}, [1], "it's"]

    assert_equal ["NULL", "1", "0", "3", "1.5", "X'6162'", %('{"a":1}'), "'[1]'", "'it''s'"],
      values.map { |value| Database.literal(value) }
  end

  def test_a_name_is_quoted
    assert_equal %("say ""hi"""), Database.name(%(say "hi"))
  end

  def test_bind_fills_known_names_only
    assert_equal "SELECT 'a' WHERE b = :b AND c::text", Database.bind("SELECT :a WHERE b = :b AND c::text", a: "a")
  end

  def test_bind_with_no_values_leaves_the_sql
    assert_equal "SELECT :a", Database.bind("SELECT :a", {})
  end

  def test_the_schema_is_made_on_the_first_read
    assert_empty @database.rows("SELECT name FROM notes")
  end

  def test_rows_and_row_read_with_values
    insert("a")
    insert("b")

    assert_equal [{"name" => "a"}, {"name" => "b"}], @database.rows("SELECT name FROM routine_runs ORDER BY id")
    assert_equal({"name" => "b"}, @database.row("SELECT name FROM routine_runs WHERE name = :name", name: "b"))
  end

  def test_an_empty_transaction_runs_nothing
    assert_empty(@database.transaction { |_batch| nil })
    refute_path_exists @database.path
  end

  def test_returning_rows_come_back_in_order
    returned = @database.transaction do |batch|
      batch.write(:routine_runs, "INSERT INTO routine_runs(name) VALUES (:name) RETURNING name", name: "a")
      batch.write(:routine_runs, "INSERT INTO routine_runs(name) VALUES (:name) RETURNING name", name: "b")
    end

    assert_equal [[{"name" => "a"}], [{"name" => "b"}]], returned
  end

  def test_a_conflict_clause_skips_the_duplicate
    insert("a")
    @database.transaction { |batch| batch.insert(:routine_runs, {name: "a"}, conflict: "NOTHING") }

    assert_equal 1, @database.row("SELECT count(*) AS n FROM routine_runs")["n"]
  end

  def test_a_store_goes_first_in_the_row
    @database.transaction { |batch| batch.insert(:stored, {name: "x"}, store: "plastic") }

    assert_equal({"store" => "plastic", "name" => "x"}, @database.row("SELECT * FROM stored"))
  end

  def test_nothing_written_has_no_phrase
    assert_nil @database.written_phrase
  end

  def test_one_table_written_is_one_phrase
    insert("a")
    insert("b")

    assert_equal "2 routine runs in work_graph.db", @database.written_phrase
  end

  def test_two_tables_join_with_and
    insert("a")
    insert("t", table: :tallies)

    assert_equal "1 routine run and 1 tallies in work_graph.db", @database.written_phrase
  end

  def test_three_tables_join_with_commas
    insert("a")
    insert("t", table: :tallies)
    insert("n", table: :notes)

    assert_equal "1 routine run, 1 tallies, and 1 notes in work_graph.db", @database.written_phrase
  end

  def test_an_uncounted_write_is_kept_off_the_phrase
    @database.transaction { |batch| batch.write(:notes, "INSERT INTO notes VALUES ('x')", count: false) }

    assert_nil @database.written_phrase
  end

  def test_a_write_that_changes_nothing_counts_nothing
    @database.transaction { |batch| batch.write(:notes, "DELETE FROM notes") }

    assert_nil @database.written_phrase
  end

  def test_bytes_go_in_as_a_blob
    @database.transaction { |batch| batch.insert(:routine_runs, {name: "b", data: Database::Bytes.new("hi")}) }

    assert_equal "hi", @database.row("SELECT CAST(data AS TEXT) AS t FROM routine_runs")["t"]
  end

  def test_an_sql_error_names_the_file
    error = assert_raises(Database::Error) { @database.rows("SELECT nope FROM notes") }

    assert_match(/\Awork_graph\.db: .*no such column: nope/, error.message)
  end

  def test_the_schema_names_routine_runs_one_and_many
    assert_equal ["routine run", "routine runs", "x"],
      [Plastic::Graph::Schema.noun(:routine_runs, 1), Plastic::Graph::Schema.noun("routine_runs", 2), Plastic::Graph::Schema.noun(:x, 1)]
  end

  def test_the_work_schema_holds_the_routine_runs_table
    assert_includes Plastic::Graph::Schema.fetch(:work), "CREATE TABLE IF NOT EXISTS routine_runs("
  end
end
