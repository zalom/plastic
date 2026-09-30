# frozen_string_literal: true

require_relative "../sql"

module Plastic
  module Graph
    class Database
      # One statement list with the row count after each counted write, so
      # the counts are exact rather than one per statement.
      class Batch
        attr_reader :statements

        def initialize = @statements = []

        def empty? = @statements.empty?

        # The whole transaction as one script.
        def script = ["BEGIN IMMEDIATE;", *@statements, "COMMIT;"].join("\n")

        # A statement kept off the report, as for the hashes that the
        # checkout records. Its RETURNING rows, such as a new id, come back
        # from the transaction.
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
      end
    end
  end
end
