# frozen_string_literal: true

require "sqlite3"
require_relative "../backup"
require_relative "../schema"
require_relative "../schema/migration_list"

module Plastic
  module Graph
    module Backup
      # Checks one backup file before a restore trusts it: SQLite reads it and
      # its quick check passes. At version 0 it holds every table of beta.2, and at
      # the newest version every declared table; an earlier known version passes on
      # the quick check alone, and the migrations move it forward after the restore.
      # A version this code does not know is refused.
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

        def initialize(path, name, version:, migrations: MIGRATIONS)
          @path = path
          @name = name
          @version = version
          @migrations = migrations
        end

        def call
          known_version
          SQLite3::Database.open(@path, readonly: true) { |database| verify(database) }
        rescue SQLite3::Exception => error
          reject("is not a readable database: #{error.message}")
        end

        private

        def reject(reason) = raise(Rejected, "#{@path} #{reason}")

        def verify(database)
          reject("fails the integrity check") unless database.get_first_value("PRAGMA quick_check") == "ok"
          missing = expected - database.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten
          reject("lacks the tables #{missing.join(", ")}") unless missing.empty?
        end

        def known_version
          newest = @migrations.newest(:store).to_i
          reject("records the version #{@version}, which is newer than this code (version #{newest})") if number > newest
          reject("records the version #{@version}, which this code does not know") unless @migrations.known_number?(:store, number)
        end

        def number = @migrations.number(:store, @version)

        def expected
          return BETA_2_TABLES.fetch(@name) if @version.zero?

          (number == @migrations.newest(:store).to_i) ? declared : []
        end

        def declared
          _file, names = Schema.databases.values.find { |file, _names| File.basename(file, ".db") == @name }
          names.to_a.map(&:to_s)
        end
      end
    end
  end
end
