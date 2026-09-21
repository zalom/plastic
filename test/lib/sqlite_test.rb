# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require_relative "../../scripts/lib/sqlite"

class SqliteTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("plastic-sqlite")
    @db = File.join(@dir, "t.db")
    Plastic::Sqlite.call(@db, "CREATE TABLE t(a, b); INSERT INTO t VALUES (1, 'x'), (2, 'y');")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_rows_come_back_as_hashes
    assert_equal [{"a" => 1, "b" => "x"}, {"a" => 2, "b" => "y"}],
      Plastic::Sqlite.call(@db, "SELECT a, b FROM t ORDER BY a")
  end

  def test_no_rows_is_an_empty_list
    assert_empty Plastic::Sqlite.call(@db, "SELECT a FROM t WHERE a > 9")
  end

  def test_a_sql_error_raises_with_the_message_of_sqlite3
    error = assert_raises(Plastic::Sqlite::Error) { Plastic::Sqlite.call(@db, "SELECT nope FROM t") }

    assert_includes error.message, "no such column: nope"
  end

  def test_read_only_refuses_a_write
    error = assert_raises(Plastic::Sqlite::Error) do
      Plastic::Sqlite.call(@db, "DELETE FROM t", readonly: true)
    end

    assert_includes error.message, "readonly"
    assert_equal 2, Plastic::Sqlite.call(@db, "SELECT count(*) AS n FROM t").first["n"]
  end
end
