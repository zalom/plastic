# frozen_string_literal: true

require_relative "sql"

module Plastic
  module Graph
    # One table: its columns with their SQL types, and the key that names one
    # row. The statements that write a row and log the write are built here.
    Table = Data.define(:name, :columns, :key) do
      def ddl
        parts = columns.map { |column, type| "#{SQL.name(column)} #{type}" }
        parts << "UNIQUE(#{SQL.names(key)})" unless key.empty?
        "CREATE TABLE IF NOT EXISTS #{SQL.name(name)}(#{parts.join(", ")});"
      end

      def origin? = columns.key?(:origin_id)

      def insert(row) = "INSERT INTO #{SQL.name(name)} #{SQL.tuple(row)}"

      # An insert that updates the row its key names, column by column.
      def upsert(row)
        rest = row.keys - key
        action = rest.empty? ? "NOTHING" : "UPDATE SET #{rest.map { |column| SQL.assignment(column) }.join(", ")}"
        "#{insert(row)} ON CONFLICT(#{SQL.names(key)}) DO #{action}"
      end

      def key_of(row) = key.to_h { |column| [column, row[column]] }

      # The whole row as a JSON object, with bytes as hex, so a change row
      # holds the row after the write.
      def json_row = json_object(columns.keys)

      def json_key = json_object(key)

      # The printed table is what this machine printed, so it is never logged.
      def logged? = name != :printed

      # Machine state that the report leaves out: the printed hashes and the routine runs.
      def counted? = !%i[printed routine_runs].include?(name)

      # The `changes` row of a put or a remove of the rows `match` names.
      # Built from literals, never bound: a bound name would also match text
      # inside a value.
      def change(operation, match, origin_id)
        row = { "put" => json_row }.fetch(operation, "NULL")
        values = [name.to_s, operation, Plastic.now, origin_id].map { |value| SQL.literal(value) }
        "INSERT INTO changes(\"table\", \"key\", operation, \"row\", at, origin_id) " \
          "SELECT #{values[0]}, #{json_key}, #{values[1]}, #{row}, #{values[2]}, #{values[3]} " \
          "FROM #{SQL.name(name)} WHERE #{SQL.where(match)}"
      end

      private

      def json_object(list) = "json_object(#{list.map { |column| "'#{column}', #{json_value(column)}" }.join(", ")})"

      def json_value(column)
        quoted = SQL.name(column)
        columns.fetch(column).start_with?("BLOB") ? "hex(#{quoted})" : quoted
      end
    end
  end
end
