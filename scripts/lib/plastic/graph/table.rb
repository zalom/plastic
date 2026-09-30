# frozen_string_literal: true

require_relative "sql"

module Plastic
  module Graph
    # One table: its columns with their SQL types, and the key that names one
    # row. The statements that write a row and log the write are built here.
    Table = Data.define(:name, :columns, :key) do
      def ddl
        parts = columns.map { |column, type| "#{SQL.name(column)} #{type}" }
        parts << "UNIQUE(#{names(key)})" unless key.empty?
        "CREATE TABLE IF NOT EXISTS #{SQL.name(name)}(#{parts.join(", ")});"
      end

      def origin? = columns.key?(:origin_id)

      def insert(row) = "INSERT INTO #{SQL.name(name)} #{SQL.tuple(row)}"

      # An insert that updates the row its key names, column by column.
      def upsert(row)
        rest = row.keys - key
        action = rest.empty? ? "NOTHING" : "UPDATE SET #{rest.map { |column| assignment(column) }.join(", ")}"
        "#{insert(row)} ON CONFLICT(#{names(key)}) DO #{action}"
      end

      # `a IS 1 AND b IS 'x'`: IS matches a NULL as well.
      def where(values) = values.empty? ? "1" : values.map { |column, value| "#{SQL.name(column)} IS #{SQL.literal(value)}" }.join(" AND ")

      def key_of(row) = key.to_h { |column| [column, row[column]] }

      # The whole row as a JSON object, with bytes as hex, so a change row
      # holds the row after the write.
      def json_row = json_object(columns.keys)

      def json_key = json_object(key)

      private

      def names(list) = list.map { |column| SQL.name(column) }.join(", ")

      def assignment(column) = "#{SQL.name(column)} = excluded.#{SQL.name(column)}"

      def json_object(list) = "json_object(#{list.map { |column| "'#{column}', #{json_value(column)}" }.join(", ")})"

      def json_value(column) = columns.fetch(column).start_with?("BLOB") ? "hex(#{SQL.name(column)})" : SQL.name(column)
    end
  end
end
