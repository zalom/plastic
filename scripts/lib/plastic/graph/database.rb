# frozen_string_literal: true

require "json"
require "open3"
require_relative "schema"

module Plastic
  module Graph
    # One SQLite file of the home, reached through the sqlite3 program.
    # The rows are the authority.
    #
    #   work_graph.db  routine runs
    #
    # A write is one transaction in one sqlite3 process. BEGIN IMMEDIATE takes
    # the write lock first, so two calls that both ask for the next intent id
    # get two ids. Each database counts the rows that this call wrote, and the
    # report prints the counts on its `wrote:` line.
    class Database
      FILES = {work: "work_graph.db"}.freeze

      Error = Class.new(StandardError)

      # Bytes that go in as a BLOB literal, such as a kept file.
      Bytes = Data.define(:data)

      # The databases under one home, each with its schema. Every
      # database is reached through the sqlite3 program, so it must be on PATH.
      def self.open_all(home, path: ENV.fetch("PATH", ""))
        found = path.split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, "sqlite3")) }
        raise Error, "sqlite3 is not on PATH; install it, then call again" unless found

        FILES.to_h { |key, file| [key, new(File.join(home, file), Schema.fetch(key))] }
      end

      # A value as an SQL literal. Hashes and arrays are stored as JSON text.
      def self.literal(value)
        case value
        in nil then "NULL"
        in true then "1"
        in false then "0"
        in Integer | Float then value.to_s
        in Bytes then "X'#{value.data.unpack1("H*")}'"
        in Hash | Array then literal(JSON.generate(value))
        else "'#{value.to_s.gsub("'", "''")}'"
        end
      end

      def self.name(identifier) = %("#{identifier.to_s.gsub('"', '""')}")

      attr_reader :path, :written

      def initialize(path, schema)
        @path = path
        @schema = schema
        @created = false
        @written = Hash.new(0)
      end

      def file = File.basename(path)

      # Rows from one read. `:name` in the SQL takes the value of `name`.
      def rows(sql, **values) = execute(bind(sql, values)).first || []

      def row(sql, **values) = rows(sql, **values).first

      # Every write of one call to this database, in one transaction. The
      # block adds statements to the Batch; the rows that RETURNING gives back
      # come back in the order the statements were added.
      def transaction
        batch = Batch.new
        yield batch
        return [] if batch.empty?

        sets = execute(["BEGIN IMMEDIATE;", *batch.statements, "COMMIT;"].join("\n"))
        counts, returned = sets.partition { |set| set.first.key?("written_table") }
        count(counts.flatten)
        returned
      end

      # One statement list with the row count after each write, so the
      # counts are exact rather than one per statement.
      class Batch
        attr_reader :statements

        def initialize = @statements = []

        def empty? = @statements.empty?

        # A write. Its RETURNING rows, such as a new id, come back from
        # the transaction. `count: false` keeps it off the report, as for
        # the hashes that the checkout records.
        def write(table, sql, count: true, **values)
          @statements << "#{Database.bind(sql, values)};"
          @statements << "SELECT #{Database.literal(table.to_s)} AS written_table, changes() AS n WHERE changes() > 0;" if count
          self
        end

        def insert(table, record, store: nil, conflict: nil)
          columns = {store:}.compact.merge(record.to_h)
          names = columns.keys.map { |key| Database.name(key) }.join(", ")
          values = columns.values.map { |value| Database.literal(value) }.join(", ")
          clause = conflict ? " ON CONFLICT DO #{conflict}" : ""
          write(table, "INSERT INTO #{Database.name(table)} (#{names}) VALUES (#{values})#{clause}")
        end
      end

      def self.bind(sql, values)
        return sql if values.empty?

        sql.gsub(/(?<!:):([a-z_][a-z0-9_]*)\b/) do
          key = Regexp.last_match(1).to_sym
          values.key?(key) ? literal(values[key]) : Regexp.last_match(0)
        end
      end

      def bind(sql, values) = self.class.bind(sql, values)

      # What this call wrote here, as the report says it:
      # "1 intent and 1 ledger line in work_graph.db". Nil when nothing.
      def written_phrase
        return nil if written.empty?

        parts = written.map { |table, n| "#{n} #{Schema.noun(table, n)}" }
        list = (parts.size < 3) ? parts.join(" and ") : "#{parts[0..-2].join(", ")}, and #{parts.last}"
        "#{list} in #{file}"
      end

      private

      def count(counts)
        counts.each { |count| @written[count["written_table"]] += count["n"].to_i }
      end

      # One sqlite3 process per call. The schema goes first in the first
      # script of the process, so a new home needs no separate setup step.
      # Each result set prints as one JSON array; a raw newline never occurs
      # inside a JSON string, so "]\n[" only separates two sets.
      def execute(script)
        script = "#{@schema}\n#{script}" unless @created
        out, err, status = Open3.capture3("sqlite3", "-json", "-bail", path, stdin_data: script)
        raise Error, "#{file}: #{err.strip}" unless status.success?

        @created = true
        text = out.strip
        text.empty? ? [] : JSON.parse("[#{text.gsub("]\n[", "],[")}]")
      end
    end
  end
end
