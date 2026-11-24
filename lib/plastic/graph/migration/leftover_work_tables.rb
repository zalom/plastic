# frozen_string_literal: true

module Plastic
  module Graph
    # Builds the ten leftover tables of the work graph again, empty and with the text of the old tables, so a store that
    # went down below migration 20261124120000 has the layout an old checkout made, and `plastic update` can drop them
    # again. A table that held a row gets its rows back from legacy.db. Seven of the names (intents, clusters, completions,
    # approvals, verdicts, archives, archive_entries) and printed are live tables of knowledge_graph.db or plastic.db too:
    # every statement here names the `work` schema, and no other migration reads these names there.
    # Docs: docs/contributing/MIGRATIONS.md.
    module LeftoverWorkTables
      # The migration that drops the tables. It keeps a table only when it holds a row, so an empty one is kept nowhere.
      VERSION = "20261124120000"
      # The migrations that keep these tables only when the store has them.
      WHEN_PRESENT = [VERSION].freeze
      SCHEMA = "work"
      NAMES = %w[savepoints changes intents clusters completions approvals verdicts archives archive_entries printed].freeze

      DDL = [
        '"savepoints"("intent_id" TEXT NOT NULL, "position" INTEGER NOT NULL, "at" TEXT, "text" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "session_id" TEXT, UNIQUE("intent_id", "position", "origin_id"))',
        '"changes"("seq" INTEGER PRIMARY KEY AUTOINCREMENT, "table" TEXT NOT NULL, "key" TEXT NOT NULL, "operation" TEXT NOT NULL CHECK(operation IN (\'put\', \'remove\')), "row" TEXT, "at" TEXT NOT NULL, "origin_id" TEXT NOT NULL)',
        '"intents"("id" INTEGER PRIMARY KEY AUTOINCREMENT, "intent_id" TEXT NOT NULL, "parent_id" TEXT, "ref" TEXT, "origin_id" TEXT NOT NULL, "slug" TEXT NOT NULL, "title" TEXT NOT NULL, "kind" TEXT, "status" TEXT NOT NULL CHECK(status IN (\'open\', \'active\', \'parked\', \'future\', \'done\', \'abandoned\')), "disposition" TEXT, "opened_at" TEXT, "closed_at" TEXT, "updated_at" TEXT, UNIQUE("intent_id", "origin_id"))',
        '"clusters"("name" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("name", "intent_id", "origin_id"))',
        '"completions"("intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "at" TEXT NOT NULL, "session_id" TEXT NOT NULL, "judge" TEXT NOT NULL, "criteria" TEXT NOT NULL, "evidence" TEXT NOT NULL, "outcome_sha256" TEXT NOT NULL, UNIQUE("intent_id", "origin_id"))',
        '"approvals"("intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "origin_id"))',
        '"verdicts"("intent_id" TEXT NOT NULL, "round" INTEGER NOT NULL, "origin_id" TEXT NOT NULL, "verdict" TEXT NOT NULL, "findings" TEXT NOT NULL, "at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "round", "origin_id"))',
        '"archives"("intent_id" TEXT NOT NULL, "at" TEXT, "origin_id" TEXT NOT NULL, "restored_at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "origin_id"))',
        '"archive_entries"("intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "kind" TEXT NOT NULL, "mode" INTEGER, "mtime" TEXT, "data" BLOB, UNIQUE("intent_id", "path", "origin_id"))',
        '"printed"("path" TEXT NOT NULL, "sha256" TEXT NOT NULL, "at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("path"))'
      ].freeze

      # Whether `table` of the migration `version` is one of the ten, which live in `work` for this version only.
      def self.home?(version, table) = version == VERSION && NAMES.include?(table)

      # Keeps each table that holds a row, before the migration drops it, through the `keep` of the run on `connection`.
      def self.keep(keep, connection)
        NAMES.each { |table| keep.rows(VERSION, table) if LegacyTable.new(connection, table, VERSION).rows? }
      end

      # Makes each table that is missing and answers that it built no rows.
      def self.call(connection)
        DDL.each { |table| connection.execute("CREATE TABLE IF NOT EXISTS #{SCHEMA}.#{table}") }
        {}
      end
    end
  end
end
