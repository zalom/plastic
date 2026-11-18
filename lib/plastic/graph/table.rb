# frozen_string_literal: true

require_relative "sql"

module Plastic
  module Graph
    # One table: its columns with their SQL types, and the key that names one
    # row. The statements that write a row are built here.
    Table = Data.define(:name, :columns, :key)

    # The statements of one table.
    class Table
      def ddl(schema = nil)
        parts = columns.map { |column, type| "#{SQL.name(column)} #{type}" }
        parts << "UNIQUE(#{SQL.names(key)})" unless key.empty?
        "CREATE TABLE IF NOT EXISTS #{SQL.qualified(schema, name)}(#{parts.join(", ")});"
      end

      def origin? = columns.key?(:origin_id)

      def insert(row) = SQL.insert(name, row)

      # An insert that updates the row its key names, column by column.
      def upsert(row) = SQL.insert(name, row, " ON CONFLICT(#{SQL.names(key)}) DO #{update_action(row)}")

      # Machine state that the report leaves out: the printed hashes.
      def counted? = name != :printed

      # The name the report counts the writes under, or nil when the report leaves them out.
      def counted_as = counted? ? name.to_s : nil

      private

      def update_action(row)
        rest = row.keys - key
        rest.empty? ? "NOTHING" : "UPDATE SET #{SQL.assignments(rest)}"
      end
    end
  end
end
