# frozen_string_literal: true

require_relative "legacy_table"

module Plastic
  module Graph
    # Builds the five roadmap tables of the work graph again, empty and with the text of the live tables (UNIQUE keys, and
    # the batch and position of an item NOT NULL), so a store that went down below migration 20261124090000 has the layout
    # it had before, and `plastic update` can drop them again. A table that held a row gets its rows back from legacy.db.
    # Docs: docs/contributing/MIGRATIONS.md.
    module RoadmapTables
      # The migration that drops the tables. It keeps a table only when it holds a row, so an empty one is kept nowhere.
      VERSION = "20261124090000"
      # The migrations that keep these tables only when the store has them.
      WHEN_PRESENT = [VERSION, "20261123120000"].freeze
      NAMES = %w[roadmaps batches roadmap_items roadmap_edges roadmap_log].freeze

      DDL = [
        '"roadmaps"("slug" TEXT NOT NULL, "title" TEXT NOT NULL, "goal" TEXT, "opened_at" TEXT, "updated_at" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("slug", "origin_id"))',
        '"batches"("roadmap" TEXT NOT NULL, "position" INTEGER NOT NULL, "title" TEXT NOT NULL, "goal" TEXT, "done" TEXT, "updated_at" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("roadmap", "position", "origin_id"))',
        '"roadmap_items"("roadmap" TEXT NOT NULL, "item" TEXT NOT NULL, "batch" INTEGER NOT NULL, "position" INTEGER NOT NULL, "title" TEXT, "goal" TEXT, "done" TEXT, "intent_id" TEXT, "mark" TEXT, "updated_at" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("roadmap", "item", "origin_id"))',
        '"roadmap_edges"("roadmap" TEXT NOT NULL, "from" TEXT NOT NULL, "to" TEXT NOT NULL, "kind" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("roadmap", "from", "to", "origin_id"))',
        '"roadmap_log"("roadmap" TEXT NOT NULL, "position" INTEGER NOT NULL, "at" TEXT, "text" TEXT NOT NULL, "session_id" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("roadmap", "position", "origin_id"))'
      ].freeze

      # Keeps each table that holds a row, before the migration drops it, through the `keep` of the run on `connection`.
      def self.keep(keep, connection)
        NAMES.each { |table| keep.rows(VERSION, table) if LegacyTable.new(connection, table, VERSION).rows? }
      end

      # Makes each table that is missing and answers that it built no rows.
      def self.call(connection)
        DDL.each { |table| connection.execute("CREATE TABLE IF NOT EXISTS work.#{table}") }
        {}
      end
    end
  end
end
