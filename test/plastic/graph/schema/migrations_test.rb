# frozen_string_literal: true

require "sqlite3"
require "delegate"
require "tmpdir"
require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/schema"

class SchemaMigrationsTest < Minitest::Test
  def test_rebuilds_both_legacy_tables_in_an_immediate_transaction
    connection = migration_connection(revision_sql: 'UNIQUE("sha256", "origin_id")', passage_sql: "CREATE TABLE document_passages (sha256 TEXT)")

    Plastic::Graph::Schema.prepare(connection, "")

    assert_equal 2, connection.transactions
    migrations = connection.batches.reject(&:empty?)

    assert_equal %i[document_revisions document_passages], migrations.map { |sql| sql[/ALTER TABLE (\w+)/, 1].to_sym }
    assert migrations.all? { |sql| sql.include?("DROP TABLE") }
  end

  def test_leaves_current_or_missing_tables_unchanged
    connection = migration_connection(revision_sql: nil, passage_sql: 'CREATE TABLE document_passages ("intent_id" TEXT)')

    Plastic::Graph::Schema.prepare(connection, "")

    assert_equal [""], connection.batches
    assert_equal 0, connection.transactions
  end

  def test_a_database_with_no_intents_table_rebuilds_nothing
    connection = migration_connection(revision_sql: nil, passage_sql: nil)

    Plastic::Graph::Schema.prepare(connection, "")

    assert_equal [0, [""]], [connection.transactions, connection.batches]
  end

  private

  def migration_connection(revision_sql:, passage_sql:)
    SchemaMigrationConnection.new("document_revisions" => revision_sql, "document_passages" => passage_sql, "intents" => nil)
  end
end

class SchemaMigrationConnection
  attr_reader :batches, :transactions

  def initialize(schemas)
    @schemas = schemas
    @batches = []
    @transactions = 0
  end

  def get_first_value(query) = @schemas.fetch(query[/name = '([^']+)'/, 1])

  def execute_batch(sql) = @batches << sql

  def transaction(_mode)
    @transactions += 1
    yield
  end
end

class SchemaIntentStatesMigrationTest < Minitest::Test
  OLD_INTENTS = <<~SQL
    CREATE TABLE "intents"("id" INTEGER PRIMARY KEY AUTOINCREMENT, "intent_id" TEXT NOT NULL, "parent_id" TEXT, "ref" TEXT,
      "origin_id" TEXT NOT NULL, "slug" TEXT NOT NULL, "title" TEXT NOT NULL, "kind" TEXT,
      "status" TEXT NOT NULL CHECK(status IN ('open', 'active', 'parked', 'future', 'done', 'abandoned')),
      "disposition" TEXT, "opened_at" TEXT, "closed_at" TEXT, "updated_at" TEXT, UNIQUE("intent_id", "origin_id"));
  SQL

  ROWS = [[1, "active", nil], [2, "done", "shipped on friday"], [3, "abandoned", "superseded by intent 9"],
    [4, "abandoned", "dropped by the owner"], [5, "open", "left over"], [6, "parked", nil], [7, "future", nil]].freeze

  def setup
    @database = SQLite3::Database.new(":memory:")
    @database.execute_batch(OLD_INTENTS)
    ROWS.each do |id, status, disposition|
      @database.execute("INSERT INTO intents (id, intent_id, origin_id, slug, title, status, disposition) VALUES (?, ?, 'o', 's', 't', ?, ?)",
        [id, id.to_s, status, disposition])
    end
    @database.execute("INSERT INTO intents (id, intent_id, origin_id, slug, title, status) VALUES (8, '8', 'o', 's', 't', 'open')")
    @database.execute("DELETE FROM intents WHERE id = 8")
    @connection = CountingConnection.new(@database)
  end

  def prepare = Plastic::Graph::Schema.prepare(@connection, Plastic::Graph::Schema.fetch(:work))

  def intents = @database.execute("SELECT id, status, disposition, reason FROM intents ORDER BY id")

  def test_the_old_word_for_work_under_way_becomes_in_progress_and_the_ids_stay
    prepare

    assert_equal [[1, "in_progress"], [2, "done"], [3, "abandoned"], [4, "abandoned"], [5, "open"], [6, "parked"], [7, "future"]],
      intents.map { |id, status| [id, status] }
  end

  def test_the_new_state_passes_the_status_check
    prepare
    @database.execute("INSERT INTO intents (intent_id, origin_id, slug, title, status) VALUES ('9', 'o', 's', 't', 'in_progress')")

    assert_equal "in_progress", @database.get_first_value("SELECT status FROM intents WHERE intent_id = '9'")
  end

  def test_free_text_in_the_disposition_moves_to_the_reason
    prepare

    assert_equal [[2, "delivered", "shipped on friday"], [3, "superseded", "superseded by intent 9"],
      [4, "cancelled", "dropped by the owner"], [5, nil, "left over"], [6, nil, nil]],
      intents.select { |id, _status| id > 1 && id < 7 }.map { |id, _status, disposition, reason| [id, disposition, reason] }
  end

  def test_a_done_intent_without_text_is_delivered
    @database.execute("UPDATE intents SET disposition = NULL WHERE id = 2")
    prepare

    assert_equal ["delivered", nil], @database.get_first_row("SELECT disposition, reason FROM intents WHERE id = 2")
  end

  def test_a_database_without_the_intents_table_gets_the_current_one
    @database.execute("DROP TABLE intents")
    prepare

    assert_includes @database.execute("PRAGMA table_info(intents)").map { |column| column[1] }, "reason"
  end

  def test_the_sequence_of_the_ids_is_kept
    prepare
    @database.execute("INSERT INTO intents (intent_id, origin_id, slug, title, status) VALUES ('9', 'o', 's', 't', 'open')")

    assert_equal 9, @database.get_first_value("SELECT id FROM intents WHERE intent_id = '9'")
  end

  def test_a_table_with_neither_the_old_word_nor_the_reason_is_rebuilt
    @database.execute("DROP TABLE intents")
    @database.execute(OLD_INTENTS.sub("'open', 'active',", "'open', 'in_progress',"))
    prepare

    assert_includes @database.execute("PRAGMA table_info(intents)").map { |column| column[1] }, "reason"
  end

  def test_a_table_another_process_rebuilt_in_the_meantime_is_left_alone
    @connection = RebuiltMeanwhileConnection.new(@database)
    prepare

    assert_equal 1, @connection.transactions
    refute_includes @database.execute("PRAGMA table_info(intents)").map { |column| column[1] }, "reason"
  end

  def test_a_database_file_keeps_its_sequence_above_the_highest_id_after_the_rebuild
    Dir.mktmpdir("plastic-sequence-test") do |dir|
      file = SQLite3::Database.new(File.join(dir, "work.db"))
      file.execute_batch(OLD_INTENTS)
      (1..3).each { |id| file.execute("INSERT INTO intents (id, intent_id, origin_id, slug, title, status) VALUES (?, ?, 'o', 's', 't', 'open')", [id, id.to_s]) }
      file.execute("DELETE FROM intents WHERE id = 3")
      Plastic::Graph::Schema.prepare(CountingConnection.new(file), Plastic::Graph::Schema.fetch(:work))
      file.execute("INSERT INTO intents (intent_id, origin_id, slug, title, status) VALUES ('4', 'o', 's', 't', 'open')")

      assert_equal [2, 4], [file.get_first_value("SELECT MAX(id) FROM intents WHERE intent_id != '4'"), file.get_first_value("SELECT id FROM intents WHERE intent_id = '4'")]
      file.close
    end
  end

  def test_a_second_prepare_rebuilds_nothing
    prepare
    before = @connection.transactions
    ddl = @database.get_first_value("SELECT sql FROM sqlite_master WHERE name = 'intents'")
    prepare

    assert_equal [before, ddl], [@connection.transactions, @database.get_first_value("SELECT sql FROM sqlite_master WHERE name = 'intents'")]
  end

  def test_a_database_made_with_the_current_schema_is_not_rebuilt
    current = CountingConnection.new(SQLite3::Database.new(":memory:"))
    Plastic::Graph::Schema.prepare(current, Plastic::Graph::Schema.fetch(:work))

    assert_equal 0, current.transactions
  end
end

class RebuiltMeanwhileConnection < SimpleDelegator
  attr_reader :transactions

  def initialize(connection)
    super
    @transactions = 0
    @asked = 0
  end

  def get_first_value(query)
    value = super
    return value unless query.include?("name = 'intents'")

    @asked += 1
    (@asked == 1) ? value : '"reason"'
  end

  def transaction(*, &)
    @transactions += 1
    __getobj__.transaction(*, &)
  end
end

class CountingConnection < SimpleDelegator
  attr_reader :transactions

  def initialize(connection)
    super
    @transactions = 0
  end

  def transaction(*, &)
    @transactions += 1
    __getobj__.transaction(*, &)
  end
end
