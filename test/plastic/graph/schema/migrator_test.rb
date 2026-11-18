# frozen_string_literal: true

require "tmpdir"
require_relative "../../../test_helper"
require_relative "../../../test_helpers/beta_2_store"
require_relative "../../../test_helpers/schema_versions"
Plastic::TestCase.boot

module MigratorFixtures
  include SchemaVersions

  Migrator = Plastic::Graph::SchemaMigrator
  Connection = Plastic::Graph::Database::Connection
  SchemaMigration = Plastic::Graph::SchemaMigration
  MigrationList = Plastic::Graph::MigrationList
  FIXTURES = File.expand_path("../../../fixtures/migrations", __dir__)
  FIRST = "20261117000000"
  SECOND = "20270101000000"

  def migration(version, name) = SchemaMigration.new(kind: :store, version:, path: File.join(FIXTURES, "#{name}.sql"))

  # The later migration comes first, so the list proves its own order.
  def tickets_then_owners = MigrationList.new([migration(SECOND, "add_owners"), migration(FIRST, "add_tickets")])

  def tickets_then_failure = MigrationList.new([migration(FIRST, "add_tickets"), migration(SECOND, "fail_on_first_ticket")])

  def tickets_only = MigrationList.new([migration(FIRST, "add_tickets")])

  def migrator(connection, list) = Migrator.new(connection, :store, migrations: list)

  def tables(connection = @connection) = connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'").map { |row| row["name"] }
end

class SchemaMigratorTest < Plastic::TestCase
  include MigratorFixtures

  def setup
    super
    @path = File.join(Dir.mktmpdir("migrator", @home), "store.db")
    @connection = Connection.open(@path)
    @connection.execute("CREATE TABLE legacy (id)")
  end

  def teardown
    @connection.close
    super
  end

  def owners = @connection.execute("SELECT title, owner FROM tickets").map { |row| row.values_at("title", "owner") }

  def test_pending_migrations_run_in_ascending_order_and_record_each_version
    migrator(@connection, tickets_then_owners).call

    assert_equal [[%w[first ada]], [FIRST, SECOND]], [owners, recorded_versions(@path)]
  end

  def test_a_second_run_applies_nothing
    migrator(@connection, tickets_then_owners).call
    @connection.execute("INSERT INTO tickets(title) VALUES ('later')")
    migrator(@connection, tickets_then_owners).call

    assert_equal [%w[first ada], ["later", nil]], owners
  end

  def test_a_failing_second_migration_rolls_back_the_whole_run_and_records_no_version
    assert_raises(SQLite3::ConstraintException) { migrator(@connection, tickets_then_failure).call }

    assert_equal [%w[legacy], nil], [tables, recorded_versions(@path)]
  end

  def test_a_recorded_version_is_skipped_and_only_the_later_one_runs
    migrator(@connection, tickets_only).call
    migrator(@connection, tickets_then_owners).call

    assert_equal [[%w[first ada]], [FIRST, SECOND]], [owners, recorded_versions(@path)]
  end

  def test_an_alpha_file_at_stamp_1_gets_the_baseline_row_and_runs_no_sql
    @connection.execute("PRAGMA user_version = 1")
    migrator(@connection, tickets_only).call

    assert_equal [%w[legacy schema_migrations], [FIRST]], [tables.sort, recorded_versions(@path)]
  end

  def test_a_file_that_records_an_unknown_version_raises_ahead_naming_it_and_stays_unchanged
    record_unknown_version(@path)
    before = File.binread(@path)

    error = assert_raises(Plastic::Graph::Ahead) { migrator(@connection, tickets_only).call }

    assert_includes error.message, UNKNOWN
    assert_equal before, File.binread(@path)
  end

  def test_a_file_with_no_table_and_an_unknown_stamp_raises_ahead_naming_the_stamp
    @connection.execute("PRAGMA user_version = 7")

    error = assert_raises(Plastic::Graph::Ahead) { migrator(@connection, tickets_only).call }

    assert_includes error.message, "user_version 7"
    assert_equal %w[legacy], tables
  end
end

class SchemaMigratorRaceTest < Plastic::TestCase
  include MigratorFixtures

  # Another session records the versions just before this runner takes the write lock.
  class MigratedBeforeLock < SimpleDelegator
    def initialize(connection, path, versions)
      super(connection)
      @path = path
      @versions = versions
    end

    def atomically(&)
      SQLite3::Database.open(@path) do |other|
        other.execute(Plastic::Graph::SchemaMigrator::TABLE)
        @versions.each { |version| other.execute(Plastic::Graph::SchemaMigrator::INSERT, [version]) }
      end
      super
    end
  end

  def setup
    super
    @path = File.join(Dir.mktmpdir("migrator", @home), "store.db")
    @connection = Connection.open(@path)
    @connection.execute("CREATE TABLE legacy (id)")
  end

  def teardown
    @connection.close
    super
  end

  def test_a_runner_that_finds_the_versions_recorded_once_it_holds_the_write_lock_runs_no_migration
    late = MigratedBeforeLock.new(@connection, @path, [FIRST])

    assert_nil migrator(late, tickets_only).call
    assert_equal %w[legacy schema_migrations], tables.sort
  end
end

class SchemaMigratorJournalTest < Plastic::TestCase
  include MigratorFixtures
  include Beta2Store

  def store_connection(home, knowledge)
    connection = Plastic::Graph::Database::ConnectionPool.for(knowledge, attach: Plastic::Graph::Database::Store.attachments(knowledge))
    connection.execute("ATTACH DATABASE ? AS refs", [store_path(home, "references.db")])
    connection
  end

  def test_every_attached_file_of_a_store_is_in_delete_journal_mode_during_the_run
    home = beta_2_home
    knowledge = store_path(home, "knowledge_graph.db")
    connection = store_connection(home, knowledge)
    list = Plastic::Graph::MIGRATIONS.with(migration(SECOND, "observe_journal_modes"))
    migrator(connection, list).call
    modes = connection.execute("SELECT schema, mode FROM observed_journal_modes ORDER BY schema").map { |row| row.values_at("schema", "mode") }

    assert_equal [%w[main delete], %w[refs delete], %w[retrieval delete], %w[work delete]], modes
  ensure
    Plastic::Graph::Database::ConnectionPool.release(store_root(home)) if home
  end
end
