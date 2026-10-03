# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/schema"

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

  private

  def migration_connection(revision_sql:, passage_sql:)
    Class.new do
      attr_reader :batches, :transactions

      define_method(:initialize) do
        @schemas = { "document_revisions" => revision_sql, "document_passages" => passage_sql }
        @batches = []
        @transactions = 0
      end

      define_method(:get_first_value) do |query|
        @schemas.fetch(query[/name = '([^']+)'/, 1])
      end

      define_method(:execute_batch) { |sql| @batches << sql }
      define_method(:transaction) { |_mode, &block| @transactions += 1; block.call }
    end.new
  end
end
