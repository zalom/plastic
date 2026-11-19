# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/beta_2_store"

class SchemaGateTest < Plastic::TestCase
  include Beta2Store
  include SchemaVersions

  Behind = Plastic::Graph::Behind
  STORE_VERSIONS = Plastic::Graph::MIGRATIONS.versions(:store)

  def store_database(home) = Plastic::Graph::Database.open_store(store_root(home), Plastic::Graph::Origin.new(home))

  def gate_of(connection) = Plastic::Graph::SchemaGate.new(connection, layouts: { "main" => :knowledge, "work" => :work, "retrieval" => :retrieval }, file: "knowledge_graph.db")

  def test_a_second_session_that_waited_for_the_lock_finds_the_tables_and_builds_nothing
    connection = SQLite3::Database.new(File.join(Dir.mktmpdir, "a.db"))
    connection.execute("CREATE TABLE taken (id)")

    assert_equal [false, nil], [gate_of(connection).send(:build_layout), recorded_versions(connection.filename)]
  end

  def test_a_file_that_is_not_a_database_is_not_called_behind
    path = File.join(Dir.mktmpdir, "knowledge_graph.db")
    File.write(path, "this is not a database" * 100)

    refute Plastic::Graph::SchemaGate.behind?(path, [])
  end

  def test_a_lost_attached_file_is_built_again_empty_and_the_recorded_versions_stay
    path = File.join(Dir.mktmpdir, "a.db")
    record_versions(path, STORE_VERSIONS)
    connection = SQLite3::Database.new(path)
    connection.execute("ATTACH DATABASE ? AS retrieval", [File.join(Dir.mktmpdir, "r.db")])
    connection.execute("CREATE TABLE taken (id)")
    Plastic::Graph::SchemaGate.new(connection, layouts: { nil => :knowledge, "retrieval" => :retrieval }, file: "a.db").call

    assert_includes connection.execute("SELECT name FROM retrieval.sqlite_master").flatten, "document_passages"
    assert_equal STORE_VERSIONS, recorded_versions(path)
  end

  def test_a_new_empty_store_gets_the_declared_schema_and_records_every_store_version_on_its_knowledge_file
    root = File.join(Dir.mktmpdir, "stores", "new")
    FileUtils.mkdir_p(root)
    store_database_at(root).rows("SELECT 1")

    assert_equal STORE_VERSIONS, recorded_versions(File.join(root, "knowledge_graph.db"))
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

  def finish_rival(rival)
    rival.execute(Plastic::Graph::SchemaMigrator::TABLE)
    STORE_VERSIONS.each { |version| rival.execute(Plastic::Graph::SchemaMigrator::INSERT, [version]) }
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

    assert_equal STORE_VERSIONS, recorded_versions(store_path(home, "knowledge_graph.db"))
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

class SchemaGateAheadTest < Plastic::TestCase
  include Beta2Store
  include SchemaVersions

  Behind = Plastic::Graph::Behind

  def store_database(home) = Plastic::Graph::Database.open_store(store_root(home), Plastic::Graph::Origin.new(home))

  def created_home
    Plastic::Graph.create(home: @plastic_home, store: "alpha")
    Plastic::Graph::Database::ConnectionPool.release(store_root(@plastic_home))
    @plastic_home
  end

  def test_a_store_that_records_an_unknown_version_is_refused_naming_it_and_keeps_every_byte
    home = created_home
    record_unknown_version(store_path(home, "knowledge_graph.db"))
    before = beta_2_files(home)
    error = assert_raises(Plastic::Graph::Ahead) { store_database(home).rows("SELECT 1") }

    assert_equal [true, true], [error.message.include?("is newer than this code"), error.message.include?(UNKNOWN)]
    assert_equal before, beta_2_files(home)
  end

  def test_a_store_with_no_table_of_migrations_and_an_unknown_stamp_is_refused_naming_the_stamp
    home = created_home
    SQLite3::Database.open(store_path(home, "knowledge_graph.db")) { |db| db.execute_batch("DROP TABLE schema_migrations; PRAGMA user_version = 99") }

    error = assert_raises(Plastic::Graph::Ahead) { store_database(home).rows("SELECT 1") }

    assert_includes error.message, "user_version 99"
  end

  def test_an_alpha_store_at_stamp_1_is_refused_as_behind
    home = created_home
    SQLite3::Database.open(store_path(home, "knowledge_graph.db")) { |db| db.execute_batch("DROP TABLE schema_migrations; PRAGMA user_version = 1") }

    error = assert_raises(Behind) { store_database(home).rows("SELECT 1") }

    assert_includes error.message, "(it lacks #{(Plastic::Graph::MIGRATIONS.versions(:store) - Plastic::Graph::MIGRATIONS.held(:store)).join(", ")})"
  end

  def test_a_fresh_build_runs_no_migration_and_records_every_version_of_the_list
    path = File.join(Dir.mktmpdir, "plastic.db")
    connection = SQLite3::Database.new(path)
    failing = Plastic::Graph::SchemaMigration.new(kind: :home, version: "20990101000000", path: "/no/such/migration.sql")
    Plastic::Graph::SchemaGate.new(connection, layouts: { nil => :local }, file: "plastic.db", migrations: Plastic::Graph::MIGRATIONS.with(failing)).call

    assert_equal [*Plastic::Graph::MIGRATIONS.versions(:home), "20990101000000"], recorded_versions(path)
  end

  def test_a_command_on_a_store_newer_than_the_code_exits_3_names_the_version_and_changes_no_byte
    created_home
    File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  alpha:\n    path: #{Dir.mktmpdir}\n")
    record_unknown_version(store_path(@plastic_home, "knowledge_graph.db"))
    before = beta_2_files(@plastic_home)
    result = plastic("intent", "new", "Gamma", "--project", "alpha", env: { "PLASTIC_HOME" => @plastic_home }, table: Plastic::CLI::TABLE)

    assert_equal [3, true], [result.code, result.err.include?("refused")]
    assert_includes result.out, "because: knowledge_graph.db is newer than this code (it records #{UNKNOWN})"
    assert_equal before, beta_2_files(@plastic_home)
  end
end
