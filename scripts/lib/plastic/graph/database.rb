# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require_relative "schema"
require_relative "sql"
require_relative "database/batch"

module Plastic
  module Graph
    # One SQLite file, reached through the sqlite3 program. The rows are the
    # authority; the files are printed from them.
    #
    # A write is one transaction in one sqlite3 process. BEGIN IMMEDIATE takes
    # the write lock first, so two calls that both ask for the next intent id
    # get two ids. Each database counts the rows that this call wrote, and the
    # report prints the counts on its `wrote:` line.
    class Database
      # The sqlite3 program is missing, or a statement failed.
      class Error < StandardError; end

      # The database of the home, for what belongs to one machine.
      def self.open_home(home, path: ENV.fetch("PATH", ""))
        find_sqlite3(path)
        { home: new(File.join(home, Schema::FILES[:home]), Schema.fetch(:home)) }
      end

      # The three databases of one store folder. `origin` stamps their rows and their change log.
      def self.open_store(root, origin, path: ENV.fetch("PATH", ""))
        find_sqlite3(path)
        Schema::STORE.to_h { |key| [key, new(File.join(root, Schema::FILES.fetch(key)), Schema.fetch(key), origin:)] }
      end

      def self.find_sqlite3(path)
        found = path.split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, "sqlite3")) }
        raise Error, "sqlite3 is not on PATH; install it, then call again" unless found
      end

      # The result sets of one sqlite3 run. Each set prints as one JSON
      # array; a raw newline never occurs inside a JSON string, so "]\n["
      # only separates two sets.
      def self.result_sets(out)
        text = out.strip
        text.empty? ? [] : JSON.parse("[#{text.gsub("]\n[", "],[")}]")
      end

      attr_reader :path, :written

      def initialize(path, schema, origin: nil)
        @path = path
        @schema = schema
        @origin = origin
        @created = false
        @written = Hash.new(0)
      end

      def file = File.basename(path)

      # Rows from one read. `:name` in the SQL takes the value of `name`.
      def rows(sql, **values) = execute(SQL.bind(sql, values)).first || []

      def row(sql, **values) = rows(sql, **values).first

      # Every write of one call to this database, in one transaction. The
      # block adds statements to the Batch; the rows that RETURNING gives back
      # come back in the order the statements were added.
      def transaction
        batch = Batch.new(origin: @origin)
        yield batch
        batch.empty? ? [] : commit(batch)
      end

      # What this call wrote here, as the report says it:
      # "1 intent and 1 savepoint line in work_graph.db". Nil when nothing.
      def written_phrase = written.empty? ? nil : "#{Schema.phrase(written)} in #{file}"

      private

      def commit(batch)
        tallies, returned = execute(batch.script).partition { |set| set.first.key?("written_table") }
        tallies.flatten.each { |tally| count(*tally.values_at("written_table", "written_rows")) }
        returned
      end

      def count(table, rows) = @written[table] += rows

      # One sqlite3 process per call. The schema goes first in the first
      # script of the process, so a new folder needs no separate setup step.
      def execute(script)
        out, err, status = Open3.capture3("sqlite3", "-json", "-bail", folder, stdin_data: with_schema(script))
        raise Error, "#{file}: #{err.strip}" unless status.success?

        @created = true
        Database.result_sets(out)
      end

      # The database's path, with its folder made first.
      def folder
        FileUtils.mkdir_p(File.dirname(path))
        path
      rescue SystemCallError => error
        raise Error, "#{file}: #{error.message}"
      end

      def with_schema(script) = @created ? script : "#{@schema}\n#{script}"
    end
  end
end
