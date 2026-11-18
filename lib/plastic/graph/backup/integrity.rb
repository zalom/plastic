# frozen_string_literal: true

require "sqlite3"
require_relative "../backup"
require_relative "../schema"
require_relative "../schema/migrator"

module Plastic
  module Graph
    module Backup
      # Checks one backup file before a restore trusts it: SQLite reads it,
      # its quick check passes and it holds every table that the store had at the
      # version its folder recorded. A version above the newest of the code is refused.
      class Integrity
        # A backup file failed its check.
        class Rejected < StandardError; end

        # The tables of each database file of a beta.2 store, which no stamp marks.
        BETA_2_TABLES = {
          "work_graph" => %w[intents clusters nodes edges savepoints completions printed changes roadmaps batches roadmap_items
            roadmap_edges roadmap_log archives archive_entries],
          "knowledge_graph" => %w[documents document_revisions document_heads document_passages document_fts retrieval_schema
            retrieval_backfills retrieval_contexts retrieval_discoveries rulings links printed changes],
          "references" => %w[sqlar printed changes]
        }.freeze

        def initialize(path, name, version:)
          @path = path
          @name = name
          @version = version
          @database = nil
        end

        def call
          @database = SQLite3::Database.new(@path, readonly: true)
          verify
        rescue SQLite3::Exception => error
          reject("is not a readable database: #{error.message}")
        ensure
          @database&.close
        end

        private

        def reject(reason) = raise(Rejected, "#{@path} #{reason}")

        def verify
          newest = SchemaMigrator::VERSION
          reject("records the version #{@version}, which is newer than this code (version #{newest})") if @version > newest
          reject("fails the integrity check") unless @database.get_first_value("PRAGMA quick_check") == "ok"
          missing = expected - tables
          reject("lacks the tables #{missing.join(", ")}") unless missing.empty?
        end

        def tables = @database.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten

        def expected = @version.zero? ? BETA_2_TABLES.fetch(@name) : declared

        def declared
          _file, names = Schema.databases.values.find { |file, _names| File.basename(file, ".db") == @name }
          names.to_a.map(&:to_s)
        end
      end
    end
  end
end
