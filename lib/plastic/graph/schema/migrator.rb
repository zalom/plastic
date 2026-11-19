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

      # The `before` step runs with the version of each pending migration just before its SQL, in the same transaction.
      # `released` names the held versions whose switch is on, so the run applies them.
      def initialize(connection, kind, migrations: MIGRATIONS, before: ->(_version) {}, released: [])
        @connection = connection
        @kind = kind
        @migrations = migrations
        @before = before
        @released = released
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

      def reading = SchemaState.new(@connection, @kind, migrations: @migrations, released: @released).call

      def apply(state)
        self.class.record(@connection, state.adopted)
        @migrations.of(@kind).select { |migration| state.pending.include?(migration.version) }.each { |migration| migrate(migration) }
      end

      def migrate(migration)
        version = migration.version
        @before.call(version)
        @connection.execute_batch(migration.sql)
        @connection.execute(INSERT, [version])
      end
    end
  end
end
