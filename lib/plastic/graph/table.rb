# frozen_string_literal: true

require_relative "sql"

module Plastic
  module Graph
    # One table: its columns with their SQL types, and the key that names one
    # row. The statements that write a row and log the write are built here.
    Table = Data.define(:name, :columns, :key)

    # The statements of one table.
    class Table
      def ddl
        parts = columns.map { |column, type| "#{SQL.name(column)} #{type}" }
        parts << "UNIQUE(#{SQL.names(key)})" unless key.empty?
        "CREATE TABLE IF NOT EXISTS #{SQL.name(name)}(#{parts.join(", ")});"
      end

      def origin? = columns.key?(:origin_id)

      def insert(row) = SQL.insert(name, row)

      # An insert that updates the row its key names, column by column.
      def upsert(row) = SQL.insert(name, row, " ON CONFLICT(#{SQL.names(key)}) DO #{update_action(row)}")

      def key_of(row) = key.to_h { |column| [column, row[column]] }

      # The whole row as a JSON object, with bytes as hex, so a change row
      # holds the row after the write.
      def json_row = json_object(columns.keys)

      def json_key = json_object(key)

      # The printed table is what this machine printed, so it is never logged.
      def logged? = name != :printed

      # Machine state that the report leaves out: the printed hashes.
      def counted? = name != :printed

      # The name the report counts the writes under, or nil when the report leaves them out.
      def counted_as = counted? ? name.to_s : nil

      # The `changes` row of a put or a remove of the rows `match` names.
      def change(operation, match, origin_id)
        row = { "put" => json_row }.fetch(operation, "NULL")
        where = SQL.where(match, "m")
        logged = { c_table: name.to_s, c_operation: operation, c_at: Plastic.now, c_origin: origin_id }
        sql = "INSERT INTO changes(\"table\", \"key\", operation, \"row\", at, origin_id) " \
          "SELECT :c_table, #{json_key}, :c_operation, #{row}, :c_at, :c_origin " \
          "FROM #{SQL.name(name)} WHERE #{where.sql}"
        SQL::Bound.new(sql, logged.merge(where.values))
      end

      private

      def update_action(row)
        rest = row.keys - key
        rest.empty? ? "NOTHING" : "UPDATE SET #{SQL.assignments(rest)}"
      end

      def json_object(list) = "json_object(#{list.map { |column| "'#{column}', #{json_value(column)}" }.join(", ")})"

      def json_value(column)
        quoted = SQL.name(column)
        columns.fetch(column).start_with?("BLOB") ? "hex(#{quoted})" : quoted
      end
    end
  end
end
