# frozen_string_literal: true

require_relative "../database"
require_relative "../backup/writer"
require_relative "../schema/migration_list"
require_relative "../schema/state"
require_relative "legacy_keep"
require_relative "legacy_store"
require_relative "legacy_table"
require_relative "migration_ledger"
require_relative "migration_reason"

module Plastic
  module Graph
    # Undoes the newest migration of one current store. It backs the store up, puts the rows the migration kept in
    # legacy.db back into the live tables in their old shape, drops them from legacy.db and removes the version from the
    # store, all in one transaction, and adds a down row to the ledger in plastic.db. It refuses a store that is not
    # current, a migration that kept nothing, kept rows that are gone, and a live row that changed after the migration
    # kept it. Docs: docs/contributing/MIGRATIONS.md.
    class MigrationDown
      # The store cannot go down; the message says why and what to do instead.
      class Refused < Database::Error; end

      # The backup before the down failed, so the down changed nothing.
      class BackupFailed < Database::Error; end

      # Ends the trial restore, which rolls its transaction back.
      class Trial < StandardError; end
      private_constant :Trial

      # The version a down removed, the rows it put back by table, and the backup it took first.
      Undone = Data.define(:version, :moved, :backup)

      UNDO = "a down cannot undo it; restore a backup to go back"
      DELETE = "DELETE FROM main.schema_migrations WHERE version = ?"

      def initialize(home, slug, now, keeps: LegacyKeep::KEEPS)
        @home = home
        @slug = slug
        @now = now
        @keeps = keeps
        @store = LegacyStore.new(home, slug)
        @version = MIGRATIONS.versions(:store).last
      end

      # The newest store migration of this release, the one a down undoes.
      attr_reader :version

      # Why the store cannot go down, or nil when it can.
      def refusal
        check
        nil
      rescue Refused, LegacyTable::Changed => error
        error.message
      ensure
        @store.release
      end

      def call
        check
        backup = backed_up
        moved = undo
        MigrationLedger.new(Database.open_local(@home).fetch(:local), @now).record(@slug, "down", version, moved:, undoable: false)
        Undone.new(version:, moved:, backup:)
      ensure
        @store.release
      end

      private

      def connection = @store.connection

      def tables = @store.tables(version)

      def check
        current
        raise Refused, "migration #{version} kept nothing in legacy.db, so #{UNDO}" unless @keeps.include?(version)
        raise Refused, "the legacy rows of migration #{version} are not in legacy.db, so #{UNDO}" if tables.empty?

        trial
      end

      def current
        state = SchemaState.of_file(@store.knowledge_file, :store)
        raise Refused, "#{@slug} records migrations newer than this release (#{state.unknown.join(", ")}); run plastic update" if state.ahead?
        return if state.current?

        raise Refused, "#{@slug} has not run every migration of this release (#{state.pending.join(", ")}); run plastic update first"
      end

      # Restores every kept table in a transaction that rolls back, so a changed row refuses before anything changes.
      def trial
        connection.atomically do
          tables.each(&:restore)
          raise Trial
        end
      rescue Trial
        nil
      end

      def backed_up
        Backup::Writer.new(@store.root, @slug, now: @now, reason: "migration down").call.fetch(:name)
      rescue Backup::Writer::Error, SQLite3::Exception, SystemCallError => error
        raise BackupFailed, "the backup of #{@slug} failed (#{MigrationReason.of(error)}), so the down changed nothing"
      end

      def undo
        moved = connection.atomically do
          connection.execute(DELETE, [version])
          tables.to_h { |table| [table.table, table.restore.tap { table.drop }] }
        end
        @store.give_back
        moved
      end
    end
  end
end
