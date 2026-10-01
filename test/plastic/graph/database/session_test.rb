# frozen_string_literal: true

require_relative "../../../test_helper"

class SessionTest < Plastic::TestCase
  Database = Plastic::Graph::Database
  Program = Database::Program

  def path = File.join(@home, "x.db")

  def test_calls_on_one_file_share_one_connection_until_a_disconnect
    Program.new.call(path, "CREATE TEMP TABLE t(a); INSERT INTO t VALUES (1);")

    assert_equal [[{ "a" => 1 }]], Program.new.call(path, "SELECT a FROM t")
    Program.disconnect
    assert_raises(Database::Error) { Program.new.call(path, "SELECT a FROM t;") }
  end

  def test_a_failed_script_rolls_back_and_the_next_call_works
    Program.new.call(path, "CREATE TABLE t(a);")
    assert_raises(Database::Error) { Program.new.call(path, "BEGIN IMMEDIATE; INSERT INTO t VALUES (1); SELECT nope; COMMIT;") }

    assert_equal [[{ "n" => 0 }]], Program.new.call(path, "SELECT count(*) AS n FROM t;")
  end

  def test_a_forked_child_opens_its_own_connection
    Program.new.call(path, "CREATE TEMP TABLE t(a);")
    reader, writer = IO.pipe
    child = fork { writer.write(Program.new.call(path, "SELECT count(*) AS n FROM sqlite_temp_master;").to_json) }
    writer.close
    Process.wait(child)

    assert_equal [[{ "n" => 0 }]], JSON.parse(reader.read)
  end
end
