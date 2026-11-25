# frozen_string_literal: true

require_relative "../database"
require_relative "row_key"

module Plastic
  module Graph
    # The old text of each value a migration rewrote in place, kept in legacy.db in one table named for the version, as
    # `changed_values_20261121090000`: the schema, table and column of the value, the key of its row, its old text and
    # its new text. The table is made only when a value is kept. A restore writes each old text back on its own row
    # where the live value still equals the new text, so a value written after the migration stays. The connection has
    # legacy.db attached as `legacy`. Docs: docs/contributing/MIGRATIONS.md.
    class LegacyValues
      TABLE = "changed_values"
      CREATE = <<~SQL
        CREATE TABLE IF NOT EXISTS legacy."%<name>s"("schema_name" TEXT NOT NULL, "table_name" TEXT NOT NULL, "column_name" TEXT NOT NULL,
          "row_key" TEXT NOT NULL, "old" TEXT NOT NULL, "new" TEXT NOT NULL, PRIMARY KEY("schema_name", "table_name", "column_name", "row_key"))
      SQL
      ANY = %(SELECT EXISTS(SELECT 1 FROM %<schema>s."%<table>s" WHERE %<where>s))
      KEEP = %(INSERT INTO legacy."%<legacy>s" SELECT ?, ?, ?, %<key>s, "%<name>s", %<change>s FROM %<schema>s."%<table>s" WHERE %<where>s)
      PUT_BACK = <<~SQL
        UPDATE %<schema>s."%<table>s" AS live SET "%<column>s" = kept.old FROM legacy."%<name>s" AS kept
        WHERE kept.schema_name = ? AND kept.table_name = ? AND kept.column_name = ? AND kept.row_key = %<key>s AND live."%<column>s" = kept.new
      SQL

      attr_reader :version

      def initialize(connection, version)
        @connection = connection
        @version = version
      end

      def table = TABLE

      def name = "#{TABLE}_#{@version}"

      # Keeps each value the `where` text of the column selects, with the key of its row and the new text its `change`
      # expression makes of it, and answers how many values it kept.
      def keep(column)
        return 0 unless any?(column)

        @connection.execute(format(CREATE, name:))
        @connection.execute(kept(column), column.to_h.values)
        @connection.changes
      end

      # Writes each kept old text back on its own row where the live value still equals its new text, and answers how
      # many values it wrote.
      def restore = columns.sum { |schema, table, column| put_back(schema, table, column) }

      def drop = @connection.execute(%(DROP TABLE IF EXISTS legacy."#{name}"))

      def count = @connection.get_first_value(%(SELECT count(*) FROM legacy."#{name}"))

      private

      def any?(column) = @connection.get_first_value(format(ANY, **column.to_h, where: column.where)).positive?

      def kept(column) = format(KEEP, legacy: name, **column.to_h, key: key(column.schema, column.table), change: column.change, where: column.where)

      def key(schema, table, prefix = nil) = RowKey.new(@connection, schema, table).expression(prefix)

      def columns
        @connection.execute(%(SELECT DISTINCT schema_name, table_name, column_name FROM legacy."#{name}" ORDER BY 1, 2, 3))
          .map { |row| row.values_at("schema_name", "table_name", "column_name") }
      end

      def put_back(schema, table, column)
        @connection.execute(format(PUT_BACK, schema:, table:, column:, name:, key: key(schema, table, "live")), [schema, table, column])
        @connection.changes
      end
    end
  end
end
