# frozen_string_literal: true

require_relative "../database"
require_relative "leftover_work_tables"
require_relative "legacy_values"

module Plastic
  module Graph
    # One table of legacy.db: the rows a migration removed from a live table, kept in the old shape. It is named for the
    # live table and the version, as `sqlar_20261119000000`, and is made from the live table's own CREATE TABLE text. The
    # connection has legacy.db attached as `legacy`. Docs: docs/contributing/MIGRATIONS.md.
    class LegacyTable
      # A row that a restore would put back differs from the live row with its key.
      class Changed < Database::Error; end

      SCHEMA = "legacy"
      NAME = /\A(?<table>.+)_(?<version>\d{14})\z/
      HEAD = /\ACREATE TABLE\s+(?:IF NOT EXISTS\s+)?(?:\w+\.)?(?:"[^"]+"|\w+)/i
      # The schema a table lives in when it is not `main`: the roadmap tables of the work graph. The ten leftover tables of
      # migration 20261124120000 live there too, but by version (see LeftoverWorkTables), as their names are live tables of main.
      HOMES = %w[roadmaps batches roadmap_items roadmap_edges roadmap_log].to_h { |table| [table, "work"] }.freeze
      DEFINITION = "SELECT sql FROM %<schema>s.sqlite_master WHERE type = 'table' AND name = ?"

      # The legacy tables that the migration `version` kept.
      def self.of(connection, version) = all(connection).select { |table| table.version == version }

      # Every legacy table of legacy.db, by name; the old values of a migration that rewrote values in place are a LegacyValues.
      def self.all(connection)
        connection.execute("SELECT name FROM #{SCHEMA}.sqlite_master WHERE type = 'table' ORDER BY name")
          .filter_map { |row| NAME.match(row.fetch("name")) }
          .map { |name| named(connection, name[:table], name[:version]) }
      end

      def self.named(connection, table, version) = (table == LegacyValues::TABLE) ? LegacyValues.new(connection, version) : new(connection, table, version)

      attr_reader :table, :version

      def initialize(connection, table, version)
        @connection = connection
        @table = table
        @version = version
        @home = LeftoverWorkTables.home?(version, table) ? LeftoverWorkTables::SCHEMA : HOMES.fetch(table, "main")
      end

      def name = "#{@table}_#{@version}"

      # Copies the rows of the live table that the `where` text selects, or all of them, and answers how many it copied. A
      # kept row with the key of a live row gives way to it. A missing live table keeps nothing and makes no table.
      def keep(where = nil, values = [])
        definition = definition(@home, @table)
        return 0 unless definition

        @connection.execute(definition.sub(HEAD, %(CREATE TABLE IF NOT EXISTS #{SCHEMA}."#{name}")))
        @connection.execute(%(INSERT OR REPLACE INTO #{SCHEMA}."#{name}" SELECT * FROM #{@home}."#{@table}"#{" WHERE #{where}" if where}), values)
        @connection.changes
      end

      # Puts the kept rows back into the live table, made again in the old shape when it is gone, and answers how many it
      # put back. A live row that is the same as its kept row is skipped.
      def restore
        @connection.execute(definition(SCHEMA, name).sub(HEAD, %(CREATE TABLE IF NOT EXISTS #{@home}."#{@table}")))
        @connection.execute(%(INSERT INTO #{@home}."#{@table}" SELECT * FROM #{SCHEMA}."#{name}" EXCEPT SELECT * FROM #{@home}."#{@table}"))
        @connection.changes
      rescue SQLite3::ConstraintException
        raise Changed, "a row of #{@table} changed after migration #{@version} kept it"
      end

      # Whether the live table is there and holds a row.
      def rows? = !definition(@home, @table).nil? && @connection.get_first_value(%(SELECT EXISTS (SELECT 1 FROM #{@home}."#{@table}"))) == 1

      def drop = @connection.execute(%(DROP TABLE IF EXISTS #{SCHEMA}."#{name}"))

      def count = @connection.get_first_value(%(SELECT count(*) FROM #{SCHEMA}."#{name}"))

      def kept? = !definition(SCHEMA, name).nil?

      private

      def definition(schema, table) = @connection.get_first_value(format(DEFINITION, schema:), [table])
    end
  end
end
