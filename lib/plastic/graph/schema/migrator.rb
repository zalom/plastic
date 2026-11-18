# frozen_string_literal: true

require_relative "../behind"
require_relative "migration_list"
require_relative "state"

module Plastic
  module Graph
    # Docs: docs/contributing/MIGRATIONS.md.
    class SchemaMigrator
      TABLE = "CREATE TABLE IF NOT EXISTS main.schema_migrations (version TEXT PRIMARY KEY)"
      INSERT = "INSERT INTO main.schema_migrations (version) VALUES (?)"

      def self.record(connection, versions)
        connection.execute(TABLE)
        versions.each { |version| connection.execute(INSERT, [version]) }
      end

      def initialize(connection, kind, migrations: MIGRATIONS)
        @connection = connection
        @kind = kind
        @migrations = migrations
      end

      def call
        return unless reading.due?(Ahead)

        @connection.atomically do
          fresh = reading
          apply(fresh) if fresh.due?(Ahead)
        end
        nil
      end

      private

      def reading = SchemaState.new(@connection, @kind, migrations: @migrations).call

      def apply(state)
        self.class.record(@connection, state.adopted)
        @migrations.of(@kind).select { |migration| state.pending.include?(migration.version) }.each { |migration| migrate(migration) }
      end

      def migrate(migration)
        @connection.execute_batch(migration.sql)
        @connection.execute(INSERT, [migration.version])
      end
    end
  end
end
