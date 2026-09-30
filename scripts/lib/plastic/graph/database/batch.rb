# frozen_string_literal: true

require_relative "../sql"
require_relative "../schema"

module Plastic
  module Graph
    class Database
      # One statement list with the row count after each counted write, so
      # the counts are exact rather than one per statement. In a store
      # database every put and remove also appends its `changes` row here, so
      # the log commits with the write or not at all.
      class Batch
        attr_reader :statements

        # `origin` names the installation that writes; the home database has none and keeps no log.
        def initialize(origin: nil)
          @statements = []
          @origin = origin
        end

        def empty? = @statements.empty?

        # The whole transaction as one script.
        def script = ["BEGIN IMMEDIATE;", *@statements, "COMMIT;"].join("\n")

        # A statement kept off the report. Its RETURNING rows, such as a new
        # id, come back from the transaction.
        def add(sql, **values)
          @statements << "#{SQL.bind(sql, values)};"
          self
        end

        # A write the report counts under `table`.
        def write(table, sql, **values)
          add(sql, **values)
          @statements << "SELECT #{SQL.literal(table.to_s)} AS written_table, changes() AS written_rows WHERE changes() > 0;"
          self
        end

        def insert(table, record, conflict: nil)
          clause = conflict ? " ON CONFLICT DO #{conflict}" : ""
          write(table, "INSERT INTO #{SQL.name(table)} #{SQL.tuple(record.to_h)}#{clause}")
        end

        # Writes the whole row its key names, and logs it. `new_row: true`
        # refuses a row that is already there instead of updating it.
        def put(name, row, count: true, new_row: false)
          table = Schema.table_named(name)
          row = stamped(table, row.to_h)
          sql = new_row ? table.insert(row) : table.upsert(row)
          count ? write(name, sql) : add(sql)
          log(table, "put", table.json_row, table.key_of(row))
        end

        # Removes the rows `values` match, and logs each one with no row.
        def remove(name, **values)
          table = Schema.table_named(name)
          values = stamped(table, values)
          log(table, "remove", "NULL", values)
          write(name, "DELETE FROM #{SQL.name(name)} WHERE #{table.where(values)}")
        end

        private

        def stamped(table, row) = (table.origin? && @origin) ? { origin_id: @origin.id }.merge(row) : row

        # The printed table is what this machine printed, so it is never logged.
        # Built from literals, never bound: a bound name would also match text inside a value.
        def log(table, operation, row_sql, match)
          return self unless @origin && table.name != :printed

          values = [table.name.to_s, operation, Plastic.now, @origin.id].map { |value| SQL.literal(value) }
          add("INSERT INTO changes(\"table\", \"key\", operation, \"row\", at, origin_id) " \
              "SELECT #{values[0]}, #{table.json_key}, #{values[1]}, #{row_sql}, #{values[2]}, #{values[3]} " \
              "FROM #{SQL.name(table.name)} WHERE #{table.where(match)}")
        end
      end
    end
  end
end
