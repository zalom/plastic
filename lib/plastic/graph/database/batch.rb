# frozen_string_literal: true

require_relative "../sql"
require_relative "../schema"

module Plastic
  module Graph
    class Database
      # One statement list. Each statement keeps its text and its values apart;
      # a counted write also names its table, so the count is read from the
      # write itself. In a store database every put and remove also appends
      # its `changes` row here, so the log commits with the write or not at all.
      class Batch
        # `table` is nil for a statement kept off the report.
        Entry = Data.define(:sql, :values, :table)

        attr_reader :statements

        # `origin` names the installation that writes; the local database has none and keeps no log.
        def initialize(origin: nil)
          @statements = []
          @origin = origin
        end

        def empty? = @statements.empty?

        # A statement kept off the report. Its RETURNING rows, such as a new
        # id, come back from the transaction.
        def add(sql, **values)
          @statements << Entry.new(sql, values, nil)
          self
        end

        # A write the report counts under `table`.
        def write(table, sql, **values)
          @statements << Entry.new(sql, values, table.to_s)
          self
        end

        def insert(table, record, conflict: nil)
          clause = conflict ? " ON CONFLICT DO #{conflict}" : ""
          tuple = SQL.tuple(record.to_h, "v")
          write(table, "INSERT INTO #{SQL.name(table)} #{tuple.sql}#{clause}", **tuple.values)
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

        # Machine state, such as the printed hashes, stays off the report.
        def counted(table, bound)
          table.counted? ? write(table.name, bound.sql, **bound.values) : add(bound.sql, **bound.values)
        end

        def stamped(table, row) = (table.origin? && @origin) ? { origin_id: @origin.id }.merge(row) : row

        def log(table, operation, match)
          return self unless @origin && table.logged?

          change = table.change(operation, match, @origin.id)
          add(change.sql, **change.values)
        end
      end
    end
  end
end
