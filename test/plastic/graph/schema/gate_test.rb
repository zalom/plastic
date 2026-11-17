# frozen_string_literal: true

require_relative "../../../test_helper"

class SchemaGateTest < Plastic::TestCase
  include BackupHomes
  include OldLayoutHomes

  Behind = Plastic::Graph::Behind
  Sequences = Plastic::Graph::SchemaSequences

  def store_database(home, key = :work) = Plastic::Graph::Database.open_store(File.join(home, "stores", "alpha"), Plastic::Graph::Origin.new(home)).fetch(key)

  def test_a_second_session_that_waited_for_the_lock_finds_the_tables_and_builds_nothing
    connection = SQLite3::Database.new(File.join(Dir.mktmpdir, "a.db"))
    connection.execute("CREATE TABLE taken (id)")
    gate = Plastic::Graph::SchemaGate.new(connection, sequence: :store, key: :work, file: "a.db")

    assert_equal [false, 0], [gate.send(:build_layout), connection.get_first_value("PRAGMA user_version")]
  end

  def test_a_new_empty_database_gets_the_declared_schema_and_the_newest_stamp
    root = File.join(Dir.mktmpdir, "stores", "new")
    FileUtils.mkdir_p(root)
    database = Plastic::Graph::Database.open_store(root, Plastic::Graph::Origin.new(@plastic_home)).fetch(:work)
    database.rows("SELECT 1")

    assert_equal Sequences.newest(:store), SQLite3::Database.new(File.join(root, "work_graph.db")).get_first_value("PRAGMA user_version")
  end

  def test_the_layouts_of_an_old_home_differ_from_those_of_a_new_one
    layouts = ->(home) { database_files(home).map { |path| layout_of(path) } }

    refute_equal layouts.call(fresh_home), layouts.call(old_layout(fresh_home))
  end

  def test_a_database_behind_its_sequence_is_refused_and_no_byte_changes
    home = old_layout(fresh_home)
    before = file_bytes(home)

    assert_raises(Behind) { store_database(home).rows("SELECT 1") }
    assert_equal before, file_bytes(home)
  end

  def test_the_refusal_names_the_update_command
    home = old_layout(fresh_home)
    error = assert_raises(Behind) { store_database(home).rows("SELECT 1") }

    assert_equal "plastic update", error.next_command
  end

  def test_a_database_newer_than_the_code_is_refused
    home = fresh_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    SQLite3::Database.new(store_file(home, "work_graph")).tap { |db| db.execute("PRAGMA user_version = 99") }.close

    assert_raises(Plastic::Graph::Ahead) { store_database(home).rows("SELECT 1") }
  end

  def finish_rival(rival)
    rival.execute("PRAGMA user_version = #{Sequences.newest(:store)}")
    rival.execute("COMMIT")
    true
  end

  def test_a_session_that_waits_for_the_write_lock_finds_the_store_current
    home = old_layout(fresh_home)
    path = store_file(home, "work_graph")
    rival = SQLite3::Database.new(path)
    rival.execute("BEGIN IMMEDIATE")
    waiting = SQLite3::Database.new(path)
    waiting.busy_handler { |_count| finish_rival(rival) }
    Plastic::Graph::SchemaGate.new(waiting, sequence: :store, key: :work, file: "work_graph.db").call

    assert_equal Sequences.newest(:store), waiting.get_first_value("PRAGMA user_version")
  end

  def test_a_session_that_waits_and_still_finds_the_store_behind_is_refused
    home = old_layout(fresh_home)
    path = store_file(home, "work_graph")
    rival = SQLite3::Database.new(path)
    rival.execute("BEGIN IMMEDIATE")
    waiting = SQLite3::Database.new(path)
    waiting.busy_handler do |_count|
      rival.execute("COMMIT")
      true
    end

    assert_raises(Behind) { Plastic::Graph::SchemaGate.new(waiting, sequence: :store, key: :work, file: "work_graph.db").call }
  end

  def test_a_session_whose_wait_for_the_write_lock_gives_up_is_refused_as_busy_and_behind
    home = old_layout(fresh_home)
    path = store_file(home, "work_graph")
    rival = SQLite3::Database.new(path)
    rival.execute("BEGIN IMMEDIATE")
    waiting = SQLite3::Database.new(path)
    waiting.busy_handler { |_count| false }
    error = assert_raises(Behind) { Plastic::Graph::SchemaGate.new(waiting, sequence: :store, key: :work, file: "work_graph.db").call }

    assert_includes error.message, "is busy and behind this code"
    rival.execute("ROLLBACK")
  end
end

class SchemaBehindCommandTest < Plastic::TestCase
  include BackupHomes
  include OldLayoutHomes

  def behind_home
    home = fresh_home
    seed_store(home, "global")
    old_layout(home).tap do
      Plastic::Graph::SchemaRunner.new(home:, now: Time.utc(2026, 1, 1)).call
      Plastic::Graph::Database::ConnectionPool.release(home)
      SQLite3::Database.new(store_file(home, "work_graph")).tap { |db| db.execute("PRAGMA user_version = 0") }.close
    end
  end

  def test_a_command_on_a_behind_store_exits_3_names_the_update_command_and_changes_no_store_byte
    home = behind_home
    before = file_bytes(home).reject { |path, _| path.end_with?("plastic.db") }
    result = plastic("intent", "new", "Gamma", "--project", "alpha", env: env_for(home), table: Plastic::CLI::TABLE)

    assert_equal 3, result.code
    assert_includes result.err, "plastic update"
    assert_equal before, file_bytes(home).reject { |path, _| path.end_with?("plastic.db") }
  end

  def test_a_hook_on_a_behind_store_prints_one_line_and_exits_0
    home = behind_home
    result = plastic("hook", "start", input: JSON.generate({ cwd: YAML.load_file(File.join(home, "projects.yml")).dig("projects", "alpha", "path") }),
      env: env_for(home).merge("PLASTIC_SESSION" => "s-1"), table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    assert_equal 1, result.err.lines.size
  end

  def finish_rival(rival)
    rival.execute("PRAGMA user_version = #{Sequences.newest(:store)}")
    rival.execute("COMMIT")
    true
  end
end
