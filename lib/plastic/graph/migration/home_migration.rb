# frozen_string_literal: true

require_relative "../database"
require_relative "../schema/gate"
require_relative "home_copy"
require_relative "home_rename"
require_relative "../schema/migrator"
require_relative "migration_reason"

module Plastic
  module Graph
    # Brings the home database to the newest version. A database behind is copied into backups first, and the former
    # name local.db is renamed to plastic.db. The answer is :current, :migrated, or the reason it stayed behind.
    class HomeMigration
      def initialize(home, now)
        @home = home
        @now = now
      end

      def call
        path = [current, former].find { |file| File.exist?(file) }
        path ? migrate(path) : :current
      rescue SQLite3::Exception, Database::Error, SystemCallError, HomeRename::Taken => error
        "it could not be migrated (#{MigrationReason.of(error)})"
      end

      private

      def former = File.join(@home, "local.db")

      def current = File.join(@home, "plastic.db")

      def migrate(path) = preparation_failure(path) || advance

      def advance = (local.version >= SchemaMigrator::VERSION) ? :current : migrated

      def local = (@local ||= Database.open_local(@home).fetch(:local))

      def migrated
        local.migrate
        :migrated
      end

      def preparation_failure(path)
        reason = copy_failure(path) if SchemaGate.stamp_of(path) < SchemaMigrator::VERSION
        return "the copy of its database failed (#{reason})" if reason

        HomeRename.new(former, current).call if path == former
        nil
      end

      def copy_failure(path)
        HomeCopy.new(path, File.join(@home, "backups"), @now).call
        nil
      rescue SQLite3::Exception, SystemCallError, HomeCopy::Exists => error
        MigrationReason.of(error)
      end
    end
  end
end
