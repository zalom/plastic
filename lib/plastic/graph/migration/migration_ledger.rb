# frozen_string_literal: true

require "json"
require_relative "../../clock"
require_relative "../database"
require_relative "migration_reason"

module Plastic
  module Graph
    # The ledger of store migrations in the `store_migrations` table of plastic.db: one row for each up, down or purge
    # of a migration on a store, with the rows it moved into or out of legacy.db. The store's own schema_migrations
    # table stays the truth of its version. Docs: docs/contributing/MIGRATIONS.md.
    class MigrationLedger
      FLAG = { true => 1, false => 0 }.freeze
      EVENTS = "SELECT id, store, version, event, at, moved, undoable FROM store_migrations WHERE store = :store ORDER BY id"
      # What a write to the ledger raises when plastic.db is locked, behind, or refuses the row.
      ERRORS = [SQLite3::Exception, Database::Error, SystemCallError].freeze

      # Opens the ledger of the home `home` and yields it. Answers nil, or the reason the write failed. The store
      # change it records has committed already, so a failed write is a note, never a failure.
      def self.write(home, now)
        yield new(Database.open_local(home).fetch(:local), now)
        nil
      rescue *ERRORS => error
        MigrationReason.of(error)
      end

      def initialize(local, now)
        @local = local
        @now = now
      end

      def record(store, event, version, moved:, undoable:) = insert([row(store, event, version, moved, undoable)])

      # Records an up row for each LegacyKeep::Entry of the migrations that ran on the store `store`, in one transaction.
      def ups(store, entries) = insert(entries.map { |entry| row(store, "up", entry.version, entry.kept, entry.undoable) })

      # The events of the store `store`, in the order they were recorded.
      def of(store) = @local.rows(EVENTS, store:)

      private

      def row(store, event, version, moved, undoable)
        { store:, version:, event:, at: Plastic.timestamp(@now), moved: JSON.generate(moved), undoable: FLAG.fetch(undoable) }
      end

      def insert(rows) = @local.transaction { |batch| rows.each { |row| batch.put(:store_migrations, row, statement: :insert) } }
    end
  end
end
