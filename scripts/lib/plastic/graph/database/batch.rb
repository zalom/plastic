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

        # The transaction up to its commit. The commit is a call of its own,
        # sent only when every statement here succeeded.
        def script = ["BEGIN IMMEDIATE;", *@statements].join("\n")

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

        # Writes the whole row its key names, and logs it. `statement: :insert`
        # refuses a row already there under its key, and fails the transaction.
        def put(name, row, statement: :upsert)
          table = Schema.table_named(name)
          row = stamped(table, row.to_h)
          counted(table, table.public_send(statement, row))
          log(table, "put", table.key_of(row))
        end

        def put_all(name, rows)
          rows.each { |row| put(name, row) }
          self
        end

        # Adds the statements of each read, in order.
        def apply(applies)
          applies.each { |apply| apply.call(self) }
          self
        end

        # Removes the rows `values` match, and logs each one with no row.
        def remove(name, **values)
          table = Schema.table_named(name)
          values = stamped(table, values)
          log(table, "remove", values)
          write(name, "DELETE FROM #{SQL.name(name)} WHERE #{SQL.where(values)}")
        end

        private

        # Machine state, such as the printed hashes, stays off the report.
        def counted(table, sql) = table.counted? ? write(table.name, sql) : add(sql)

        def stamped(table, row) = (table.origin? && @origin) ? { origin_id: @origin.id }.merge(row) : row

        def log(table, operation, match)
          @statements << "#{table.change(operation, match, @origin.id)};" if @origin && table.logged?
          self
        end
      end
    end
  end
end
