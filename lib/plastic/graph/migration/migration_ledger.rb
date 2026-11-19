# frozen_string_literal: true

require "json"
require_relative "../../clock"

module Plastic
  module Graph
    # The ledger of store migrations in the `store_migrations` table of plastic.db: one row for each up, down or purge
    # of a migration on a store, with the rows it moved into or out of legacy.db. The store's own schema_migrations
    # table stays the truth of its version. Docs: docs/contributing/MIGRATIONS.md.
    class MigrationLedger
      FLAG = { true => 1, false => 0 }.freeze
      EVENTS = "SELECT id, store, version, event, at, moved, undoable FROM store_migrations WHERE store = :store ORDER BY id"

      def initialize(local, now)
        @local = local
        @now = now
      end

      def record(store, event, version, moved:, undoable:)
        row = { store:, version:, event:, at: Plastic.timestamp(@now), moved: JSON.generate(moved), undoable: FLAG.fetch(undoable) }
        @local.transaction { |batch| batch.put(:store_migrations, row, statement: :insert) }
      end

      # Records an up row for each LegacyKeep::Entry of the migrations that ran on the store `store`.
      def ups(store, entries) = entries.each { |entry| record(store, "up", entry.version, moved: entry.kept, undoable: entry.undoable) }

      # The events of the store `store`, in the order they were recorded.
      def of(store) = @local.rows(EVENTS, store:)
    end
  end
end
