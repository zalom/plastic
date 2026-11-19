# frozen_string_literal: true

require_relative "../database"
require_relative "legacy_store"
require_relative "migration_ledger"

module Plastic
  module Graph
    # Removes from legacy.db the rows one migration of a store kept, gives their space back to the disk, and adds a purge
    # row to the ledger in plastic.db. After it, a down cannot undo that migration. Docs: docs/contributing/MIGRATIONS.md.
    class MigrationPurge
      # The migration keeps no rows of the store in legacy.db.
      class Nothing < Database::Error; end

      # The rows a purge removed, by table, and why the ledger lacks its row when the write failed.
      Purged = Data.define(:moved, :ledger_gap)

      def initialize(home, slug, now)
        @home = home
        @slug = slug
        @now = now
        @store = LegacyStore.new(home, slug)
      end

      # The rows it removed, by table, and the reason the ledger lacks its purge row, or nil.
      def call(version)
        moved = removed(version)
        Purged.new(moved:, ledger_gap: MigrationLedger.write(@home, @now) { |ledger| ledger.record(@slug, "purge", version, moved:, undoable: false) })
      ensure
        @store.release
      end

      private

      def removed(version)
        tables = @store.tables(version)
        raise Nothing, "migration #{version} keeps no rows of #{@slug} in legacy.db, so there is nothing to purge" if tables.empty?

        moved = @store.connection.atomically { tables.to_h { |table| [table.table, table.count.tap { table.drop }] } }
        @store.give_back
        moved
      end
    end
  end
end
