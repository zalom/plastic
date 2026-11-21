# frozen_string_literal: true

require_relative "../database"

module Plastic
  module Graph
    # The old text of each value a migration rewrote in place, kept in legacy.db in one table named for the version, as
    # `changed_values_20261121090000`: the schema, table and column of the value, its old text and its new text. A
    # restore writes the old text back where the live value still equals the new text, so a value written after the
    # migration stays. The connection has legacy.db attached as `legacy`. Docs: docs/contributing/MIGRATIONS.md.
    class LegacyValues
      TABLE = "changed_values"
      CREATE = <<~SQL
        CREATE TABLE IF NOT EXISTS legacy."%<name>s"("schema_name" TEXT NOT NULL, "table_name" TEXT NOT NULL, "column_name" TEXT NOT NULL,
          "old" TEXT NOT NULL, "new" TEXT NOT NULL, PRIMARY KEY("schema_name", "table_name", "column_name", "old"))
      SQL
      KEEP = %(INSERT OR IGNORE INTO legacy."%<legacy>s" SELECT ?, ?, ?, "%<name>s", %<change>s FROM %<schema>s."%<table>s" WHERE %<where>s GROUP BY "%<name>s")
      KEPT = %(FROM legacy."%<name>s" WHERE schema_name = ? AND table_name = ? AND column_name = ?)
      PUT_BACK = %(UPDATE %<schema>s."%<table>s" SET "%<column>s" = (SELECT old %<kept>s AND new = "%<table>s"."%<column>s" ORDER BY old LIMIT 1)
        WHERE "%<column>s" IN (SELECT new %<kept>s))

      attr_reader :version

      def initialize(connection, version)
        @connection = connection
        @version = version
      end

      def table = TABLE

      def name = "#{TABLE}_#{@version}"

      # Keeps each value the `where` text of the column selects, with the new text its `change` expression makes of it, and
      # answers how many values it kept. The table is made even when no value is kept, so a down finds it.
      def keep(column)
        @connection.execute(format(CREATE, name:))
        fields = column.to_h
        @connection.execute(format(KEEP, legacy: name, **fields, change: column.change, where: column.where), fields.values)
        @connection.changes
      end

      # Writes each kept old text back where the live value still equals its new text, and answers how many values it wrote.
      def restore = columns.sum { |schema, table, column| put_back(schema, table, column) }

      def drop = @connection.execute(%(DROP TABLE IF EXISTS legacy."#{name}"))

      def count = @connection.get_first_value(%(SELECT count(*) FROM legacy."#{name}"))

      private

      def columns
        @connection.execute(%(SELECT DISTINCT schema_name, table_name, column_name FROM legacy."#{name}" ORDER BY 1, 2, 3))
          .map { |row| row.values_at("schema_name", "table_name", "column_name") }
      end

      def put_back(schema, table, column)
        kept = format(KEPT, name:)
        @connection.execute(format(PUT_BACK, schema:, table:, column:, kept:), [schema, table, column] * 2)
        @connection.changes
      end
    end
  end
end
