# frozen_string_literal: true

require "tmpdir"
require_relative "../../../test_helper"

class SchemaStateTest < Plastic::TestCase
  include SchemaVersions

  SchemaState = Plastic::Graph::SchemaState
  SchemaMigration = Plastic::Graph::SchemaMigration
  BASELINE = Plastic::Graph::MIGRATIONS.baseline(:store)
  LATER = "20270101000000"
  ALL = Plastic::Graph::MIGRATIONS.versions(:store)
  NEWEST = ALL.last

  # Counts the statements a reader sends, so a test can tell how many queries a check takes.
  class Counting < SimpleDelegator
    attr_reader :count

    def initialize(database)
      super
      @count = 0
    end

    def get_first_value(...)
      @count += 1
      super
    end

    def execute(...)
      @count += 1
      super
    end
  end

  def setup
    super
    @path = File.join(Dir.mktmpdir("state", @home), "knowledge_graph.db")
    @database = SQLite3::Database.new(@path)
  end

  def teardown
    @database.close
    super
  end

  def longer = Plastic::Graph::MIGRATIONS.with(SchemaMigration.new(kind: :store, version: LATER, path: "/nowhere.sql"))

  def state(migrations: Plastic::Graph::MIGRATIONS) = SchemaState.new(@database, :store, migrations:).call

  def summary(reading) = [reading.name, reading.pending, reading.unknown, reading.number]

  def test_a_schema_migrations_table_with_no_version_column_raises_its_error
    @database.execute("CREATE TABLE schema_migrations (id INTEGER)")

    error = assert_raises(SQLite3::SQLException) { state }

    assert_includes error.message, "no such column: version"
  end

  def with_tables(stamp)
    @database.execute("CREATE TABLE intents (id)")
    @database.execute("PRAGMA user_version = #{stamp}")
  end

  def test_a_file_with_no_table_reads_empty_with_every_version_pending
    assert_equal [:empty, ALL, [], 0], summary(state)
  end

  def test_a_file_that_records_every_version_reads_current_at_the_newest_version
    record_versions(@path, ALL)

    assert_equal [:current, [], [], NEWEST.to_i], summary(state)
  end

  def test_a_file_that_lacks_a_known_version_reads_behind_and_names_it
    record_versions(@path, ALL)

    assert_equal [:behind, [LATER], [], NEWEST.to_i], summary(state(migrations: longer))
  end

  def test_a_file_that_records_an_unknown_version_reads_ahead_and_names_it
    record_versions(@path, [*ALL, UNKNOWN])

    assert_equal [:ahead, [], [UNKNOWN], UNKNOWN.to_i], summary(state)
  end

  def test_a_beta_2_file_with_tables_and_stamp_0_reads_behind_with_every_version_pending
    with_tables(0)

    assert_equal [:behind, [*ALL, LATER], [], 0], summary(state(migrations: longer))
  end

  def test_an_alpha_file_at_stamp_1_reads_behind_with_every_version_after_the_baseline_pending
    with_tables(1)

    assert_equal [:behind, [*ALL.drop(1), LATER], [], BASELINE.to_i], summary(state(migrations: longer))
  end

  def test_an_alpha_file_at_stamp_1_adopts_the_baseline
    with_tables(1)

    assert_equal [BASELINE], state.adopted
  end

  def test_the_kind_of_an_unknown_schema_key_is_refused
    assert_raises(KeyError) { SchemaState.kind_of(:nowhere) }
  end

  def test_a_file_ahead_of_this_code_is_refused_as_newer_than_this_code
    with_tables(7)

    error = assert_raises(Plastic::Graph::Ahead) { state.due?(Plastic::Graph::Ahead) }

    assert_equal "the database is newer than this code (it records user_version 7); run plastic update", error.message
  end

  def test_a_file_with_no_table_and_another_stamp_reads_ahead_and_names_the_stamp
    with_tables(7)

    assert_equal [:ahead, [], ["user_version 7"], 7], summary(state)
  end

  def test_the_check_of_a_current_file_is_one_query
    record_versions(@path, ALL)
    counting = Counting.new(@database)
    SchemaState.new(counting, :store).call

    assert_equal 1, counting.count
  end

  def test_a_file_read_by_its_path_keeps_every_byte
    record_versions(@path, ALL)
    before = File.binread(@path)

    assert_equal [:current, before], [SchemaState.of_file(@path, :store).name, File.binread(@path)]
  end

  def test_the_key_of_each_stamped_schema_names_its_kind_of_migrations
    assert_equal %i[home store], %i[local knowledge].map { |key| SchemaState.kind_of(key) }
  end
end
