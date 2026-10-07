# frozen_string_literal: true

require "sqlite3"
require_relative "../backup"
require_relative "../../schema"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # Checks one backup file before a restore trusts it: SQLite reads it,
        # its quick check passes and it holds every table the schema names.
        class Integrity
          # A backup file failed its check.
          class Rejected < StandardError; end

          def initialize(path, name)
            @path = path
            @name = name
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
            reject("fails the integrity check") unless @database.get_first_value("PRAGMA quick_check") == "ok"
            missing = expected - tables
            reject("lacks the tables #{missing.join(", ")}") unless missing.empty?
          end

          def tables = @database.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten

          def expected
            key = Schema.store.find { |candidate| Schema.file(candidate) == "#{@name}.db" }
            Schema.databases.fetch(key).last.map(&:to_s) - Schema.later_tables.map(&:to_s)
          end
        end
      end
    end
  end
end
