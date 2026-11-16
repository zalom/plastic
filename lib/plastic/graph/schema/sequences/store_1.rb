# frozen_string_literal: true

require_relative "store_1/layout"
require_relative "store_1/swaps"

module Plastic
  module Graph
    # Store migration 1, frozen. It brings a store database of any older
    # release to the layout the first stamped release has: the declared
    # tables, then the three rebuilds of older tables. Its statements are
    # written out in Layout and Swaps and never call the live schema, so a
    # later change to the schema cannot change what migration 1 does. The
    # runner holds the write lock around it, so a rebuild opens no transaction.
    module SchemaStore1
      TABLES = {
        "work_graph" => %w[intents clusters nodes edges savepoints completions printed changes roadmaps batches roadmap_items
          roadmap_edges roadmap_log archives archive_entries approvals verdicts],
        "knowledge_graph" => %w[documents legacy_intents_data document_revisions document_heads document_passages document_fts
          retrieval_schema retrieval_backfills retrieval_contexts retrieval_discoveries rulings links printed changes],
        "references" => %w[sqlar printed changes]
      }.freeze

      REVISION_MEMBERSHIP = 'UNIQUE("sha256", "origin_id")'
      OUTDATED_INTENTS = /'active'|\A(?!.*"reason")/m

      module_function

      # Every text this migration holds, in a fixed order, for the digest that pins it.
      def texts = [*Layout::TEXT.values, *Swaps.constants.sort.map { |name| Swaps.const_get(name) }]

      def apply(connection, key)
        connection.execute_batch(Layout::TEXT.fetch(key))
        rebuild_revisions(connection)
        rebuild_passages(connection)
        rebuild_intents(connection)
      end

      def table_sql(connection, name) = connection.get_first_value("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = '#{name}'")

      def rebuild_revisions(connection)
        return unless table_sql(connection, "document_revisions")&.include?(REVISION_MEMBERSHIP)

        swap(connection, "document_revisions", [Swaps::REVISIONS, Swaps::REVISIONS_COPY], guarded: true)
      end

      def rebuild_passages(connection)
        sql = table_sql(connection, "document_passages")
        return if sql.nil? || sql.include?('"intent_id"')

        swap(connection, "document_passages", [Swaps::PASSAGES, Swaps::PASSAGES_COPY], guarded: true)
      end

      def rebuild_intents(connection)
        return unless table_sql(connection, "intents")&.match?(OUTDATED_INTENTS)

        swap(connection, "intents", [Swaps::INTENTS, Swaps::INTENT_STATES_COPY], guarded: false)
      end

      # Renames the old table, makes the new one, copies the rows across and drops the old one. The search
      # triggers sit on the heads table and read the two tables that are rebuilt, so they are dropped first and made again after.
      def swap(connection, table, (ddl, copy), guarded:)
        drops, creates = guarded ? [Swaps::SEARCH_TRIGGER_DROPS, Swaps::SEARCH_TRIGGER_CREATES] : ["", ""]
        connection.execute_batch("#{drops}\nALTER TABLE #{table} RENAME TO #{table}_legacy;\n#{ddl}\n#{copy}\nDROP TABLE #{table}_legacy;\n#{creates}")
      end
    end
  end
end
