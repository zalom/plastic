# frozen_string_literal: true

require "digest"
require_relative "../../../invalid"
require_relative "store_4"

module Plastic
  module Graph
    # Store migration 5, frozen. The passages and the search entries leave the knowledge file for a derived file,
    # retrieval_graph.db, beside it. The step copies both tables into the new file in one retrieval transaction,
    # compares a digest of each in both files, and only when they are equal drops the tables, the three triggers
    # that fed the search entries, and the retrieval marker tables from knowledge. While knowledge holds the
    # tables it is the source, so a run that stopped after the copy copies again and then drops. Its statements are
    # written out and never call the live schema; the retrieval file is reached through its own connection.
    module SchemaStore5
      # The digests of a copied table differ between the two files.
      class Mismatch < Plastic::Invalid; end

      FILE = "retrieval_graph.db"
      STAMP = 5
      DERIVED = %w[document_passages document_fts].freeze
      DROPPED = %w[document_fts document_passages retrieval_schema retrieval_backfills].freeze
      TRIGGERS = %w[document_heads_search_insert document_heads_search_update document_heads_search_delete].freeze

      TABLES = {
        "work_graph" => SchemaStore4::TABLES.fetch("work_graph"),
        "knowledge_graph" => (SchemaStore4::TABLES.fetch("knowledge_graph") - DROPPED).freeze,
        "retrieval_graph" => DERIVED,
        "references" => SchemaStore4::TABLES.fetch("references")
      }.freeze

      COLUMNS = {
        "document_passages" => %w[sha256 intent_id path position body line_start line_end origin_id],
        "document_fts" => %w[body intent_id path sha256 position origin_id]
      }.freeze

      TEXT = {
        document_passages: <<~SQL,
          CREATE TABLE IF NOT EXISTS "document_passages"("sha256" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "position" INTEGER NOT NULL, "body" TEXT NOT NULL, "line_start" INTEGER NOT NULL, "line_end" INTEGER NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("sha256", "intent_id", "path", "position", "origin_id"));
        SQL
        document_fts: <<~SQL
          CREATE VIRTUAL TABLE IF NOT EXISTS "document_fts" USING fts5(body, intent_id UNINDEXED, path UNINDEXED, sha256 UNINDEXED, position UNINDEXED, origin_id UNINDEXED);
        SQL
      }.freeze

      module_function

      def texts = [*TEXT.values, *COLUMNS.flatten, *DROPPED, *TRIGGERS]

      # `siblings` names the path of the knowledge file; `between` runs after the digests agree and before the drop.
      def apply(connection, key, siblings = {}, between: nil)
        return unless key == :knowledge && siblings.key?(:knowledge) && holds_passages?(connection)

        move(connection, File.join(File.dirname(siblings.fetch(:knowledge)), FILE), between)
      end

      def holds_passages?(connection) = connection.get_first_value("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'document_passages'").positive?

      def move(connection, path, between)
        require "sqlite3"
        retrieval = SQLite3::Database.new(path, results_as_hash: true)
        begin
          retrieval.busy_timeout = 5000
          carry(connection, retrieval, between)
        ensure
          retrieval.close
        end
      end

      def carry(connection, retrieval, between)
        copy(connection, retrieval)
        verify(connection, retrieval)
        between&.call
        drop(connection)
      end

      def copy(knowledge, retrieval)
        retrieval.transaction(:immediate) do
          TEXT.each_value { |sql| retrieval.execute_batch(sql) }
          COLUMNS.each do |table, names|
            retrieval.execute("DELETE FROM \"#{table}\"")
            rows(knowledge, table, names).each { |row| insert(retrieval, table, names, row) }
          end
          retrieval.execute("PRAGMA user_version = #{STAMP}")
        end
      end

      def rows(connection, table, names)
        list = names.map { |name| "\"#{name}\"" }.join(", ")
        connection.execute("SELECT #{list} FROM \"#{table}\" ORDER BY rowid").map { |row| row.is_a?(Hash) ? names.map { |name| row.fetch(name) } : row.to_a }
      end

      def insert(retrieval, table, names, row)
        list = names.map { |name| "\"#{name}\"" }.join(", ")
        retrieval.execute("INSERT INTO \"#{table}\" (#{list}) VALUES (#{(["?"] * names.size).join(", ")})", row)
      end

      def verify(knowledge, retrieval)
        COLUMNS.each do |table, names|
          next if digest(rows(knowledge, table, names)) == digest(rows(retrieval, table, names))

          raise Mismatch, "the copied rows of #{table} differ between knowledge_graph.db and #{FILE}"
        end
      end

      def digest(rows) = Digest::SHA256.hexdigest(rows.map { |row| row.map { |value| value.is_a?(String) ? value.b.unpack1("H*") : value.inspect }.join("|") }.sort.join("\n"))

      def drop(connection)
        inside(connection) do
          TRIGGERS.each { |name| connection.execute("DROP TRIGGER IF EXISTS \"#{name}\"") }
          DROPPED.each { |table| connection.execute("DROP TABLE IF EXISTS \"#{table}\"") }
        end
      end

      def inside(connection, &) = connection.transaction_active? ? yield : connection.transaction(:immediate, &)
    end
  end
end
