# frozen_string_literal: true

module Plastic
  module Graph
    # Home migration 1, frozen. It brings the machine database to the layout
    # the first stamped release has: the declared tables, then the rename of
    # the lock time column that older releases call taken_at. Its statements
    # are written out and never call the live schema. The runner holds the
    # write lock around it.
    module SchemaHome1
      TABLES = { "local" => %w[routine_runs sessions locks backups] }.freeze

      TEXT = {
        local: <<~SQL
          CREATE TABLE IF NOT EXISTS "routine_runs"("store" TEXT NOT NULL, "tool" TEXT NOT NULL, "subject" TEXT NOT NULL DEFAULT '', "at" TEXT, "finished" TEXT, "status" TEXT, "facts" TEXT, "next_command" TEXT, "because" TEXT, "exit_code" INTEGER, "started_at" TEXT, "updated_at" TEXT, "session_id" TEXT, UNIQUE("store", "tool", "subject"));
          CREATE TABLE IF NOT EXISTS "sessions"("session_id" TEXT NOT NULL, "harness" TEXT, "store" TEXT, "directory" TEXT, "started_at" TEXT, "last_turn_at" TEXT, "ended_at" TEXT, "end_reason" TEXT, "note" TEXT, UNIQUE("session_id"));
          CREATE TABLE IF NOT EXISTS "locks"("store" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "session_id" TEXT NOT NULL, "mode" TEXT, "locked_at" TEXT, "renewed_at" TEXT, UNIQUE("store", "intent_id"));
          CREATE TABLE IF NOT EXISTS "backups"("name" TEXT NOT NULL, "files" INTEGER, "bytes" INTEGER, "sha256" TEXT, "at" TEXT, "session_id" TEXT, UNIQUE("name"));
        SQL
      }.freeze

      LOCKS_SQL = "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'locks'"

      module_function

      # Every text this migration holds, for the digest that pins it.
      def texts = TEXT.values

      def apply(connection, key)
        connection.execute_batch(TEXT.fetch(key))
        rename_lock_column(connection)
      end

      def rename_lock_column(connection)
        return unless connection.get_first_value(LOCKS_SQL)&.include?("taken_at")

        connection.execute("ALTER TABLE locks RENAME COLUMN taken_at TO locked_at")
      end
    end
  end
end
