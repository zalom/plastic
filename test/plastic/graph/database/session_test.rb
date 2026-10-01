# frozen_string_literal: true

require_relative "../../../test_helper"

class SessionTest < Plastic::TestCase
  Database = Plastic::Graph::Database
  Program = Database::Program
  Session = Database::Session

  # A query that runs for seconds: it counts to a hundred million.
  SLOW = "WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c WHERE x < 100000000) SELECT count(*) FROM c;"

  def path = File.join(@home, "x.db")

  def test_calls_on_one_file_share_one_connection_until_a_disconnect
    Program.new.call(path, "CREATE TEMP TABLE t(a); INSERT INTO t VALUES (1);")

    assert_equal [[{ "a" => 1 }]], Program.new.call(path, "SELECT a FROM t")
    Program.disconnect
    assert_raises(Database::Error) { Program.new.call(path, "SELECT a FROM t;") }
  end

  def test_a_failed_statement_raises_its_line_and_rolls_back
    Program.new.call(path, "CREATE TABLE t(a);")
    error = assert_raises(Database::Error) { Program.new.call(path, "BEGIN IMMEDIATE; INSERT INTO t VALUES (1); SELECT nope;") }

    assert_match(/\Ax\.db: Parse error near line \d+: no such column: nope\z/, error.message)
    assert_equal [[{ "n" => 0 }]], Program.new.call(path, "SELECT count(*) AS n FROM t;")
  end

  def test_the_connection_survives_a_failed_statement
    Program.new.call(path, "CREATE TEMP TABLE t(a);")
    assert_raises(Database::Error) { Program.new.call(path, "INSERT INTO t VALUES (1, 2);") }

    assert_equal [[{ "n" => 0 }]], Program.new.call(path, "SELECT count(*) AS n FROM t;")
  end

  def test_a_call_with_no_answer_by_the_deadline_raises
    session = Session.new(path, deadline: 0.2)
    error = assert_raises(Database::Error) { session.call(SLOW) }

    assert_equal "x.db: sqlite3 gave no answer in 0.2 s", error.message
  end

  def test_a_session_whose_process_ended_raises
    session = Session.new(path)
    session.close

    assert_raises(Database::Error, IOError) { session.call("SELECT 1;") }
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
