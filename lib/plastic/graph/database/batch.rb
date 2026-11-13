# frozen_string_literal: true

require_relative "../sql"
require_relative "../schema"

module Plastic
  module Graph
    class Database
      # The statements of one transaction, in the order they were added.
      class Batch
        # One statement, the values it binds, and the table whose rows it counts, if any.
        Entry = Data.define(:sql, :values, :table)

        # What one statement did on a connection: the rows it returned.
        class Entry
          def run(connection)
            rows = connection.read(sql, values)
            changed = connection.changes
            yield table, changed if table && changed.positive?
            rows unless rows.empty?
          end
        end

        attr_reader :statements

        # `origin` names the installation that writes; the local database has none and keeps no log.
        def initialize(origin: nil)
          @statements = []
          @origin = origin
        end

        def empty? = @statements.empty?

        # A statement kept off the report. Its RETURNING rows, such as a new
        # id, come back from the transaction.
        def add(sql, **values) = bind(nil, SQL::Bound.new(sql, values))

        # A write the report counts under `table`.
        def write(table, sql, **values) = bind(table.to_s, SQL::Bound.new(sql, values))

        def insert(table, record, conflict: nil)
          clause = conflict ? " ON CONFLICT DO #{conflict}" : ""
          bind(table.to_s, SQL.insert(table, record.to_h, clause))
        end

        # Writes the whole row its key names, and logs it. `statement: :insert`
        # refuses a row already there under its key, and fails the transaction.
        def put(name, row, statement: :upsert)
          table = Schema.table_named(name)
          row = stamped(table, row.to_h)
          bind(table.counted_as, table.public_send(statement, row))
          log(table, "put", table.key_of(row))
        end

        def put_all(name, rows)
          rows.each { |row| put(name, row) }
          self
        end

        # Inserts each row under its table name, in order, as
        # `insert_rows(rulings: row, links: row)`. A row already there fails the transaction.
        def insert_rows(rows)
          rows.each { |name, row| put(name, row, statement: :insert) }
          self
        end

        # Adds the statements of each read, in order.
        def apply(applies)
          applies.each { |apply| apply.call(self) }
          self
        end

        # Removes the rows each of `keys` matches, in order.
        def remove_all(name, keys)
          keys.each { |values| remove(name, **values) }
          self
        end

        # Removes the rows `values` match, and logs each one with no row.
        def remove(name, **values)
          table = Schema.table_named(name)
          values = stamped(table, values)
          log(table, "remove", values)
          where = SQL.where(values, "m")
          write(name, "DELETE FROM #{SQL.name(name)} WHERE #{where.sql}", **where.values)
        end

        private

        def stamped(table, row) = (table.origin? && @origin) ? { origin_id: @origin.id }.merge(row) : row

        def bind(table, bound)
          @statements << Entry.new(bound.sql, bound.values, table)
          self
        end

        def log(table, operation, match)
          return self unless @origin && table.logged?

          change = table.change(operation, match, @origin.id)
          bind(nil, change)
        end
      end
    end
  end
end
