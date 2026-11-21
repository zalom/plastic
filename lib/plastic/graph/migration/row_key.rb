# frozen_string_literal: true

require_relative "../database"

module Plastic
  module Graph
    # The key of one row of a live table, as SQL: a json_array of the columns of the first full unique index of the
    # table, so a value kept in legacy.db finds its own row again. Docs: docs/contributing/MIGRATIONS.md.
    class RowKey
      def initialize(connection, schema, table)
        @connection = connection
        @schema = schema
        @table = table
      end

      # The key of each row, its columns named through `prefix`, the name or alias of the table, when one is given.
      def expression(prefix = nil) = "json_array(#{columns.map { |column| [prefix, %("#{column}")].compact.join(".") }.join(", ")})"

      private

      def columns = (@columns ||= @connection.execute(%(PRAGMA #{@schema}.index_info("#{index}"))).sort_by { |row| row.fetch("seqno") }.map { |row| row.fetch("name") })

      def index
        unique = @connection.execute(%(PRAGMA #{@schema}.index_list("#{@table}"))).find { |row| row.fetch("unique") == 1 && row.fetch("partial").zero? }
        raise Database::Error, "#{@schema}.#{@table} has no unique key, so a migration cannot keep its old values by row" unless unique

        unique.fetch("name")
      end
    end
  end
end
