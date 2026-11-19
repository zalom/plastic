# frozen_string_literal: true

require_relative "earlier_revisions"
require_relative "legacy_table"

module Plastic
  module Graph
    # Keeps in legacy.db what the migrations of one store run remove, and counts it. A version of KEEPS keeps the tables
    # drops, just before its SQL runs, and its data step keeps each row it deletes. The connection has legacy.db
    # attached as `legacy` while a version of KEEPS is pending. Docs: docs/contributing/MIGRATIONS.md.
    class LegacyKeep
      FILE = "legacy.db"
      # The versions that keep what they remove, so a down can undo them.
      KEEPS = %w[20261119000000].freeze
      # The rows of the tables a version drops that a down cannot rebuild, kept before its SQL runs.
      DROPPED = { "20261119000000" => EarlierRevisions }.freeze

      # The legacy.db of the store at `root`, attached as `legacy` only while a `pending` version keeps what it removes.
      def self.attachment(root, pending) = (KEEPS & pending).empty? ? {} : { legacy: File.join(root, FILE) }

      # One migration that ran on the store: the rows it kept by table, and whether a down can undo it.
      Entry = Data.define(:version, :kept, :undoable)

      # `selection` is the sync selection of the machine, which names the paths whose rows are worth keeping.
      def initialize(connection, selection)
        @connection = connection
        @selection = selection
        @kept = {}
      end

      # Runs just before the SQL of `version`.
      def call(version)
        @kept[version] = {}
        DROPPED[version]&.new(@connection, @selection)&.call(at(version))
      end

      # Keeps the rows of `table` that the `where` text selects, or all of them, for the migration `version`.
      def rows(version, table, where = nil, values = [])
        count = LegacyTable.new(@connection, table, version).keep(where, values)
        kept = @kept.fetch(version)
        kept[table] = kept.fetch(table, 0) + count
      end

      # The keep of the data step of `version`.
      def at(version) = ->(table, where, values) { rows(version, table, where, values) }

      # Each migration that ran, in order.
      def entries = @kept.map { |version, kept| Entry.new(version:, kept:, undoable: KEEPS.include?(version)) }
    end
  end
end
