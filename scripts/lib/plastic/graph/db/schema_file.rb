# frozen_string_literal: true

require "forwardable"
require_relative "../sql"
require_relative "../table"
require_relative "../knowledge/intent"

module Plastic
  module Graph
    # The design of Plastic's databases, read from db/schema.rb the way Rails reads
    # db/schema.rb: every table once, every database as a list of tables, a version
    # stamp, and a mark on the tables that hold legacy data. docs/contributing/ARCHITECTURE.md says how.
    class SchemaFile
      extend Forwardable

      TYPES = {
        text: "TEXT", kept: "TEXT NOT NULL", integer: "INTEGER", int: "INT", blob: "BLOB",
        number: "INTEGER NOT NULL", blank: "TEXT NOT NULL DEFAULT ''", primary: "TEXT PRIMARY KEY",
        serial: "INTEGER PRIMARY KEY AUTOINCREMENT",
        operation: "TEXT NOT NULL CHECK(operation IN ('put', 'remove'))",
        status: "TEXT NOT NULL CHECK(status IN (#{Knowledge::Intent::STATUSES.map { |status| "'#{status}'" }.join(", ")}))"
      }.freeze

      # One table's columns, declared one type at a time: `t.kept :a, :b`.
      class TableBuilder
        attr_reader :columns

        def initialize
          @columns = {}
        end

        TYPES.each do |type, sql|
          define_method(type) { |*names| names.each { |name| columns[name] = sql } }
        end
      end

      # What the block of SchemaFile.define declares: tables, virtual tables, marks and databases.
      class Declared
        attr_reader :tables, :virtual, :databases

        def initialize
          @tables = {}
          @marks = {}
          @virtual = {}
          @databases = {}
        end

        # A table declared once. `legacy: true` marks a table of old data that nothing new
        # reads; `since: VERSION` marks a table that databases older than VERSION lack.
        def create_table(name, key:, **marks)
          builder = TableBuilder.new
          yield builder
          tables[name] = Table.new(name:, key:, columns: builder.columns)
          @marks[name] = marks
        end

        def create_virtual_table(name, using:)
          virtual[name] = "CREATE VIRTUAL TABLE IF NOT EXISTS #{SQL.name(name)} USING #{using};"
        end

        # A database: its key, its file and the tables it holds, in order.
        def database(key, file, names) = databases[key] = [file, names]

        def legacy = marked(:legacy)

        def since = marked(:since)

        private

        def marked(mark) = @marks.select { |_name, marks| marks[mark] }.keys
      end

      attr_reader :version

      def_delegators :@declared, :tables, :virtual, :databases, :legacy, :since

      def self.define(version:, &block) = new(version, Declared.new.tap { |declared| declared.instance_eval(&block) })

      def initialize(version, declared)
        @version = version
        @declared = declared
      end
    end
  end
end
