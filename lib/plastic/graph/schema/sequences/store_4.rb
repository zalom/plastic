# frozen_string_literal: true

require "digest"
require_relative "../../../invalid"
require_relative "store_1"

module Plastic
  module Graph
    # Store migration 4, frozen. The knowledge file owns the intent: the intent rows, its clusters, completions,
    # go-aheads, verdicts, archives and the lines a write still owes move from the work file to the knowledge file,
    # with the printed and changes rows of their paths. The knowledge step creates the empty tables. The work step
    # copies each table into the knowledge file in one knowledge transaction, compares a digest of every moved table
    # in both files, and only when all are equal drops the tables from work. While work holds a table it is the
    # source, so a run that stopped after the copy copies again and then drops. Its statements are written out and
    # never call the live schema; the other file is reached through its own connection.
    module SchemaStore4
      # The digests of a moved table differ between the two files.
      class Mismatch < Plastic::Invalid; end

      MOVED = %w[intents clusters completions approvals verdicts archives archive_entries work_log_pending].freeze
      MOVED_PRINTED = %q("path" NOT LIKE '%/work.log' AND "path" NOT LIKE 'roadmaps/%')
      MOVED_CHANGES = %("table" IN (#{MOVED.map { |name| "'#{name}'" }.join(", ")})).freeze

      TABLES = {
        "work_graph" => %w[nodes edges work_log roadmaps batches roadmap_items roadmap_edges roadmap_log runs printed changes],
        "knowledge_graph" => [*SchemaStore1::TABLES.fetch("knowledge_graph"), *MOVED].freeze,
        "references" => SchemaStore1::TABLES.fetch("references")
      }.freeze

      TEXT = {
        knowledge: <<~SQL
          CREATE TABLE IF NOT EXISTS "intents"("id" INTEGER PRIMARY KEY AUTOINCREMENT, "intent_id" TEXT NOT NULL, "parent_id" TEXT, "ref" TEXT, "origin_id" TEXT NOT NULL, "slug" TEXT NOT NULL, "title" TEXT NOT NULL, "kind" TEXT, "status" TEXT NOT NULL CHECK(status IN ('open', 'in_progress', 'parked', 'future', 'done', 'abandoned')), "disposition" TEXT, "reason" TEXT, "opened_at" TEXT, "closed_at" TEXT, "updated_at" TEXT, UNIQUE("intent_id", "origin_id"));
          CREATE TABLE IF NOT EXISTS "clusters"("name" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("name", "intent_id", "origin_id"));
          CREATE TABLE IF NOT EXISTS "completions"("intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "at" TEXT NOT NULL, "session_id" TEXT NOT NULL, "judge" TEXT NOT NULL, "criteria" TEXT NOT NULL, "evidence" TEXT NOT NULL, "outcome_sha256" TEXT NOT NULL, UNIQUE("intent_id", "origin_id"));
          CREATE TABLE IF NOT EXISTS "approvals"("intent_id" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "origin_id"));
          CREATE TABLE IF NOT EXISTS "verdicts"("intent_id" TEXT NOT NULL, "round" INTEGER NOT NULL, "origin_id" TEXT NOT NULL, "verdict" TEXT NOT NULL, "findings" TEXT NOT NULL, "at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "round", "origin_id"));
          CREATE TABLE IF NOT EXISTS "archives"("intent_id" TEXT NOT NULL, "at" TEXT, "origin_id" TEXT NOT NULL, "restored_at" TEXT, "session_id" TEXT, UNIQUE("intent_id", "origin_id"));
          CREATE TABLE IF NOT EXISTS "archive_entries"("intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "kind" TEXT NOT NULL, "mode" INTEGER, "mtime" TEXT, "data" BLOB, UNIQUE("intent_id", "path", "origin_id"));
          CREATE TABLE IF NOT EXISTS "work_log_pending"("write_id" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "at" TEXT, "phase" TEXT NOT NULL DEFAULT '', "node" TEXT NOT NULL DEFAULT '', "session_id" TEXT, "kind" TEXT NOT NULL, "path" TEXT NOT NULL DEFAULT '', "sha256" TEXT NOT NULL DEFAULT '', "text" TEXT NOT NULL DEFAULT '', "origin_id" TEXT NOT NULL, UNIQUE("write_id"));
        SQL
      }.freeze

      # What is copied and compared: the table, and the rows of it that move.
      SPECS = [*MOVED.map { |name| [name, "1 = 1"] }, ["printed", MOVED_PRINTED], ["changes", MOVED_CHANGES]].freeze

      module_function

      def texts = [*TEXT.values, *SPECS.flatten, MOVED_PRINTED, MOVED_CHANGES]

      # `siblings` names the path of the knowledge file for the work step; `between` runs after the digests agree and before the drop.
      def apply(connection, key, siblings = {}, between: nil)
        return connection.execute_batch(TEXT.fetch(:knowledge)) if key == :knowledge
        return unless key == :work && siblings.key?(:knowledge) && moved_tables_in?(connection)

        move(connection, siblings.fetch(:knowledge), between)
      end

      def moved_tables_in?(connection) = connection.get_first_value("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'intents'").positive?

      def move(connection, path, between)
        require "sqlite3"
        knowledge = SQLite3::Database.new(path, results_as_hash: true)
        knowledge.busy_timeout = 5000
        plan = plan_for(connection)
        copy(connection, knowledge, plan)
        verify(connection, knowledge, plan)
        between&.call
        drop(connection)
      ensure
        knowledge&.close
      end

      # Each table with the condition on the work file and the condition on the knowledge file for the rows that move.
      def plan_for(work)
        paths = work.execute("SELECT \"path\" FROM \"printed\" WHERE #{MOVED_PRINTED}").map { |row| named(row, "path") }
        listed = paths.empty? ? "1 = 0" : "\"path\" IN (#{paths.map { |path| "'#{path.gsub("'", "''")}'" }.join(", ")})"
        SPECS.map { |table, where| [table, where, (table == "printed") ? listed : where] }
      end

      def copy(work, knowledge, plan)
        knowledge.transaction(:immediate) do
          plan.each do |table, work_where, knowledge_where|
            names = columns(work, table)
            knowledge.execute("DELETE FROM \"#{table}\" WHERE #{knowledge_where}")
            rows(work, table, work_where, names).each { |row| insert(knowledge, table, names, row) }
          end
        end
      end

      def columns(connection, table)
        names = connection.execute("SELECT name FROM pragma_table_info('#{table}')").map { |row| named(row, "name") }
        (table == "changes") ? names - ["seq"] : names
      end

      def named(row, name) = row.is_a?(Hash) ? row.fetch(name) : row.first

      def rows(connection, table, where, names)
        list = names.map { |name| "\"#{name}\"" }.join(", ")
        connection.prepare("SELECT #{list} FROM \"#{table}\" WHERE #{where} ORDER BY rowid") { |statement| statement.map { |row| values(row, names) } }
      end

      def values(row, names) = row.is_a?(Hash) ? names.map { |name| row.fetch(name) } : row.to_a

      def insert(knowledge, table, names, row)
        list = names.map { |name| "\"#{name}\"" }.join(", ")
        knowledge.execute("INSERT INTO \"#{table}\" (#{list}) VALUES (#{(["?"] * names.size).join(", ")})", row.map { |value| (value.is_a?(String) && value.encoding == Encoding::BINARY) ? SQLite3::Blob.new(value) : value })
      end

      def verify(work, knowledge, plan)
        plan.each do |table, work_where, knowledge_where|
          names = columns(work, table)
          next if digest(work, table, work_where, names) == digest(knowledge, table, knowledge_where, names)

          raise Mismatch, "the moved rows of #{table} differ between work_graph.db and knowledge_graph.db"
        end
      end

      def digest(connection, table, where, names)
        lines = rows(connection, table, where, names).map { |row| row.map { |value| value.is_a?(String) ? value.b.unpack1("H*") : value.inspect }.join("|") }
        Digest::SHA256.hexdigest(lines.sort.join("\n"))
      end

      def drop(connection)
        inside(connection) do
          connection.execute("DELETE FROM \"printed\" WHERE #{MOVED_PRINTED}")
          connection.execute("DELETE FROM \"changes\" WHERE #{MOVED_CHANGES}")
          MOVED.each { |table| connection.execute("DROP TABLE \"#{table}\"") }
        end
      end

      def inside(connection, &) = connection.transaction_active? ? yield : connection.transaction(:immediate, &)
    end
  end
end
