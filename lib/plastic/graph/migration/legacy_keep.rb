# frozen_string_literal: true

require_relative "legacy_table"

module Plastic
  module Graph
    # Keeps in legacy.db what the migrations of one store run remove, and counts it. A version of KEEPS keeps the tables
    # it drops whole, just before its SQL runs, and its data step keeps each row it deletes. The connection has legacy.db
    # attached as `legacy` while a version of KEEPS or TRIMS is pending. Docs: docs/contributing/MIGRATIONS.md.
    class LegacyKeep
      FILE = "legacy.db"
      # The versions that keep what they remove, so a down can undo them.
      KEEPS = %w[20261119000000].freeze
      # The tables a version drops, kept whole before its SQL runs.
      WHOLE = { "20261119000000" => %w[document_revisions] }.freeze
      # The versions that remove from legacy.db rows an earlier version kept, rows a down rebuilds or no sync reads.
      TRIMS = %w[20261119190000].freeze
      # The versions that keep nothing and that a down undoes by removing the version alone: a sync up reads back every
      # row they drop that the rules still read, or a down of the earlier version rebuilds it.
      ALONE = %w[20261119180000 20261119190000].freeze

      # The legacy.db of the store at `root`, attached as `legacy` only while a `pending` version keeps or trims what it holds.
      def self.attachment(root, pending) = ((KEEPS + TRIMS) & pending).empty? ? {} : { legacy: File.join(root, FILE) }

      # One migration that ran on the store: the rows it kept by table, and whether a down can undo it.
      Entry = Data.define(:version, :kept, :undoable)

      def initialize(connection)
        @connection = connection
        @kept = {}
      end

      # Runs just before the SQL of `version`.
      def call(version)
        @kept[version] = {}
        WHOLE.fetch(version, []).each { |table| rows(version, table) }
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
      def entries = @kept.map { |version, kept| Entry.new(version:, kept:, undoable: KEEPS.include?(version) || ALONE.include?(version)) }
    end
  end
end
