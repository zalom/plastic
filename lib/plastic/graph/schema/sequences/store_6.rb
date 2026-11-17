# frozen_string_literal: true

require "digest"
require_relative "../../../invalid"
require_relative "store_5"

module Plastic
  module Graph
    # Store migration 6, frozen. The files a store keeps move from references.db into the knowledge file: the sqlar rows,
    # the printed rows and the changes rows are copied, and the digest of the copied sqlar and changes rows is
    # compared with the source inside the same transaction. The retire step runs after that transaction has committed:
    # it reads each sqlar row back from knowledge by name and hash, and only when every row matches does it
    # remove references.db. A run that stopped before the commit leaves references.db whole and copies again; a run
    # that stopped after it finds the file and retires it. Its statements are written out and never call the live schema.
    module SchemaStore6
      # A row of references.db is missing from knowledge, or differs from it.
      class Mismatch < Plastic::Invalid; end

      FILE = "references.db"
      STAMP = 6
      SIDECARS = ["", "-wal", "-shm", "-journal"].freeze

      TABLES = {
        "work_graph" => SchemaStore5::TABLES.fetch("work_graph"),
        "knowledge_graph" => [*SchemaStore5::TABLES.fetch("knowledge_graph"), "sqlar"].freeze,
        "retrieval_graph" => SchemaStore5::TABLES.fetch("retrieval_graph")
      }.freeze

      COLUMNS = {
        "sqlar" => %w[name mode mtime sz data intent_id sha256 origin_id],
        "printed" => %w[path sha256 at origin_id],
        "changes" => %w[table key operation row at origin_id]
      }.freeze

      VERBS = { "sqlar" => "INSERT OR REPLACE", "printed" => "INSERT OR IGNORE", "changes" => "INSERT" }.freeze

      TEXT = <<~SQL
        CREATE TABLE IF NOT EXISTS "sqlar"("name" TEXT PRIMARY KEY, "mode" INT, "mtime" INT, "sz" INT, "data" BLOB, "intent_id" TEXT, "sha256" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("name"));
      SQL

      module_function

      def texts = [TEXT, FILE, *VERBS.values, *COLUMNS.flatten]

      # `siblings` names the path of the knowledge file; `between` runs after the digests agree.
      def apply(connection, key, siblings = {}, between: nil)
        return unless key == :knowledge

        connection.execute_batch(TEXT)
        path = references_path(siblings)
        copy_from(connection, path, between) if path && File.file?(path)
      end

      def references_path(siblings) = siblings.key?(:knowledge) ? File.join(File.dirname(siblings.fetch(:knowledge)), FILE) : nil

      def copy_from(connection, path, between)
        require "sqlite3"
        source = SQLite3::Database.new(path, readonly: true, results_as_hash: true)
        begin
          inside(connection) { carry(connection, source, between) }
        ensure
          source.close
        end
      end

      def carry(connection, source, between)
        floor = connection.get_first_value("SELECT coalesce(max(seq), 0) FROM changes").to_i
        present(source).each { |table| copy(connection, source, table) }
        verify(connection, source, floor)
        between&.call
      end

      def present(source) = COLUMNS.keys.select { |table| source.get_first_value("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = ?", [table]).positive? }

      def names(table) = COLUMNS.fetch(table).map { |name| "\"#{name}\"" }.join(", ")

      def order(table) = (table == "changes") ? "seq" : "rowid"

      def rows(connection, table, tail = "")
        connection.execute("SELECT #{names(table)} FROM \"#{table}\" #{tail} ORDER BY #{order(table)}").map { |row| row.is_a?(Hash) ? COLUMNS.fetch(table).map { |name| row.fetch(name) } : row.to_a }
      end

      def copy(connection, source, table)
        marks = (["?"] * COLUMNS.fetch(table).size).join(", ")
        rows(source, table).each { |row| connection.execute("#{VERBS.fetch(table)} INTO \"#{table}\" (#{names(table)}) VALUES (#{marks})", blob(row)) }
      end

      def blob(row) = row.map { |value| (value.is_a?(String) && value.encoding == Encoding::BINARY) ? SQLite3::Blob.new(value) : value }

      def verify(connection, source, floor)
        tables = present(source)
        verify_sqlar(connection, source) if tables.include?("sqlar")
        verify_changes(connection, source, floor) if tables.include?("changes")
      end

      def verify_sqlar(connection, source)
        expected = rows(source, "sqlar")
        actual = expected.map { |row| named(connection, row.first) }
        raise Mismatch, "the copied sqlar rows differ between #{FILE} and knowledge_graph.db" unless digest(expected) == digest(actual.compact)
      end

      def named(connection, name) = rows(connection, "sqlar", "WHERE name = #{quote(name)}").first

      def quote(text) = "'#{text.gsub("'", "''")}'"

      def verify_changes(connection, source, floor)
        return if digest(rows(source, "changes")) == digest(rows(connection, "changes", "WHERE seq > #{floor}"))

        raise Mismatch, "the copied changes rows differ between #{FILE} and knowledge_graph.db"
      end

      def digest(rows) = Digest::SHA256.hexdigest(rows.map { |row| row.map { |value| value.is_a?(String) ? value.b.unpack1("H*") : value.inspect }.join("|") }.sort.join("\n"))

      # Removes references.db once knowledge answers each of its sqlar rows by name with the same hash. True when the file is gone.
      def retire(knowledge_path, references_path)
        return true unless File.file?(references_path)

        require "sqlite3"
        check(knowledge_path, references_path)
        SIDECARS.map { |suffix| "#{references_path}#{suffix}" }.select { |file| File.file?(file) }.each { |file| File.delete(file) }
        true
      end

      def check(knowledge_path, references_path)
        source = SQLite3::Database.new(references_path, readonly: true, results_as_hash: true)
        knowledge = SQLite3::Database.new(knowledge_path, readonly: true, results_as_hash: true)
        begin
          present(source).include?("sqlar") && rows(source, "sqlar").each { |row| read_back(knowledge, row) }
        ensure
          source.close
          knowledge.close
        end
      end

      def read_back(knowledge, row)
        name, _mode, _mtime, _sz, data, _intent, sha256, = row
        found = knowledge.get_first_row("SELECT data, sha256 FROM sqlar WHERE name = ?", [name])
        stored = found && [found["data"].to_s.b, found["sha256"]]
        return if stored && stored == [data.to_s.b, sha256] && Digest::SHA256.hexdigest(stored.first) == Digest::SHA256.hexdigest(data.to_s.b)

        raise Mismatch, "#{name} of #{FILE} is not in knowledge_graph.db with the same bytes and hash"
      end

      def inside(connection, &) = connection.transaction_active? ? yield : connection.transaction(:immediate, &)
    end
  end
end
