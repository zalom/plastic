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
require_relative "revision_rows"
require_relative "node_judge_columns"
require_relative "roadmap_needs_links"
require_relative "run_usage_columns"

module Plastic
  module Graph
    # Undoes the newest migration of one current store. It backs the store up, puts the rows the migration kept in
    # legacy.db back into the live tables in their old shape, drops them from legacy.db and removes the version from the
    # store, all in one transaction. In it, a version of REBUILDS also builds the rows the older code expects, such as a
    # revision row for each current document. A version of LegacyKeep::ALONE kept nothing, and a version of
    # LegacyKeep::VALUES that changed no value made no table, so the down of either removes the version alone. It adds a down row to the ledger in plastic.db. It refuses a store that lacks a migration older than its
    # newest, a migration that kept nothing, kept rows that are gone, and a live row that changed after the migration
    # kept it. A store an earlier down took back can go down again, one migration at a time. Docs: docs/contributing/MIGRATIONS.md.
    class MigrationDown
      # The store cannot go down; the message says why and what to do instead.
      class Refused < Database::Error; end

      # The backup before the down failed, so the down changed nothing.
      class BackupFailed < Database::Error; end

      # Ends the trial restore, which rolls its transaction back.
      class Trial < StandardError; end
      private_constant :Trial

      # The version a down removed, the rows it put back by table, the rows it built by table, and the backup it took first.
      Undone = Data.define(:version, :moved, :built, :backup, :ledger_gap)

      # The versions whose down builds rows the older code expects, beside the rows it puts back.
      REBUILDS = { "20261119000000" => RevisionRows, "20261123090000" => RunUsageColumns, "20261123100000" => NodeJudgeColumns,
                   "20261123120000" => RoadmapNeedsLinks }.freeze
      NONE = ->(_connection) { {} }

      UNDO = "a down cannot undo it; restore a backup to go back"
      DELETE = "DELETE FROM main.schema_migrations WHERE version = ?"

      def initialize(home, slug, now, keeps: LegacyKeep::KEEPS, rebuilds: REBUILDS)
        @home = home
        @slug = slug
        @now = now
        @keeps = keeps
        @rebuilds = rebuilds
        @store = LegacyStore.new(home, slug)
      end

      # The newest migration the store records, the one a down undoes.
      def version = (@version ||= SchemaState.of_file(@store.knowledge_file, :store).number.to_s)

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
        moved, built = undo
        ledger_gap = MigrationLedger.write(@home, @now) { |ledger| ledger.record(@slug, "down", version, moved:, undoable: false) }
        Undone.new(version:, moved:, built:, backup:, ledger_gap:)
      ensure
        @store.release
      end

      private

      def connection = @store.connection

      def tables = alone? ? [] : @store.tables(version)

      def alone? = LegacyKeep::ALONE.include?(version) || (LegacyKeep.kept_when_present?(version) && @store.tables(version).empty?)

      def check
        current
        return if alone?

        raise Refused, "migration #{version} kept nothing in legacy.db, so #{UNDO}" unless @keeps.include?(version)
        raise Refused, "the legacy rows of migration #{version} are not in legacy.db, so #{UNDO}" if tables.empty?

        trial
      end

      def current
        state = SchemaState.of_file(@store.knowledge_file, :store)
        raise Refused, "#{@slug} records migrations newer than this release (#{state.unknown.join(", ")}); run plastic update" if state.ahead?
        older = state.pending.select { |pending| state.number.zero? || pending.to_i < state.number }
        return if older.empty?

        raise Refused, "#{@slug} has not run every migration of this release (#{older.join(", ")}); run plastic update first"
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
        undone = connection.atomically do
          connection.execute(DELETE, [version])
          [tables.to_h { |table| [table.table, table.restore.tap { table.drop }] }, @rebuilds.fetch(version, NONE).call(connection)]
        end
        @store.give_back
        undone
      end
    end
  end
end
