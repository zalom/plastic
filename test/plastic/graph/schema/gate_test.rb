# frozen_string_literal: true

require_relative "../../../test_helper"

class SchemaGateTest < Plastic::TestCase
  include Beta2Store

  Behind = Plastic::Graph::Behind

  def store_database(home) = Plastic::Graph::Database.open_store(store_root(home), Plastic::Graph::Origin.new(home))

  def newest = Plastic::Graph::SchemaMigrator::VERSION

  def gate_of(connection) = Plastic::Graph::SchemaGate.new(connection, layouts: { "main" => :knowledge, "work" => :work, "retrieval" => :retrieval }, file: "knowledge_graph.db")

  def test_a_second_session_that_waited_for_the_lock_finds_the_tables_and_builds_nothing
    connection = SQLite3::Database.new(File.join(Dir.mktmpdir, "a.db"))
    connection.execute("CREATE TABLE taken (id)")

    assert_equal [false, 0], [gate_of(connection).send(:build_layout), connection.get_first_value("PRAGMA user_version")]
  end

  def test_a_file_that_is_not_a_database_is_not_called_behind
    path = File.join(Dir.mktmpdir, "knowledge_graph.db")
    File.write(path, "this is not a database" * 100)

    refute Plastic::Graph::SchemaGate.behind?(path, [])
  end

  def test_a_lost_attached_file_is_built_again_empty_and_the_stamp_stays
    connection = SQLite3::Database.new(File.join(Dir.mktmpdir, "a.db"))
    connection.execute("ATTACH DATABASE ? AS retrieval", [File.join(Dir.mktmpdir, "r.db")])
    connection.execute("CREATE TABLE taken (id)")
    connection.execute("PRAGMA user_version = #{newest}")
    Plastic::Graph::SchemaGate.new(connection, layouts: { nil => :knowledge, "retrieval" => :retrieval }, file: "a.db").call

    assert_includes connection.execute("SELECT name FROM retrieval.sqlite_master").flatten, "document_passages"
  end

  def test_a_new_empty_store_gets_the_declared_schema_and_the_newest_stamp_on_its_knowledge_file
    root = File.join(Dir.mktmpdir, "stores", "new")
    FileUtils.mkdir_p(root)
    store_database_at(root).rows("SELECT 1")

    assert_equal newest, stamp_of(File.join(root, "knowledge_graph.db"))
  end

  def store_database_at(root) = Plastic::Graph::Database.open_store(root, Plastic::Graph::Origin.new(@plastic_home))

  def test_a_store_behind_the_code_is_refused_and_no_file_appears_and_no_byte_changes
    home = beta_2_home(references: false)
    before = beta_2_files(home)

    assert_raises(Behind) { store_database(home).rows("SELECT 1") }
    assert_equal before, beta_2_files(home)
  end

  def test_the_refusal_names_the_update_command
    home = beta_2_home
    error = assert_raises(Behind) { store_database(home).rows("SELECT 1") }

    assert_equal "plastic update", error.next_command
  end

  def test_a_store_newer_than_the_code_is_refused
    home = Plastic::Graph.create(home: @plastic_home, store: "alpha") && @plastic_home
    Plastic::Graph::Database::ConnectionPool.release(store_root(home))
    SQLite3::Database.new(store_path(home, "knowledge_graph.db")).tap { |db| db.execute("PRAGMA user_version = 99") }.close

    assert_raises(Plastic::Graph::Ahead) { store_database(home).rows("SELECT 1") }
  end

  def finish_rival(rival)
    rival.execute("PRAGMA user_version = #{newest}")
    rival.execute("COMMIT")
    true
  end

  def test_a_session_that_waits_for_the_write_lock_finds_the_store_current
    home = beta_2_home
    rival = SQLite3::Database.new(store_path(home, "knowledge_graph.db"))
    rival.execute("BEGIN IMMEDIATE")
    waiting = SQLite3::Database.new(store_path(home, "knowledge_graph.db"))
    waiting.busy_handler { |_count| finish_rival(rival) }
    gate_of(waiting).call

    assert_equal newest, waiting.get_first_value("PRAGMA user_version")
  end

  def test_a_session_that_waits_and_still_finds_the_store_behind_is_refused
    home = beta_2_home
    rival = SQLite3::Database.new(store_path(home, "knowledge_graph.db"))
    rival.execute("BEGIN IMMEDIATE")
    waiting = SQLite3::Database.new(store_path(home, "knowledge_graph.db"))
    waiting.busy_handler do |_count|
      rival.execute("COMMIT")
      true
    end

    assert_raises(Behind) { gate_of(waiting).call }
  end

  def test_a_session_whose_wait_for_the_write_lock_gives_up_is_refused_as_busy_and_behind
    home = beta_2_home
    rival = SQLite3::Database.new(store_path(home, "knowledge_graph.db"))
    rival.execute("BEGIN IMMEDIATE")
    waiting = SQLite3::Database.new(store_path(home, "knowledge_graph.db"))
    waiting.busy_handler { |_count| false }
    error = assert_raises(Behind) { gate_of(waiting).call }

    assert_includes error.message, "is busy and behind this code"
    rival.execute("ROLLBACK")
  end
end

class SchemaBehindCommandTest < Plastic::TestCase
  include Beta2Store

  def test_a_command_on_a_behind_store_exits_3_names_the_update_command_and_changes_no_byte_of_the_store
    home = beta_2_home
    before = beta_2_files(home)
    result = plastic("intent", "new", "Gamma", "--project", "alpha", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE)

    assert_equal 3, result.code
    assert_includes result.err, "plastic update"
    assert_equal before, beta_2_files(home)
  end

  def test_a_hook_on_a_behind_store_prints_one_line_and_exits_0
    home = beta_2_home
    cwd = YAML.load_file(File.join(home, "projects.yml")).dig("projects", "alpha", "path")
    result = plastic("hook", "start", input: JSON.generate({ cwd: }), env: { "PLASTIC_HOME" => home, "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

    assert_equal [0, 1], [result.code, result.err.lines.size]
  end
end
