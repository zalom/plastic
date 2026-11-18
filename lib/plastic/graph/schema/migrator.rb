# frozen_string_literal: true

require_relative "../behind"

module Plastic
  module Graph
    # Runs one SQL migration on one connection. The file's stamp moves from 0 to 1 in the
    # same transaction as the migration, and a runner that read 0 before another committed
    # reads 1 once it holds the write lock and runs nothing.
    class SchemaMigrator
      VERSION = 1
      STAMP = "PRAGMA main.user_version"

      def initialize(connection, migration)
        @connection = connection
        @migration = migration
      end

      def call
        return if stamped?

        @connection.atomically { apply unless stamped? }
        nil
      end

      private

      def stamped?
        stamp = @connection.get_first_value(STAMP)
        raise Ahead, "the database is at version #{stamp} and this code migrates to #{VERSION}; restore the backup taken before the update" if stamp > VERSION

        stamp == VERSION
      end

      def apply
        @connection.execute_batch(File.read(@migration))
        @connection.execute("PRAGMA main.user_version = #{VERSION}")
      end
    end
  end
end
