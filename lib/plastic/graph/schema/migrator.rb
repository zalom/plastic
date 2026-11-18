# frozen_string_literal: true

require_relative "../behind"
require_relative "migration_list"
require_relative "state"

module Plastic
  module Graph
    # Runs the pending migrations of one kind on one connection, in ascending order, and records each version in the
    # schema_migrations table of the main file right after it runs. An empty main file, as a store whose knowledge file
    # was lost, takes every migration. The whole run is one transaction under the write lock: a failure leaves no
    # migration and no row. A runner that finds the versions recorded once it holds the lock runs nothing.
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
        @migrations.of(@kind).select { |migration| state.pending.include?(migration.version) }.each { |migration| run(migration) }
      end

      def run(migration)
        @connection.execute_batch(migration.sql)
        @connection.execute(INSERT, [migration.version])
      end
    end
  end
end
