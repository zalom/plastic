# frozen_string_literal: true

require_relative "../../../test_helper"

class ConnectionPoolTest < Plastic::TestCase
  Database = Plastic::Graph::Database
  Pool = Database::ConnectionPool

  def path = File.join(@home, "pool", "x.db")

  def test_one_file_has_one_connection_until_a_disconnect
    first = Pool.for(path)

    assert_same first, Pool.for(path)
    Pool.disconnect

    refute_same first, Pool.for(path)
  end

  def test_a_disconnect_keeps_the_named_paths
    kept = Pool.for(path)
    Pool.disconnect(keep: [path])

    assert_same kept, Pool.for(path)
  end

  def test_a_connection_turns_foreign_keys_on_and_waits_when_busy
    connection = Pool.for(path)

    assert_equal [1, Database::Connection::BUSY_TIMEOUT],
      [connection.get_first_value("PRAGMA foreign_keys"), connection.get_first_value("PRAGMA busy_timeout")]
  end

  def test_a_file_the_pool_makes_is_listed_as_made_and_a_file_on_the_disk_is_not
    older = File.join(@home, "pool", "older.db")
    FileUtils.mkdir_p(File.dirname(older))
    SQLite3::Database.new(older).close
    Pool.for(older)
    Pool.for(path)

    assert_equal [true, false], [Pool.created.include?(path), Pool.created.include?(older)]
  end

  def test_read_binds_the_values_its_placeholders_name
    assert_equal [{ "a" => 7 }], Pool.for(path).read("SELECT :n AS a", n: 7, other: 1)
  end
end
