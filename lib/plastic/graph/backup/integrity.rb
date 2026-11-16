# frozen_string_literal: true

require "sqlite3"
require_relative "../backup"
require_relative "../schema"
require_relative "../schema/sequences"

module Plastic
  module Graph
    module Backup
      # Checks one backup file before a restore trusts it: SQLite reads it,
      # its quick check passes and it holds every table that the store had at the
      # version its folder recorded. A version above the newest of the code is refused.
      class Integrity
        # A backup file failed its check.
        class Rejected < StandardError; end

        def initialize(path, name, version:, migrations: SchemaSequences::SEQUENCES.fetch(:store))
          @path = path
          @name = name
          @version = version
          @migrations = migrations
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
          newest = @migrations.last.number
          reject("records the version #{@version}, which is newer than this code (version #{newest})") if @version > newest
          reject("fails the integrity check") unless @database.get_first_value("PRAGMA quick_check") == "ok"
          missing = expected - tables
          reject("lacks the tables #{missing.join(", ")}") unless missing.empty?
        end

        def tables = @database.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten

        def expected = SchemaSequences.tables(@migrations, @version, @name)
      end
    end
  end
end
