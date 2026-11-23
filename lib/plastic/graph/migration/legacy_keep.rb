# frozen_string_literal: true

require_relative "legacy_pages"
require_relative "legacy_table"
require_relative "legacy_values"

module Plastic
  module Graph
    # Keeps in legacy.db what the migrations of one store run remove, and counts it. A version of KEEPS keeps the tables
    # it drops whole, just before its SQL runs, and its data step keeps each row it deletes or the old text of each value
    # it rewrites. The connection has legacy.db
    # attached as `legacy` while a version of KEEPS or TRIMS is pending, or a version of LegacyPages finds the file.
    # Docs: docs/contributing/MIGRATIONS.md.
    class LegacyKeep
      FILE = "legacy.db"
      # The versions that keep what they remove, so a down can undo them.
      KEEPS = %w[20261119000000 20261121090000 20261123120000].freeze
      # The tables a version drops, kept whole before its SQL runs.
      WHOLE = { "20261119000000" => %w[document_revisions],
                "20261123120000" => %w[roadmaps batches roadmap_items roadmap_edges roadmap_log] }.freeze
      # The versions that remove from legacy.db rows an earlier version kept, rows a down rebuilds or no sync reads.
      TRIMS = %w[20261119190000].freeze
      # The versions that keep nothing and that a down undoes by removing the version alone: a sync up reads back every
      # row they drop that the rules still read, or a down of the earlier version rebuilds it.
      ALONE = %w[20261119180000 20261119190000 20261120090000 20261123090000 20261123100000 20261123130000].freeze
      # The versions that keep the old text of values they rewrite, in a table made only when a value changed; a down
      # undoes one that kept no value by removing the version alone.
      VALUES = %w[20261121090000].freeze

      # The legacy.db of the store at `root`, attached as `legacy` only while a `pending` version keeps or trims what it holds,
      # or gives back the free pages of the file that is there.
      def self.attachment(root, pending)
        file = File.join(root, FILE)
        attached = !((KEEPS + TRIMS) & pending).empty? || (!(LegacyPages::VERSIONS & pending).empty? && File.file?(file))
        attached ? { legacy: file } : {}
      end

      # One migration that ran on the store: the rows it kept by table, and whether a down can undo it.
      Entry = Data.define(:version, :kept, :undoable)

      # The keep a data step is given: it keeps rows of a table, or the old text of the values of a column, for one migration.
      Step = Data.define(:keep, :version) do
        def call(table, where = nil, values = []) = keep.rows(version, table, where, values)

        def values(column) = keep.values(version, column)
      end

      def initialize(connection)
        @connection = connection
        @kept = {}
      end

      # Whether a down can leave `version` with nothing in legacy.db: it keeps only when a value changed or a table was there.
      # (Migration 20261123120000 keeps its tables only when the store has them, and its down then takes its links off.)
      def self.kept_when_present?(version) = VALUES.include?(version) || version == "20261123120000"

      # Runs just before the SQL of `version`.
      def call(version)
        @kept[version] = Hash.new(0)
        WHOLE.fetch(version, []).each { |table| rows(version, table) }
      end

      # Keeps the rows of `table` that the `where` text selects, or all of them, for the migration `version`.
      def rows(version, table, where = nil, values = [])
        @kept.fetch(version)[table] += LegacyTable.new(@connection, table, version).keep(where, values)
      end

      # Keeps the old text of each value of the column that its `where` text selects, with the new text its `change` makes of it.
      def values(version, column)
        @kept.fetch(version)[LegacyValues::TABLE] += LegacyValues.new(@connection, version).keep(column)
      end

      # The keep of the data step of `version`.
      def at(version) = Step.new(keep: self, version:)

      # Each migration that ran, in order.
      def entries = @kept.map { |version, kept| Entry.new(version:, kept:, undoable: KEEPS.include?(version) || ALONE.include?(version)) }
    end
  end
end
