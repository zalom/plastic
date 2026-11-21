# frozen_string_literal: true

require "tmpdir"
require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/migration/row_key"

class RowKeyTest < Plastic::TestCase
  RowKey = Plastic::Graph::RowKey
  TABLES = <<~SQL
    CREATE TABLE log("id" INTEGER PRIMARY KEY, "intent_id" TEXT NOT NULL, "position" INTEGER NOT NULL, "at" TEXT,
      "origin_id" TEXT NOT NULL, UNIQUE("intent_id", "position", "origin_id"));
    CREATE TABLE notes("text" TEXT, "at" TEXT);
    CREATE UNIQUE INDEX notes_text ON notes("text") WHERE "text" IS NOT NULL;
    INSERT INTO log ("intent_id", "position", "at", "origin_id") VALUES ('7', 2, 'then', 'o');
  SQL

  def setup
    super
    @connection = Plastic::Graph::Database::Connection.open(File.join(Dir.mktmpdir("row-key", @home), "knowledge_graph.db"))
    @connection.execute_batch(TABLES)
  end

  def teardown
    @connection.close
    super
  end

  def test_the_key_of_a_row_is_the_json_array_of_the_columns_of_the_unique_index
    key = RowKey.new(@connection, "main", "log").expression

    assert_equal '["7",2,"o"]', @connection.get_first_value("SELECT #{key} FROM main.log")
  end

  def test_the_key_names_its_columns_through_the_alias_it_is_given
    key = RowKey.new(@connection, "main", "log").expression("live")

    assert_equal '["7",2,"o"]', @connection.get_first_value("SELECT #{key} FROM main.log AS live")
  end

  def test_a_table_with_only_a_partial_unique_index_has_no_key
    error = assert_raises(Plastic::Graph::Database::Error) { RowKey.new(@connection, "main", "notes").expression }

    assert_equal "main.notes has no unique key, so a migration cannot keep its old values by row", error.message
  end
end
